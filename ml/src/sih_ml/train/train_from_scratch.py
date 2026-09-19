"""Stage 4 — training from scratch: the hardened training pipeline around the
Stage 3 baseline config (same hyperparameters; this stage adds the infrastructure —
MLflow tracking, full train/val curves, crash-resume checkpoints, determinism
guarantees, best-checkpoint selection). Hyperparameter search is Stage 6.

    python -m sih_ml.train.train_from_scratch [conf/train_config.yaml]
    python -m sih_ml.train.train_from_scratch --resume   # same command; resume is
                                                          # automatic if checkpoints exist

Outputs
  models/training_v1/       fold_{k}.txt(+meta), final.txt(+meta), calibrator.pkl,
                            model_card.json, oof_predictions.parquet
  reports/stage4/           metrics.json, TRAINING_REPORT.md, training_curve_fold*.png,
                            + the Stage-3-style diagnostic plots
  checkpoints/training_v1/  periodic per-fold snapshots (deleted on success unless
                            training.clean_checkpoints_on_success: false)
  mlruns/                   full MLflow experiment history
"""
from __future__ import annotations

import json
import shutil
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.eval import plots
from sih_ml.eval.metrics import confusion_at, cost_optimal_threshold, ranking_report
from sih_ml.models.baselines import REGISTRY as RULES
from sih_ml.models.calibration import Calibrator
from sih_ml.models.dataset import load_data
from sih_ml.train import cv, tracking
from sih_ml.utils.common import get_logger, git_sha, resolve, set_seed, write_manifest

log = get_logger("train_from_scratch")


def _rule_scores(data, idx):
    X = data.panel.iloc[idx]
    return {name: fn(X) for name, fn in RULES.items()}


