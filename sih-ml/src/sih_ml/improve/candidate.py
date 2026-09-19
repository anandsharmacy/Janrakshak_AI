"""Champion state -> trainable candidate, and the fold-level fit that scores it.

A model in this loop is described by a small STATE dict, and every experiment is ONE
change applied to the champion's state:

    coverage_mask   bool     drop rows whose rainfall cutoff is beyond CHIRPS (D1)
    composite_steps [str]    the Stage 7 training recipe (augmentation / loss / weights)
    lgbm            {k: v}   hyperparameter-level overrides
    add_features    [str]    engineered feature groups
    bag             int      number of seed-bagged boosters averaged at inference

`apply_change` refuses a change that touches more than one key, and a recipe change
that adds or removes more than one step — "change one variable" is enforced where
the candidate is built, not left to discipline.

`fit_fold` reproduces `optimize.harness.fit_one_fold` exactly when bag = 1 and the
train/eval masks equal the model scope (same ES split seed, same transform seed, same
booster seed), which is what lets the loop verify it has reconstructed the Stage 9
champion before measuring anything against it.
"""
from __future__ import annotations

import copy
import time
from dataclasses import dataclass, field

import numpy as np
from sklearn.metrics import average_precision_score, roc_auc_score

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.optimize.augment import ID_EXCEED_COLS, ID_RATIO_COLS, RAIN_COLS, TERRAIN_COLS
from sih_ml.optimize.harness import Arm, _scale_pos_weight, identity_trainset
from sih_ml.train import cv as CV
from sih_ml.utils.common import Config

BAG_SEED_STRIDE = 10_000
KNOWN_KEYS = ("coverage_mask", "composite_steps", "lgbm", "add_features", "bag")
CHANGE_KEYS = ("coverage_mask", "add_step", "remove_step", "lgbm", "add_features", "bag")


def initial_state(cfg: Config) -> dict:
    return {"coverage_mask": False,
            "composite_steps": list(cfg.remediate.composite_steps),
            "lgbm": {}, "add_features": [], "bag": 1}


def apply_change(state: dict, change: dict) -> dict:
    """Return a new state with exactly one change applied."""
    if len(change) != 1:
        raise ValueError(f"an experiment must change exactly one thing, got {list(change)}")
    (k, v), = change.items()
    if k not in CHANGE_KEYS:
        raise ValueError(f"unknown change {k!r}")
    s = copy.deepcopy(state)
    if k == "coverage_mask":
        s["coverage_mask"] = bool(v)
    elif k == "add_step":
        if v in s["composite_steps"]:
            raise ValueError(f"{v} already in recipe")
        s["composite_steps"].append(v)
    elif k == "remove_step":
        if v not in s["composite_steps"]:
            raise ValueError(f"{v} not in recipe")
        s["composite_steps"].remove(v)
    elif k == "lgbm":
        if len(v) != 1:
            raise ValueError("an lgbm change may override one parameter")
        s["lgbm"].update(v)
    elif k == "add_features":
        if v in s["add_features"]:
            raise ValueError(f"{v} already added")
        s["add_features"].append(v)
    elif k == "bag":
        s["bag"] = int(v)
    return s


def n_components(state: dict) -> int:
    """Complexity used as the simplicity tie-break: recipe steps + feature groups +
    overrides + (bag > 1) + coverage fix is NOT counted (it removes rows, adds nothing)."""
    return (len(state["composite_steps"]) + len(state["add_features"])
            + len(state["lgbm"]) + int(state["bag"] > 1))


# --------------------------------------------------------------------------- #
class BaggedModel:
    """Average of seed-bagged boosters. Presents the LGBMBaseline predict contract."""

    def __init__(self, models: list[LGBMBaseline]):
        self.models = models

    def predict(self, X):
        return np.mean([m.predict(X) for m in self.models], axis=0)


