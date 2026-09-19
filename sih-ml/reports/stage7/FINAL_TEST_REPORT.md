# Stage 7/8 — Final model on the locked test set

Opened **2026-09-11T12:55:17 UTC** · opening #1 · config `5c8ab2326f9c5b5c` · git `nogit`

This split has been held out since Stage 2 and was read for the first time by this run. The configuration and this metric list were frozen in `PREREGISTRATION.json` beforehand.

Test set: **8,277 rows**, 1,344 positives, 3 gold (verified) labels.

## Headline

| metric | value |
|--|--|
| **Average precision (PR-AUC)** | **0.3760** |
| ROC-AUC | 0.7879 |
| Brier | 0.1174 |
| ECE | 0.0469 |
| base rate | 0.1624 |

### Dev vs test — read the base rates before the APs

| | dev (spatial-CV OOF) | locked test |
|--|--|--|
| rows | 94,969 | 8,277 |
| base rate | 0.0847 | **0.1624** |
| average precision (pooled) | 0.3791 | 0.3760 |
| **AP / base rate** | **4.48×** | **2.32×** |
| ROC-AUC (base-rate independent) | 0.8564 | **0.7879** |

*(The pre-registered dev figure, 0.3782, is the **mean of the five per-fold APs** — the quantity the decision rule used. 0.3791 is the **pooled** OOF AP, which is the like-for-like comparator for a single test pool. Both are quoted so neither can be swapped in for the other.)*

Raw AP barely moves (0.3782 → 0.3760, -0.0022) and that is **a coincidence, not evidence of transfer**. The locked split is 1.9× denser in positives than the dev panel — it holds all 3 gold labels and was built as a spatially separate block set — and average precision scales with the base rate, so the same AP means substantially *less* skill there.

The base-rate-free comparisons both show real degradation: lift over chance **4.48× → 2.32×**, ROC-AUC **0.8564 → 0.7879**.

That gap mixes two causes that cannot be separated with one test split: selection bias (the dev number was used to choose among ~25 arms) and genuine distribution shift (a different region, a different label mix). Quoting the flat AP as "the model generalizes" would be the single most misleading sentence available here.


## Ranking

| k | precision@k | recall@k |
|--|--|--|
| 10 | 1.000 | 0.007 |
| 50 | 0.840 | 0.031 |
| 100 | 0.810 | 0.060 |
| 200 | 0.685 | 0.102 |

| top fraction | lift |
|--|--|
| 1% | 4.97× |
| 5% | 2.68× |
| 10% | 1.90× |

## Steep terrain (slope ≥ 10°) — the operational number

Stage 5 §1 established that global AP is inflated by separating plains from hills, which routing already knows for free. This is the subset where decisions actually happen.

- rows: **4,586**, base rate **0.2564**
- AP **0.3689** → lift over chance **1.44×**
- **ROC-AUC 0.6242**
- lift in the top 10% of scores: **1.35×**

**This is the weakest result in the report and the most important one.** A ROC-AUC of 0.624 on steep terrain is close to chance (0.5): once the model is confined to the roads that actually fail, it can barely rank them. The healthy-looking global numbers above are carried by telling plains from hills.

Stage 5 measured 1.63× steep-terrain lift on dev and flagged it as the finding that mattered most; the locked test confirms it independently. This is the number a judge should be shown, and it is the number that higher-resolution rainfall (Stage 5 P1) is meant to move.

## At the frozen operating threshold

threshold **0.0567** (frozen before opening; derived from the FN:FP cost policy, which is still unvalidated)

| | value |
|--|--|
| precision | 0.284 |
| recall | 0.926 |
| F1 | 0.435 |
| TP / FP / FN / TN | 1244 / 3133 / 100 / 3800 |

## The 3 verified labels

The only *verified* road closures in the entire project sit in this split. They scored at percentiles **99.08%**, **98.83%**, **98.83%** — all three in the **top 1.2%** of 8,277 test rows.

This is the most encouraging number in the project and it carries **no statistical weight whatsoever**: n = 3. It is reported because these are the only ground-truth labels that exist, and suppressing them would be as dishonest as over-claiming them. It is consistent with the model being useful at the top of the ranking; it is not evidence of it.

## Calibration on the test set

| stratum | n | pos | predicted | observed | pred/obs |
|--|--|--|--|--|--|
| slope [0, 2.5) | 3,057 | 39 | 0.0146 | 0.0128 | 1.14× |
| slope [2.5, 10) | 634 | 129 | 0.0923 | 0.2035 | 0.45× |
| slope [10, 20) | 1,515 | 219 | 0.1679 | 0.1446 | 1.16× |
| slope [20, 90) | 3,071 | 957 | 0.1954 | 0.3116 | 0.63× |
| all | 8,277 | 1,344 | 0.1157 | 0.1624 | 0.71× |

**The per-slope calibration fix does not survive the region shift.** Cross-fitted *within* dev it brought the worst terrain stratum to 1.32× (Stage 7 §6); on the locked split the worst stratum is **2.20×**, the model under-predicts overall at **0.71×**, and test ECE is 0.0469 against 0.0193 on dev.

This is the documented limitation arriving exactly as predicted: a calibrator can condition on terrain, which travels with the row, but not on *region* — a model scoring a new area cannot look up its own base rate. **Calibrated probabilities should not be trusted as absolute risk on unseen terrain**, which directly constrains the routing penalty `W = dist·(1 + λ·P)`. Use the ranking; re-fit the calibrator on local history before trusting the magnitude.


## Frozen configuration

```json
{
  "lgbm": {
    "objective": "binary",
    "boosting_type": "gbdt",
    "learning_rate": 0.03218814577630251,
    "num_leaves": 4,
    "max_depth": 11,
    "min_child_samples": 364,
    "min_split_gain": 0.8392636293753901,
    "subsample": 0.6971305573243116,
    "subsample_freq": 1,
    "colsample_bytree": 0.8531476828735367,
    "reg_alpha": 1.9787843500081188,
    "reg_lambda": 0.23696573020861914,
    "n_estimators": 1200,
    "early_stopping_rounds": 80,
    "max_bin": 255,
    "verbosity": -1,
    "auto_scale_pos_weight": true,
    "monotone_rainfall_features": [
      "rain_1d_mm",
      "rain_3d_mm",
      "rain_7d_mm",
      "rain_15d_mm",
      "rain_30d_mm",
      "rain_max_1d_in_3d_mm",
      "api_mm",
      "id_ratio_1d",
      "id_ratio_3d",
      "id_ratio_7d"
    ],
    "early_stopping_metric": "pr_auc",
    "scale_pos_weight_mult": 0.1381132349355172
  },
  "n_estimators_final": 1200,
  "cv_mean_best_iter": 944.8,
  "cv": {
    "es_split_mode": "event",
    "drop_buffer_rows": true
  },
  "scorer": "composite/passed",
  "ensemble_weights": null,
  "calibration": "per_slope_isotonic",
  "operating_threshold": 0.05667060212514758,
  "cost_fn_over_fp": 20.0,
  "composite_steps": [
    "aug/gaussian_all_s0.1",
    "aug/smote_k5_f0.5"
  ]
}
```