def main(config_path: str | None = None) -> None:
    t0 = time.time()
    from sih_ml.utils.common import REPO_ROOT
    cfg_path = Path(config_path) if config_path else REPO_ROOT / "conf" / "train_config.yaml"
    if not cfg_path.is_absolute():
        cfg_path = REPO_ROOT / cfg_path
    data, mcfg = load_data(cfg_path)
    set_seed(mcfg.seed)

    tracking.init_tracking(resolve(mcfg, mcfg.paths.mlruns))
    mdir = resolve(mcfg, mcfg.paths.models) / mcfg.model_version
    rdir = resolve(mcfg, mcfg.paths.reports)
    ckpt_root = resolve(mcfg, mcfg.paths.checkpoints) / mcfg.model_version
    mdir.mkdir(parents=True, exist_ok=True)
    rdir.mkdir(parents=True, exist_ok=True)

    dev_idx = np.where(data.dev_mask())[0]
    y_dev = data.y[dev_idx]
    train_prior = float(y_dev.mean())

    run_tags = {"stage": "4-training-from-scratch", "git_sha": git_sha()}
    with tracking.run(f"{mcfg.model_version}_{int(t0)}", params={
        "model_version": mcfg.model_version, "seed": mcfg.seed, **dict(mcfg.lgbm),
        "checkpoint_every": mcfg.training.checkpoint_every_rounds,
        "train_prior": train_prior,
    }, tags=run_tags):

        # -------------------------------------------------- primary: spatial CV
        log.info("=== spatial-block CV, tracked (checkpoints under %s) ===", ckpt_root)
        sp = cv.run_spatial_cv_tracked(
            data, mcfg, seed=mcfg.seed, ckpt_root=ckpt_root,
            checkpoint_every=mcfg.training.checkpoint_every_rounds,
        )
        oof, fold_of = sp["oof"], sp["fold_of"]
        val_mask = ~np.isnan(oof)
        y_oof, p_oof = data.y[val_mask], oof[val_mask]

        fold_metrics, fold_aps = {}, {}
        for k in range(mcfg.cv.n_spatial_folds):
            mk = fold_of == k
            r = ranking_report(data.y[mk], oof[mk], ks=mcfg.eval.precision_at_k,
                               lifts=mcfg.eval.top_frac_for_lift)
            fold_metrics[k] = r
            fold_aps[k] = r["average_precision"]

        for k, m in sp["models"].items():
            m.save(mdir / f"fold_{k}.txt")
            plots.training_curve(
                sp["histories"][k], rdir / f"training_curve_fold{k}.png",
                title=f"Fold {k} — in-distribution (es) curve vs held-out-block AP",
                holdout_ap=fold_aps[k], best_iter=sp["best_iters"][k],
            )
        spatial_pooled = ranking_report(y_oof, p_oof, ks=mcfg.eval.precision_at_k,
                                        lifts=mcfg.eval.top_frac_for_lift)
        tracking.log_metrics({"spatial_mean_AP": float(np.mean(list(fold_aps.values()))),
                              "spatial_std_AP": float(np.std(list(fold_aps.values()))),
                              "spatial_pooled_AP": spatial_pooled["average_precision"]})

        # -------------------------------------------------- calibration
        cal = Calibrator(mcfg.calibration.method).fit(
            p_oof, y_oof, train_prior=train_prior,
            target_prior=(mcfg.calibration.true_prior if mcfg.calibration.apply_prior_correction else None))
        cal.save(mdir / "calibrator.pkl")
        p_cal = cal.transform(p_oof, apply_prior=mcfg.calibration.apply_prior_correction)
        cal_metrics = ranking_report(y_oof, p_cal, ks=mcfg.eval.precision_at_k,
                                     lifts=mcfg.eval.top_frac_for_lift)
        tracking.log_metrics({"calibrated_AP": cal_metrics["average_precision"],
                              "calibrated_brier": cal_metrics["brier"],
                              "calibrated_ece": cal_metrics["ece"]})

        thr = cost_optimal_threshold(y_oof, p_cal, mcfg.eval.cost_fn_over_fp, mcfg.eval.fbeta)
        cm_cost = confusion_at(y_oof, p_cal, thr["cost_threshold"])

        # -------------------------------------------------- rule + linear comparison
        rule_metrics = {}
        for name, s in _rule_scores(data, np.where(val_mask)[0]).items():
            rule_metrics[name] = ranking_report(y_oof, np.nan_to_num(s), ks=mcfg.eval.precision_at_k,
                                                lifts=mcfg.eval.top_frac_for_lift)
        lin = cv.run_spatial_cv_linear(data, mcfg, seed=mcfg.seed)
        lin_mask = ~np.isnan(lin["oof"])
        rule_metrics["logistic_regression"] = ranking_report(
            data.y[lin_mask], lin["oof"][lin_mask],
            ks=mcfg.eval.precision_at_k, lifts=mcfg.eval.top_frac_for_lift)

        # -------------------------------------------------- final model
        mean_best = int(round(np.mean(list(sp["best_iters"].values()))))
        log.info("=== final model on all dev data (%d rounds) ===", mean_best)
        final = cv.fit_final(data, mcfg, n_estimators=mean_best, seed=mcfg.seed)
        final.save(mdir / "final.txt")
        fi = final.feature_importance()
        fi.to_csv(rdir / "feature_importance.csv", index=False)
        tracking.log_artifact(mdir / "final.txt")
        tracking.log_artifact(rdir / "feature_importance.csv")

        # -------------------------------------------------- OOF dump + plots
        oof_df = data.panel.loc[val_mask, ["segment_id", "date", "target", "label_tier",
                                           "spatial_block_id", "spatial_fold"]].copy()
        oof_df["p_raw"] = p_oof
        oof_df["p_cal"] = p_cal
        oof_df.to_parquet(mdir / "oof_predictions.parquet", index=False)

        plots.pr_curve(y_oof, {
            "LightGBM (cal)": p_cal,
            "logistic_regression": np.nan_to_num(lin["oof"][val_mask]),
            "terrain only": np.nan_to_num(_rule_scores(data, np.where(val_mask)[0])["terrain_only"]),
        }, rdir / "pr_curve.png")
        plots.reliability(y_oof, p_oof, p_cal, rdir / "reliability.png")
        plots.score_hist(y_oof, p_cal, rdir / "score_hist.png")
        plots.confusion(cm_cost, rdir / "confusion_cost.png")
        plots.feature_importance(fi, rdir / "feature_importance.png")
        plots.per_fold_bars(fold_aps, rdir / "perfold_ap.png")
        for p in rdir.glob("*.png"):
            tracking.log_artifact(p, artifact_path="plots")

        # -------------------------------------------------- consistency check vs Stage 3
        stage3_metrics_path = resolve(mcfg, "reports/stage3/metrics.json")
        consistency = None
        if stage3_metrics_path.exists():
            s3 = json.loads(stage3_metrics_path.read_text())
            d = abs(s3["spatial_cv"]["mean_AP"] - float(np.mean(list(fold_aps.values()))))
            consistency = {"stage3_spatial_mean_AP": s3["spatial_cv"]["mean_AP"],
                           "stage4_spatial_mean_AP": float(np.mean(list(fold_aps.values()))),
                           "abs_diff": d,
                           "note": "should be ~0: the tracked fit path adds curve "
                                   "logging/checkpointing only, not a different "
                                   "training algorithm — a large diff means something "
                                   "in the tracked path changed training behaviour."}
            log.info("Stage3 vs Stage4 spatial mean AP diff: %.4f", d)

        # -------------------------------------------------- cleanup checkpoints
        if mcfg.training.clean_checkpoints_on_success and ckpt_root.exists():
            shutil.rmtree(ckpt_root)
            log.info("cleaned checkpoints at %s (training.clean_checkpoints_on_success=true)", ckpt_root)

        metrics = {
            "model_version": mcfg.model_version, "git_sha": git_sha(),
            "spatial_cv": {"pooled": spatial_pooled, "per_fold": fold_metrics,
                           "mean_AP": float(np.mean(list(fold_aps.values()))),
                           "std_AP": float(np.std(list(fold_aps.values()))),
                           "calibrated_pooled": cal_metrics},
            "rule_baselines": rule_metrics,
            "threshold": thr, "confusion_cost": cm_cost,
            "final_model_rounds": mean_best, "fold_best_iters": sp["best_iters"],
            "stage3_consistency_check": consistency,
            "top_features": fi.head(15).to_dict("records"),
            "runtime_sec": round(time.time() - t0, 1),
        }
        (rdir / "metrics.json").write_text(json.dumps(metrics, indent=2, default=float))
        write_manifest(resolve(mcfg, "data/processed/manifests"), "training_v1",
                       {"train_config": dict(mcfg),
                        "spatial_mean_AP": metrics["spatial_cv"]["mean_AP"]})
        _write_model_card(metrics, mcfg, data, mdir)
        _write_report(metrics, rdir, mcfg)
        log.info("Stage 4 training done in %.1fs — spatial mean AP %.3f ± %.3f",
                 time.time() - t0, metrics["spatial_cv"]["mean_AP"], metrics["spatial_cv"]["std_AP"])


