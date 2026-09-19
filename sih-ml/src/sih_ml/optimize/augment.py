"""Stage 7 §2 — augmentation for a tabular hazard panel.

There is no flip/crop/rotate here, and that is not an oversight. This panel has no
spatial invariance to exploit: absolute location *is* the signal (a segment's
lithology, slope and rainfall cell are its identity), so a mirrored segment is not
another valid segment, it is a fabricated one.

What IS legitimate is augmenting along the axes where the data is genuinely
uncertain. Stage 5 measured exactly one such axis: **rainfall**. CHIRPS is ~25 km
and daily, Stage 5 §3 attributed the dominant false-negative mode partly to "real
rain that CHIRPS missed", and §1 attributed the weak steep-terrain lift to the same
resolution limit. Perturbing rainfall therefore simulates a measurement error we
know exists, which is the honest justification for an augmentation.

Meaning-preservation rule (brief §2: "avoid augmentations that change the meaning
of the target")
---------------------------------------------------------------------------------
Rainfall features are not independent columns — they are windowed integrals of one
underlying process, and `id_ratio_*` are *derived* from them. Jittering `rain_1d_mm`
alone produces a row where the 1-day total contradicts the 3-day total and the
intensity-duration ratio contradicts both: a physically impossible row that teaches
the model a relationship that does not exist. So:

  * ONE multiplicative factor per row is applied across every rainfall window
    (a CHIRPS cell bias is coherent, not independent per accumulation window),
  * `id_ratio_*` scale with it (I is proportional to rain / duration),
  * `id_exceed_*` flags are RECOMPUTED from the jittered ratios rather than carried
    over stale,
  * `days_since_rain` is left alone (a magnitude bias does not move the date of the
    last rain).

Held constant by the physics-preserving arms, and why
-----------------------------------------------------
  * `slope_*`, `elevation_*`, `aspect_*`, `upslope_basin_area_km2` — Copernicus DEM
    at 30 m is effectively exact at segment scale, so jittering it does not model
    any real measurement error.
  * `month`, `doy_sin/cos`, `is_monsoon` — the date is known exactly.
  * `target`, `label_tier`, `label_confidence` — augmenting the label is not
    augmentation.
  * `highway`, `bridge`, `tunnel`, `surface` — categorical facts from OSM.

`gaussian_all` violates all of that on purpose, as a contrast arm.

MEASURED OUTCOME — the contrast arm won, and the reasoning above was wrong
--------------------------------------------------------------------------
The expectation written here before the run was that `gaussian_all` would lose,
because fabricating terrain teaches a relationship that does not exist. **It did
not lose: it produced the largest consistent gain of any augmentation arm, improving
all 5 folds.** The physics-preserving rainfall jitter was flat-to-negative.

The prediction was wrong because it answered the wrong question. Noise on a feature
is not only a claim about measurement error — it is also a **regulariser that
prevents the tree from splitting on an exact value**. Stages 3 and 5 both measured
the failure this attacks: in-sample AP 0.9999, a LOECO leak through repeat-offender
segments, and 464 segments carrying more than one event. Static terrain columns form
an effectively unique per-segment fingerprint, and the model was memorising it.
Blurring those columns is not modelling DEM error, it is destroying the fingerprint.

`gaussian_terrain_only` and `gaussian_rain_only` decompose the effect to test that
explanation rather than leave it as a story. The physics-consistency rule above is
still correct *as a rule about realism*; it is simply not the binding consideration
here, because the binding problem is memorisation, not realism.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from sih_ml.models.dataset import Data
from sih_ml.optimize.harness import TrainSet

# Windowed rainfall accumulations + derived intensity ratios. All scale together.
RAIN_COLS = ["rain_1d_mm", "rain_3d_mm", "rain_7d_mm", "rain_15d_mm", "rain_30d_mm",
             "rain_max_1d_in_3d_mm", "api_mm"]
ID_RATIO_COLS = ["id_ratio_1d", "id_ratio_3d", "id_ratio_7d"]
ID_EXCEED_COLS = ["id_exceed_1d", "id_exceed_3d", "id_exceed_7d"]

# Never perturbed — see module docstring.
FROZEN_COLS = ["elevation_mean", "slope_mean_deg", "slope_max_deg", "aspect_mean_deg",
               "aspect_sin", "aspect_cos", "upslope_basin_area_km2", "length_m",
               "month", "doy_sin", "doy_cos", "is_monsoon", "days_since_rain",
               "bridge", "tunnel", "maxspeed"]


def rainfall_jitter(X: pd.DataFrame, sigma: float, rng: np.random.Generator) -> pd.DataFrame:
    """Multiply every rainfall column of a row by one lognormal(0, sigma) factor.

    Lognormal rather than additive Gaussian because rainfall error is
    multiplicative and rainfall cannot go negative; a factor of exp(N(0, 0.25))
    spans roughly x0.6-x1.6, which is the right order for CHIRPS against gauges in
    complex terrain.
    """
    X = X.copy()
    f = rng.lognormal(mean=0.0, sigma=sigma, size=len(X))
    for c in RAIN_COLS:
        if c in X:
            X[c] = X[c].to_numpy(float) * f
    for c in ID_RATIO_COLS:
        if c in X:
            X[c] = X[c].to_numpy(float) * f
    # recompute the exceedance flags from the jittered ratios; leaving the old
    # flags in place would contradict the very columns they are derived from
    for rc, fc in zip(ID_RATIO_COLS, ID_EXCEED_COLS):
        if rc in X and fc in X:
            X[fc] = (X[rc].to_numpy(float) >= 1.0).astype(X[fc].dtype)
    return X


def gaussian_all(X: pd.DataFrame, sigma: float, rng: np.random.Generator,
                 numeric_cols: list[str]) -> pd.DataFrame:
    """Naive contrast arm: independent N(0, sigma*std) noise on EVERY numeric
    column, including the frozen terrain ones and including each rainfall window
    separately. This is what generic "add noise to tabular data" advice produces.
    It is here to be measured, not recommended."""
    X = X.copy()
    for c in numeric_cols:
        if c not in X:
            continue
        v = X[c].to_numpy(float)
        s = np.nanstd(v)
        if s > 0:
            X[c] = v + rng.normal(0.0, sigma * s, size=len(v))
    return X


def smote_positives(data: Data, tr_idx: np.ndarray, k: int, frac: float,
                    rng: np.random.Generator) -> TrainSet:
    """SMOTE restricted to within-spatial-block positive pairs.

    Vanilla SMOTE interpolates between any two minority rows, which here would
    average a Sikkim landslide with a Bihar flood and emit a row describing
    terrain that exists nowhere. Restricting donors to the same `spatial_block_id`
    keeps synthetic rows inside one geographic/lithological regime.

    Categoricals take the seed row's value (interpolating a category is
    meaningless). Synthetic rows carry the mean of the two parents' confidence
    weights, so fabricated data never outranks observed data.
    """
    y = data.y[tr_idx]
    pos_rel = np.where(y == 1)[0]
    if len(pos_rel) < 2:
        return TrainSet(data.X(tr_idx), y, data.w[tr_idx])

    blocks = data.panel["spatial_block_id"].to_numpy()[tr_idx]
    num_cols = [c for c in data.features if c not in data.categorical]
    Xtr = data.X(tr_idx)
    Xpos_num = Xtr.iloc[pos_rel][num_cols].to_numpy(float)

    by_block: dict = {}
    for i, b in enumerate(blocks[pos_rel]):
        by_block.setdefault(b, []).append(i)

    n_new = int(round(frac * len(pos_rel)))
    rows, w_new = [], []
    seeds = rng.choice(len(pos_rel), size=n_new, replace=True) if n_new else []
    w_pos = data.w[tr_idx][pos_rel]
    for i in seeds:
        pool = by_block.get(blocks[pos_rel][i], [])
        pool = [j for j in pool if j != i]
        if not pool:
            continue                      # a lone positive in its block has no donor
        j = int(rng.choice(pool[:k] if len(pool) > k else pool))
        lam = float(rng.random())
        rows.append((i, j, lam))
        w_new.append(float((w_pos[i] + w_pos[j]) / 2.0))
    if not rows:
        return TrainSet(Xtr, y, data.w[tr_idx])

    ii = np.array([r[0] for r in rows]); jj = np.array([r[1] for r in rows])
    lam = np.array([r[2] for r in rows])[:, None]
    synth_num = Xpos_num[ii] + lam * (Xpos_num[jj] - Xpos_num[ii])

    synth = Xtr.iloc[pos_rel[ii]].copy().reset_index(drop=True)
    synth[num_cols] = synth_num
    X_aug = pd.concat([Xtr, synth], ignore_index=True)
    # preserve the categorical dtypes pandas drops across concat
    for c in data.categorical:
        if c in X_aug:
            X_aug[c] = X_aug[c].astype("category")
    y_aug = np.concatenate([y, np.ones(len(synth), int)])
    w_aug = np.concatenate([data.w[tr_idx], np.array(w_new, float)])
    return TrainSet(X_aug, y_aug, w_aug)


# --------------------------------------------------------------------------- #
# Arm factories
# --------------------------------------------------------------------------- #
def make_rainfall_jitter_arm(sigma: float):
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        rng = np.random.default_rng(seed + 5000 + fold)
        return TrainSet(rainfall_jitter(data.X(tr_idx), sigma, rng),
                        data.y[tr_idx], data.w[tr_idx])
    return _t


def make_gaussian_all_arm(sigma: float):
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        rng = np.random.default_rng(seed + 6000 + fold)
        num = [c for c in data.features if c not in data.categorical]
        return TrainSet(gaussian_all(data.X(tr_idx), sigma, rng, num),
                        data.y[tr_idx], data.w[tr_idx])
    return _t


# --- decomposition of the gaussian_all result (see module docstring) ----------
# Static, per-segment, effectively exact — the columns that form the fingerprint.
TERRAIN_COLS = ["elevation_mean", "slope_mean_deg", "slope_max_deg", "aspect_mean_deg",
                "aspect_sin", "aspect_cos", "upslope_basin_area_km2", "length_m",
                "distance_to_nearest_river_m", "nearest_river_order",
                "nearest_river_discharge_cms", "cell_dist_m", "maxspeed",
                "soil_clay_0_5cm_pct", "soil_sand_0_5cm_pct", "soil_silt_0_5cm_pct",
                "soil_soc_0_5cm_dg_kg", "soil_bdod_0_5cm_cg_cm3",
                "soil_cfvo_0_5cm_cm3_dm3", "soil_phh2o_0_5cm_ph10"]


def make_gaussian_subset_arm(sigma: float, cols: list[str], name: str):
    """Independent Gaussian noise on a NAMED SUBSET of columns.

    Used to answer "where did the gaussian_all gain come from": if the mechanism is
    anti-fingerprinting regularisation, noise on the static terrain columns should
    reproduce most of it and noise on rainfall alone should not.
    """
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        rng = np.random.default_rng(seed + 6500 + fold)
        use = [c for c in cols if c in data.features]
        return TrainSet(gaussian_all(data.X(tr_idx), sigma, rng, use),
                        data.y[tr_idx], data.w[tr_idx])
    _t.__name__ = name
    return _t


def make_smote_arm(k: int, frac: float):
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        rng = np.random.default_rng(seed + 7000 + fold)
        return smote_positives(data, tr_idx, k, frac, rng)
    return _t


def make_jitter_plus_original_arm(sigma: float):
    """Append a jittered COPY of the training rows instead of replacing them, so
    the model sees both the observed value and its uncertainty envelope. This is
    the closest tabular analogue of image augmentation as usually practised
    (original + transformed), at 2x the training rows."""
    def _t(data: Data, tr_idx, fold, seed) -> TrainSet:
        rng = np.random.default_rng(seed + 8000 + fold)
        X0 = data.X(tr_idx)
        X1 = rainfall_jitter(X0, sigma, rng)
        X = pd.concat([X0, X1], ignore_index=True)
        for c in data.categorical:
            if c in X:
                X[c] = X[c].astype("category")
        return TrainSet(X, np.concatenate([data.y[tr_idx]] * 2),
                        np.concatenate([data.w[tr_idx]] * 2))
    return _t
