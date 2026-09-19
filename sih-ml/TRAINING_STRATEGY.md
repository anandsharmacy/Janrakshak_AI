# TRAINING_STRATEGY — Stage 4 (training from scratch)

How this model is trained, what is guaranteed, what is deliberately *not*, and the
decision rules for what happens next. Numbers here come from
`reports/stage4/metrics.json`; nothing is estimated.

---

## 0. Vocabulary: this is a GBDT, not a neural net

The brief is phrased in neural-network terms. The honest mapping, so nothing is
silently faked:

| NN concept | GBDT equivalent here | Status |
|---|---|---|
| Architecture / initialization | Ensemble of depth-≤6 trees, `num_leaves=24`; init = prior log-odds | real |
| Epochs | Boosting rounds (≤1200, early-stopped) | real |
| Batch size | `bagging_fraction=0.8` + `bagging_freq=1` (row subsample per round) | real |
| Optimizer | Gradient boosting (Newton steps on logloss); no SGD/Adam | real |
| Learning rate | `learning_rate=0.025` (shrinkage per tree) | real |
| LR scheduler | **Not applicable.** Constant shrinkage is standard for GBDT; a decay schedule is available (`lgb.reset_parameter`) but has no evidence behind it here — not used. | N/A |
| Gradient clipping | `min_split_gain`, `min_child_samples=40`, L1/L2 (0.3/1.5) constrain step size | analogue |
| Mixed precision (AMP) | **Not applicable.** No GPU tensors. The nearest analogue, histogram quantization (`max_bin=255`), is already on and is what makes LightGBM fast. | N/A |
| GPU training | **Not used.** 103k rows × 47 features trains in ~20 s/fold on CPU; a GPU would be slower (transfer overhead). `device_type: gpu` is a one-line change if the panel grows ~100×. | deliberate |
| Dropout / weight decay | `feature_fraction=0.8`, `bagging_fraction=0.8`, L1/L2, `max_depth`, monotone constraints | real |

Claiming AMP or a LR scheduler here would be cargo-culting. They are listed as N/A
with the reason.

---

## 1. Training configuration

Defined in `conf/train_config.yaml`, which inherits `conf/model_baseline.yaml`
(deep-merge, `base_config:` key) and overrides only what Stage 4 changes.

- **Loss:** binary logloss, with per-fold `scale_pos_weight = n_neg/n_pos` for class
  imbalance, applied *on top of* Stage 2's per-row `sample_weight` (label
  confidence). Two independent levers, never conflated — imbalance vs label noise.
- **Early-stopping metric:** **PR-AUC** (`early_stopping_metric: pr_auc`). See §5 —
  this was the single highest-impact fix in Stage 4.
- **Regularization:** `num_leaves=24`, `max_depth=6`, `min_child_samples=40`,
  `reg_alpha=0.3`, `reg_lambda=1.5`, `feature_fraction=0.8`, `bagging_fraction=0.8`,
  plus monotone-increasing constraints on 10 rainfall features (more rain must not
  lower predicted risk).
- **"Augmentation":** handled upstream in Stage 2, not at train time — case-control
  negative sampling, the 2–25 km matched hard-negative donut, location-radius label
  spreading, season-matched negative dates. Synthetic tabular augmentation (SMOTE
  etc.) is deliberately off; with ~115 independent positive clusters it manufactures
  a decision boundary that does not generalize.

## 2. Training pipeline

`src/sih_ml/train/train_from_scratch.py`, run via `scripts/run_stage4.py`.

1. Load `panel_v1.parquet` + `folds_v1.parquet`, coerce dtypes, attach fold columns.
2. For each of the 5 spatial-block folds: carve an inner early-stopping split from
   the training rows, fit with early stopping, predict the held-out blocks (OOF).
3. Fit an isotonic calibrator on pooled OOF; compute the cost-sensitive threshold.
4. Fit the final model on all dev data at the mean of the folds' best iterations.
5. Write checkpoints, metrics, plots, model card; log everything to MLflow.

**Best-model selection:** per fold, the booster is truncated to `best_iteration`
(PR-AUC-optimal round on the inner split). The final production model uses the
*mean* of the folds' best iterations — not the max, which would inherit the most
overfit fold's budget.

**Resume:** `periodic_checkpoint_callback` snapshots the booster every 50 rounds
to `checkpoints/<model_version>/fold_k/` plus a `_progress.json`. Re-running the
same command auto-detects the snapshot and continues via LightGBM `init_model`.
Verified end-to-end: a fold checkpointed at round 80 resumed to 180 rather than
restarting.