def _write_model_card(m: dict, mcfg, data, mdir: Path) -> None:
    card = {
        "name": mcfg.model_version,
        "stage": "4 — training from scratch (hardened pipeline, Stage 3 hyperparameters)",
        "task": "per-road-segment-per-day disruption classification (rainfall-triggered landslide/flood)",
        "model": "LightGBM gradient-boosted decision trees",
        "n_features": len(data.features),
        "categorical_features": data.categorical,
        "monotone_increasing": list(mcfg.lgbm.monotone_rainfall_features),
        "training_rows_dev": int(data.dev_mask().sum()),
        "class_balance": "~10:1 neg:pos (Stage 2 case-control); per-fold scale_pos_weight "
                         "on top of Stage 2 label-confidence sample weights",
        "primary_metric": "average_precision under spatial-block CV",
        "spatial_cv_AP_mean": m["spatial_cv"]["mean_AP"],
        "spatial_cv_AP_std": m["spatial_cv"]["std_AP"],
        "final_model_rounds": m["final_model_rounds"],
        "calibration": {"method": mcfg.calibration.method,
                        "prior_correction": mcfg.calibration.apply_prior_correction},
        "reproducibility": {
            "seed": mcfg.seed,
            "deterministic_lightgbm": True,
            "resume_is_bit_identical": False,
            "resume_note": "init_model resume restarts the bagging/feature-sampling RNG "
                           "at the boundary — verified empirically; use for crash recovery, "
                           "not to reproduce a specific uninterrupted run",
        },
        "known_limitations": [
            "1 verified gold label; positives are weak/silver, spatially clustered",
            "logistic regression currently matches/beats this model on spatial CV",
            "temporal split confounded by GLC->reliefweb label-source shift",
            "CHIRPS ~25 km daily rainfall — smooths valley extremes",
        ],
        "intended_use": "risk RANKING of segments per day + routing edge penalty; NOT a "
                        "standalone closure decision",
        "checkpoints": sorted(p.name for p in mdir.glob("*.txt")),
    }
    (mdir / "model_card.json").write_text(json.dumps(card, indent=2, default=float))


