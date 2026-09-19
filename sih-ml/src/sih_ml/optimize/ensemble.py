"""Stage 7 §3/§5 — ensembling.

Why this is the one model-side change with a measured reason to work: Stage 3
found logistic regression at AP 0.318 against LightGBM's 0.247 on identical OOF
rows. A linear model beating a GBDT is not a quirk — it says the usable structure
is mostly additive and the trees are spending capacity on interactions that do not
generalize across blocks. Two models that disagree *for a reason* are the textbook
case where blending helps, unlike stacking two tuned GBDTs.

The `rain_x_terrain` rule is included as a third member because it is completely
non-learned, so whatever it contributes cannot be an artifact of fitting.

Honest weight selection
-----------------------
Picking blend weights on the same out-of-fold predictions you then report is
selection-on-evaluation, and it always produces a "gain". Weights here are chosen
**leave-one-fold-out**: fold k's blended score uses weights fitted on folds != k.
No fold is scored by a weight that saw it. This costs nothing in compute (the
member predictions already exist) and it is the difference between a real number
and a flattering one.

Scores are combined as **within-fold percentile ranks**, not raw probabilities: the
members live on wildly different scales (a logistic probability, a GBDT probability
and an unbounded rule score) and AP depends only on ordering, so rank-averaging is
both scale-free and exactly what the metric rewards. The blend is therefore a
ranker; `calibrate.py` is what turns it back into a probability.
"""
from __future__ import annotations

import itertools

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score

from sih_ml.models.baselines import REGISTRY
from sih_ml.models.dataset import Data
from sih_ml.models.linear_baseline import LinearBaseline
from sih_ml.utils.common import Config, get_logger

log = get_logger("stage7.ens")


def _rank_within(v: np.ndarray) -> np.ndarray:
    return pd.Series(v).rank(pct=True, method="average").to_numpy()


def logistic_oof(data: Data, cfg: Config, folds: list[int], seed: int = 42) -> np.ndarray:
    """Logistic-regression OOF over the SAME folds, with the same buffer policy."""
    oof = np.full(len(data.panel), np.nan)
    for k in folds:
        tr, va = data.spatial_fold_indices(k, drop_buffer=cfg.cv.drop_buffer_rows)
        m = LinearBaseline(data.spec, C=0.1, seed=seed + k)
        m.fit(data.X(tr), data.y[tr], data.w[tr])
        oof[va] = m.predict(data.X(va))
        log.info("  logistic fold %d: AP=%.4f", k,
                 average_precision_score(data.y[va], oof[va]))
    return oof


def rule_scores(data: Data, name: str = "rain_x_terrain") -> np.ndarray:
    """Non-learned rule score for every row — no fitting, so no fold structure."""
    return np.asarray(REGISTRY[name](data.X()), float)


def _weight_grid(n_members: int, step: float) -> list[tuple]:
    """All non-negative weights on the simplex at the given step."""
    m = int(round(1.0 / step))
    grid = []
    for combo in itertools.product(range(m + 1), repeat=n_members):
        if sum(combo) == m:
            grid.append(tuple(c / m for c in combo))
    return grid


def blend_oof(members: dict[str, np.ndarray], data: Data, fold_of: np.ndarray,
              folds: list[int], step: float = 0.1) -> dict:
    """Leave-one-fold-out weighted rank blend.

    `members` maps name -> full-length OOF score array (NaN outside scored rows).
    Returns per-fold AP for the blend plus the weights chosen for each fold.
    """
    names = list(members)
    # per-fold percentile ranks for every member
    ranks: dict[int, dict[str, np.ndarray]] = {}
    ytrue: dict[int, np.ndarray] = {}
    idx_of: dict[int, np.ndarray] = {}
    for f in folds:
        idx = np.where(fold_of == f)[0]
        idx_of[f] = idx
        ytrue[f] = data.y[idx]
        ranks[f] = {n: _rank_within(np.nan_to_num(members[n][idx], nan=0.0)) for n in names}

    grid = _weight_grid(len(names), step)

    def ap_for(f: int, w: tuple) -> float:
        s = sum(wi * ranks[f][n] for wi, n in zip(w, names))
        return float(average_precision_score(ytrue[f], s)) if ytrue[f].sum() else np.nan

    per_fold_ap, chosen, blended = {}, {}, np.full(len(data.panel), np.nan)
    for f in folds:
        others = [g for g in folds if g != f]
        best_w, best_v = None, -np.inf
        for w in grid:
            v = float(np.nanmean([ap_for(g, w) for g in others]))
            if v > best_v:
                best_v, best_w = v, w
        per_fold_ap[f] = ap_for(f, best_w)
        chosen[f] = dict(zip(names, best_w))
        blended[idx_of[f]] = sum(wi * ranks[f][n] for wi, n in zip(best_w, names))

    # a single "consensus" weight, fitted on ALL folds, for shipping. Reported for
    # transparency only — its in-sample AP is NOT the number quoted anywhere.
    best_w, best_v = None, -np.inf
    for w in grid:
        v = float(np.nanmean([ap_for(f, w) for f in folds]))
        if v > best_v:
            best_v, best_w = v, w

    vals = [per_fold_ap[f] for f in folds]
    return {
        "fold_ap": per_fold_ap,
        "mean_AP": float(np.nanmean(vals)),
        "std_AP": float(np.nanstd(vals)),
        "weights_per_fold": chosen,
        "consensus_weights": dict(zip(names, best_w)),
        "consensus_insample_AP": float(best_v),
        "members": names,
        "oof": blended,
    }


def member_solo_ap(members: dict[str, np.ndarray], data: Data,
                   fold_of: np.ndarray, folds: list[int]) -> dict:
    """Each member's own per-fold AP, so the blend's gain is attributable."""
    out = {}
    for n, v in members.items():
        aps = {}
        for f in folds:
            idx = np.where(fold_of == f)[0]
            y = data.y[idx]
            aps[f] = (float(average_precision_score(y, np.nan_to_num(v[idx], nan=0.0)))
                      if y.sum() else np.nan)
        out[n] = {"fold_ap": aps, "mean_AP": float(np.nanmean(list(aps.values())))}
    return out
