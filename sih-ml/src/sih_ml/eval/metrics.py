"""Rare-event evaluation metrics. Ranking + calibration first, accuracy last."""
from __future__ import annotations

import numpy as np
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    precision_recall_curve,
    roc_auc_score,
)


def expected_calibration_error(y: np.ndarray, p: np.ndarray, n_bins: int = 10) -> float:
    bins = np.linspace(0, 1, n_bins + 1)
    idx = np.clip(np.digitize(p, bins) - 1, 0, n_bins - 1)
    ece = 0.0
    for b in range(n_bins):
        m = idx == b
        if m.any():
            ece += m.mean() * abs(p[m].mean() - y[m].mean())
    return float(ece)


def precision_recall_at_k(y: np.ndarray, p: np.ndarray, k: int) -> tuple[float, float]:
    k = min(k, len(y))
    order = np.argsort(-p)[:k]
    tp = y[order].sum()
    total_pos = y.sum()
    return float(tp / k), float(tp / total_pos) if total_pos else 0.0


def lift_at_frac(y: np.ndarray, p: np.ndarray, frac: float) -> float:
    n = max(1, int(round(frac * len(y))))
    order = np.argsort(-p)[:n]
    top_rate = y[order].mean()
    base = y.mean()
    return float(top_rate / base) if base else 0.0


def cost_optimal_threshold(y: np.ndarray, p: np.ndarray, cost_fn_over_fp: float,
                           fbeta: float | None = None) -> dict:
    """Pick the probability threshold that minimises expected misclassification cost
    (a false negative costs `cost_fn_over_fp` times a false positive). Also reports
    the F-beta-optimal threshold if fbeta is given."""
    prec, rec, thr = precision_recall_curve(y, p)
    prec, rec = prec[:-1], rec[:-1]  # align with thr
    P = y.sum()
    N = len(y) - P
    tp = rec * P
    fn = P - tp
    fp = np.where(prec > 0, tp * (1 - prec) / np.clip(prec, 1e-9, None), 0.0)
    cost = cost_fn_over_fp * fn + fp
    i = int(np.argmin(cost))
    out = {"cost_threshold": float(thr[i]), "cost_precision": float(prec[i]),
           "cost_recall": float(rec[i]), "expected_cost": float(cost[i] / len(y))}
    if fbeta:
        b2 = fbeta ** 2
        f = (1 + b2) * prec * rec / np.clip(b2 * prec + rec, 1e-9, None)
        j = int(np.argmax(f))
        out.update({"fbeta_threshold": float(thr[j]), "fbeta": float(f[j]),
                    "fbeta_precision": float(prec[j]), "fbeta_recall": float(rec[j])})
    return out


def confusion_at(y: np.ndarray, p: np.ndarray, threshold: float) -> dict:
    yhat = (p >= threshold).astype(int)
    tp = int(((yhat == 1) & (y == 1)).sum())
    fp = int(((yhat == 1) & (y == 0)).sum())
    fn = int(((yhat == 0) & (y == 1)).sum())
    tn = int(((yhat == 0) & (y == 0)).sum())
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    return {"threshold": float(threshold), "tp": tp, "fp": fp, "fn": fn, "tn": tn,
            "precision": prec, "recall": rec,
            "f1": 2 * prec * rec / (prec + rec) if prec + rec else 0.0}


def ranking_report(y: np.ndarray, p: np.ndarray, ks=(10, 50, 100, 200),
                   lifts=(0.01, 0.05, 0.10)) -> dict:
    y = np.asarray(y, int)
    p = np.asarray(p, float)
    is_prob = np.isfinite(p).all() and p.min() >= 0.0 and p.max() <= 1.0
    out = {
        "n": int(len(y)), "n_pos": int(y.sum()), "base_rate": float(y.mean()),
        "average_precision": float(average_precision_score(y, p)) if y.sum() else float("nan"),
        "roc_auc": float(roc_auc_score(y, p)) if 0 < y.sum() < len(y) else float("nan"),
        "brier": float(brier_score_loss(y, p)) if is_prob else float("nan"),
        "ece": expected_calibration_error(y, p) if is_prob else float("nan"),
    }
    for k in ks:
        pk, rk = precision_recall_at_k(y, p, k)
        out[f"precision@{k}"] = pk
        out[f"recall@{k}"] = rk
    for fr in lifts:
        out[f"lift@{int(fr*100)}pct"] = lift_at_frac(y, p, fr)
    return out
