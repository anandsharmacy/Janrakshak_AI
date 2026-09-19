# Stage 4 — Training-from-scratch report

Model `training_v1`, git `nogit`, runtime 126.9s.
Same hyperparameters as the Stage 3 baseline — this run adds the training infrastructure (MLflow tracking, per-round train/val curves, crash-resume checkpoints). See `TRAINING_STRATEGY.md` for the full methodology.

## Spatial-CV (primary)

- AP pooled **0.300**, per-fold mean **0.325 ± 0.139**
- calibrated AP 0.294, ROC-AUC 0.856, Brier 0.0658

**Consistency check vs Stage 3 baseline:** stage3 mean AP 0.285 vs stage4 0.325 (|diff|=0.0393) — DIVERGED, investigate.

## Comparison (same OOF rows)

| model | AP | ROC-AUC |
|--|--|--|
| majority_class | 0.085 | 0.500 |
| rainfall_id_threshold | 0.129 | 0.649 |
| antecedent_rain_15d | 0.126 | 0.642 |
| terrain_only | 0.189 | 0.770 |
| rain_x_terrain | 0.165 | 0.690 |
| logistic_regression | 0.318 | 0.853 |
| **LightGBM (cal)** | **0.294** | **0.856** |

## Per-fold training curves
`training_curve_fold{0..4}.png` — train vs val PR-AUC per boosting round.
Read: gap widening while val flattens/drops = overfitting that fold's region; both curves flat and low = underfit (see fold_best_iters).

fold_best_iters: {0: 1200, 1: 1192, 2: 1199, 3: 1200, 4: 1200}

## MLflow
Full experiment history: `mlflow ui --backend-store-uri ./mlruns`

## Artifacts
`models/training_v1/` (per-fold + final boosters, calibrator, OOF predictions, model card) · `reports/stage4/` (this report, metrics.json, plots)