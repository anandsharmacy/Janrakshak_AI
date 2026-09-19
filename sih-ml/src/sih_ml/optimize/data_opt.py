"""Stage 7 §1 — data optimization: dedup, label pruning, weighting, sample mining.

All of these transform a fold's TRAINING rows only (see harness.py).

The leakage trap in "mining"
----------------------------
Hard-negative mining needs a score per training row saying "how wrong is the model
about this row". The obvious source is the Stage 5 OOF prediction — and it is
**wrong**, subtly. In spatial CV every row is validated exactly once; a training
row of fold k was validated by some model j != k, and model j trained on blocks
that include fold k's *held-out* blocks. So fold k's validation labels reach fold
k's training weights through model j. The effect is small but it is real, and it
biases in the flattering direction.

The fix implemented here: for each outer fold, a **prospector** model is
cross-fitted strictly *inside* that fold's own training rows (`inner_oof_scores`),
grouped by `event_id` exactly like the outer early-stopping split. No row of the
held-out fold participates in any way. It costs `inner_folds` extra fits per outer
fold, which at ~4 s a fit is a price worth paying to keep the number honest.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.optimize.harness import TrainSet
from sih_ml.utils.common import Config, get_logger

log = get_logger("stage7.data")

_PROSPECTOR = {          # deliberately small/fast: it ranks rows, it is not the model
    "objective": "binary", "boosting_type": "gbdt", "learning_rate": 0.05,
    "num_leaves": 16, "max_depth": 6, "min_child_samples": 50, "min_split_gain": 0.0,
    "subsample": 0.8, "subsample_freq": 1, "colsample_bytree": 0.8,
    "reg_alpha": 0.1, "reg_lambda": 1.0, "n_estimators": 200,
    "early_stopping_rounds": 30, "max_bin": 255, "verbosity": -1,
}


# --------------------------------------------------------------------------- #
# 1. Deduplication
# --------------------------------------------------------------------------- #
def dedup_indices(data: Data, tr_idx: np.ndarray) -> np.ndarray:
    """Drop exact duplicate feature vectors within the training rows (keep first).

    Stage 5 §8 measured 430 duplicated rows in 215 groups with **zero** label
    conflicts, so this cannot fix a contradiction — it can only stop a handful of
    rows being counted twice. Included because the brief asks for it and because
    measuring a null result is worth more than assuming one.
    """
    sub = data.panel.iloc[tr_idx][data.features]
    h = pd.util.hash_pandas_object(sub, index=False)
    keep = ~pd.Series(h.to_numpy()).duplicated().to_numpy()
    return tr_idx[keep]


def make_dedup_arm():
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        k = dedup_indices(data, tr_idx)
        return TrainSet(data.X(k), data.y[k], data.w[k])
    return _t


# --------------------------------------------------------------------------- #
# 2. Label-quality pruning
# --------------------------------------------------------------------------- #
def make_confidence_floor_arm(floor: float):
    """Drop POSITIVES below a label_confidence floor; keep every negative.

    Stage 5 §4 measured ROC-AUC 0.688 for positives in [0, 0.25) against 0.865 for
    [0.5, 1.0] — the bottom bucket is close to unlearnable. Whether removing it
    helps is an empirical question: it also removes 174 positives from a
    label-starved dataset, so the arm can easily lose.
    """
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        conf = data.panel["label_confidence"].to_numpy(float)[tr_idx]
        y = data.y[tr_idx]
        keep = (y == 0) | (np.nan_to_num(conf, nan=1.0) >= floor)
        k = tr_idx[keep]
        return TrainSet(data.X(k), data.y[k], data.w[k])
    return _t


# --------------------------------------------------------------------------- #
# 3. Sample-weight schemes
# --------------------------------------------------------------------------- #
def make_weight_scheme_arm(scheme: str):
    """Re-shape the Stage 2 confidence weight.

    `sample_weight` = tier_prior x distance_decay x susceptibility_factor. The
    exponent controls how hard the model is pushed to believe the confident labels:
    `square` sharpens (trust the good labels more), `sqrt` flattens (treat all
    labels as roughly equal), `uniform` discards the weighting entirely — which is
    the arm that tests whether Stage 2's weighting scheme earns its place at all.
    """
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        w = data.w[tr_idx].copy()
        if scheme == "uniform":
            w = np.ones_like(w)
        elif scheme == "sqrt":
            w = np.sqrt(np.clip(w, 0, None))
        elif scheme == "square":
            w = np.clip(w, 0, None) ** 2
        else:
            raise ValueError(f"unknown weight scheme {scheme!r}")
        # keep the total weight mass constant so this is a SHAPE change, not a
        # learning-rate change in disguise
        m = w.mean()
        if m > 0:
            w = w * (data.w[tr_idx].mean() / m)
        return TrainSet(data.X(tr_idx), data.y[tr_idx], w)
    return _t


# --------------------------------------------------------------------------- #
# 4. The prospector — inner cross-fitted scores, no outer leakage
# --------------------------------------------------------------------------- #
def inner_oof_scores(data: Data, cfg: Config, tr_idx: np.ndarray, seed: int,
                     n_inner: int = 2) -> np.ndarray:
    """Score every row of `tr_idx` with a model that did not train on it, using
    ONLY rows from `tr_idx`. Positives are grouped by `event_id` so a positive's
    up-to-60 sibling rows never straddle the inner split (the same defect Stage 5
    found in the early-stopping split)."""
    rng = np.random.default_rng(seed)
    y = data.y[tr_idx]
    events = data.panel["event_id"].astype(str).to_numpy()[tr_idx]

    assign = np.full(len(tr_idx), -1)
    pos = np.where(y == 1)[0]
    if len(pos):
        ev = np.array(sorted(pd.unique(events[pos])))
        rng.shuffle(ev)
        ev_fold = {e: i % n_inner for i, e in enumerate(ev)}
        assign[pos] = [ev_fold[events[i]] for i in pos]
    neg = np.where(y == 0)[0]
    assign[neg] = rng.integers(0, n_inner, size=len(neg))

    scores = np.full(len(tr_idx), np.nan)
    for i in range(n_inner):
        in_i = assign == i
        tr_i, va_i = tr_idx[~in_i], tr_idx[in_i]
        if len(va_i) == 0 or data.y[tr_i].sum() == 0:
            continue
        p = dict(_PROSPECTOR)
        p["seed"] = seed + 991 + i
        m = LGBMBaseline(p, data.features, data.categorical, [])
        # a small stratified slice of the inner-train rows drives early stopping
        n_es = max(50, int(0.1 * len(tr_i)))
        perm = rng.permutation(len(tr_i))
        es_sel, fit_sel = tr_i[perm[:n_es]], tr_i[perm[n_es:]]
        m.fit(data.X(fit_sel), data.y[fit_sel], data.w[fit_sel],
              data.X(es_sel), data.y[es_sel], data.w[es_sel],
              scale_pos_weight=max(1e-3, (data.y[fit_sel] == 0).sum()
                                   / max(1, data.y[fit_sel].sum())))
        scores[in_i] = m.predict(data.X(va_i))
    # rows that never got a score (degenerate inner fold) fall back to the median
    med = np.nanmedian(scores) if np.isfinite(scores).any() else 0.5
    return np.where(np.isfinite(scores), scores, med)


def _rank_pct(x: np.ndarray) -> np.ndarray:
    """0 = lowest score, 1 = highest. Ties get their average rank."""
    if len(x) == 0:
        return x
    return pd.Series(x).rank(pct=True, method="average").to_numpy()


def _preserve_mass(w_new: np.ndarray, w_old: np.ndarray) -> np.ndarray:
    """Rescale so a mining arm REDISTRIBUTES weight rather than adding it.

    Without this, `w *= 1 + alpha*rank` raises the total negative mass by ~alpha/2
    (measured: 43.7k -> 102.8k at alpha=3), which silently changes the effective
    class balance and the effective learning rate. The arm would then be testing
    "more negative weight" confounded with "better-chosen negative weight", and a
    win could not be attributed to mining at all. Holding the mass fixed makes it a
    clean test of WHICH rows get the weight.
    """
    s = w_new.sum()
    return w_new * (w_old.sum() / s) if s > 0 else w_new


# --------------------------------------------------------------------------- #
# 5. Mining arms
# --------------------------------------------------------------------------- #
def make_hard_negative_arm(cfg: Config, alpha: float, n_inner: int = 2):
    """Upweight the negatives the model finds hardest: `w *= 1 + alpha * rank_pct`.

    Stage 2 already mines hard negatives *geometrically* (a matched 2-25 km donut
    around each event, 45% of negatives). This arm mines them **by model
    difficulty** instead, which is the classic formulation and targets a different
    population: Stage 5 §5 measured that false positives are diffuse across 19,625
    segments and are NOT near-misses, so the geometric donut is not reaching them.
    """
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        s = inner_oof_scores(data, cfg, tr_idx, seed + fold, n_inner)
        y = data.y[tr_idx]
        w = data.w[tr_idx].copy()
        neg = y == 0
        if neg.any():
            w[neg] = _preserve_mass(w[neg] * (1.0 + alpha * _rank_pct(s[neg])), w[neg])
        return TrainSet(data.X(tr_idx), y, w)
    return _t


def make_easy_negative_drop_arm(cfg: Config, frac: float, n_inner: int = 2):
    """Delete the `frac` lowest-scoring negatives — the ones the model already
    gets right and which contribute almost no gradient. Tests whether the 10:1
    negative budget is being spent on informative rows."""
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        s = inner_oof_scores(data, cfg, tr_idx, seed + fold, n_inner)
        y = data.y[tr_idx]
        r = _rank_pct(np.where(y == 0, s, np.inf))
        keep = (y == 1) | (r > frac)
        k = tr_idx[keep]
        return TrainSet(data.X(k), data.y[k], data.w[k])
    return _t


def make_hard_positive_arm(cfg: Config, alpha: float, n_inner: int = 2):
    """Upweight the positives the model ranks LOWEST — the difficult-sample mining
    the brief asks for, and the data-level analogue of focal loss.

    Stage 5 §3 is the reason to be sceptical: the hardest positives are the ones
    with ~0.43 mm of rain, which it attributed to non-rainfall triggers, date
    errors, or rain CHIRPS never saw. If that diagnosis is right, this arm is
    upweighting label noise and should LOSE. That makes it a useful test of the
    Stage 5 diagnosis, not just of the technique."""
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        s = inner_oof_scores(data, cfg, tr_idx, seed + fold, n_inner)
        y = data.y[tr_idx]
        w = data.w[tr_idx].copy()
        pos = y == 1
        if pos.any():
            w[pos] = _preserve_mass(w[pos] * (1.0 + alpha * (1.0 - _rank_pct(s[pos]))), w[pos])
        return TrainSet(data.X(tr_idx), y, w)
    return _t
