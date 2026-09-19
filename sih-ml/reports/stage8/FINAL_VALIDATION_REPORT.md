# Stage 8 — Final Model Validation

Frozen config `5c8ab2326f9c5b5c` · git `nogit` · test-set **decision openings: 1**

Stage 8 selects nothing. The locked split was opened once, under pre-registration, at the end of Stage 7; everything here is descriptive analysis of that frozen artifact. The config hash is verified on entry and a mismatch aborts the run.

## 1. Reproducibility

- recorded test AP: `0.376003011273`
- retrained from config + seed: `0.376003011273`
- **bit-identical: True**

> Bit-exactness holds for this machine and these pinned library versions. LightGBM/OpenMP version changes or a different CPU architecture can alter floating-point summation order; pin requirements.txt for cross-machine reproduction.

## 2. Final test results

| metric | value |
|--|--|
| average precision | **0.3760** |
| ROC-AUC | 0.7879 |
| Brier | 0.1174 |
| ECE | 0.0469 |
| base rate | 0.1624 |
| **AP / base rate** | **2.32×** |

### Class-wise

| class | precision | recall | F1 | support | predicted |
|--|--|--|--|--|--|
| 0 — no disruption | 0.974 | 0.548 | 0.702 | 6,933 | 3,900 |
| 1 — disruption | 0.284 | 0.926 | 0.435 | 1,344 | 4,377 |

Confusion @ threshold 0.0567: TP 1,244 · FP 3,133 · FN 100 · TN 3,800

Plots: `confusion_matrix.png` · `pr_curve.png` · `roc_curve.png` · `reliability.png` · `score_distribution.png`

## 3. Generalization

| split | n | base rate | AP | lift over chance | ROC-AUC |
|--|--|--|--|--|--|
| train (in-sample) | 80,688 | 0.0843 | 0.7731 | **9.17×** | 0.9655 |
| early-stopping | 14,281 | 0.0870 | 0.7291 | **8.38×** | 0.9528 |
| dev spatial-CV OOF | 94,969 | 0.0847 | 0.3791 | **4.48×** | 0.8564 |
| LOCKED TEST | 8,277 | 0.1624 | 0.3760 | **2.32×** | 0.7879 |

Lift over chance is the comparable column — these splits have very different base rates and AP scales with the base rate.

## 4. Leakage audit

- exact (segment, date) overlap dev↔test: **0**
- shared positive `event_id`s: **0**
- shared `segment_id`s: **1 of 4392** test segments
- shared spatial blocks: 1 of 6

> **`SEG291652`** — 15 training rows (15 positive, across 5 distinct events) and 3 test rows (3 positive, tiers ['gold']). Nearest training row is 671 days away.

## 4b. Why the test number looks the way it does

`final_test` was defined in Stage 2 as a set of spatial blocks **plus every gold label**, with no constraint on label-source mix. The split therefore differs from dev in *what kind of positive it contains*, not only in where it is:

| split | label source | positives | share | mean rain 7d |
|--|--|--|--|--|
| dev | coolr_glc | 7,263 | 90% | 101.0 mm |
| dev | corridor_landslides | 660 | 8% | 76.7 mm |
| dev | reliefweb_events | 120 | 1% | 0.1 mm |
| locked test | coolr_glc | 741 | 55% | 84.7 mm |
| locked test | corridor_landslides | 480 | 36% | 48.1 mm |
| locked test | reliefweb_events | 120 | 9% | 13.2 mm |
| locked test | verified_segment_label | 3 | 0% | 44.0 mm |

### Rainfall as a standalone ranking score (no model)

| feature | dev ROC | test ROC | dev pos/neg mm | test pos/neg mm |
|--|--|--|--|--|
| rain_1d_mm | 0.5886 | **0.5161** | 15.1 / 9.3 | 13.8 / 11.3 |
| rain_3d_mm | 0.6395 | **0.5011** | 44.4 / 27.8 | 31.5 / 33.1 |
| rain_7d_mm | 0.6475 | **0.4595** | 97.5 / 64.9 | 65.1 / 76.2 |
| rain_15d_mm | 0.6422 | **0.4293** | 194.4 / 137.9 | 133.6 / 162.2 |
| rain_30d_mm | 0.6431 | **0.4128** | 386.8 / 270.8 | 252.5 / 318.5 |
| api_mm | 0.6469 | **0.4214** | 151.3 / 105.0 | 101.4 / 123.6 |
| id_ratio_3d | 0.6395 | **0.5011** | 0.6 / 0.4 | 0.4 / 0.5 |