> **Resume contract (verified empirically, not assumed):** resumed training is
> **not** bit-identical to one uninterrupted run — the bagging / feature-sampling
> RNG stream restarts at the resume boundary. Measured on a controlled 100-round
> job (50 + resumed 50 vs continuous 100): max per-row probability difference
> 0.18, AP 0.9442 vs 0.9487. **Use resume for crash recovery, never to reproduce a
> specific run.** For an exact reproduction, delete the checkpoints and start clean.

## 3. Monitoring

- **MLflow** (local SQLite backend — MLflow 3.x put the old `./mlruns` file store
  into maintenance mode): one parent run per training run, one nested run per fold.
  Logged: all hyperparameters, per-round train/val curves as step-indexed metrics,
  fold and pooled metrics, and artifacts (plots, final model, feature importance).
  `mlflow ui --backend-store-uri sqlite:///mlruns/mlflow.db`
- **Per-round curves** (`reports/stage4/training_curve_fold{k}.png`): one panel per
  metric (never logloss and PR-AUC on the same axis), with the outer fold's
  held-out-block AP drawn as a reference line.
- **Every future run must record** the ledger defined in
  `reports/stage3/BASELINE_ANALYSIS.md` §4 — pooled AP *and* per-fold mean±std,
  rule-baseline APs from the same OOF rows, fold best-iterations, feature-importance
  top-15. Single numbers without the spread are not acceptable comparisons.

### The overfitting diagnostic that actually matters here

The inner early-stopping set is a **stratified row sample of the same spatial
blocks as train** — it is in-distribution. So a train-vs-`es` gap is *not* an
overfitting signal in this project. The real signal is **`es` vs held-out blocks**:

> Fold 0: inner-ES PR-AUC climbs to **0.87**, while the actual held-out-block AP is
> **0.46**. That ~0.4 gap *is* the spatial generalization gap — it is the single
> clearest quantification of why this project refuses random k-fold.

Read the curves this way:
- `es` and held-out both low & flat → underfit (add capacity/rounds).
- `es` high, held-out far below → the model is learning region-specific structure
  that does not transfer. More rounds will not help; better features / labels will.
- `es` logloss rising while `es` PR-AUC still climbs → probability drift without
  ranking loss; calibration will absorb it, do not stop on logloss (see §5).

## 4. Reproducibility & reliability

**Guaranteed:** `seed=42` threaded through numpy, Python `random`, and every
LightGBM bagging/feature-sampling call; LightGBM `deterministic=True` +
`force_row_wise=True` (disables the multithreaded histogram race that otherwise
makes LightGBM non-deterministic); fixed row order (parquet, no shuffle on load);
pinned versions in `requirements.txt`. Enforced by
`test_same_seed_same_predictions` (exact equality, `atol=0`) — paired with
`test_different_seed_different_predictions` so the determinism test cannot pass
vacuously by the seed being ignored.

**Not guaranteed:** resumed runs (§2); bit-exactness across different
LightGBM/OpenMP versions or CPU architectures (floating-point summation order).

**Leakage prevention** (inherited from Stage 2, enforced by
`tests/test_no_leakage.py` + `tests/test_splits.py`): rainfall features lagged 1
day; event-history features lagged 30 days *and* excluded from the model entirely;
all in-fold transforms fitted on training rows only; spatial blocks never split
across folds; 5 km buffer zone; positive events pinned to their modal block; LOECO
union-find merges repeat-offender segments; `final_test` untouched since Stage 2.

**Consistency check:** Stage 4 re-runs the Stage 3 fold definitions through the new
tracked/checkpointed code path and asserts the result matches. It reports
**|diff| = 0.0000** with the Stage 3 config — proof that the added infrastructure
does not perturb training. (The first attempt reported 0.0010; the cause was a real
bug — see §5.)

## 5. Two bugs this stage's monitoring caught

**(a) The curve-tracking valid set was influencing early stopping.** To plot the
training curve I passed the training set as a second `valid_set`. LightGBM's
early-stopping callback skips the training set *only* if its name matches
`Booster._train_data_name`, which defaults to the literal string `"training"`.
Mine was named `"train"` — so it was being counted, and `best_iteration` shifted
(17 → 15 on fold 0). Fixed by using the exact name; the consistency check then went
to 0.0000.

**(b) Early stopping was driven by logloss, not the declared primary metric.**
LightGBM tracks the objective's built-in `binary_logloss` *in addition to* our
custom PR-AUC `feval`, and stops on whichever goes stale first. On fold 0, logloss
bottomed at round ~17 while PR-AUC was still climbing at round 96 — so training was
cut short by a metric we never declared as primary. Setting `metric: "None"` leaves
PR-AUC as the sole early-stopping signal.

