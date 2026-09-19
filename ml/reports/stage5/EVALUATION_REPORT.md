# Stage 5 — Evaluation & Error Analysis

All numbers below are MEASURED from actual model outputs on held-out data (Stage 4 spatial-CV OOF + a fresh out-of-time fit + in-sample scores). Recommendations are clearly marked as such. The locked `final_test` split was NOT opened.

## 0. Evaluation set

- Held-out OOF rows: **94,969**, positives **8,043**, base rate **0.0847**
- Tier composition: negative=86926, bronze=4560, silver=3483
- **Zero gold-tier positives here** — all 3 verified labels sit inside the locked test split. Every positive evaluated below is a weak (silver/bronze) label.

## 1. Headline metrics (held-out OOF)

| metric | value |
|--|--|
| Average precision (PRIMARY) | **0.294** |
| ROC-AUC | 0.856 |
| Brier | 0.0658 |
| ECE | 0.0000 |
| precision@50 | 0.880 |
| lift@1% | 5.3x |
| chance (base rate) | 0.0847 |

At the cost-optimal operating point (policy: one missed closure costs as much as 20 false alarms), threshold **0.0476**: precision **0.184**, recall **0.956** (TP 7,687 · FP 34,004 · FN 356 · TN 52,922).

## 2. Generalization gap (the overfitting/underfitting read)

| evaluation | AP | ROC-AUC | interpretation |
|--|--|--|--|
| in_sample_dev | 0.999 | 1.000 | model scored on data it trained on |
| held_out_spatial_oof | 0.294 | 0.856 | new REGION (spatial blocks held out) |
| out_of_time_test | 0.232 | 0.852 | new TIME + new label source (hardest) |

In-sample AP 0.999 vs held-out 0.294 = the cost of moving to an unseen region; the further drop to 0.232 out-of-time is the cost of moving to a new period AND a different label source (GLC -> reliefweb).

## 3. Per-event detection — *would we have flagged the real event?*

- Events evaluated: **146**
- Detected in **top-1**: 46.6% · **top-10**: 89.0% · **top-50**: 98.6% · **top-100**: 100.0%
- Median best rank: **2** out of a median **63** rows scored that day

> **Caveat, stated plainly:** the panel holds only labelled rows (positives + sampled negatives), not all 309k corridor segments. So this is rank-within-the-scored-sample, an OPTIMISTIC proxy for live deployment. It is the right shape of metric for comparing models, not a deployment guarantee.

## 4. Where the model is strong vs weak

Full table: `stratified_performance.csv`. Strata where AP collapses toward the base rate have no usable signal.

| stratum | value | n | pos | AP | base rate | lift |
|--|--|--|--|--|--|--|
| elevation_quartile | (0.747, 32.808] | 23,743 | 111 | 0.167 | 0.005 | 35.7x |
| slope_quartile | (1.481, 2.541] | 23,746 | 165 | 0.198 | 0.007 | 28.5x |
| elevation_quartile | (32.808, 85.139] | 23,742 | 429 | 0.435 | 0.018 | 24.0x |
| lithology_class | ssmx | 5,269 | 186 | 0.406 | 0.035 | 11.5x |
| lithology_class | sumx | 26,240 | 396 | 0.150 | 0.015 | 9.9x |
| season | dry | 24,609 | 1340 | 0.373 | 0.054 | 6.9x |
| highway | residential | 35,128 | 2244 | 0.409 | 0.064 | 6.4x |
| soil_missing | soil NODATA | 2,186 | 129 | 0.323 | 0.059 | 5.5x |
| highway | secondary | 913 | 234 | 0.466 | 0.256 | 1.8x |
| elevation_quartile | (526.563, 5069.209] | 23,742 | 4350 | 0.312 | 0.183 | 1.7x |
| highway | trunk | 1,429 | 657 | 0.776 | 0.460 | 1.7x |
| lithology_class | smmxmt | 7,641 | 789 | 0.169 | 0.103 | 1.6x |
| slope_quartile | (18.752, 54.975] | 23,741 | 4353 | 0.298 | 0.183 | 1.6x |
| lithology_class | smmx | 637 | 168 | 0.313 | 0.264 | 1.2x |
| lithology_class | pa | 651 | 282 | 0.428 | 0.433 | 1.0x |
| lithology_class | ssmxcl | 459 | 66 | 0.132 | 0.144 | 0.9x |

