"""Stage 8 §3 — robustness of the frozen final model.

None of these probes can change the model. They exist to establish *where it breaks*
before a deployment finds out on its behalf.

The probes, and the question each answers:

  counterfactual_rainfall  If we delete the rain, does the risk go away? For a model
                           sold as "rainfall-triggered disruption", a positive that
                           stays positive under zero rainfall was never a rainfall
                           prediction. This is the sharpest single test in the suite.
  feature_group_ablation   Which input, if a live feed dropped it, takes the model
                           down? Answers the operational question "what must the
                           pipeline guarantee".
  perturbation_sweep       How fast does skill decay as inputs get noisier? Deployment
                           rainfall will be a forecast, not an observation.
  edge_cases               Where does it behave worst — zero rain, extreme rain,
                           missing soil, bridges, unseen categories.
  monotonicity_check       The model declares 10 monotone rainfall constraints.
                           Verify empirically rather than trusting the flag.
  risk_coverage            If we only alert on the most confident predictions, does
                           precision actually rise? This is what makes a high-FP model
                           usable in practice.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score

from sih_ml.models.dataset import Data
from sih_ml.optimize.augment import ID_EXCEED_COLS, ID_RATIO_COLS, RAIN_COLS
from sih_ml.utils.common import get_logger

log = get_logger("stage8.robust")

FEATURE_GROUPS = {
    "rainfall": RAIN_COLS + ID_RATIO_COLS + ID_EXCEED_COLS + ["days_since_rain"],
    "terrain": ["elevation_mean", "slope_mean_deg", "slope_max_deg", "aspect_mean_deg",
                "aspect_sin", "aspect_cos"],
    "soil": ["soil_clay_0_5cm_pct", "soil_sand_0_5cm_pct", "soil_silt_0_5cm_pct",
             "soil_soc_0_5cm_dg_kg", "soil_bdod_0_5cm_cg_cm3", "soil_cfvo_0_5cm_cm3_dm3",
             "soil_phh2o_0_5cm_ph10", "soil_is_missing"],
    "hydrology": ["distance_to_nearest_river_m", "nearest_river_order",
                  "nearest_river_discharge_cms", "upslope_basin_area_km2"],
    "road": ["highway", "surface", "bridge", "tunnel", "maxspeed", "length_m"],
    "seasonal": ["month", "doy_sin", "doy_cos", "is_monsoon"],
    "landcover_lithology": ["landcover_class", "lithology_class"],
    # Distance from the segment to the centre of its CHIRPS cell: a statement about
    # how trustworthy that row's rainfall is, not a rainfall value. Kept out of the
    # "rainfall" group so the rainfall ablation measures rainfall alone.
    "rainfall_provenance": ["cell_dist_m"],
}


def _ap(y, p):
    return float(average_precision_score(y, p)) if np.asarray(y).sum() else float("nan")


def _fill_category(col: pd.Series, value: str) -> pd.Categorical:
    """Set every row of a categorical column to `value`.

    `dataset.load_data` already fills NaN with the literal "__missing__", so that
    level is usually present; appending it unconditionally raises "Categorical
    categories must be unique".
    """
    cats = list(col.cat.categories)
    if value not in cats:
        cats = cats + [value]
    return pd.Categorical([value] * len(col), categories=cats)


def counterfactual_rainfall(data: Data, model, idx: np.ndarray,
                            highlight_mask: np.ndarray | None = None) -> dict:
    """Zero every rainfall input and re-score. Nothing else changes.

    A rainfall-triggered model should collapse toward its terrain prior. Rows whose
    score barely moves are being predicted from *identity*, not from weather — and if
    those rows are the ones being celebrated, the celebration is misplaced.

    Both sides use RAW booster output, so the comparison is like-for-like. The raw
    AP differs slightly from the headline calibrated AP because per-slope isotonic
    calibration is only piecewise monotone and can reorder across strata.
    """
    X = data.X(idx).copy()
    base = model.predict(X)
    for c in RAIN_COLS + ID_RATIO_COLS:
        if c in X:
            X[c] = 0.0
    for c in ID_EXCEED_COLS:
        if c in X:
            X[c] = 0
    if "days_since_rain" in X:
        X["days_since_rain"] = float(np.nanmax(data.X(idx)["days_since_rain"].to_numpy(float)))
    dry = model.predict(X)

    y = data.y[idx]
    out = {
        "AP_observed": _ap(y, base), "AP_zero_rain": _ap(y, dry),
        "mean_score_observed": float(base.mean()), "mean_score_zero_rain": float(dry.mean()),
        "positives_mean_drop": float((base[y == 1] - dry[y == 1]).mean()) if y.sum() else np.nan,
        "positives_median_retained_frac": (float(np.median(dry[y == 1] / np.clip(base[y == 1], 1e-9, None)))
                                           if y.sum() else np.nan),
        "negatives_mean_drop": float((base[y == 0] - dry[y == 0]).mean()),
    }
    if highlight_mask is not None and highlight_mask.any():
        h = highlight_mask
        out["highlight"] = {
            "n": int(h.sum()),
            "score_observed": [float(x) for x in base[h]],
            "score_zero_rain": [float(x) for x in dry[h]],
            "retained_frac": [float(a / max(b, 1e-9)) for a, b in zip(dry[h], base[h])],
            "percentile_observed": [float((base < x).mean()) for x in base[h]],
            "percentile_zero_rain": [float((dry < x).mean()) for x in dry[h]],
        }
    return out


def feature_group_ablation(data: Data, model, idx: np.ndarray) -> pd.DataFrame:
    """Blank one feature group at a time (NaN for numeric, unseen level for
    categorical) and measure the damage. LightGBM handles NaN natively, so this is
    the same code path a live pipeline with a dead feed would take."""
    y = data.y[idx]
    X0 = data.X(idx)
    base = _ap(y, model.predict(X0))
    rows = [{"group": "(none — baseline)", "n_cols": 0, "AP": base, "delta": 0.0,
             "pct_of_baseline": 100.0}]
    for g, cols in FEATURE_GROUPS.items():
        X = X0.copy()
        present = [c for c in cols if c in X]
        for c in present:
            if c in data.categorical:
                X[c] = _fill_category(X0[c], "__missing__")
            else:
                X[c] = np.nan
        ap = _ap(y, model.predict(X))
        rows.append({"group": g, "n_cols": len(present), "AP": ap, "delta": ap - base,
                     "pct_of_baseline": 100.0 * ap / base if base else np.nan})
    return pd.DataFrame(rows).sort_values("AP")


def perturbation_sweep(data: Data, model, idx: np.ndarray,
                       sigmas=(0.05, 0.1, 0.25, 0.5, 1.0), seed: int = 0) -> pd.DataFrame:
    """Multiplicative lognormal noise on rainfall at INFERENCE time.

    Deployment will not have CHIRPS observations for tomorrow — it will have a
    forecast. This estimates how much skill survives that substitution, treating
    forecast error as a multiplicative bias.
    """
    y = data.y[idx]
    X0 = data.X(idx)
    base = _ap(y, model.predict(X0))
    rows = [{"sigma": 0.0, "AP": base, "pct_of_clean": 100.0, "roc_auc": float(
        roc_auc_score(y, model.predict(X0))) if 0 < y.sum() < len(y) else np.nan}]
    for s in sigmas:
        rng = np.random.default_rng(seed)
        X = X0.copy()
        f = rng.lognormal(0.0, s, size=len(X))
        for c in RAIN_COLS + ID_RATIO_COLS:
            if c in X:
                X[c] = X[c].to_numpy(float) * f
        for rc, fc in zip(ID_RATIO_COLS, ID_EXCEED_COLS):
            if rc in X and fc in X:
                X[fc] = (X[rc].to_numpy(float) >= 1.0).astype(X0[fc].dtype)
        p = model.predict(X)
        rows.append({"sigma": s, "AP": _ap(y, p),
                     "pct_of_clean": 100.0 * _ap(y, p) / base if base else np.nan,
                     "roc_auc": float(roc_auc_score(y, p)) if 0 < y.sum() < len(y) else np.nan})
    return pd.DataFrame(rows)


def edge_cases(data: Data, model, idx: np.ndarray, threshold: float) -> pd.DataFrame:
    """Slice the test set by the conditions a deployment will actually hit."""
    P = data.panel.iloc[idx]
    y = data.y[idx]
    p = model.predict(data.X(idx))
    rows = []

    def add(name, m, note=""):
        m = np.asarray(m, bool)
        if m.sum() < 20:
            return
        yhat = (p[m] >= threshold).astype(int)
        tp = int(((yhat == 1) & (y[m] == 1)).sum()); fp = int(((yhat == 1) & (y[m] == 0)).sum())
        fn = int(((yhat == 0) & (y[m] == 1)).sum())
        rows.append({"case": name, "n": int(m.sum()), "n_pos": int(y[m].sum()),
                     "base_rate": float(y[m].mean()),
                     "AP": _ap(y[m], p[m]),
                     "AP_over_base": (_ap(y[m], p[m]) / y[m].mean()) if y[m].mean() else np.nan,
                     "mean_score": float(p[m].mean()),
                     "recall": tp / max(1, tp + fn), "precision": tp / max(1, tp + fp),
                     "note": note})

    r1 = np.nan_to_num(P["rain_1d_mm"].to_numpy(float))
    r7 = np.nan_to_num(P["rain_7d_mm"].to_numpy(float))
    s = np.nan_to_num(P["slope_mean_deg"].to_numpy(float))
    add("all test rows", np.ones(len(y), bool))
    add("zero rain (1d = 0)", r1 <= 0.0, "cannot be rainfall-triggered on the day")
    add("bone dry (7d = 0)", r7 <= 0.0, "no rain all week")
    add("extreme rain (1d, top 1%)", r1 >= np.quantile(r1, 0.99))
    add("extreme rain (7d, top 1%)", r7 >= np.quantile(r7, 0.99))
    add("soil NODATA", P["soil_is_missing"].to_numpy().astype(bool))
    add("bridges", P["bridge"].to_numpy().astype(bool))
    add("tunnels", P["tunnel"].to_numpy().astype(bool))
    add("very steep (slope >= 30)", s >= 30)
    add("flat (slope < 2.5)", s < 2.5)
    add("dry season", ~P["is_monsoon"].to_numpy().astype(bool))
    add("monsoon", P["is_monsoon"].to_numpy().astype(bool))
    return pd.DataFrame(rows)


def unseen_category_probe(data: Data, model, idx: np.ndarray) -> pd.DataFrame:
    """Inject a category the model has never seen, one column at a time.

    A new OSM `highway` value or a lithology class absent from the corridor sample is
    a realistic production event. The question is whether it degrades gracefully or
    throws.
    """
    y = data.y[idx]
    X0 = data.X(idx)
    base = _ap(y, model.predict(X0))
    rows = []
    for c in data.categorical:
        if c not in X0:
            continue
        X = X0.copy()
        X[c] = _fill_category(X0[c], "__never_seen__")
        try:
            ap = _ap(y, model.predict(X))
            err = ""
        except Exception as e:                       # noqa: BLE001 - reporting the failure IS the result
            ap, err = float("nan"), f"{type(e).__name__}: {e}"
        rows.append({"column": c, "AP": ap, "delta": ap - base, "error": err})
    return pd.DataFrame(rows)


def monotonicity_check(data: Data, model, idx: np.ndarray, cols: list[str],
                       factors=(1.0, 1.25, 1.5, 2.0, 4.0), n: int = 3000,
                       seed: int = 0, update_exceed_flags: bool = True) -> pd.DataFrame:
    """The config declares 10 rainfall features monotone-increasing. Verify it.

    Rainfall is scaled up coherently (all windows together, ID ratios with them) and
    the score must never decrease.

    `update_exceed_flags` is the decisive switch. The `id_exceed_*` flags are
    *derived* from `id_ratio_*` but are **not** in the monotone list, so recomputing
    them lets more rain flip a flag the model may have learned a negative
    relationship with — producing an apparent monotonicity violation that is not a
    LightGBM failure at all. Running both variants separates "the constraint is
    broken" from "an unconstrained derived feature is fighting it".
    """
    rng = np.random.default_rng(seed)
    sel = idx if len(idx) <= n else rng.choice(idx, size=n, replace=False)
    X0 = data.X(sel)
    prev = model.predict(X0)
    rows = []
    for f in factors[1:]:
        X = X0.copy()
        for c in cols:
            if c in X:
                X[c] = X[c].to_numpy(float) * f
        if update_exceed_flags:
            for rc, fc in zip(ID_RATIO_COLS, ID_EXCEED_COLS):
                if rc in X and fc in X:
                    X[fc] = (X[rc].to_numpy(float) >= 1.0).astype(X0[fc].dtype)
        cur = model.predict(X)
        viol = cur < prev - 1e-9
        rows.append({"rain_multiplier": f, "n": int(len(sel)),
                     "exceed_flags_updated": update_exceed_flags,
                     "violations": int(viol.sum()),
                     "violation_rate": float(viol.mean()),
                     "max_violation": float(np.max(prev - cur)) if viol.any() else 0.0,
                     "mean_score": float(cur.mean())})
        prev = cur
    return pd.DataFrame(rows)


def steep_metrics(data: Data, idx: np.ndarray, p: np.ndarray,
                  slope_deg: float = 10.0) -> dict:
    """Stage 5 §1's metric: performance confined to the terrain where roads fail.

    Global AP on this panel is inflated by separating plains from hills — a
    distinction routing already has for free — so this is the number that describes
    operational value.
    """
    s = np.nan_to_num(data.panel["slope_mean_deg"].to_numpy(float)[idx], nan=0.0)
    m = s >= slope_deg
    y = data.y[idx]
    if not m.sum() or not y[m].sum():
        return {}
    base = float(y[m].mean())
    k = max(1, int(0.10 * m.sum()))
    top = np.argsort(-p[m])[:k]
    return {
        "steep_n": int(m.sum()), "steep_base_rate": base,
        "steep_AP": float(average_precision_score(y[m], p[m])),
        "steep_AP_over_base": float(average_precision_score(y[m], p[m]) / base),
        "steep_roc_auc": (float(roc_auc_score(y[m], p[m]))
                          if 0 < y[m].sum() < m.sum() else float("nan")),
        "steep_lift@10pct": float(y[m][top].mean() / base),
    }


def risk_coverage(y: np.ndarray, p: np.ndarray,
                  coverages=(0.01, 0.02, 0.05, 0.10, 0.20, 0.30, 0.50, 1.0)) -> pd.DataFrame:
    """Selective prediction: alert only on the top-scoring fraction.

    Stage 7 measured 32.6% of negatives flagged at the cost-optimal threshold. The
    practical answer to a high false-alarm rate is usually to alert on fewer, more
    confident rows — this quantifies exactly what that buys and costs.
    """
    order = np.argsort(-p)
    n, base = len(y), y.mean()
    rows = []
    for c in coverages:
        k = max(1, int(round(c * n)))
        sel = order[:k]
        rows.append({"coverage": c, "n_alerts": k,
                     "precision": float(y[sel].mean()),
                     "recall": float(y[sel].sum() / max(1, y.sum())),
                     "lift": float(y[sel].mean() / base) if base else np.nan,
                     "score_threshold": float(p[sel][-1])})
    return pd.DataFrame(rows)


def failure_cases(data: Data, idx: np.ndarray, p: np.ndarray, threshold: float,
                  k: int = 15) -> dict:
    """The worst false negatives and false positives, with the features that explain
    them — so failures are named, not just counted."""
    P = data.panel.iloc[idx].copy()
    y = data.y[idx]
    P = P.assign(score=p, y=y)
    cols = ["segment_id", "date", "score", "label_tier", "hazard", "rain_1d_mm",
            "rain_7d_mm", "api_mm", "slope_mean_deg", "elevation_mean", "highway",
            "label_confidence"]
    cols = [c for c in cols if c in P.columns]
    fn = P[(P.y == 1) & (P.score < threshold)].nsmallest(k, "score")[cols]
    fp = P[(P.y == 0) & (P.score >= threshold)].nlargest(k, "score")[cols]
    return {"worst_false_negatives": fn, "worst_false_positives": fp,
            "n_fn": int(((y == 1) & (p < threshold)).sum()),
            "n_fp": int(((y == 0) & (p >= threshold)).sum())}
