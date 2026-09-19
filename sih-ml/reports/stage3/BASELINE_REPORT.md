# Stage 3 — Baseline model report

Model: **LightGBM GBDT** (baseline_v1), git `nogit`. Runtime 129.4s.

## Primary — spatial-block CV (pooled OOF)

- **AP (PR-AUC): 0.243**  (per-fold mean 0.285 ± 0.106)
- ROC-AUC 0.799 · Brier 0.0745 · ECE 0.0316
- calibrated: AP 0.247 · Brier 0.0677 · ECE 0.0000
- precision@50 0.700 · recall@50 0.004 · lift@1% 2.2×

### Per spatial fold

| fold | n | pos | AP | ROC-AUC | P@50 | R@50 |
|--|--|--|--|--|--|--|
| 0 | 21631 | 2568 | 0.296 | 0.823 | 0.580 | 0.011 |
| 1 | 17549 | 2286 | 0.484 | 0.859 | 0.960 | 0.021 |
| 2 | 20629 | 1449 | 0.218 | 0.866 | 0.060 | 0.002 |
| 3 | 20266 | 891 | 0.183 | 0.793 | 0.780 | 0.044 |
| 4 | 14894 | 849 | 0.246 | 0.875 | 0.280 | 0.016 |

## Secondary splits

- **LOECO** (leave-events-out): average_precision=0.305 | roc_auc=0.868 | brier=0.071 | ece=0.054 | precision@50=0.680 | recall@50=0.004 | lift@1pct=3.791
- **Temporal OOT** (train≤2015 / test≥2019, also a label-source shift — pessimistic bound): average_precision=0.162 | roc_auc=0.827 | brier=0.027 | ece=0.035 | precision@50=0.760 | recall@50=0.070 | lift@1pct=16.129

## Rule baselines (same OOF rows) — the model must beat these by > fold std

| rule | AP | ROC-AUC | P@50 | lift@1% |
|--|--|--|--|--|
| majority_class | 0.085 | 0.500 | 0.020 | 0.0× |
| rainfall_id_threshold | 0.129 | 0.649 | 0.000 | 1.4× |
| antecedent_rain_15d | 0.126 | 0.642 | 0.000 | 2.5× |
| terrain_only | 0.189 | 0.770 | 0.180 | 3.7× |
| rain_x_terrain | 0.165 | 0.690 | 0.180 | 2.4× |
| logistic_regression | 0.318 | 0.853 | 0.780 | 6.5× |
| **LightGBM (cal)** | **0.247** | **0.813** | **0.760** | **0.7×** |

⚠️ **Logistic regression (0.318) currently beats LightGBM (0.247) on the primary metric.** In this label-scarce, spatially-confounded regime a heavily-regularised linear model can out-generalize an under-tuned GBDT. Do not force LightGBM to win by removing regularization — that reproduces the memorization failure documented below. Stage 4 HPO must beat this number honestly, and the linear model stays the fallback / ensemble component if it doesn't.

## Operating point (cost-sensitive, FN = 20× FP)

- cost-optimal threshold 0.055: P=0.13 R=0.97 (TP 7768, FP 53633, FN 275)
- F3-optimal threshold 0.068: P=0.24 R=0.71

## Top features (final model, gain)

slope_mean_deg, upslope_basin_area_km2, rain_30d_mm, lithology_class, slope_max_deg, cell_dist_m, doy_sin, nearest_river_discharge_cms, doy_cos, rain_15d_mm, distance_to_nearest_river_m, landcover_class

## Plots

`pr_curve.png` `roc.png` `reliability.png` `score_hist.png` `confusion_cost.png` `feature_importance.png` `perfold_ap.png`

## Overfitting / underfitting read

- fold best-iterations: {0: 17, 1: 19, 2: 1200, 3: 1200, 4: 1200} — if these hit the 3000 cap the model is underfit (raise LR or rounds); if wildly different across folds the signal is unstable.
- AP spread across folds is ±0.106 on a mean of 0.285. A spread comparable to the mean means the metric is dominated by *which* region is held out — report the range, never just the mean.
- Compare pooled OOF AP to the per-fold early-stop AP logged during training: a large train→val gap = overfitting; both low = underfitting / weak features.
- If `terrain_only` AP is close to the model AP, the model is riding the hills-vs-plains confound rather than predicting events — revisit negatives / features.