def _write_report(m: dict, rdir: Path, mcfg) -> None:
    sp = m["spatial_cv"]
    lines = [
        "# Stage 4 — Training-from-scratch report", "",
        f"Model `{m['model_version']}`, git `{m['git_sha']}`, runtime {m['runtime_sec']}s.",
        "Same hyperparameters as the Stage 3 baseline — this run adds the training "
        "infrastructure (MLflow tracking, per-round train/val curves, crash-resume "
        "checkpoints). See `TRAINING_STRATEGY.md` for the full methodology.", "",
        "## Spatial-CV (primary)", "",
        f"- AP pooled **{sp['pooled']['average_precision']:.3f}**, per-fold mean "
        f"**{sp['mean_AP']:.3f} ± {sp['std_AP']:.3f}**",
        f"- calibrated AP {sp['calibrated_pooled']['average_precision']:.3f}, "
        f"ROC-AUC {sp['calibrated_pooled']['roc_auc']:.3f}, "
        f"Brier {sp['calibrated_pooled']['brier']:.4f}", "",
    ]
    if m.get("stage3_consistency_check"):
        c = m["stage3_consistency_check"]
        lines += [f"**Consistency check vs Stage 3 baseline:** stage3 mean AP "
                  f"{c['stage3_spatial_mean_AP']:.3f} vs stage4 {c['stage4_spatial_mean_AP']:.3f} "
                  f"(|diff|={c['abs_diff']:.4f}) — {'OK, matches as expected' if c['abs_diff'] < 0.01 else 'DIVERGED, investigate'}.",
                  ""]
    lines += ["## Comparison (same OOF rows)", "", "| model | AP | ROC-AUC |", "|--|--|--|"]
    for name, r in m["rule_baselines"].items():
        lines.append(f"| {name} | {r['average_precision']:.3f} | {r['roc_auc']:.3f} |")
    lines.append(f"| **LightGBM (cal)** | **{sp['calibrated_pooled']['average_precision']:.3f}** | "
                 f"**{sp['calibrated_pooled']['roc_auc']:.3f}** |")
    lines += ["", "## Per-fold training curves",
              "`training_curve_fold{0..4}.png` — train vs val PR-AUC per boosting round.",
              "Read: gap widening while val flattens/drops = overfitting that fold's "
              "region; both curves flat and low = underfit (see fold_best_iters).", "",
              f"fold_best_iters: {m['fold_best_iters']}", "",
              "## MLflow", "Full experiment history: `mlflow ui --backend-store-uri ./mlruns`",
              "", "## Artifacts",
              f"`models/{m['model_version']}/` (per-fold + final boosters, calibrator, "
              "OOF predictions, model card) · `reports/stage4/` (this report, metrics.json, plots)"]
    (rdir / "TRAINING_REPORT.md").write_text("\n".join(lines))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
