"""Stage 7 §3 — a terrain-stratified model, motivated by a specific failure case.

Stage 5 §1 is the sharpest finding in the project: global AP 0.294 looks
respectable, but within the steepest slope quartile the lift over base rate is only
**1.63x**. The headline number is carried by separating plains from hills — which
the routing layer already knows for free — so most of the reported AP is not
operational value.

One plausible mechanism: a single model spends its capacity (and its splits) on the
easy plains/hills boundary, because that is where the loss is. A model that only
ever sees steep terrain cannot make that split and must find within-hill structure
or nothing.

This tests that mechanism directly, and it is designed so it can FAIL cleanly: the
comparison is the steep-terrain subset of the global model's OOF against a
steep-only model's OOF on exactly the same rows. If splitting does not help, the
right conclusion is that the within-hill signal is genuinely absent (Stage 5's
data-resolution diagnosis), not that the model was mis-specified.
"""
from __future__ import annotations

import numpy as np
from sklearn.metrics import average_precision_score

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.train import cv
from sih_ml.utils.common import Config, get_logger

log = get_logger("stage7.strat")


def steep_mask(data: Data, slope_deg: float) -> np.ndarray:
    s = data.panel["slope_mean_deg"].to_numpy(float)
    return np.nan_to_num(s, nan=0.0) >= slope_deg


def run_stratified(data: Data, cfg: Config, folds: list[int], slope_deg: float,
                   seed: int = 42) -> dict:
    """Train a steep-only model per fold; score only that fold's steep rows.

    The steep model never sees a flat row, in training OR early stopping — mixing
    them back into early stopping would reintroduce the very boundary the
    experiment removes.
    """
    steep = steep_mask(data, slope_deg)
    oof = np.full(len(data.panel), np.nan)
    fold_ap, n_tr = {}, []

    for f in folds:
        tr_all, va = data.spatial_fold_indices(f, drop_buffer=cfg.cv.drop_buffer_rows)
        tr_all = tr_all[steep[tr_all]]
        va_s = va[steep[va]]
        if len(va_s) == 0 or data.y[tr_all].sum() == 0:
            fold_ap[f] = float("nan")
            continue
        m_tr, m_es = cv.make_es_split(data, tr_all, cfg, seed + f)
        tr, es = tr_all[m_tr], tr_all[m_es]

        p = dict(cfg.lgbm)
        p["seed"] = seed + f
        model = LGBMBaseline(p, data.features, data.categorical,
                             list(cfg.lgbm.get("monotone_rainfall_features", [])))
        spw = (cv._scale_pos_weight(data.y[tr])
               * float(cfg.lgbm.get("scale_pos_weight_mult", 1.0)))
        model.fit(data.X(tr), data.y[tr], data.w[tr],
                  data.X(es), data.y[es], data.w[es], scale_pos_weight=spw)
        oof[va_s] = model.predict(data.X(va_s))
        y = data.y[va_s]
        fold_ap[f] = float(average_precision_score(y, oof[va_s])) if y.sum() else float("nan")
        n_tr.append(len(tr))
        log.info("  steep-only fold %d: n_tr=%d n_val=%d AP=%.4f",
                 f, len(tr), len(va_s), fold_ap[f])

    vals = [fold_ap[f] for f in folds]
    return {"fold_ap": fold_ap, "mean_AP": float(np.nanmean(vals)),
            "std_AP": float(np.nanstd(vals)), "oof": oof,
            "mean_train_rows": float(np.mean(n_tr)) if n_tr else 0.0,
            "slope_deg": slope_deg, "n_steep_rows": int(steep.sum())}


def restrict_to_steep(data: Data, oof: np.ndarray, fold_of: np.ndarray,
                      folds: list[int], slope_deg: float) -> dict:
    """The global model's per-fold AP on the SAME steep rows — the fair comparator."""
    steep = steep_mask(data, slope_deg)
    fold_ap = {}
    for f in folds:
        idx = np.where((fold_of == f) & steep & np.isfinite(oof))[0]
        y = data.y[idx]
        fold_ap[f] = (float(average_precision_score(y, oof[idx]))
                      if len(idx) and y.sum() else float("nan"))
    vals = [fold_ap[f] for f in folds]
    return {"fold_ap": fold_ap, "mean_AP": float(np.nanmean(vals)),
            "std_AP": float(np.nanstd(vals))}
