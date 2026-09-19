"""Stage 7 §5 — calibration (Stage 5 P2).

Stage 5 §6 measured a single global isotonic calibrator being wrong by up to **3x**
depending on region and terrain: predicted/observed was 2.59x on spatial fold 3 and
0.68x on fold 1; by slope it was 3.02x on the flattest band and ~0.95x above 2.5
degrees. Seasonal calibration was already fine, so the defect is spatial/terrain,
not temporal.

This matters more than the AP does. The product turns a calibrated probability into
a routing edge penalty, `W = dist * (1 + lambda * P)`. A 3x inflated probability on
flat roads systematically over-penalises the safe plains route — a *ranking-neutral*
error that changes the recommendation anyway, and one that AP cannot see.

Cross-fitting
-------------
A calibrator scored on the rows it was fitted on always looks well-calibrated. Every
number here is **cross-fitted**: fold k's rows are calibrated by a model fitted on
folds != k. That is also exactly how it would run in production (fit on history,
apply to today), so the measurement matches the deployment.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from sih_ml.eval.metrics import expected_calibration_error
from sih_ml.models.calibration import Calibrator
from sih_ml.models.dataset import Data
from sih_ml.utils.common import get_logger

log = get_logger("stage7.cal")


def slope_stratum(data: Data, bins: list[float]) -> np.ndarray:
    s = np.nan_to_num(data.panel["slope_mean_deg"].to_numpy(float), nan=0.0)
    return np.clip(np.digitize(s, bins[1:-1]), 0, len(bins) - 2)


def _brier(y, p):
    return float(np.mean((np.asarray(p, float) - np.asarray(y, float)) ** 2))


def cross_fitted_calibration(data: Data, oof: np.ndarray, fold_of: np.ndarray,
                             folds: list[int], strata: np.ndarray | None,
                             method: str = "isotonic",
                             target_prior: float | None = None) -> np.ndarray:
    """Calibrate each fold using calibrators fitted on the other folds.

    When `strata` is given, a separate calibrator is fitted per stratum; a stratum
    with too few positives in the fitting folds falls back to the pooled
    calibrator rather than fitting a degenerate one.
    """
    out = np.full(len(oof), np.nan)
    scored = np.isfinite(oof)
    for f in folds:
        fit_idx = np.where(scored & (fold_of != f) & np.isin(fold_of, folds))[0]
        app_idx = np.where(scored & (fold_of == f))[0]
        if len(fit_idx) == 0 or len(app_idx) == 0:
            continue
        prior = float(data.y[fit_idx].mean())

        pooled = Calibrator(method).fit(oof[fit_idx], data.y[fit_idx], prior, target_prior)
        if strata is None:
            out[app_idx] = pooled.transform(oof[app_idx])
            continue

        out[app_idx] = pooled.transform(oof[app_idx])      # default, then refine
        for s in np.unique(strata[app_idx]):
            fi = fit_idx[strata[fit_idx] == s]
            ai = app_idx[strata[app_idx] == s]
            if len(ai) == 0 or len(fi) < 200 or data.y[fi].sum() < 20:
                continue                                   # too thin — keep pooled
            c = Calibrator(method).fit(oof[fi], data.y[fi], float(data.y[fi].mean()),
                                       target_prior)
            out[ai] = c.transform(oof[ai])
    return out


def calibration_table(data: Data, p: np.ndarray, fold_of: np.ndarray,
                      folds: list[int], slope_bins: list[float]) -> pd.DataFrame:
    """Predicted/observed ratio + ECE per stratum — the Stage 5 §6 table, recomputed."""
    scored = np.isfinite(p)
    rows = []

    def add(kind, label, m):
        m = m & scored
        if m.sum() < 50:
            return
        y, q = data.y[m], p[m]
        obs = float(y.mean())
        rows.append({"stratum_type": kind, "stratum": label, "n": int(m.sum()),
                     "n_pos": int(y.sum()), "predicted": float(q.mean()),
                     "observed": obs,
                     "pred_over_obs": float(q.mean() / obs) if obs > 0 else np.nan,
                     "ece": expected_calibration_error(y, q),
                     "brier": _brier(y, q)})

    add("overall", "all", np.ones(len(p), bool))
    for f in folds:
        add("spatial_fold", f"fold {f}", fold_of == f)
    s = np.nan_to_num(data.panel["slope_mean_deg"].to_numpy(float), nan=0.0)
    for i in range(len(slope_bins) - 1):
        lo, hi = slope_bins[i], slope_bins[i + 1]
        add("slope_deg", f"[{lo:g}, {hi:g})", (s >= lo) & (s < hi))
    mon = data.panel["is_monsoon"].to_numpy()
    add("season", "monsoon", mon.astype(bool))
    add("season", "dry", ~mon.astype(bool))
    return pd.DataFrame(rows)


def compare_calibrators(data: Data, oof: np.ndarray, fold_of: np.ndarray,
                        folds: list[int], slope_bins: list[float],
                        target_prior: float | None = None) -> dict:
    """Global vs per-slope-stratum calibration, both cross-fitted.

    The headline is deliberately NOT global ECE — a global calibrator optimises
    global ECE by construction, so that comparison is rigged. What is reported is
    the **worst-stratum** predicted/observed ratio, which is the quantity Stage 5
    flagged and the one the routing layer is exposed to — split into its terrain
    axis (fixable at inference) and its region axis (not), see below.
    """
    strata = slope_stratum(data, slope_bins)
    out = {}
    variants = {
        "uncalibrated": oof,
        "global_isotonic": cross_fitted_calibration(data, oof, fold_of, folds, None,
                                                    target_prior=target_prior),
        "per_slope_isotonic": cross_fitted_calibration(data, oof, fold_of, folds, strata,
                                                       target_prior=target_prior),
    }
    def _worst(tab, kinds):
        r = tab.loc[tab.stratum_type.isin(kinds), "pred_over_obs"].to_numpy(float)
        r = r[np.isfinite(r) & (r > 0)]
        # symmetric miscalibration: 0.5x is as wrong as 2x
        return float(np.max(np.maximum(r, 1.0 / r))) if len(r) else np.nan

    for name, p in variants.items():
        tab = calibration_table(data, p, fold_of, folds, slope_bins)
        m = np.isfinite(p) & np.isin(fold_of, folds)
        out[name] = {
            "global_ece": expected_calibration_error(data.y[m], p[m]),
            "global_brier": _brier(data.y[m], p[m]),
            # The two axes are reported SEPARATELY because only one of them is
            # fixable at inference time. Terrain is a feature of the row being
            # scored, so a per-slope calibrator can condition on it in production.
            # "Which spatial fold" is not knowable for a new region — a model
            # deployed on unseen terrain has no way to look up its own base rate —
            # so region miscalibration is a residual limitation to be REPORTED,
            # not a target to optimise. Pooling the two into one "worst stratum"
            # number hides a real fix behind an unfixable one.
            "worst_slope_ratio": _worst(tab, ["slope_deg"]),
            "worst_region_ratio": _worst(tab, ["spatial_fold"]),
            "worst_stratum_ratio": _worst(tab, ["slope_deg", "spatial_fold"]),
            "table": tab.to_dict("records"),
        }
        out[name]["predictions"] = p
    return out
