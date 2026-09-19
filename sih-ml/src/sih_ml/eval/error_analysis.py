"""Stage 5 — systematic evaluation + error analysis.

Everything here is computed from ACTUAL model outputs (the spatial-CV OOF
predictions written by Stage 4, plus fresh in-sample / temporal-OOT scores).
Nothing is estimated. The locked `final_test` split is NOT touched — opening it
to guide improvements would invalidate Stage 8.

Sections
  A  stratified ranking performance        (where is the model strong/weak?)
  B  per-event detection                   (would we have flagged the real event?)
  C  false-negative vs true-positive probe (why do we miss?)
  D  false-positive structure              (are FPs chronic? near-misses?)
  E  label-noise ceiling probe             (is the limit the model or the labels?)
  F  data-quality scan                     (duplicates, conflicts, missingness)
  G  train vs held-out vs out-of-time      (overfit / underfit / leakage)
  H  calibration by stratum
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score

from sih_ml.eval.metrics import expected_calibration_error
from sih_ml.utils.common import get_logger

log = get_logger("error_analysis")

MIN_STRATUM_N = 200          # don't report a stratum thinner than this
MIN_STRATUM_POS = 20         # ...or with too few positives for AP to mean anything


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def _safe_metrics(y, p) -> dict:
    y = np.asarray(y, int)
    p = np.asarray(p, float)
    out = {"n": int(len(y)), "n_pos": int(y.sum()), "base_rate": float(y.mean()) if len(y) else np.nan}
    if y.sum() == 0 or y.sum() == len(y):
        out["AP"] = np.nan
        out["ROC_AUC"] = np.nan
        out["lift_vs_chance"] = np.nan
    else:
        out["AP"] = float(average_precision_score(y, p))
        out["ROC_AUC"] = float(roc_auc_score(y, p))
        out["lift_vs_chance"] = float(out["AP"] / out["base_rate"]) if out["base_rate"] else np.nan
    return out


def _qbucket(s: pd.Series, q: int = 4, label: str = "q") -> pd.Series:
    """Quantile buckets that survive heavy ties (rainfall is mostly zeros)."""
    try:
        return pd.qcut(s, q, duplicates="drop").astype(str)
    except Exception:
        return pd.Series([f"{label}_all"] * len(s), index=s.index)


def _std_mean_diff(a: pd.Series, b: pd.Series) -> float:
    """Cohen's d — effect size of the difference between two groups."""
    a, b = a.dropna(), b.dropna()
    if len(a) < 2 or len(b) < 2:
        return np.nan
    pooled = np.sqrt((a.var(ddof=1) + b.var(ddof=1)) / 2)
    return float((a.mean() - b.mean()) / pooled) if pooled > 0 else np.nan


# --------------------------------------------------------------------------- #
# A — stratified ranking performance
# --------------------------------------------------------------------------- #
def stratified_performance(df: pd.DataFrame, score_col: str = "p_cal") -> pd.DataFrame:
    """AP / ROC-AUC within each stratum. A stratum where AP ~= base rate means the
    model has no usable signal there, regardless of the global number."""
    strata: dict[str, pd.Series] = {
        "label_tier": df["label_tier"],
        "label_source": df["label_source"],
        "hazard": df["hazard"].where(df.target == 1, "n/a (negative)"),
        "persist_day": df["persist_day"].where(df.target == 1, -1).astype("Int64").astype(str),
        "season": np.where(df["is_monsoon"] == 1, "monsoon (Jun-Sep)", "dry"),
        "spatial_fold": df["spatial_fold"].astype(str),
        "slope_quartile": _qbucket(df["slope_mean_deg"]),
        "rain_3d_quartile": _qbucket(df["rain_3d_mm"]),
        "api_quartile": _qbucket(df["api_mm"]),
        "elevation_quartile": _qbucket(df["elevation_mean"]),
        "highway": df["highway"].astype(str),
        "lithology_class": df["lithology_class"].astype(str),
        "soil_missing": df["soil_is_missing"].map({0: "soil present", 1: "soil NODATA"}),
    }
    rows = []
    for name, col in strata.items():
        col = pd.Series(col, index=df.index).fillna("__missing__")
        for value, g in df.groupby(col, observed=True):
            if len(g) < MIN_STRATUM_N:
                continue
            m = _safe_metrics(g.target, g[score_col])
            if m["n_pos"] < MIN_STRATUM_POS and m["n_pos"] > 0:
                continue
            rows.append({"stratum": name, "value": str(value), **m})
    return pd.DataFrame(rows).sort_values(["stratum", "AP"], na_position="last")


