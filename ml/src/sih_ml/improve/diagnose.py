"""Evaluate -> Analyze errors -> IDENTIFY THE BOTTLENECK.

Re-measures, on the current champion's out-of-fold predictions, every major error
pattern earlier stages found, so the loop's next experiment is chosen from where the
model is failing NOW rather than where it was failing when the pattern was first
written down. Each pattern names the layer a fix must come from and the backlog
experiments that target it; that mapping is declared in conf/improve_config.yaml, not
inferred, so it can be argued with.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score

from sih_ml.optimize import calibrate as cal_mod


def calibrated_oof(c, res: dict, folds: list[int], bins: list[float], seed=None) -> np.ndarray:
    s = next(iter(res["oof"])) if seed is None else seed
    return cal_mod.cross_fitted_calibration(c.data, res["oof"][s], res["fold_of"], folds,
                                            cal_mod.slope_stratum(c.data, bins))


def terrain_cal_per_seed(c, res: dict, folds: list[int], bins: list[float]) -> dict:
    """Worst terrain-stratum calibration ratio for every seed's OOF. One seed is too
    noisy to gate on (the smoke run moved it by 0.4x between seeds)."""
    return {s: worst_ratios(c, calibrated_oof(c, res, folds, bins, s), res["fold_of"],
                            folds, bins)["terrain"] for s in res["oof"]}


def worst_ratios(c, p_cal: np.ndarray, fold_of: np.ndarray, folds, bins) -> dict:
    tab = cal_mod.calibration_table(c.data, p_cal, fold_of, folds, bins)

    def worst(kind):
        r = tab.loc[tab.stratum_type == kind, "pred_over_obs"].to_numpy(float)
        r = r[np.isfinite(r) & (r > 0)]
        return float(np.max(np.maximum(r, 1 / r))) if len(r) else float("nan")
    return {"terrain": worst("slope_deg"), "region": worst("spatial_fold")}


def cost_threshold(y: np.ndarray, p: np.ndarray, ratio: float) -> float:
    """Expected-cost-minimising threshold at FN:FP = ratio — Stage 7/9's routine,
    reused rather than reimplemented so the reproduction check compares like with like."""
    from sih_ml.optimize.threshold import cost_curve
    cc = cost_curve(y, p, [ratio], 3.0)
    return float(cc.loc[cc.cost_fn_over_fp == ratio, "threshold"].iloc[0])


def bottlenecks(c, res: dict, folds: list[int], seeds: list, bins: list[float],
                slope_deg: float, cost_ratio: float, coverage: np.ndarray) -> dict:
    data = c.data
    y = data.y
    s0 = seeds[0]
    oof = res["oof"][s0]
    m = np.isfinite(oof)

    # B1 memorisation: in-sample vs out-of-fold, same fold models
    ins = []
    for f, model in res["models"].items():
        tr = res["tr"][f]
        ins.append(float(average_precision_score(y[tr], model.predict(data.X(tr)))))
    oof_fold = [res["ap"][s0][f] for f in folds]

    # B2 region transfer
    fold_avg = [float(np.mean([res["ap"][s][f] for s in seeds])) for f in folds]
    p_cal = calibrated_oof(c, res, folds, bins)
    ratios = worst_ratios(c, p_cal, res["fold_of"], folds, bins)

    # B3 steep terrain
    slope = np.nan_to_num(data.panel["slope_mean_deg"].to_numpy(float), nan=0.0)
    st = m & (slope >= slope_deg)
    ns = m & (slope < slope_deg)

    def roc(mask):
        return float(roc_auc_score(y[mask], oof[mask])) if 0 < y[mask].sum() < mask.sum() else np.nan
    k = max(1, int(0.10 * st.sum()))
    top = np.argsort(-oof[st])[:k]
    steep_lift = float(y[st][top].mean() / y[st].mean())

    # B4 missed positives at the cost-optimal threshold on calibrated OOF
    thr = cost_threshold(y[m], p_cal[m], cost_ratio)
    pos = m & (y == 1)
    fn = pos & (p_cal < thr)
    tp = pos & (p_cal >= thr)
    r1 = data.panel["rain_1d_mm"].to_numpy(float)
    r7 = data.panel["rain_7d_mm"].to_numpy(float)

    # B6 data integrity: rows the champion TRAINS on whose rainfall is beyond the record
    dev = data.dev_mask() & c.train_mask
    beyond = dev & ~coverage

    return {
        "memorisation": {"in_sample_AP": float(np.mean(ins)), "oof_AP": float(np.mean(oof_fold)),
                         "ratio": float(np.mean(ins) / np.mean(oof_fold))},
        "region": {"fold_AP_seed_avg": fold_avg, "worst_fold_AP": float(min(fold_avg)),
                   "best_fold_AP": float(max(fold_avg)),
                   "spread": float(max(fold_avg) - min(fold_avg)),
                   "worst_region_cal_ratio": ratios["region"]},
        "steep": {"steep_roc": roc(st), "non_steep_roc": roc(ns), "steep_lift@10pct": steep_lift,
                  "steep_share_of_positives": float(y[st].sum() / max(1, y[m].sum()))},
        "missed_positives": {"threshold": thr, "cost_fn_over_fp": cost_ratio,
                             "n_fn": int(fn.sum()), "n_tp": int(tp.sum()),
                             "fn_median_rain_1d": float(np.nanmedian(r1[fn])) if fn.any() else np.nan,
                             "tp_median_rain_1d": float(np.nanmedian(r1[tp])) if tp.any() else np.nan,
                             "fn_median_rain_7d": float(np.nanmedian(r7[fn])) if fn.any() else np.nan,
                             "tp_median_rain_7d": float(np.nanmedian(r7[tp])) if tp.any() else np.nan,
                             "fn_share_dry_day": float(np.mean(r1[fn] < 1.0)) if fn.any() else np.nan},
        "calibration": {"worst_terrain_cal_ratio": ratios["terrain"],
                        "worst_region_cal_ratio": ratios["region"]},
        "data_integrity": {"dev_rows_beyond_rainfall_record": int(beyond.sum()),
                           "of_which_positive": int(y[beyond].sum()),
                           "share_of_dev_negatives": float(
                               beyond.sum() / max(1, (dev & (y == 0)).sum()))},
    }


def operating_points(c, p_cal: np.ndarray, slope_deg: float,
                     fracs=(0.005, 0.01, 0.02, 0.05, 0.10)) -> pd.DataFrame:
    """Dev precision/recall at top-k coverage, for the population the Stage 9 pilot
    would rank autonomously (non-steep) and the one routed to a human (steep)."""
    y = c.data.y
    slope = np.nan_to_num(c.data.panel["slope_mean_deg"].to_numpy(float), nan=0.0)
    m = np.isfinite(p_cal)
    rows = []
    for name, pop in (("all", m), ("non-steep (autonomous pilot)", m & (slope < slope_deg)),
                      ("steep (human review)", m & (slope >= slope_deg))):
        yy, pp = y[pop], p_cal[pop]
        if not yy.sum():
            continue
        order = np.argsort(-pp)
        for fr in fracs:
            k = max(1, int(round(fr * len(yy))))
            hit = yy[order[:k]]
            rows.append({"population": name, "coverage": fr, "alerts": k,
                         "precision": float(hit.mean()), "recall": float(hit.sum() / yy.sum()),
                         "lift": float(hit.mean() / yy.mean()), "base_rate": float(yy.mean()),
                         "threshold": float(pp[order[k - 1]])})
    return pd.DataFrame(rows)
