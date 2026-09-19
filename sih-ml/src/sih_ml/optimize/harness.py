"""Controlled-experiment harness for Stage 7.

The contract
------------
An **arm** is a transform of a single fold's TRAINING rows:

    arm.transform(data, tr_idx, fold, seed) -> TrainSet(X, y, w)

It may drop rows, reweight rows, perturb feature values or append synthetic rows.
It may **not** see, touch or transform:
  * the held-out fold (`va`)      — that is the thing being measured,
  * the early-stopping rows (`es`) — that is the inner validation signal.

Augmenting or reweighting either of those would manufacture the very signal the
experiment is supposed to measure. This is enforced structurally: `run_arm` only
ever hands `tr_idx` to the arm.

Why paired folds
----------------
Stage 6 compared two means over 2 report folds and could not resolve anything
below ~0.03 AP, because fold-to-fold variance (AP ranges 0.18-0.55 across folds)
swamps any plausible effect. Here every arm is run on the SAME 5 folds with the
SAME seeds and the SAME early-stopping splits, so that variance is common to both
sides of the comparison and cancels in the per-fold difference. What is tested is
the *delta*, not the absolute score.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Callable

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.train import cv
from sih_ml.utils.common import Config, get_logger

log = get_logger("stage7")


@dataclass
class TrainSet:
    """A fold's training rows after an arm has transformed them."""
    X: pd.DataFrame
    y: np.ndarray
    w: np.ndarray


@dataclass
class Arm:
    name: str
    group: str                                   # data | augment | loss | model | baseline
    transform: Callable | None = None            # (data, tr_idx, fold, seed) -> TrainSet
    param_overrides: dict = field(default_factory=dict)
    objective: str | None = None                 # None | "focal"
    objective_kwargs: dict = field(default_factory=dict)
    note: str = ""


def identity_trainset(data: Data, tr_idx: np.ndarray, fold: int, seed: int) -> TrainSet:
    return TrainSet(data.X(tr_idx), data.y[tr_idx], data.w[tr_idx])


def _scale_pos_weight(cfg: Config, y: np.ndarray) -> float | None:
    if not cfg.lgbm.get("auto_scale_pos_weight", True):
        return None
    mult = float(cfg.lgbm.get("scale_pos_weight_mult", 1.0))
    return cv._scale_pos_weight(y) * mult


def fit_one_fold(data: Data, cfg: Config, arm: Arm, fold: int, seed: int):
    """Train one fold under one arm and score its held-out blocks.

    Returns (ap, val_idx, val_pred, model, n_train_rows, fit_seconds).
    """
    tr_all, va = data.spatial_fold_indices(fold, drop_buffer=cfg.cv.drop_buffer_rows)
    # Scope is applied to training, early stopping AND the held-out fold together.
    # Filtering only one of them would train on a different target than it is scored
    # against, which is a quieter and worse bug than not scoping at all.
    tr_all, va = data.scoped(tr_all), data.scoped(va)
    m_tr, m_es = cv.make_es_split(data, tr_all, cfg, seed + fold)
    tr, es = tr_all[m_tr], tr_all[m_es]

    ts = (arm.transform or identity_trainset)(data, tr, fold, seed)

    p = dict(cfg.lgbm)
    p.update(arm.param_overrides)
    p["seed"] = seed + fold

    fobj = None
    if arm.objective == "focal":
        from sih_ml.optimize.losses import make_focal_objective
        fobj = make_focal_objective(**arm.objective_kwargs)

    model = LGBMBaseline(
        params=p, features=data.features, categorical=data.categorical,
        monotone_increasing=list(p.get("monotone_rainfall_features", [])),
    )
    # scale_pos_weight is a built-in-objective mechanism; with a custom objective
    # the class balance is carried by focal `alpha` instead (see losses.py).
    spw = None if fobj is not None else _scale_pos_weight(cfg, ts.y)

    t0 = time.time()
    model.fit(ts.X, ts.y, ts.w,
              data.X(es), data.y[es], data.w[es],
              scale_pos_weight=spw, fobj=fobj)
    dt = time.time() - t0

    pred = model.predict(data.X(va))
    ap = float(average_precision_score(data.y[va], pred)) if data.y[va].sum() else float("nan")
    return ap, va, pred, model, len(ts.y), dt


