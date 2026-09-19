"""Stage 8 §2 — evaluation plots for the frozen final model on the locked test set."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.eval.metrics import expected_calibration_error


def _mpl():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    return plt


def confusion_matrix_plot(y, p, threshold: float, path: Path) -> dict:
    plt = _mpl()
    yhat = (p >= threshold).astype(int)
    cm = np.array([[int(((yhat == 0) & (y == 0)).sum()), int(((yhat == 1) & (y == 0)).sum())],
                   [int(((yhat == 0) & (y == 1)).sum()), int(((yhat == 1) & (y == 1)).sum())]])
    fig, ax = plt.subplots(figsize=(5.2, 4.4))
    ax.imshow(cm, cmap="Blues")
    for i in range(2):
        for j in range(2):
            frac = cm[i, j] / cm[i].sum() if cm[i].sum() else 0
            ax.text(j, i, f"{cm[i, j]:,}\n({frac:.1%} of row)", ha="center", va="center",
                    color="white" if cm[i, j] > cm.max() / 2 else "black", fontsize=10)
    ax.set_xticks([0, 1], ["pred: no disruption", "pred: disruption"])
    ax.set_yticks([0, 1], ["actual: none", "actual: disruption"])
    ax.set_title(f"Confusion matrix @ frozen threshold {threshold:.4f}")
    fig.savefig(path, dpi=120, bbox_inches="tight"); plt.close(fig)
    return {"tn": cm[0, 0], "fp": cm[0, 1], "fn": cm[1, 0], "tp": cm[1, 1]}


def pr_roc_plot(y, p, path_pr: Path, path_roc: Path) -> None:
    from sklearn.metrics import (average_precision_score, precision_recall_curve,
                                 roc_auc_score, roc_curve)
    plt = _mpl()
    prec, rec, _ = precision_recall_curve(y, p)
    ap, base = average_precision_score(y, p), y.mean()
    fig, ax = plt.subplots(figsize=(5.6, 4.4))
    ax.plot(rec, prec, lw=2, label=f"final model (AP = {ap:.4f})")
    ax.axhline(base, ls="--", c="grey", label=f"chance (base rate = {base:.4f})")
    ax.set_xlabel("recall"); ax.set_ylabel("precision")
    ax.set_title("Precision–recall, locked test set"); ax.legend(fontsize=8); ax.grid(alpha=.3)
    fig.savefig(path_pr, dpi=120, bbox_inches="tight"); plt.close(fig)

    fpr, tpr, _ = roc_curve(y, p)
    fig, ax = plt.subplots(figsize=(5.2, 4.4))
    ax.plot(fpr, tpr, lw=2, label=f"final model (AUC = {roc_auc_score(y, p):.4f})")
    ax.plot([0, 1], [0, 1], ls="--", c="grey", label="chance")
    ax.set_xlabel("false positive rate"); ax.set_ylabel("true positive rate")
    ax.set_title("ROC, locked test set"); ax.legend(fontsize=8); ax.grid(alpha=.3)
    fig.savefig(path_roc, dpi=120, bbox_inches="tight"); plt.close(fig)


def reliability_plot(y, p, path: Path, n_bins: int = 10) -> None:
    plt = _mpl()
    edges = np.linspace(0, max(p.max(), 1e-6), n_bins + 1)
    idx = np.clip(np.digitize(p, edges) - 1, 0, n_bins - 1)
    xs, ys, ns = [], [], []
    for b in range(n_bins):
        m = idx == b
        if m.sum() >= 20:
            xs.append(p[m].mean()); ys.append(y[m].mean()); ns.append(int(m.sum()))
    fig, ax = plt.subplots(figsize=(5.4, 4.4))
    lim = max(max(xs + [0]), max(ys + [0])) * 1.05
    ax.plot([0, lim], [0, lim], ls="--", c="grey", label="perfect calibration")
    ax.plot(xs, ys, "o-", label=f"final model (ECE = {expected_calibration_error(y, p):.4f})")
    for x, yv, n in zip(xs, ys, ns):
        ax.annotate(f"n={n:,}", (x, yv), fontsize=6, xytext=(3, -8),
                    textcoords="offset points")
    ax.set_xlabel("mean predicted probability"); ax.set_ylabel("observed frequency")
    ax.set_title("Reliability, locked test set"); ax.legend(fontsize=8); ax.grid(alpha=.3)
    fig.savefig(path, dpi=120, bbox_inches="tight"); plt.close(fig)


def score_distribution_plot(y, p, threshold: float, path: Path) -> None:
    plt = _mpl()
    fig, ax = plt.subplots(figsize=(6.4, 4))
    bins = np.linspace(0, max(p.max(), 1e-6), 50)
    ax.hist(p[y == 0], bins=bins, alpha=.6, label=f"no disruption (n={int((y == 0).sum()):,})",
            density=True, color="#4c72b0")
    ax.hist(p[y == 1], bins=bins, alpha=.6, label=f"disruption (n={int(y.sum()):,})",
            density=True, color="#c44e52")
    ax.axvline(threshold, c="k", ls="--", lw=1.2, label=f"threshold {threshold:.4f}")
    ax.set_xlabel("calibrated probability"); ax.set_ylabel("density")
    ax.set_title("Score separation, locked test set"); ax.legend(fontsize=8)
    fig.savefig(path, dpi=120, bbox_inches="tight"); plt.close(fig)


def group_performance_plot(bias: pd.DataFrame, path: Path) -> None:
    """Lift over chance by group — the comparable quantity when base rates differ."""
    plt = _mpl()
    d = bias[bias.group_type.isin(["slope_deg", "spatial_block", "season", "label_tier"])]
    d = d.sort_values("AP_over_base")
    if d.empty:
        return
    fig, ax = plt.subplots(figsize=(7.2, max(3.5, 0.32 * len(d))))
    colors = {"slope_deg": "#c44e52", "spatial_block": "#4c72b0",
              "season": "#55a868", "label_tier": "#8172b2"}
    ax.barh([f"{r.group_type}: {r.group}" for _, r in d.iterrows()], d.AP_over_base,
            color=[colors.get(t, "#999") for t in d.group_type])
    ax.axvline(1.0, c="k", lw=1, ls="--", label="chance")
    for i, (_, r) in enumerate(d.iterrows()):
        ax.text(r.AP_over_base, i, f" {r.AP_over_base:.2f}x  (n={r.n:,})", va="center", fontsize=7)
    ax.set_xlabel("AP / base rate  (lift over chance — comparable across groups)")
    ax.set_title("Performance by group, locked test set")
    ax.tick_params(labelsize=7); ax.legend(fontsize=7)
    fig.savefig(path, dpi=120, bbox_inches="tight"); plt.close(fig)


def robustness_plot(pert: pd.DataFrame, abl: pd.DataFrame, rc: pd.DataFrame,
                    path: Path) -> None:
    plt = _mpl()
    fig, axes = plt.subplots(1, 3, figsize=(14, 4))

    axes[0].plot(pert.sigma, pert.pct_of_clean, "o-")
    axes[0].axhline(80, ls="--", c="crimson", lw=1, label="80% gate")
    axes[0].set_xlabel("rainfall noise σ (lognormal)")
    axes[0].set_ylabel("% of clean AP retained")
    axes[0].set_title("Sensitivity to rainfall error"); axes[0].grid(alpha=.3)
    axes[0].legend(fontsize=7)

    a = abl[abl.group != "(none — baseline)"].sort_values("delta")
    axes[1].barh(a.group, a.delta, color="#c44e52")
    axes[1].axvline(0, c="k", lw=1)
    axes[1].set_xlabel("ΔAP when the group is blanked")
    axes[1].set_title("Feature-group ablation"); axes[1].tick_params(labelsize=7)

    axes[2].plot(rc.coverage * 100, rc.precision, "o-", label="precision")
    axes[2].plot(rc.coverage * 100, rc.recall, "s-", label="recall")
    axes[2].set_xscale("log")
    axes[2].set_xlabel("% of rows alerted on (log)")
    axes[2].set_title("Selective prediction"); axes[2].grid(alpha=.3)
    axes[2].legend(fontsize=7)

    fig.tight_layout()
    fig.savefig(path, dpi=120, bbox_inches="tight"); plt.close(fig)


def generalization_plot(gen: pd.DataFrame, path: Path) -> None:
    plt = _mpl()
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(gen["split"], gen["AP_over_base"], color=["#999", "#4c72b0", "#55a868", "#c44e52"][:len(gen)])
    for i, (_, r) in enumerate(gen.iterrows()):
        ax.text(i, r.AP_over_base, f"{r.AP_over_base:.1f}x\nAP {r.AP:.3f}",
                ha="center", va="bottom", fontsize=8)
    ax.set_ylabel("AP / base rate (lift over chance)")
    ax.set_title("Generalization: train → early-stopping → new region → locked test")
    plt.setp(ax.get_xticklabels(), rotation=12, ha="right", fontsize=8)
    fig.savefig(path, dpi=120, bbox_inches="tight"); plt.close(fig)
