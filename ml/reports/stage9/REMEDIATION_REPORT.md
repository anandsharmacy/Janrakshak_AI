# Stage 9 — Remediation results

`final_v2` · config `5aed65f3f8729060` · git `nogit` · supersedes `5c8ab2326f9c5b5c` (retained as known-leaked).

> This is NOT an unbiased first read in the way final_v1's was. The remediation was prompted by findings obtained from reading the v1 test set. Every fix rests on dev-side measurement or label metadata, never on a test score, and the test region was deliberately NOT re-drawn — but the direction of investigation was test-informed and no protocol undoes that. Treat the v2 test number as a strong check, not a virgin estimate.

## A — leak

- segments spanning dev/test: **0** (was 1)
- positive events spanning: **0**
- blocks spanning: **0**

## B — rainfall signal, once leak and confound are removed

| | AP with rainfall | AP rainfall deleted | Δ | fold-seed pairs |
|--|--|--|--|--|
| in-scope target | **0.4023** | 0.2747 | **+0.1277** | **15/15** |

### Test metrics by label source

| stratum | n | pos | base rate | AP | lift | ROC |
|--|--|--|--|--|--|--|
| all | 8,274 | 1,341 | 0.1621 | 0.3366 | 2.08× | 0.7537 |
| IN SCOPE (rain-attributable) | 7,674 | 741 | 0.0966 | 0.2146 | 2.22× | 0.7699 |
| OUT OF SCOPE (not rain-attributable) | 7,533 | 600 | 0.0796 | 0.2146 | 2.69× | 0.7338 |
| coolr_glc | 7,674 | 741 | 0.0966 | 0.2146 | 2.22× | 0.7699 |
| corridor_landslides | 7,413 | 480 | 0.0648 | 0.1207 | 1.86× | 0.7471 |
| reliefweb_events | 7,053 | 120 | 0.0170 | 0.3259 | 19.16× | 0.6802 |

## C — monotonicity

| rain × | flags recomputed | violations |
|--|--|--|
| 1.25 | True | 0 |
| 1.50 | True | 0 |
| 2.00 | True | 0 |
| 4.00 | True | 0 |
| 1.25 | False | 0 |
| 1.50 | False | 0 |
| 2.00 | False | 0 |
| 4.00 | False | 0 |

## D — steep terrain

- NOT under-represented — steep carries 89.3% of dev positives from 41.0% of rows, so sampling/weighting is not the lever
- base-rate spread across steep sub-bands: 0.0669

## E — deployment gates, before and after

| gate | threshold | v1 | | v2 | |
|--|--|--|--|--|--|
| beats chance on held-out ground | test AP / base rate > 2.0 | 2.32x | PASS | 2.20x | PASS |
| top-of-ranking precision | precision@100 >= 0.50 | 0.810 | PASS | 0.290 | **FAIL** |
| recall at the operating threshold | >= 0.80 | 0.926 | PASS | 0.955 | PASS |
| STEEP-TERRAIN discrimination | steep ROC-AUC >= 0.70 | 0.624 | **FAIL** | 0.630 | **FAIL** |
| steep-terrain lift | >= 2.0x | 1.44x | **FAIL** | 1.43x | **FAIL** |
| probability calibration transfers | worst terrain stratum within 1.5x on unseen region | 2.20x | **FAIL** | 2.65x | **FAIL** |
| survives rainfall forecast error | >= 80% of clean AP at sigma = 0.25 | 97.3% | PASS | 99.5% | PASS |
| rainfall is actually driving the prediction | positives lose >= 30% of score under zero rainfall | 92.9% | PASS | 95.9% | PASS |
| daily corridor scoring fits the batch window | < 300 s for 309,042 segments | 1.03 s | PASS | 1.06 s | PASS |
| artifact size is deployable | < 50 MB | 0.69 MB | PASS | 0.69 MB | PASS |
| reproducible from config + seed | retrain reproduces the recorded test AP | bit-identical | PASS | bit-identical | PASS |
| rainfall monotonicity enforced end-to-end | 0 rank violations with derived flags recomputed | n/a (new gate) | — | 0 violations | PASS |

**8 of 12 gates pass.**
