"""Stage 3 orchestrator — build, calibrate, evaluate and checkpoint the baseline.

    python -m sih_ml.train.run_baseline [conf/model_baseline.yaml]

Outputs
  models/baseline_v1/     fold_{k}.txt (+meta), final.txt (+meta), calibrator.pkl,
                          model_card.json, oof_predictions.parquet
  reports/stage3/         metrics.json, BASELINE_REPORT.md, *.png
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.eval import plots
from sih_ml.eval.metrics import confusion_at, cost_optimal_threshold, ranking_report
from sih_ml.models.baselines import REGISTRY as RULES
from sih_ml.models.calibration import Calibrator
from sih_ml.models.dataset import load_data
from sih_ml.train import cv
from sih_ml.utils.common import get_logger, git_sha, resolve, set_seed, write_manifest

log = get_logger("baseline")


def _rule_scores(data, idx):
    X = data.panel.iloc[idx]
    return {name: fn(X) for name, fn in RULES.items()}


def main(model_cfg_path: str | None = None) -> None:
    t0 = time.time()
    data, mcfg = load_data(model_cfg_path)
    set_seed(mcfg.seed)
    mdir = resolve(mcfg, mcfg.paths.models) / mcfg.model_version
    rdir = resolve(mcfg, mcfg.paths.reports)
    mdir.mkdir(parents=True, exist_ok=True)
    rdir.mkdir(parents=True, exist_ok=True)

    dev_idx = np.where(data.dev_mask())[0]
    y_dev = data.y[dev_idx]
    train_prior = float(y_dev.mean())

    # rough real-world base rate (for optional prior correction) -------------
    n_seg = data.panel.segment_id.nunique()
    span_days = (data.panel.date.max() - data.panel.date.min()).days + 1
    n_pos_dev = int(y_dev.sum())
    est_true_prior = n_pos_dev / (n_seg * span_days)
    target_prior = mcfg.calibration.true_prior or None
    log.info("train_prior=%.4f  est_true_prior≈%.2e (n_seg=%d span=%dd)  target_prior=%s",
             train_prior, est_true_prior, n_seg, span_days, target_prior)

    # ---------------------------------------------------------------- spatial CV
    log.info("=== spatial-block CV (primary) ===")
    sp = cv.run_spatial_cv(data, mcfg, seed=mcfg.seed)
    oof, fold_of = sp["oof"], sp["fold_of"]
    val_mask = ~np.isnan(oof)
    y_oof, p_oof = data.y[val_mask], oof[val_mask]

    for k, m in sp["models"].items():
        m.save(mdir / f"fold_{k}.txt")

    # per-fold + pooled metrics
    fold_metrics, fold_aps = {}, {}
    for k in range(mcfg.cv.n_spatial_folds):
        mk = fold_of == k
        r = ranking_report(data.y[mk], oof[mk],
                           ks=mcfg.eval.precision_at_k, lifts=mcfg.eval.top_frac_for_lift)
        fold_metrics[k] = r
        fold_aps[k] = r["average_precision"]
    spatial_pooled = ranking_report(y_oof, p_oof, ks=mcfg.eval.precision_at_k,
                                    lifts=mcfg.eval.top_frac_for_lift)

    # rule baselines on the same OOF rows
    rule_metrics = {}
    for name, s in _rule_scores(data, np.where(val_mask)[0]).items():
        rule_metrics[name] = ranking_report(y_oof, np.nan_to_num(s), ks=mcfg.eval.precision_at_k,
                                            lifts=mcfg.eval.top_frac_for_lift)

    # logistic-regression baseline over the same spatial folds
    log.info("=== logistic-regression baseline (spatial CV) ===")
    lin = cv.run_spatial_cv_linear(data, mcfg, seed=mcfg.seed)
    lin_mask = ~np.isnan(lin["oof"])
    rule_metrics["logistic_regression"] = ranking_report(
        data.y[lin_mask], lin["oof"][lin_mask],
        ks=mcfg.eval.precision_at_k, lifts=mcfg.eval.top_frac_for_lift)

    # ---------------------------------------------------------------- calibration
    cal = Calibrator(mcfg.calibration.method).fit(
        p_oof, y_oof, train_prior=train_prior,
        target_prior=target_prior if mcfg.calibration.apply_prior_correction else None)
    cal.save(mdir / "calibrator.pkl")
    p_cal = cal.transform(p_oof, apply_prior=mcfg.calibration.apply_prior_correction)
    cal_metrics = ranking_report(y_oof, p_cal, ks=mcfg.eval.precision_at_k,
                                 lifts=mcfg.eval.top_frac_for_lift)

    # ---------------------------------------------------------------- threshold
    thr = cost_optimal_threshold(y_oof, p_cal, mcfg.eval.cost_fn_over_fp, mcfg.eval.fbeta)
    cm_cost = confusion_at(y_oof, p_cal, thr["cost_threshold"])
    cm_fbeta = confusion_at(y_oof, p_cal, thr.get("fbeta_threshold", 0.5))

    # ---------------------------------------------------------------- LOECO
    log.info("=== leave-one-event-cluster-out CV ===")
    lo = cv.run_loeco_cv(data, mcfg, n_splits=10, seed=mcfg.seed)
    lo_mask = ~np.isnan(lo["oof"])
    loeco_metrics = ranking_report(data.y[lo_mask], lo["oof"][lo_mask],
                                   ks=mcfg.eval.precision_at_k, lifts=mcfg.eval.top_frac_for_lift)

    # ---------------------------------------------------------------- temporal OOT
    log.info("=== temporal out-of-time split ===")
    tp = cv.run_temporal(data, mcfg, seed=mcfg.seed)
    te_idx, te_pred = tp["pred"]["test"]
    temporal_metrics = ranking_report(data.y[te_idx], te_pred,
                                      ks=mcfg.eval.precision_at_k, lifts=mcfg.eval.top_frac_for_lift)

    # ---------------------------------------------------------------- final model
    mean_best = int(round(np.mean(list(sp["best_iters"].values()))))
    log.info("=== final model on all dev data (%d rounds) ===", mean_best)
    final = cv.fit_final(data, mcfg, n_estimators=mean_best, seed=mcfg.seed)
    final.save(mdir / "final.txt")
    fi = final.feature_importance()
    fi.to_csv(rdir / "feature_importance.csv", index=False)

    # ---------------------------------------------------------------- OOF dump
    oof_df = data.panel.loc[val_mask, ["segment_id", "date", "target", "label_tier",
                                       "spatial_block_id", "spatial_fold"]].copy()
    oof_df["p_raw"] = p_oof
    oof_df["p_cal"] = p_cal
    oof_df.to_parquet(mdir / "oof_predictions.parquet", index=False)

    # ---------------------------------------------------------------- plots
    preds_for_pr = {
        "LightGBM (cal)": p_cal,
        "rain×terrain rule": np.nan_to_num(_rule_scores(data, np.where(val_mask)[0])["rain_x_terrain"]),
        "terrain only": np.nan_to_num(_rule_scores(data, np.where(val_mask)[0])["terrain_only"]),
    }
    plots.pr_curve(y_oof, preds_for_pr, rdir / "pr_curve.png")
    plots.roc(y_oof, {"LightGBM (cal)": p_cal}, rdir / "roc.png")
    plots.reliability(y_oof, p_oof, p_cal, rdir / "reliability.png")
    plots.score_hist(y_oof, p_cal, rdir / "score_hist.png")
    plots.confusion(cm_cost, rdir / "confusion_cost.png")
    plots.feature_importance(fi, rdir / "feature_importance.png")
    plots.per_fold_bars(fold_aps, rdir / "perfold_ap.png")

    # ---------------------------------------------------------------- persist metrics
    metrics = {
        "model_version": mcfg.model_version,
        "git_sha": git_sha(),
        "primary_metric": mcfg.eval.primary_metric,
        "cost_fn_over_fp": mcfg.eval.cost_fn_over_fp,
        "fbeta": mcfg.eval.fbeta,
        "train_prior": train_prior,
        "est_true_prior": est_true_prior,
        "spatial_cv": {
            "pooled": spatial_pooled,
            "per_fold": fold_metrics,
            "mean_AP": float(np.mean(list(fold_aps.values()))),
            "std_AP": float(np.std(list(fold_aps.values()))),
            "calibrated_pooled": cal_metrics,
        },
        "loeco_cv": loeco_metrics,
        "temporal_oot": temporal_metrics,
        "rule_baselines": rule_metrics,
        "threshold": thr,
        "confusion_cost": cm_cost,
        "confusion_fbeta": cm_fbeta,
        "final_model_rounds": mean_best,
        "fold_best_iters": sp["best_iters"],
        "top_features": fi.head(15).to_dict("records"),
        "runtime_sec": round(time.time() - t0, 1),
    }
    (rdir / "metrics.json").write_text(json.dumps(metrics, indent=2, default=float))
    write_manifest(resolve(mcfg, "data/processed/manifests"), "baseline_v1",
                   {"model_cfg": dict(mcfg), "metrics_summary": {
                       "spatial_mean_AP": metrics["spatial_cv"]["mean_AP"],
                       "spatial_std_AP": metrics["spatial_cv"]["std_AP"],
                       "loeco_AP": loeco_metrics["average_precision"],
                       "temporal_AP": temporal_metrics["average_precision"],
                   }})
    _write_report(metrics, rdir)
    _write_model_card(metrics, mcfg, data, mdir)
    log.info("Stage 3 done in %.1fs — mean spatial-CV AP = %.3f ± %.3f",
             time.time() - t0, metrics["spatial_cv"]["mean_AP"], metrics["spatial_cv"]["std_AP"])


def _fmt(d: dict, keys) -> str:
    return " | ".join(f"{k}={d[k]:.3f}" if isinstance(d.get(k), float) else f"{k}={d.get(k)}"
                      for k in keys)


def _write_report(m: dict, rdir: Path) -> None:
    P = ["average_precision", "roc_auc", "brier", "ece", "precision@50", "recall@50", "lift@1pct"]
    sp = m["spatial_cv"]
    lines = [
        "# Stage 3 — Baseline model report", "",
        f"Model: **LightGBM GBDT** ({m['model_version']}), git `{m['git_sha']}`. "
        f"Runtime {m['runtime_sec']}s.", "",
        "## Primary — spatial-block CV (pooled OOF)", "",
        f"- **AP (PR-AUC): {sp['pooled']['average_precision']:.3f}**  "
        f"(per-fold mean {sp['mean_AP']:.3f} ± {sp['std_AP']:.3f})",
        f"- ROC-AUC {sp['pooled']['roc_auc']:.3f} · Brier {sp['pooled']['brier']:.4f} · "
        f"ECE {sp['pooled']['ece']:.4f}",
        f"- calibrated: AP {sp['calibrated_pooled']['average_precision']:.3f} · "
        f"Brier {sp['calibrated_pooled']['brier']:.4f} · ECE {sp['calibrated_pooled']['ece']:.4f}",
        f"- precision@50 {sp['pooled']['precision@50']:.3f} · recall@50 {sp['pooled']['recall@50']:.3f} "
        f"· lift@1% {sp['pooled']['lift@1pct']:.1f}×", "",
        "### Per spatial fold", "",
        "| fold | n | pos | AP | ROC-AUC | P@50 | R@50 |", "|--|--|--|--|--|--|--|",
    ]
    for k, r in sp["per_fold"].items():
        lines.append(f"| {k} | {r['n']} | {r['n_pos']} | {r['average_precision']:.3f} | "
                     f"{r['roc_auc']:.3f} | {r['precision@50']:.3f} | {r['recall@50']:.3f} |")
    lines += [
        "", "## Secondary splits", "",
        f"- **LOECO** (leave-events-out): {_fmt(m['loeco_cv'], P)}",
        f"- **Temporal OOT** (train≤2015 / test≥2019, also a label-source shift — pessimistic bound): "
        f"{_fmt(m['temporal_oot'], P)}", "",
        "## Rule baselines (same OOF rows) — the model must beat these by > fold std", "",
        "| rule | AP | ROC-AUC | P@50 | lift@1% |", "|--|--|--|--|--|",
    ]
    for name, r in m["rule_baselines"].items():
        lines.append(f"| {name} | {r['average_precision']:.3f} | {r['roc_auc']:.3f} | "
                     f"{r['precision@50']:.3f} | {r['lift@1pct']:.1f}× |")
    lines += [
        f"| **LightGBM (cal)** | **{sp['calibrated_pooled']['average_precision']:.3f}** | "
        f"**{sp['calibrated_pooled']['roc_auc']:.3f}** | "
        f"**{sp['calibrated_pooled']['precision@50']:.3f}** | "
        f"**{sp['calibrated_pooled']['lift@1pct']:.1f}×** |", "",
    ]
    lgbm_ap = sp["calibrated_pooled"]["average_precision"]
    lin_ap = m["rule_baselines"].get("logistic_regression", {}).get("average_precision")
    if lin_ap is not None and lin_ap > lgbm_ap:
        lines += [
            f"⚠️ **Logistic regression ({lin_ap:.3f}) currently beats LightGBM "
            f"({lgbm_ap:.3f}) on the primary metric.** In this label-scarce, "
            "spatially-confounded regime a heavily-regularised linear model can "
            "out-generalize an under-tuned GBDT. Do not force LightGBM to win by "
            "removing regularization — that reproduces the memorization failure "
            "documented below. Stage 4 HPO must beat this number honestly, and the "
            "linear model stays the fallback / ensemble component if it doesn't.",
            "",
        ]
    lines += [
        f"## Operating point (cost-sensitive, FN = {m['cost_fn_over_fp']}× FP)", "",
        f"- cost-optimal threshold {m['confusion_cost']['threshold']:.3f}: "
        f"P={m['confusion_cost']['precision']:.2f} R={m['confusion_cost']['recall']:.2f} "
        f"(TP {m['confusion_cost']['tp']}, FP {m['confusion_cost']['fp']}, FN {m['confusion_cost']['fn']})",
        f"- F{m['fbeta']:.0f}-optimal threshold {m['confusion_fbeta']['threshold']:.3f}: "
        f"P={m['confusion_fbeta']['precision']:.2f} R={m['confusion_fbeta']['recall']:.2f}", "",
        "## Top features (final model, gain)", "",
        ", ".join(f"{r['feature']}" for r in m["top_features"][:12]), "",
        "## Plots", "",
        "`pr_curve.png` `roc.png` `reliability.png` `score_hist.png` "
        "`confusion_cost.png` `feature_importance.png` `perfold_ap.png`", "",
        "## Overfitting / underfitting read", "",
        f"- fold best-iterations: {m['fold_best_iters']} — if these hit the 3000 cap the "
        "model is underfit (raise LR or rounds); if wildly different across folds the "
        "signal is unstable.",
        f"- AP spread across folds is ±{sp['std_AP']:.3f} on a mean of {sp['mean_AP']:.3f}. "
        "A spread comparable to the mean means the metric is dominated by *which* region "
        "is held out — report the range, never just the mean.",
        "- Compare pooled OOF AP to the per-fold early-stop AP logged during training: "
        "a large train→val gap = overfitting; both low = underfitting / weak features.",
        "- If `terrain_only` AP is close to the model AP, the model is riding the "
        "hills-vs-plains confound rather than predicting events — revisit negatives / features.",
    ]
    (rdir / "BASELINE_REPORT.md").write_text("\n".join(lines))


def _write_model_card(m, mcfg, data, mdir: Path) -> None:
    card = {
        "name": mcfg.model_version,
        "task": "per-road-segment-per-day disruption classification (rainfall-triggered landslide/flood)",
        "model": "LightGBM gradient-boosted decision trees",
        "n_features": len(data.features),
        "categorical_features": data.categorical,
        "monotone_increasing": list(mcfg.lgbm.monotone_rainfall_features),
        "training_rows_dev": int(data.dev_mask().sum()),
        "class_balance_train": "~10:1 neg:pos (Stage 2 case-control); scale_pos_weight per fold",
        "primary_metric": mcfg.eval.primary_metric,
        "spatial_cv_AP_mean": m["spatial_cv"]["mean_AP"],
        "spatial_cv_AP_std": m["spatial_cv"]["std_AP"],
        "calibration": {"method": mcfg.calibration.method,
                        "prior_correction": mcfg.calibration.apply_prior_correction},
        "known_limitations": [
            "1 verified gold label; positives are weak/silver, spatially clustered",
            "temporal split confounded by GLC->reliefweb label-source shift",
            "CHIRPS ~25 km daily rainfall — smooths valley extremes",
            "probabilities calibrated to the training base rate unless true_prior is set",
        ],
        "intended_use": "risk RANKING of segments per day + routing edge penalty; NOT a "
                        "standalone closure decision",
        "checkpoints": sorted(p.name for p in mdir.glob("*.txt")),
    }
    (mdir / "model_card.json").write_text(json.dumps(card, indent=2, default=float))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