# --------------------------------------------------------------------------- #
# B — per-event detection ("would we have flagged it?")
# --------------------------------------------------------------------------- #
def per_event_detection(df: pd.DataFrame, score_col: str = "p_cal") -> tuple[pd.DataFrame, dict]:
    """For each positive event, on its own date: what is the best rank any of its
    segments achieved among ALL panel rows scored that date?

    CAVEAT stated explicitly: the panel contains only labelled rows (positives +
    sampled negatives), not all 309k corridor segments. So this is rank-within-the
    -scored-sample for that date, an OPTIMISTIC proxy for a live deployment that
    would rank the whole network. It is still the right shape of metric and the
    right way to compare models."""
    pos = df[df.target == 1].dropna(subset=["event_id"])
    if pos.empty:
        return pd.DataFrame(), {}
    # rank within each date (1 = highest score that day)
    df = df.copy()
    df["rank_in_day"] = df.groupby("date")[score_col].rank(ascending=False, method="min")
    df["n_scored_that_day"] = df.groupby("date")[score_col].transform("size")
    pos = df[(df.target == 1) & df.event_id.notna()]

    per_event = (pos.groupby("event_id")
                 .agg(best_rank=("rank_in_day", "min"),
                      n_segments=("segment_id", "nunique"),
                      n_rows=("segment_id", "size"),
                      scored_that_day=("n_scored_that_day", "max"),
                      date=("date", "min"),
                      tier=("label_tier", "first"),
                      source=("label_source", "first"),
                      hazard=("hazard", "first"),
                      max_score=(score_col, "max"),
                      mean_conf=("label_confidence", "mean"),
                      min_snap_m=("snap_dist_m", "min"))
                 .reset_index().sort_values("best_rank"))
    summary = {"n_events": int(len(per_event))}
    for k in (1, 5, 10, 20, 50, 100):
        summary[f"events_detected_in_top{k}"] = int((per_event.best_rank <= k).sum())
        summary[f"frac_detected_in_top{k}"] = float((per_event.best_rank <= k).mean())
    summary["median_best_rank"] = float(per_event.best_rank.median())
    summary["median_scored_per_day"] = float(per_event.scored_that_day.median())
    return per_event, summary


# --------------------------------------------------------------------------- #
# C — false negatives vs true positives
# --------------------------------------------------------------------------- #
FEATURES_TO_PROBE = [
    "rain_1d_mm", "rain_3d_mm", "rain_7d_mm", "rain_15d_mm", "rain_30d_mm",
    "api_mm", "id_ratio_1d", "id_ratio_3d", "days_since_rain",
    "slope_mean_deg", "slope_max_deg", "elevation_mean",
    "distance_to_nearest_river_m", "upslope_basin_area_km2",
    "label_confidence", "snap_dist_m", "cell_dist_m",
]


def fn_vs_tp_probe(df: pd.DataFrame, threshold: float, score_col: str = "p_cal") -> pd.DataFrame:
    """What distinguishes the positives we MISS from the ones we catch?
    Reported as Cohen's d so effects are comparable across units."""
    pos = df[df.target == 1]
    tp = pos[pos[score_col] >= threshold]
    fn = pos[pos[score_col] < threshold]
    rows = []
    for f in FEATURES_TO_PROBE:
        if f not in pos.columns:
            continue
        rows.append({
            "feature": f,
            "tp_median": float(tp[f].median()) if len(tp) else np.nan,
            "fn_median": float(fn[f].median()) if len(fn) else np.nan,
            "cohens_d_tp_minus_fn": _std_mean_diff(tp[f], fn[f]),
            "tp_n": int(tp[f].notna().sum()), "fn_n": int(fn[f].notna().sum()),
        })
    out = pd.DataFrame(rows)
    out["abs_d"] = out.cohens_d_tp_minus_fn.abs()
    return out.sort_values("abs_d", ascending=False).drop(columns="abs_d")