## 5. Why we miss (false negatives)

Cohen's *d* between caught (TP) and missed (FN) positives — full table `fn_vs_tp_probe.csv`, worst cases `worst_false_negatives.csv`.

| feature | TP median | FN median | Cohen's d |
|--|--|--|--|
| slope_mean_deg | 19.7 | 17.4 | +0.57 |
| api_mm | 134 | 86.9 | +0.54 |
| rain_15d_mm | 171 | 133 | +0.52 |
| label_confidence | 0.526 | 0.456 | +0.51 |
| slope_max_deg | 32.3 | 30.5 | +0.51 |
| rain_30d_mm | 358 | 218 | +0.49 |
| id_ratio_3d | 0.521 | 0.258 | +0.49 |
| rain_3d_mm | 37.2 | 18.4 | +0.49 |

## 6. False-positive structure

- FPs: **34,004** (39.1% of negatives)
- Concentration: the worst 10% of segments account for **22.6%** of all FPs (top 1%: 3.2%) — see `fp_top_segments.csv`
- **1.1%** of FPs fall within 10 km and 7 days of a labelled real event — these are plausibly UNLABELLED positives (inventory incompleteness), not model errors.

## 7. Is the ceiling the model or the labels?

Ranking quality recomputed using only positives of a given label quality, against the same negative set (`label_noise_probe.csv`):

| probe | bucket | n_pos | AP | lift |
|--|--|--|--|--|
| snap_dist_m | [0, 500) | 2241 | 0.120 | 4.8x |
| snap_dist_m | [500, 2000) | 4320 | 0.203 | 4.3x |
| snap_dist_m | [2000, 5000) | 1212 | 0.041 | 3.0x |
| snap_dist_m | [5000, 1e+09) | 270 | 0.013 | 4.1x |
| label_confidence | [0, 0.25) | 174 | 0.003 | 1.5x |
| label_confidence | [0.25, 0.35) | 343 | 0.010 | 2.6x |
| label_confidence | [0.35, 0.5) | 3283 | 0.150 | 4.1x |
| label_confidence | [0.5, 1.01) | 4243 | 0.200 | 4.3x |

## 7b. Early-stopping signal integrity (training-process defect)

- mean AP on TRAIN rows: **1.000**
- mean AP on the EARLY-STOPPING rows: **0.999**
- mean AP on HELD-OUT blocks: **0.325**
- verdict: **SATURATED — early stopping has no usable validation signal**

Share of ES positives whose unit also appears among TRAIN positives (`es_leakage_units.csv`):

| unit | overlap |
|--|--|
| segment | 98.9% |
| block+date | 99.9% |
| event_id | 100.0% |
| block | 100.0% |

Because one event generates up to 60 panel rows (≤20 snapped segments × 3 persistence days), a RANDOM ROW split always puts rows of the same event on both sides — so the early-stopping score measures memorization, not generalization.


## 8. Data-quality scan

| check | value |
|--|--|
| n_rows | 94,969 |
| n_duplicate_feature_vectors | 430 |
| n_duplicate_groups | 215 |
| n_duplicate_groups_with_conflicting_labels | 0 |
| rows_with_all_rainfall_nan | 0 |
| soil_nodata_rate_overall | 0.0230 |
| soil_nodata_rate_positives | 0.0160 |
| soil_nodata_rate_negatives | 0.0237 |
| positive_segments | 1,780 |
| positive_segments_with_multiple_events | 464 |
| max_events_on_one_segment | 12 |

## 9. Artifacts

`stratified_performance.csv` · `per_event_detection.csv` · `fn_vs_tp_probe.csv` · `fp_top_segments.csv` · `label_noise_probe.csv` · `calibration_by_stratum.csv` · `worst_false_negatives.csv` · `worst_false_positives.csv` · `error_analysis.json` · plots (`per_event_detection.png`, `strata_ap.png`, `generalization_gap.png`, `confusion_operating_point.png`)

Interpretation, root-cause attribution and the ranked improvement plan are in `ERROR_ANALYSIS.md` (hand-authored from these numbers).