@dataclass
class Candidate:
    name: str
    state: dict
    data: Data
    cfg: Config
    arm: Arm
    train_mask: np.ndarray
    eval_mask: np.ndarray
    derived: object | None = None          # has .recompute(X, panel) for derived columns
    notes: list[str] = field(default_factory=list)

    @property
    def monotone(self) -> list[str]:
        return list(self.cfg.lgbm.get("monotone_rainfall_features", []))

    def with_eval_mask(self, mask: np.ndarray, name: str) -> "Candidate":
        c = copy.copy(self)
        c.eval_mask, c.name = np.asarray(mask, bool), name
        return c


def build_candidate(state: dict, name: str, data: Data, cfg: Config, *,
                    coverage: np.ndarray, pctl=None) -> Candidate:
    from sih_ml.train.run_optimize import _composite_from

    lgbm = dict(cfg.lgbm)
    derived = None
    if "rain_local_percentile" in state["add_features"]:
        data = pctl.add_to(data)
        derived = pctl
        lgbm["monotone_rainfall_features"] = [*lgbm["monotone_rainfall_features"],
                                              *pctl.columns]
    for k, v in state["lgbm"].items():
        if k == "static_max_bin":
            mb = int(lgbm.get("max_bin", 255))
            lgbm["max_bin_by_feature"] = [int(v) if f in TERRAIN_COLS else mb
                                          for f in data.features]
        else:
            lgbm[k] = v
    c_cfg = Config({**dict(cfg), "lgbm": lgbm})

    arm, _ = _composite_from(c_cfg, list(state["composite_steps"]), name)
    arm = arm or Arm(name, "baseline", None)

    mask = data.in_scope().copy()
    if state["coverage_mask"]:
        mask &= coverage
    return Candidate(name=name, state=state, data=data, cfg=c_cfg, arm=arm,
                     train_mask=mask, eval_mask=mask.copy(), derived=derived)


# --------------------------------------------------------------------------- #
def _fit_member(c: Candidate, tr_all: np.ndarray, fold: int, seed: int, j: int):
    s = seed + BAG_SEED_STRIDE * j
    m_tr, m_es = CV.make_es_split(c.data, tr_all, c.cfg, s + fold)
    tr, es = tr_all[m_tr], tr_all[m_es]
    ts = (c.arm.transform or identity_trainset)(c.data, tr, fold, s)
    p = dict(c.cfg.lgbm)
    p.update(c.arm.param_overrides)
    p["seed"] = s + fold
    fobj = None
    if c.arm.objective == "focal":
        from sih_ml.optimize.losses import make_focal_objective
        fobj = make_focal_objective(**c.arm.objective_kwargs)
    model = LGBMBaseline(p, c.data.features, c.data.categorical, c.monotone)
    spw = None if fobj is not None else _scale_pos_weight(c.cfg, ts.y)
    model.fit(ts.X, ts.y, ts.w, c.data.X(es), c.data.y[es], c.data.w[es],
              scale_pos_weight=spw, fobj=fobj)
    return model, tr


def fit_fold(c: Candidate, fold: int, seed: int):
    tr_all, va = c.data.spatial_fold_indices(fold, drop_buffer=c.cfg.cv.drop_buffer_rows)
    tr_all, va = tr_all[c.train_mask[tr_all]], va[c.eval_mask[va]]
    members, tr0 = [], None
    for j in range(int(c.state["bag"])):
        m, tr = _fit_member(c, tr_all, fold, seed, j)
        members.append(m)
        tr0 = tr if tr0 is None else tr0
    model = members[0] if len(members) == 1 else BaggedModel(members)
    return model, va, model.predict(c.data.X(va)), tr0


def _ap(y, p):
    return float(average_precision_score(y, p)) if y.sum() else float("nan")