def run_arm(data: Data, cfg: Config, arm: Arm, folds: list[int], seed: int) -> dict:
    """Run one arm over every fold. Returns per-fold AP plus pooled OOF predictions."""
    oof = np.full(len(data.panel), np.nan)
    fold_of = np.full(len(data.panel), -1)
    aps, n_rows, secs, iters = {}, [], [], []
    last_model = None
    for f in folds:
        ap, va, pred, model, n_tr, dt = fit_one_fold(data, cfg, arm, f, seed)
        oof[va] = pred
        fold_of[va] = f
        aps[f] = ap
        n_rows.append(n_tr)
        secs.append(dt)
        iters.append(int(model.best_iteration_ or 0))
        last_model = model
    vals = [aps[f] for f in folds]
    return {
        "name": arm.name, "group": arm.group, "note": arm.note,
        "fold_ap": aps,
        "mean_AP": float(np.nanmean(vals)),
        "std_AP": float(np.nanstd(vals)),
        "mean_train_rows": float(np.mean(n_rows)),
        "mean_fit_sec": float(np.mean(secs)),
        "mean_best_iter": float(np.mean(iters)),
        "oof": oof, "fold_of": fold_of, "model": last_model,
    }


# --------------------------------------------------------------------------- #
# Paired comparison
# --------------------------------------------------------------------------- #
def paired_delta(arm_res: dict, base_res: dict, folds: list[int],
                 n_perm: int = 20000, seed: int = 0) -> dict:
    """Paired per-fold comparison of an arm against the bar.

    The test is a **sign-flip permutation test** on the paired differences. With
    n folds there are only 2^n sign patterns, so when 2^n <= n_perm every pattern
    is enumerated and the p-value is EXACT. Sampling 20,000 draws from a space of
    32 would add Monte Carlo noise to an answer that can be computed exactly —
    enough noise to report p = 0.0619 where the true value is 2/32 = 0.0625, i.e.
    to print a p-value below the floor the same test guarantees.

    That floor is the headline caveat: with n=5 the smallest attainable two-sided
    p is 0.0625, so this test is weak BY CONSTRUCTION — it can reject noise, it
    cannot certify a small effect, and no Bonferroni-corrected threshold across
    ~25 arms is reachable. It is still strictly better than comparing two unpaired
    means, which is what 5-fold CV usually gets.
    """
    d = np.array([arm_res["fold_ap"][f] - base_res["fold_ap"][f] for f in folds], float)
    d = d[np.isfinite(d)]
    n = len(d)
    if n == 0:
        return {"mean_delta": float("nan"), "p_value": float("nan"),
                "folds_improved": 0, "n_folds": 0, "deltas": []}

    obs = float(d.mean())
    if 2 ** n <= n_perm:                      # exact: enumerate every sign pattern
        k = np.arange(2 ** n)[:, None]
        signs = 1.0 - 2.0 * ((k >> np.arange(n)) & 1).astype(float)
        exact = True
    else:
        signs = np.random.default_rng(seed).choice([-1.0, 1.0], size=(n_perm, n))
        exact = False
    null = (signs * d).mean(axis=1)
    p = float((np.abs(null) >= abs(obs) - 1e-12).mean())
    return {
        "exact_permutation": exact,
        "mean_delta": obs,
        "std_delta": float(d.std()),
        "deltas": [float(x) for x in d],
        "folds_improved": int((d > 0).sum()),
        "n_folds": n,
        "p_value": p,
        "min_attainable_p": float(2.0 / (2 ** n)),
    }


def verdict(delta: dict, min_folds: int, alpha: float) -> str:
    """Two-condition rule; anything else is 'not demonstrated', never 'improvement'."""
    if not np.isfinite(delta.get("mean_delta", float("nan"))):
        return "invalid"
    consistent = delta["folds_improved"] >= min_folds
    significant = delta["p_value"] < alpha
    if delta["mean_delta"] > 0 and consistent and significant:
        return "improvement"
    if delta["mean_delta"] < 0 and delta["folds_improved"] <= delta["n_folds"] - min_folds \
            and delta["p_value"] < alpha:
        return "regression"
    return "not demonstrated"


def summarize(rows: list[dict]) -> pd.DataFrame:
    return pd.DataFrame(rows).sort_values("mean_delta", ascending=False)