**On the locked test split, rainfall carries no usable signal and the longer windows are inverted** — disrupted days had *less* rain than undisrupted ones. On dev the same features sit at ROC 0.59–0.65. This is the single most important line in the report: the input the entire problem framing rests on does not separate the classes on held-out ground.

## 5. Robustness

### 5.1 Counterfactual: delete the rainfall

- AP with observed rainfall: **0.3743**
- AP with every rainfall input zeroed: **0.4821**
- positives retain a median **7.1%** of their score with the rain removed

For the 3 verified (gold) rows specifically:

| | observed | zero rainfall |
|--|--|--|
| score | 0.8214 | 0.1019 |
| score | 0.8023 | 0.0993 |
| score | 0.7996 | 0.0993 |
| percentile | 99.3%, 99.2%, 99.1% | 99.1%, 99.0%, 99.0% |

### 5.2 Feature-group ablation

| group blanked | AP | Δ | % of baseline |
|--|--|--|--|
| seasonal | 0.3084 | -0.0658 | 82% |
| hydrology | 0.3342 | -0.0400 | 89% |
| road | 0.3531 | -0.0211 | 94% |
| landcover_lithology | 0.3561 | -0.0181 | 95% |
| soil | 0.3598 | -0.0145 | 96% |
| rainfall_provenance | 0.3640 | -0.0102 | 97% |
| (none — baseline) | 0.3743 | +0.0000 | 100% |
| terrain | 0.3746 | +0.0003 | 100% |
| rainfall | 0.4862 | +0.1120 | 130% |

### 5.3 Sensitivity to rainfall error (inference-time noise)

| σ | AP | % of clean | ROC-AUC |
|--|--|--|--|
| 0.00 | 0.3743 | 100.0% | 0.7652 |
| 0.05 | 0.3760 | 100.5% | 0.7658 |
| 0.10 | 0.3737 | 99.8% | 0.7641 |
| 0.25 | 0.3643 | 97.3% | 0.7555 |
| 0.50 | 0.3303 | 88.3% | 0.7362 |
| 1.00 | 0.2970 | 79.3% | 0.7096 |

Deployment scores a rainfall *forecast*, not an observation, so this curve is the realistic operating condition rather than a stress test.

### 5.4 Edge cases

| case | n | base rate | AP | lift | recall | precision |
|--|--|--|--|--|--|--|
| all test rows | 8,277 | 0.1624 | 0.3743 | 2.30× | 0.824 | 0.294 |
| zero rain (1d = 0) | 4,142 | 0.1593 | 0.3969 | 2.49× | 0.756 | 0.318 |
| bone dry (7d = 0) | 1,337 | 0.0898 | 0.1843 | 2.05× | 0.125 | 0.126 |
| extreme rain (1d, top 1%) | 83 | 0.3976 | 0.4810 | 1.21× | 0.909 | 0.423 |
| extreme rain (7d, top 1%) | 84 | 0.0714 | 0.1012 | 1.42× | 1.000 | 0.102 |
| soil NODATA | 1,489 | 0.0645 | 0.4189 | 6.50× | 0.469 | 0.181 |
| bridges | 559 | 0.3327 | 0.5290 | 1.59× | 0.806 | 0.490 |
| very steep (slope >= 30) | 718 | 0.5348 | 0.6079 | 1.14× | 0.794 | 0.566 |
| flat (slope < 2.5) | 3,057 | 0.0128 | 0.1118 | 8.76× | 0.513 | 0.082 |
| dry season | 2,105 | 0.1373 | 0.7149 | 5.21× | 0.844 | 0.483 |
| monsoon | 6,172 | 0.1709 | 0.2746 | 1.61× | 0.819 | 0.265 |

### 5.5 Monotonicity of the rainfall constraints

