"""Compose several Stage 7 arms into one, in a fixed, meaningful order.

Arms are not commutative and the order is not arbitrary:

  1. **filters** (drop rows)      — must run first, so later steps operate on the
                                    surviving rows only. Dropping a row after
                                    reweighting it just wastes the reweighting.
  2. **weights** (reweight rows)  — computed on the filtered set. Mining in
                                    particular must see the post-filter population,
                                    or its rank percentiles refer to rows that no
                                    longer exist.
  3. **features** (perturb values)— last among in-place edits, so jitter does not
                                    change what the mining prospector scored.
  4. **rows** (append synthetic)  — genuinely last; synthetic rows should not then
                                    be filtered or re-mined.

Combining winners is itself a hypothesis, not a guarantee: two changes that each
help can easily overlap (both fixing the same errors) or conflict. The composite is
therefore measured by the same paired test as every individual arm, never assumed
to be the sum of its parts.
"""
from __future__ import annotations

import numpy as np

from sih_ml.models.dataset import Data
from sih_ml.optimize.harness import TrainSet


def make_composite_arm(filters=(), weights=(), features=(), rows=()):
    """Build a single transform from step callables.

    filters : (data, tr_idx, fold, seed) -> kept tr_idx
    weights : (data, tr_idx, w, fold, seed) -> new w
    features: (data, X, fold, seed) -> new X
    rows    : (data, tr_idx, X, y, w, fold, seed) -> TrainSet
    """
    def _t(data: Data, tr_idx: np.ndarray, fold: int, seed: int) -> TrainSet:
        idx = tr_idx
        for fn in filters:
            idx = fn(data, idx, fold, seed)

        w = data.w[idx].copy()
        for fn in weights:
            w = fn(data, idx, w, fold, seed)

        X = data.X(idx)
        for fn in features:
            X = fn(data, X, fold, seed)

        y = data.y[idx]
        ts = TrainSet(X, y, w)
        for fn in rows:
            ts = fn(data, idx, ts.X, ts.y, ts.w, fold, seed)
        return ts
    return _t


# --------------------------------------------------------------------------- #
# Step adapters — wrap the standalone arms into composable steps
# --------------------------------------------------------------------------- #
def filter_dedup():
    from sih_ml.optimize.data_opt import dedup_indices
    return lambda data, idx, fold, seed: dedup_indices(data, idx)


def filter_confidence(floor: float):
    def _f(data, idx, fold, seed):
        conf = np.nan_to_num(data.panel["label_confidence"].to_numpy(float)[idx], nan=1.0)
        return idx[(data.y[idx] == 0) | (conf >= floor)]
    return _f


def filter_easy_negatives(cfg, frac: float, n_inner: int = 2):
    from sih_ml.optimize.data_opt import _rank_pct, inner_oof_scores

    def _f(data, idx, fold, seed):
        s = inner_oof_scores(data, cfg, idx, seed + fold, n_inner)
        y = data.y[idx]
        r = _rank_pct(np.where(y == 0, s, np.inf))
        return idx[(y == 1) | (r > frac)]
    return _f


def weight_scheme(scheme: str):
    def _w(data, idx, w, fold, seed):
        base_mean = w.mean()
        if scheme == "uniform":
            w = np.ones_like(w)
        elif scheme == "sqrt":
            w = np.sqrt(np.clip(w, 0, None))
        elif scheme == "square":
            w = np.clip(w, 0, None) ** 2
        else:
            raise ValueError(scheme)
        m = w.mean()
        return w * (base_mean / m) if m > 0 else w
    return _w


def weight_hard_negatives(cfg, alpha: float, n_inner: int = 2):
    from sih_ml.optimize.data_opt import _preserve_mass, _rank_pct, inner_oof_scores

    def _w(data, idx, w, fold, seed):
        s = inner_oof_scores(data, cfg, idx, seed + fold, n_inner)
        neg = data.y[idx] == 0
        w = w.copy()
        if neg.any():
            w[neg] = _preserve_mass(w[neg] * (1.0 + alpha * _rank_pct(s[neg])), w[neg])
        return w
    return _w


