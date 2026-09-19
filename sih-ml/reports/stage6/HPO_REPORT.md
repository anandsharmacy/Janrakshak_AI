# Stage 6 — Fine-Tuning & HPO results

git `nogit` · selection folds [0, 1, 2] · report folds [3, 4] (never seen by the search) · `final_test` still locked.

All numbers measured. Improvements are only claimed where they exceed the fold-spread noise floor.

## Controlled experiments (mean AP)

| experiment | selection folds | **report folds** |
|--|--|--|
| E0 baseline (row ES) | 0.3984 | **0.2143** ± 0.031 |
| E1 + event-grouped ES (P0 fix) | 0.3566 | **0.2029** ± 0.025 |
| E2 HPO best (29 complete / 11 pruned) | 0.4397 | **0.2168** ± 0.022 |

## Verdict

- argmax on report folds: **E2_hpo_tuned**
- margin over baseline: **+0.0025**
- fold-spread noise floor: **0.0313**
- exceeds noise: **NO — not demonstrated**

> Select the tuned config ONLY if its report-fold gain exceeds the fold spread AND it is not materially larger/slower. With 2 report folds the spread is a crude noise floor, so a gain inside it is reported as 'not demonstrated', never as an improvement.

## Best hyperparameters

```json
{
  "num_leaves": 4,
  "max_depth": 11,
  "min_child_samples": 364,
  "learning_rate": 0.03218814577630251,
  "reg_alpha": 1.9787843500081188,
  "reg_lambda": 0.23696573020861914,
  "colsample_bytree": 0.8531476828735367,
  "subsample": 0.6971305573243116,
  "min_split_gain": 0.8392636293753901,
  "use_monotone": true,
  "scale_pos_weight_mult": 0.1381132349355172
}
```

## Staged fine-tuning (out-of-time test, 2019+)

| stage | AP | trees |
|--|--|--|
| base_old_period_only | 0.0951 | 1,192 |
| 0_frozen_base | 0.0951 | 1,192 |
| 1_refit_leaves | 0.0980 | 1,192 |
| 2_continue_boosting | 0.0823 | 1,228 |
| 3_full_retrain_on_train+adapt | 0.1952 | 1,194 |

GBDT has no layers: stage 1 = `Booster.refit()` (tree structure frozen, leaf values recomputed), stage 2 = continue boosting at reduced LR, stage 3 = full retrain. See `finetune.py` docstring.

## Artifacts

`hpo_results.json` · `best_params.json` · `hpo_trials.csv` · `finetune_stages.csv` · `hpo_history.png` · `experiment_comparison.png` · `finetune_stages.png` · Optuna study `studies/*.db` (resumable)