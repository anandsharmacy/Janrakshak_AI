"""Evaluation plots for the baseline. All saved to reports/stage3/."""
from __future__ import annotations

from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.calibration import calibration_curve
from sklearn.metrics import precision_recall_curve, roc_curve


def pr_curve(y, preds: dict[str, np.ndarray], out: Path):
    fig, ax = plt.subplots(figsize=(6, 5))
    base = np.asarray(y).mean()
    for name, p in preds.items():
        pr, rc, _ = precision_recall_curve(y, p)
        from sklearn.metrics import average_precision_score
        ax.plot(rc, pr, label=f"{name} (AP={average_precision_score(y, p):.3f})")
    ax.axhline(base, ls="--", c="grey", label=f"chance ({base:.3f})")
    ax.set_xlabel("recall"); ax.set_ylabel("precision")
    ax.set_title("Precision–Recall (spatial-CV OOF)"); ax.legend(fontsize=8)
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def roc(y, preds: dict[str, np.ndarray], out: Path):
    fig, ax = plt.subplots(figsize=(6, 5))
    for name, p in preds.items():
        fpr, tpr, _ = roc_curve(y, p)
        ax.plot(fpr, tpr, label=name)
    ax.plot([0, 1], [0, 1], ls="--", c="grey")
    ax.set_xlabel("FPR"); ax.set_ylabel("TPR"); ax.set_title("ROC (secondary)")
    ax.legend(fontsize=8)
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def reliability(y, p_raw, p_cal, out: Path):
    fig, ax = plt.subplots(figsize=(6, 5))
    for label, p in [("raw", p_raw), ("calibrated", p_cal)]:
        frac, mean = calibration_curve(y, np.clip(p, 0, 1), n_bins=10, strategy="quantile")
        ax.plot(mean, frac, "o-", label=label)
    ax.plot([0, 1], [0, 1], ls="--", c="grey")
    ax.set_xlabel("mean predicted probability"); ax.set_ylabel("observed frequency")
    ax.set_title("Reliability diagram"); ax.legend()
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def score_hist(y, p, out: Path):
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.hist(p[y == 0], bins=40, alpha=.6, label="negative", density=True)
    ax.hist(p[y == 1], bins=40, alpha=.6, label="positive", density=True)
    ax.set_xlabel("predicted probability"); ax.set_yscale("log")
    ax.set_title("Score distribution by class"); ax.legend()
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def confusion(cm: dict, out: Path):
    fig, ax = plt.subplots(figsize=(4.2, 4))
    M = np.array([[cm["tn"], cm["fp"]], [cm["fn"], cm["tp"]]])
    ax.imshow(M, cmap="Blues")
    for (i, j), v in np.ndenumerate(M):
        ax.text(j, i, f"{v:,}", ha="center", va="center",
                color="white" if v > M.max() / 2 else "black")
    ax.set_xticks([0, 1], ["pred 0", "pred 1"]); ax.set_yticks([0, 1], ["true 0", "true 1"])
    ax.set_title(f"Confusion @ thr={cm['threshold']:.3f}\n"
                 f"P={cm['precision']:.2f} R={cm['recall']:.2f}")
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def feature_importance(fi, out: Path, top: int = 25):
    fi = fi.head(top).iloc[::-1]
    fig, ax = plt.subplots(figsize=(7, 8))
    ax.barh(fi["feature"], fi["gain"])
    ax.set_title("LightGBM gain importance (top 25)")
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def per_fold_bars(fold_aps: dict, out: Path):
    fig, ax = plt.subplots(figsize=(6, 4))
    ks = list(fold_aps.keys())
    ax.bar([str(k) for k in ks], [fold_aps[k] for k in ks])
    m = np.mean(list(fold_aps.values()))
    ax.axhline(m, ls="--", c="k", label=f"mean {m:.3f}")
    ax.set_xlabel("spatial fold"); ax.set_ylabel("val AP"); ax.legend()
    ax.set_title("Average precision by spatial fold (variance = honesty signal)")
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def training_curve(history: dict, out: Path, title: str = "Training curve",
                   holdout_ap: float | None = None, best_iter: int | None = None) -> None:
    """history: {valid_name: {metric: [...]}} from lgb.record_evaluation.

    One subplot per metric (never mix logloss and PR-AUC on one axis). When
    `holdout_ap` is given it is drawn as a horizontal line on the PR-AUC panel:
    that is the OUTER fold's held-out-block AP, and the gap between it and the
    `es` curve is the spatial generalization gap — the metric that actually
    matters. The `es` set is a stratified row sample of the same blocks as train,
    so an `es`-vs-train gap is NOT an overfitting diagnostic here; the es-vs-holdout
    gap is. See TRAINING_STRATEGY.md.
    """
    metrics = sorted({mn for m in history.values() for mn in m})
    fig, axes = plt.subplots(1, len(metrics), figsize=(6 * len(metrics), 4.2), squeeze=False)
    for ax, metric_name in zip(axes[0], metrics):
        for name, m in history.items():
            if metric_name in m:
                ax.plot(m[metric_name], label=name)
        if metric_name == "pr_auc":
            if holdout_ap is not None:
                ax.axhline(holdout_ap, ls="--", c="crimson",
                           label=f"held-out blocks AP = {holdout_ap:.3f}")
            if best_iter:
                ax.axvline(best_iter, ls=":", c="grey", label=f"best_iter = {best_iter}")
            ax.set_ylim(0, 1)
        ax.set_xlabel("boosting round")
        ax.set_ylabel(metric_name)
        ax.legend(fontsize=8)
        ax.grid(alpha=.3)
    fig.suptitle(title)
    fig.savefig(out, dpi=120, bbox_inches="tight")
    plt.close(fig)


def learning_curve(evals: dict, out: Path):
    fig, ax = plt.subplots(figsize=(6, 4))
    for k, hist in evals.items():
        ax.plot(hist, label=f"fold {k}")
    ax.set_xlabel("boosting round"); ax.set_ylabel("early-stop PR-AUC")
    ax.set_title("Early-stopping metric per fold"); ax.legend(fontsize=8)
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)