| rain × | violations | rate | mean score |
|--|--|--|--|
| 1.25 | 77 | 0.0257 | 0.1531 |
| 1.50 | 58 | 0.0193 | 0.1869 |
| 2.00 | 42 | 0.0140 | 0.2579 |
| 4.00 | 18 | 0.0060 | 0.3890 |
| 1.25 | 0 | 0.0000 | 0.1525 |
| 1.50 | 0 | 0.0000 | 0.1843 |
| 2.00 | 0 | 0.0000 | 0.2513 |
| 4.00 | 0 | 0.0000 | 0.3740 |

### 5.6 Selective prediction (alert on the top X%)

| coverage | alerts | precision | recall | lift |
|--|--|--|--|--|
| 1% | 83 | 0.807 | 0.050 | 4.97× |
| 2% | 166 | 0.723 | 0.089 | 4.45× |
| 5% | 414 | 0.435 | 0.134 | 2.68× |
| 10% | 828 | 0.308 | 0.190 | 1.90× |
| 20% | 1,655 | 0.329 | 0.405 | 2.02× |
| 30% | 2,483 | 0.320 | 0.591 | 1.97× |
| 50% | 4,138 | 0.292 | 0.900 | 1.80× |
| 100% | 8,277 | 0.162 | 1.000 | 1.00× |

## 6. Performance by group

| group | n | base rate | AP | lift | ROC-AUC |
|--|--|--|--|--|--|
| overall: all | 8,277 | 0.1624 | 0.3760 | 2.32× | 0.7879 |
| label_tier: gold | 6,936 | 0.0004 | 0.1209 | 279.47× | 0.9978 |
| label_tier: silver | 7,194 | 0.0363 | 0.1990 | 5.49× | 0.8269 |
| label_tier: bronze | 8,013 | 0.1348 | 0.3106 | 2.30× | 0.7779 |
| hazard: landslide | 7,797 | 0.1108 | 0.2925 | 2.64× | 0.7968 |
| hazard: landslide+flood | 7,293 | 0.0494 | 0.0985 | 2.00× | 0.7564 |
| hazard: flood | 7,053 | 0.0170 | 0.3643 | 21.41× | 0.8181 |
| spatial_block: BLK_004_006 | 1,978 | 0.0637 | 0.1918 | 3.01× | 0.6306 |
| spatial_block: BLK_004_007 | 646 | 0.0929 | 0.1298 | 1.40× | 0.6434 |
| spatial_block: BLK_005_004 | 3,374 | 0.0356 | 0.4373 | 12.30× | 0.8873 |
| spatial_block: BLK_006_008 | 1,265 | 0.7660 | 0.8563 | 1.12× | 0.6612 |
| spatial_block: BLK_009_005 | 1,011 | 0.0653 | 0.0914 | 1.40× | 0.6724 |
| slope_deg: [0, 2.5) | 3,057 | 0.0128 | 0.0634 | 4.97× | 0.7701 |
| slope_deg: [2.5, 10) | 634 | 0.2035 | 0.5638 | 2.77× | 0.8176 |
| slope_deg: [10, 20) | 1,515 | 0.1446 | 0.2704 | 1.87× | 0.6680 |
| slope_deg: [20, 90) | 3,071 | 0.3116 | 0.3970 | 1.27× | 0.5773 |
| season: monsoon | 6,172 | 0.1709 | 0.2874 | 1.68× | 0.7180 |
| season: dry | 2,105 | 0.1373 | 0.7240 | 5.27× | 0.9466 |
| highway: unclassified | 3,216 | 0.2015 | 0.3566 | 1.77× | 0.6689 |
| highway: residential | 2,954 | 0.0609 | 0.3588 | 5.89× | 0.9081 |
| highway: track | 952 | 0.0347 | 0.0900 | 2.60× | 0.7911 |
| highway: tertiary | 682 | 0.3211 | 0.5166 | 1.61× | 0.7683 |
| highway: secondary | 284 | 0.6761 | 0.8081 | 1.20× | 0.7169 |
| highway: trunk | 97 | 0.4639 | 0.5613 | 1.21× | 0.6521 |
| soil: soil NODATA | 1,489 | 0.0645 | 0.4838 | 7.50× | 0.8184 |
| soil: soil present | 6,788 | 0.1839 | 0.3664 | 1.99× | 0.7551 |
| period: 2007-2012 | 2,791 | 0.2397 | 0.4170 | 1.74× | 0.7504 |
| period: 2013-2018 | 2,140 | 0.0631 | 0.3449 | 5.47× | 0.8882 |
| period: 2019-2026 | 3,346 | 0.1614 | 0.4103 | 2.54× | 0.8104 |