def run(c: Candidate, folds: list[int], seeds: list[int], keep_models: bool = True) -> dict:
    """Every fold x seed. Models are kept for the first seed only (guardrails,
    efficiency, diagnostics); per-seed pooled OOF is kept for all seeds."""
    n = len(c.data.panel)
    ap = {s: {} for s in seeds}
    oof = {s: np.full(n, np.nan) for s in seeds}
    fold_of = np.full(n, -1)
    models, va_of, tr_of, iters = {}, {}, {}, []
    t0 = time.time()
    for s in seeds:
        for f in folds:
            model, va, pred, tr = fit_fold(c, f, s)
            ap[s][f] = _ap(c.data.y[va], pred)
            oof[s][va] = pred
            fold_of[va] = f
            members = model.models if isinstance(model, BaggedModel) else [model]
            iters.append(float(np.mean([m.best_iteration_ or 0 for m in members])))
            if keep_models and s == seeds[0]:
                models[f], va_of[f], tr_of[f] = model, va, tr
    return {"name": c.name, "ap": ap, "oof": oof, "fold_of": fold_of, "models": models,
            "va": va_of, "tr": tr_of, "mean_best_iter": float(np.mean(iters)),
            "fit_sec": time.time() - t0,
            "mean_AP": float(np.nanmean([ap[s][f] for s in seeds for f in folds]))}


def restrict(c: Candidate, res: dict, mask: np.ndarray, name: str) -> tuple[Candidate, dict]:
    """The SAME trained models scored on fewer rows — used when a correctness fix
    changes which rows are evaluated, so the champion can be compared on the
    challenger's rows without retraining it."""
    mask = np.asarray(mask, bool)
    out = dict(res)
    out["name"] = name
    out["oof"] = {s: np.where(mask, p, np.nan) for s, p in res["oof"].items()}
    out["ap"] = {}
    for s, p in out["oof"].items():
        out["ap"][s] = {}
        for f in res["ap"][s]:
            va = np.where((res["fold_of"] == f) & np.isfinite(p))[0]
            out["ap"][s][f] = _ap(c.data.y[va], p[va])
    out["va"] = {f: va[mask[va]] for f, va in res["va"].items()}
    out["mean_AP"] = float(np.nanmean([v for d in out["ap"].values() for v in d.values()]))
    return c.with_eval_mask(mask, name), out


# --------------------------------------------------------------------------- #
def steep_roc(c: Candidate, res: dict, slope_deg: float) -> dict:
    """Mean over seeds of ROC-AUC on pooled OOF steep rows (the Stage 5/9 metric)."""
    slope = np.nan_to_num(c.data.panel["slope_mean_deg"].to_numpy(float), nan=0.0)
    vals = {}
    for s, p in res["oof"].items():
        m = np.isfinite(p) & (slope >= slope_deg)
        y = c.data.y[m]
        if 0 < y.sum() < m.sum():
            vals[s] = float(roc_auc_score(y, p[m]))
    return {"steep_roc": float(np.mean(list(vals.values()))) if vals else float("nan"),
            "steep_roc_per_seed": vals}


def monotonicity(c: Candidate, model, idx: np.ndarray, factors=(1.25, 1.5, 2.0, 4.0),
                 n: int = 3000, seed: int = 0) -> int:
    """Scale all rainfall coherently, re-derive exceed flags AND any engineered
    rainfall-derived columns, count rows whose score went down. Same probe as
    Stage 9's gate, extended so a new derived feature cannot escape it the way
    `id_exceed_*` once did."""
    rng = np.random.default_rng(seed)
    sel = idx if len(idx) <= n else rng.choice(idx, size=n, replace=False)
    X0 = c.data.X(sel)
    prev = model.predict(X0)
    total = 0
    for f in factors:
        X = X0.copy()
        for col in RAIN_COLS + ID_RATIO_COLS:
            if col in X:
                X[col] = X[col].to_numpy(float) * f
        for rc, fc in zip(ID_RATIO_COLS, ID_EXCEED_COLS):
            if rc in X and fc in X:
                X[fc] = (X[rc].to_numpy(float) >= 1.0).astype(X0[fc].dtype)
        if c.derived is not None:
            X = c.derived.recompute(X, c.data.panel)
        cur = model.predict(X)
        total += int((cur < prev - 1e-9).sum())
        prev = cur
    return total
