"""Stage 7 §5 — decision-threshold optimization and the precision/recall trade-off.

Stage 5 §5 measured 34,004 false positives (39.1% of negatives) at the operating
point, and attributed them to POLICY rather than to the model: the threshold is set
by a cost ratio of FN = 20 x FP that was a Stage 3 placeholder and has never been
validated with MDoNER. Tuning the model to "fix" that FP rate would be optimising
against an arbitrary constant.

So this module does two things instead of one:
  1. picks the cost-optimal threshold for a GIVEN ratio, and
  2. publishes how much the answer MOVES as the ratio changes (5, 10, 20, 50),

so the operating point is presented as a decision for the domain owner with the
consequences attached, rather than silently baked in.

`per_stratum_thresholds` exists for the same reason `calibrate.py` does: one global
threshold applied to a model whose calibration varies 3x by terrain delivers very
different effective recall in the plains than in the hills.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import precision_recall_curve

from sih_ml.eval.metrics import confusion_at, precision_recall_at_k
from sih_ml.models.dataset import Data


def cost_curve(y: np.ndarray, p: np.ndarray, ratios: list[float],
               fbeta: float = 3.0) -> pd.DataFrame:
    """Cost-optimal threshold and its consequences for each FN:FP ratio."""
    prec, rec, thr = precision_recall_curve(y, p)
    prec, rec = prec[:-1], rec[:-1]
    P, N = y.sum(), len(y) - y.sum()
    tp = rec * P
    fn = P - tp
    fp = np.where(prec > 0, tp * (1 - prec) / np.clip(prec, 1e-9, None), 0.0)

    rows = []
    for r in ratios:
        i = int(np.argmin(r * fn + fp))
        rows.append({
            "cost_fn_over_fp": r, "threshold": float(thr[i]),
            "precision": float(prec[i]), "recall": float(rec[i]),
            "f1": float(2 * prec[i] * rec[i] / max(prec[i] + rec[i], 1e-9)),
            "fp": int(round(fp[i])), "fn": int(round(fn[i])),
            "fp_rate_of_neg": float(fp[i] / max(N, 1)),
            "alerts_per_1000": float(1000 * (tp[i] + fp[i]) / len(y)),
        })
    b2 = fbeta ** 2
    f = (1 + b2) * prec * rec / np.clip(b2 * prec + rec, 1e-9, None)
    j = int(np.argmax(f))
    rows.append({
        "cost_fn_over_fp": f"F{fbeta:g}-optimal", "threshold": float(thr[j]),
        "precision": float(prec[j]), "recall": float(rec[j]),
        "f1": float(2 * prec[j] * rec[j] / max(prec[j] + rec[j], 1e-9)),
        "fp": int(round(fp[j])), "fn": int(round(fn[j])),
        "fp_rate_of_neg": float(fp[j] / max(N, 1)),
        "alerts_per_1000": float(1000 * (tp[j] + fp[j]) / len(y)),
    })
    return pd.DataFrame(rows)


def operating_report(y: np.ndarray, p: np.ndarray, threshold: float,
                     ks=(10, 50, 100, 200)) -> dict:
    out = confusion_at(y, p, threshold)
    for k in ks:
        pk, rk = precision_recall_at_k(y, p, k)
        out[f"precision@{k}"] = pk
        out[f"recall@{k}"] = rk
    return out


def per_stratum_thresholds(data: Data, y: np.ndarray, p: np.ndarray,
                           strata: np.ndarray, ratio: float) -> pd.DataFrame:
    """Cost-optimal threshold computed INSIDE each terrain stratum.

    Reported as a diagnostic, not shipped by default: with a properly per-stratum
    *calibrated* probability a single global threshold is the cleaner design, and
    two mechanisms correcting the same bias would double-count. See the Stage 7
    report for which one was selected.
    """
    rows = []
    for s in np.unique(strata):
        m = strata == s
        if m.sum() < 200 or y[m].sum() < 20:
            continue
        c = cost_curve(y[m], p[m], [ratio]).iloc[0]
        rows.append({"stratum": int(s), "n": int(m.sum()), "n_pos": int(y[m].sum()),
                     "threshold": c["threshold"], "precision": c["precision"],
                     "recall": c["recall"]})
    return pd.DataFrame(rows)


def pareto_points(y: np.ndarray, p: np.ndarray, n: int = 200) -> pd.DataFrame:
    """Thinned precision/recall curve for plotting and for the MDoNER hand-off."""
    prec, rec, thr = precision_recall_curve(y, p)
    prec, rec = prec[:-1], rec[:-1]
    if len(thr) > n:
        sel = np.linspace(0, len(thr) - 1, n).astype(int)
        prec, rec, thr = prec[sel], rec[sel], thr[sel]
    return pd.DataFrame({"threshold": thr, "precision": prec, "recall": rec})