## 7. Production readiness

- model size **710.3 KB** (1199 trees, 4796 leaves)
- **3.329 µs/row**, 300,366 rows/s single-core
- full corridor (309,042 segments): **1.03 s**
- peak prediction memory 7.15 MB

### Scalability

| rows | median s | µs/row | rows/s | projected corridor |
|--|--|--|--|--|
| 1,000 | 0.0053 | 5.315 | 188,164 | 1.642 s |
| 10,000 | 0.0315 | 3.145 | 317,916 | 0.972 s |
| 50,000 | 0.1552 | 3.104 | 322,161 | 0.959 s |
| 100,000 | 0.3329 | 3.329 | 300,420 | 1.029 s |

### Deployment gates — **8 of 11 pass**

| gate | threshold | measured | pass | why it exists |
|--|--|--|--|--|
| beats chance on held-out ground | test AP / base rate > 2.0 | **2.32x** | PASS | below this the ranking is not worth the pipeline |
| top-of-ranking precision | precision@100 >= 0.50 | **0.810** | PASS | operators act on the top of the list, not the whole list |
| recall at the operating threshold | >= 0.80 | **0.926** | PASS | a missed closure is the costly error for this product |
| STEEP-TERRAIN discrimination | steep ROC-AUC >= 0.70 | **0.624** | **FAIL** | the roads that actually close are all steep; global AP is inflated by plains-vs-hills, which routing already knows |
| steep-terrain lift | >= 2.0x | **1.44x** | **FAIL** | operational value, not global value |
| probability calibration transfers | worst terrain stratum within 1.5x on unseen region | **2.20x** | **FAIL** | calibrated P becomes the routing penalty W = dist*(1 + lambda*P) |
| survives rainfall forecast error | >= 80% of clean AP at sigma = 0.25 | **97.3%** | PASS | deployment feeds a forecast, not an observation |
| rainfall is actually driving the prediction | positives lose >= 30% of score under zero rainfall | **92.9%** | PASS | otherwise it is a terrain map with a weather-shaped label |
| daily corridor scoring fits the batch window | < 300 s for 309,042 segments | **1.03 s** | PASS | once-daily batch job |
| artifact size is deployable | < 50 MB | **0.69 MB** | PASS | ships inside a container image |
| reproducible from config + seed | retrain reproduces the recorded test AP | **bit-identical** | PASS | an unreproducible model cannot be audited or rolled back |

### Inference optimization

| technique | recommended | reason | revisit if |
|--|--|--|--|
| quantization (int8 leaf values) | no | model is 0.69 MB and the full corridor scores in 1.03 s. LightGBM inference is memory-bandwidth-bound on tree traversal, not arithmetic-bound, so quantizing leaves saves neither meaningfully. | artifact must fit under ~1 MB (edge/embedded deployment) |
| pruning / tree-count reduction | no | early stopping already selected the round count on an event-grouped holdout; cutting further trades measured accuracy for latency the product does not need. | per-request latency ever becomes user-facing (< 50 ms budget) |
| ONNX / Treelite / TensorRT export | no | adds a second artifact, a conversion step and a numerical-equivalence risk to version and test, for a job with ~300x headroom in its batch window. | the serving language stops being Python, or per-row latency must drop below ~1 us |
| GPU inference | no | 1.03 s on one CPU core for the entire corridor. | corridor grows >100x or cadence becomes sub-minute |
| batch the daily scoring job + cache static features | YES | static terrain/soil/road columns never change; only the rainfall block needs recomputing daily. This is where the real pipeline cost sits — feature assembly, not model inference. | n/a — do this |

## 8. Artifacts

`models/final_v1/` — booster, calibrators, model card · `reports/stage8/` — this report, `final_validation.json`, per-probe CSVs, plots · `reports/stage7/PREREGISTRATION.json` + `TEST_SET_LEDGER.json` — the audit trail.