def weight_hard_positives(cfg, alpha: float, n_inner: int = 2):
    from sih_ml.optimize.data_opt import _preserve_mass, _rank_pct, inner_oof_scores

    def _w(data, idx, w, fold, seed):
        s = inner_oof_scores(data, cfg, idx, seed + fold, n_inner)
        pos = data.y[idx] == 1
        w = w.copy()
        if pos.any():
            w[pos] = _preserve_mass(w[pos] * (1.0 + alpha * (1.0 - _rank_pct(s[pos]))), w[pos])
        return w
    return _w


def feature_rainfall_jitter(sigma: float):
    from sih_ml.optimize.augment import rainfall_jitter

    def _f(data, X, fold, seed):
        return rainfall_jitter(X, sigma, np.random.default_rng(seed + 5000 + fold))
    return _f


def feature_gaussian_all(sigma: float):
    from sih_ml.optimize.augment import gaussian_all

    def _f(data, X, fold, seed):
        num = [c for c in data.features if c not in data.categorical]
        return gaussian_all(X, sigma, np.random.default_rng(seed + 6000 + fold), num)
    return _f


def feature_gaussian_subset(sigma: float, cols: list):
    from sih_ml.optimize.augment import gaussian_all

    def _f(data, X, fold, seed):
        use = [c for c in cols if c in data.features]
        return gaussian_all(X, sigma, np.random.default_rng(seed + 6500 + fold), use)
    return _f


def rows_smote(k: int, frac: float):
    """SMOTE as a composite step.

    Unlike the standalone arm it must interpolate the ALREADY-TRANSFORMED rows, so
    it takes X/y/w rather than re-reading the panel — otherwise a preceding jitter
    or filter would be silently undone for the synthetic rows.
    """
    import pandas as pd

    from sih_ml.optimize.harness import TrainSet as _TS

    def _r(data, idx, X, y, w, fold, seed):
        rng = np.random.default_rng(seed + 7000 + fold)
        pos = np.where(y == 1)[0]
        if len(pos) < 2:
            return _TS(X, y, w)
        blocks = data.panel["spatial_block_id"].to_numpy()[idx]
        if len(blocks) != len(y):        # rows were appended upstream — skip
            return _TS(X, y, w)
        num_cols = [c for c in data.features if c not in data.categorical]
        Xn = X.iloc[pos][num_cols].to_numpy(float)
        by_block: dict = {}
        for i, b in enumerate(blocks[pos]):
            by_block.setdefault(b, []).append(i)
        rows, wn = [], []
        for i in rng.choice(len(pos), size=int(round(frac * len(pos))), replace=True):
            pool = [j for j in by_block.get(blocks[pos][i], []) if j != i]
            if not pool:
                continue
            j = int(rng.choice(pool[:k] if len(pool) > k else pool))
            rows.append((i, j, float(rng.random())))
            wn.append(float((w[pos][i] + w[pos][j]) / 2.0))
        if not rows:
            return _TS(X, y, w)
        ii = np.array([r[0] for r in rows]); jj = np.array([r[1] for r in rows])
        lam = np.array([r[2] for r in rows])[:, None]
        synth = X.iloc[pos[ii]].copy().reset_index(drop=True)
        synth[num_cols] = Xn[ii] + lam * (Xn[jj] - Xn[ii])
        Xc = pd.concat([X, synth], ignore_index=True)
        for c in data.categorical:
            if c in Xc:
                Xc[c] = Xc[c].astype("category")
        return _TS(Xc, np.concatenate([y, np.ones(len(synth), int)]),
                   np.concatenate([w, np.array(wn, float)]))
    return _r


def rows_jitter_append(sigma: float):
    import pandas as pd

    from sih_ml.optimize.augment import rainfall_jitter

    def _r(data, idx, X, y, w, fold, seed):
        rng = np.random.default_rng(seed + 8000 + fold)
        X1 = rainfall_jitter(X, sigma, rng)
        Xc = pd.concat([X, X1], ignore_index=True)
        for c in data.categorical:
            if c in Xc:
                Xc[c] = Xc[c].astype("category")
        return TrainSet(Xc, np.concatenate([y, y]), np.concatenate([w, w]))
    return _r