# --------------------------------------------------------------------------- #
# D — false-positive structure
# --------------------------------------------------------------------------- #
def fp_structure(df: pd.DataFrame, threshold: float, score_col: str = "p_cal",
                 near_days: int = 7, near_km: float = 10.0) -> tuple[pd.DataFrame, dict]:
    """Are false positives chronic (same segments over and over) and are they
    actually near real events in space+time (i.e. plausibly UNLABELLED positives
    rather than model errors)?"""
    fp = df[(df.target == 0) & (df[score_col] >= threshold)].copy()
    tn = df[(df.target == 0) & (df[score_col] < threshold)]
    summary = {"n_fp": int(len(fp)), "n_tn": int(len(tn)),
               "fp_rate_among_negatives": float(len(fp) / max(1, len(fp) + len(tn)))}
    if fp.empty:
        return pd.DataFrame(), summary

    by_seg = (fp.groupby("segment_id").size().sort_values(ascending=False)
              .rename("n_fp").reset_index())
    n_neg_by_seg = df[df.target == 0].groupby("segment_id").size().rename("n_scored")
    by_seg = by_seg.merge(n_neg_by_seg, on="segment_id", how="left")
    by_seg["fp_rate"] = by_seg.n_fp / by_seg.n_scored
    summary["n_segments_with_any_fp"] = int(len(by_seg))
    summary["top1pct_segments_share_of_fp"] = float(
        by_seg.n_fp.head(max(1, len(by_seg) // 100)).sum() / len(fp))
    summary["top10pct_segments_share_of_fp"] = float(
        by_seg.n_fp.head(max(1, len(by_seg) // 10)).sum() / len(fp))

    # near-miss check: is this FP within near_km / near_days of a labelled positive?
    pos = df[df.target == 1][["seg_lon", "seg_lat", "date"]].dropna()
    if not pos.empty:
        from sih_ml.utils.geo import haversine_m
        plon, plat = pos.seg_lon.to_numpy(), pos.seg_lat.to_numpy()
        pdate = pd.to_datetime(pos.date).to_numpy()
        flon, flat = fp.seg_lon.to_numpy(), fp.seg_lat.to_numpy()
        fdate = pd.to_datetime(fp.date).to_numpy()
        near = np.zeros(len(fp), dtype=bool)
        for i in range(0, len(plon), 500):
            d = haversine_m(flon[:, None], flat[:, None],
                            plon[None, i:i + 500], plat[None, i:i + 500])
            dt = np.abs((fdate[:, None] - pdate[None, i:i + 500]) / np.timedelta64(1, "D"))
            near |= ((d <= near_km * 1000) & (dt <= near_days)).any(axis=1)
        summary[f"frac_fp_within_{near_km:.0f}km_{near_days}d_of_a_real_event"] = float(near.mean())
        fp["near_real_event"] = near
    return by_seg, summary


# --------------------------------------------------------------------------- #
# E — label-noise ceiling probe
# --------------------------------------------------------------------------- #
def label_noise_probe(df: pd.DataFrame, score_col: str = "p_cal") -> pd.DataFrame:
    """If ranking quality rises sharply as positive labels get more trustworthy
    (closer snap distance / higher confidence), the binding constraint is LABEL
    QUALITY, not model capacity. Each row re-scores the full negative set against
    only the positives in that bucket, so APs are comparable."""
    neg = df[df.target == 0]
    pos = df[df.target == 1]
    rows = []
    for name, col, buckets in [
        ("snap_dist_m", "snap_dist_m", [(0, 500), (500, 2000), (2000, 5000), (5000, 1e9)]),
        ("label_confidence", "label_confidence", [(0, .25), (.25, .35), (.35, .5), (.5, 1.01)]),
    ]:
        for lo, hi in buckets:
            sel = pos[(pos[col] >= lo) & (pos[col] < hi)]
            if len(sel) < MIN_STRATUM_POS:
                continue
            sub = pd.concat([sel, neg])
            m = _safe_metrics(sub.target, sub[score_col])
            rows.append({"probe": name, "bucket": f"[{lo:g}, {hi:g})", **m})
    return pd.DataFrame(rows)


# --------------------------------------------------------------------------- #
# F — data-quality scan
# --------------------------------------------------------------------------- #
def data_quality_scan(df: pd.DataFrame, feature_cols: list[str]) -> dict:
    num_cols = [c for c in feature_cols if pd.api.types.is_numeric_dtype(df[c])]
    # hash the rounded feature vector: grouping by ~47 raw columns overflows
    # pandas' internal group index
    key = pd.util.hash_pandas_object(df[num_cols].round(6), index=False)
    dup_mask = key.duplicated(keep=False)
    out = {
        "n_rows": int(len(df)),
        "n_duplicate_feature_vectors": int(dup_mask.sum()),
    }
    if dup_mask.any():
        conflicting = df[dup_mask].groupby(key[dup_mask], observed=True).target.nunique()
        out["n_duplicate_groups"] = int(len(conflicting))
        out["n_duplicate_groups_with_conflicting_labels"] = int((conflicting > 1).sum())
    out["rows_with_all_rainfall_nan"] = int(
        df[[c for c in ["rain_1d_mm", "rain_3d_mm", "rain_7d_mm"] if c in df]].isna().all(axis=1).sum())
    out["soil_nodata_rate_overall"] = float(df.soil_is_missing.mean())
    out["soil_nodata_rate_positives"] = float(df[df.target == 1].soil_is_missing.mean())
    out["soil_nodata_rate_negatives"] = float(df[df.target == 0].soil_is_missing.mean())
    # repeat-offender segments among positives (the Stage 3 leak driver)
    ppseg = df[df.target == 1].groupby("segment_id").event_id.nunique()
    out["positive_segments"] = int(len(ppseg))
    out["positive_segments_with_multiple_events"] = int((ppseg > 1).sum())
    out["max_events_on_one_segment"] = int(ppseg.max()) if len(ppseg) else 0
    return out


# --------------------------------------------------------------------------- #
# G2 — early-stopping signal integrity
# --------------------------------------------------------------------------- #
def es_leakage_units(data, mcfg) -> pd.DataFrame:
    """At what UNIT does the inner early-stopping split leak?

    Measures, per outer fold, the share of ES *positives* whose segment /
    block+date / event_id / block also appears among TRAIN positives. ~100% on a
    unit means the ES set is just other rows of something the model already
    trained on, so its score is not a validation signal at all."""
    from sih_ml.train import cv as _cv

    P = data.panel
    units = {
        "segment": P["segment_id"].to_numpy(),
        "block+date": np.char.add(np.char.add(P["spatial_block_id"].astype(str).to_numpy(), "|"),
                                  P["date"].astype(str).to_numpy()),
        "event_id": P["event_id"].astype(str).to_numpy(),
        "block": P["spatial_block_id"].astype(str).to_numpy(),
    }
    rows = []
    for k in range(mcfg.cv.n_spatial_folds):
        tr_all, _ = data.spatial_fold_indices(k, drop_buffer=mcfg.cv.drop_buffer_rows)
        blocks = P["spatial_block_id"].to_numpy()[tr_all]
        m_tr, m_es = _cv._inner_earlystop_split(blocks, mcfg.cv.inner_earlystop_block_frac,
                                                mcfg.seed + k, y=data.y[tr_all])
        tr, es = tr_all[m_tr], tr_all[m_es]
        trp, esp = tr[data.y[tr] == 1], es[data.y[es] == 1]
        r = {"fold": k, "n_es_pos": int(len(esp))}
        for name, arr in units.items():
            r[f"es_pos_share_seen_in_train__{name}"] = float(np.isin(arr[esp], arr[trp]).mean())
        rows.append(r)
    return pd.DataFrame(rows)


def es_signal_saturation(data, mcfg, fold_models: dict) -> pd.DataFrame:
    """Three-way AP per fold: TRAIN rows / ES rows / held-out blocks.
    ES AP ~= train AP ~= 1.0 means early stopping has no usable signal."""
    from sih_ml.train import cv as _cv

    rows = []
    for k, model in fold_models.items():
        tr_all, va = data.spatial_fold_indices(k, drop_buffer=mcfg.cv.drop_buffer_rows)
        blocks = data.panel["spatial_block_id"].to_numpy()[tr_all]
        m_tr, m_es = _cv._inner_earlystop_split(blocks, mcfg.cv.inner_earlystop_block_frac,
                                                mcfg.seed + k, y=data.y[tr_all])
        tr, es = tr_all[m_tr], tr_all[m_es]
        rows.append({
            "fold": k, "n_train": int(len(tr)),
            "AP_train": float(average_precision_score(data.y[tr], model.predict(data.X(tr)))),
            "AP_earlystop": float(average_precision_score(data.y[es], model.predict(data.X(es)))),
            "AP_heldout_blocks": float(average_precision_score(data.y[va], model.predict(data.X(va)))),
            "best_iteration": int(model.best_iteration_),
        })
    return pd.DataFrame(rows)


# --------------------------------------------------------------------------- #
# H — calibration by stratum
# --------------------------------------------------------------------------- #
def calibration_by_stratum(df: pd.DataFrame, by: str, score_col: str = "p_cal") -> pd.DataFrame:
    rows = []
    for value, g in df.groupby(by, observed=True):
        if len(g) < MIN_STRATUM_N:
            continue
        rows.append({
            by: str(value), "n": int(len(g)),
            "mean_predicted": float(g[score_col].mean()),
            "observed_rate": float(g.target.mean()),
            "ratio_pred_over_obs": float(g[score_col].mean() / g.target.mean()) if g.target.mean() else np.nan,
            "ECE": expected_calibration_error(g.target.to_numpy(int), g[score_col].to_numpy(float)),
        })
    return pd.DataFrame(rows)