**Measured effect of (b)** — spatial-CV mean AP, identical data/folds/seed:

| Early-stopping metric | Spatial-CV mean AP | Folds 0 / 1 |
|---|---|---|
| logloss + PR-AUC (Stage 3) | 0.285 ± 0.106 | 0.296 / 0.484 |
| **PR-AUC only (Stage 4)** | **0.325 ± 0.139** | **0.441 / 0.536** |

That single line of config is worth +0.039 mean AP and closes most of the gap to
the logistic-regression reference (0.318 pooled) flagged in Stage 3.

## 6. Training strategy: stages and decision rules

**Stage A — sanity (done).** Fixed seed, tiny round budget, confirm the pipeline
runs, checkpoints, resumes, and reproduces Stage 3 exactly.
**Stage B — train to the pre-registered budget (done).** 5 spatial folds, PR-AUC
early stopping, 1200-round cap.
**Stage C — decide: continue, tune, or move on (done, below).**

### Recorded ablation: should we train longer?

Every fold hit the 1200-round cap, which normally means "still improving — raise
the budget". So I did, and recorded the result rather than assuming:

| Round cap | Where folds stopped | Spatial-CV mean AP |
|---|---|---|
| 1200 (pre-registered) | at the cap | **0.325 ± 0.139** |
| 5000 | 1678–2712 (genuine early stop) | 0.318 ± 0.144 |

Letting the inner ES set run to its own optimum made it **worse**. Cause: the inner
ES set is in-distribution (§3), so it over-recommends rounds that fit local
structure and do not transfer across regions.

**The cap stays at 1200 — and I am explicit that this is Stage 3's pre-registered
value, not a tuned one.** Choosing 1200 *because* it scored better on the outer
folds would be selection on the evaluation set. Principled round selection needs a
*block-based* inner holdout (so the stopping signal reflects cross-region
generalization) and belongs in Stage 6 HPO, where it can be done inside a nested
loop.

### Decision rules for what comes next

| Observation | Decision |
|---|---|
| Folds stop well before the cap **and** held-out AP tracks the ES curve | Training budget is fine. Move on. |
| Folds hit the cap **and** raising it improves held-out AP | Continue training — raise the cap. |
| Folds hit the cap **but** raising it *hurts* held-out AP ← **we are here** | Stop adding rounds. The bottleneck is generalization, not capacity. Fix the stopping signal (block-based inner split) and the features/labels. |
| Held-out AP gain < the fold std (±0.14) | Not a real improvement. Do not claim it. |
| A held-out metric jumps far above spatial-block CV | Assume leakage first. (This is how the LOECO repeat-offender bug was caught in Stage 3.) |
| Rule baselines within ~1 fold-std of the model | The model is not earning its complexity — fix data, not hyperparameters. |

**Verdict: move to Stage 5/6, do not keep training.** The evidence says added
capacity does not transfer. The highest-value next moves, in order, are the ones
already listed in `reports/stage3/BASELINE_ANALYSIS.md` §5 — with one addition
promoted to the top by this stage's ablation:

0. **(new, top priority)** Replace the inner early-stopping split with a
   *block-based* inner holdout inside a nested CV, so the round count is chosen by
   a cross-region signal. This stage proved the current in-distribution signal is
   systematically biased.
1. HPO on the leak-safe harness, objective = **mean per-fold AP** (not pooled).
2. Explain the remaining LightGBM-vs-logistic gap (sweep `num_leaves` toward
   near-linear; ablate the monotone constraints).
3. Ensemble LightGBM + logistic + rules.

## 7. Commands

```bash
brew install libomp                 # macOS only — LightGBM needs OpenMP
make stage4                         # train from scratch (auto-resumes if interrupted)
make stage4-clean                   # discard checkpoints, force a fresh run
make test                           # 37 tests: leakage, schema, splits, baseline, training
mlflow ui --backend-store-uri sqlite:///mlruns/mlflow.db   # experiment history
```

Outputs: `models/training_v1/` (per-fold + final boosters, calibrator, OOF
predictions, model card), `reports/stage4/` (TRAINING_REPORT.md, metrics.json,
training curves, diagnostic plots), `mlruns/` (MLflow), `checkpoints/` (transient).

## 8. Current status

- Spatial-CV mean AP **0.325 ± 0.139**, pooled 0.300, calibrated 0.294,
  ROC-AUC 0.856. Logistic-regression reference: 0.318 pooled.
- `final_test` remains **locked and untouched** since Stage 2. It is not opened
  until Stage 8.
- This is not a finished model. It is a reproducible, monitored, resumable
  training pipeline plus the honest number it currently produces.
