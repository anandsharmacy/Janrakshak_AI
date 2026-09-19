# FINETUNING_HPO_STRATEGY — Stage 6

Methodology and decision rules. **Measured results live in
`reports/stage6/HPO_REPORT.md` / `hpo_results.json`** — this document does not
restate them, so it can never drift out of sync with the numbers.

---

## 0. The prerequisite: HPO was impossible before this stage

Stage 5 measured that the inner early-stopping set scored **AP 0.999** because
**100% of its positives belonged to an event that also had training rows** (one
event → up to 60 panel rows). A search run against that signal would rank every
hyperparameter configuration identically — the objective would be noise around 1.0.

So Stage 6 opens by landing the Stage 5 **P0 fix**: `cv.es_split_mode: "event"`
(`train/cv.py::event_grouped_es_split`). Positives are held out by whole `event_id`,
negatives split randomly. Stage 3/4 configs keep `"row"` so their published numbers
stay reproducible.

**This is sequencing, not preference.** Tuning first would have produced a
confident-looking but meaningless result.

---

## 1. Fine-tuning strategy — honest GBDT analogues

A gradient-boosted tree ensemble has **no layers to freeze**, so "progressive
unfreezing" has no literal equivalent. Rather than invent one, `train/finetune.py`
implements the real analogues, ordered by how much of the model may change:

| stage | NN analogue | GBDT mechanism |
|---|---|---|
| 0 | frozen backbone + frozen head | reuse the base model unchanged (control) |
| 1 | **freeze backbone, tune head** | `Booster.refit()` — keep every tree's split features and thresholds, recompute only the **leaf values** on the target data |
| 2 | **partial unfreeze, low LR** | continue boosting via `init_model` at a reduced learning rate: existing trees are immutable, new trees are appended to correct the residual |
| 3 | full unfreeze | retrain from scratch (control) |

**Learning rate per stage.** Stage 1 has no learning rate (it is a closed-form leaf
update; `refit_decay` controls blending toward the new data). Stage 2 uses
`continue_lr_scale × base learning_rate` — the direct equivalent of a reduced
fine-tuning LR. Stage 3 uses the tuned LR.

**What is fine-tuned toward.** The measured Stage 5 temporal degradation
(spatial-CV AP 0.294 vs out-of-time 0.232) makes the adaptation target obvious:
train on the old period (≤2015), adapt on 2016–2018, evaluate on 2019+. The test
window is never seen by any stage.

**Checkpointing / early stopping** are inherited from Stage 4 (event-grouped ES
signal, periodic crash-resume snapshots, best-iteration truncation).

---

## 2. Hyperparameter optimization

**Method: Optuna TPE (Bayesian) + median pruner.** Justification — the search space
is ~11 mixed int/float/categorical dimensions with a fit cost of ~10 s, which is
exactly TPE's regime: too expensive for exhaustive grid, too structured to waste on
pure random. The median pruner kills a trial after its first selection fold if it is
already below the running median, which is where most of the compute saving comes
from. Studies persist to SQLite (`studies/*.db`) and **resume** on re-run.

### What is searched, and why

Stage 5 measured **in-sample AP 0.9999 against held-out 0.29** — capacity is
unconstrained relative to real signal. So the space is dominated by capacity and
regularization:

| parameter | range | rationale |
|---|---|---|
| `num_leaves` | 4–64 (log) | primary capacity knob; Stage 3 hinted the near-linear end may win |
| `max_depth` | 3–12 | interacts with num_leaves; constrains per-segment fingerprinting |
| `min_child_samples` | 10–400 (log) | the main defence against memorising a single event |
| `learning_rate` | 0.005–0.15 (log) | shrinkage; trades off against round count |
| `reg_alpha` / `reg_lambda` | 1e-3–20 / 1e-3–50 (log) | L1 / L2 |
| `colsample_bytree` | 0.4–1.0 | **the GBDT analogue of dropout** |
| `subsample` | 0.5–1.0 | **the GBDT analogue of batch size** (row sampling per round) |
| `min_split_gain` | 0.0–1.0 | prunes low-value splits |
| `use_monotone` | {true, false} | Stage 3 flagged the 10 rainfall monotone constraints as possibly too rigid under label noise — make it a *decision*, not an assumption |
| `scale_pos_weight_mult` | 0.1–3.0 (log) | imbalance handling, on top of the per-fold `n_neg/n_pos` |

### Deliberately **not** searched

| excluded | why |
|---|---|
| `max_bin` | histogram resolution; negligible at 95k rows |
| `boosting_type` (`dart`/`goss`) | slower and less stable here; would consume trials for noise |
| `objective` | binary logloss is correct for the task |
| `n_estimators` | governed by early stopping, not a free parameter |
| "batch size" | GBDT has no minibatches — `subsample` **is** the analogue, and it is searched |
| "dropout" | no dropout in GBDT — `colsample_bytree` **is** the analogue, and it is searched |
| "optimizer" / "LR scheduler" | GBDT has neither; `learning_rate` is shrinkage, searched |

Listing these explicitly is the point: the brief asks for them, and quietly
inventing an "optimizer choice" for a GBDT would be a fabrication.

---

## 3. Experiment strategy — one change at a time

`train/run_hpo.py` runs a controlled ladder so every delta is attributable:

| id | what changes | isolates |
|---|---|---|
| **E0** | Stage 4 config, row-split ES | the bar to beat |
| **E1** | **only** the P0 event-grouped ES fix | the cost/benefit of the fix alone |
| **E2** | Optuna search on top of E1 | the value of tuning |
| **E3** | staged fine-tuning (stages 0–3) | the value of adaptation |

### The anti-overfitting device: selection vs report folds

HPO maximises mean held-out AP over **selection folds {0, 1, 2}**.
**Report folds {3, 4} are never seen by the search.** Reporting the search's own
objective would be selection-on-evaluation — the number would only go up.

This is a two-level guard, and the locked `final_test` is a third:

```
selection folds {0,1,2}  ->  what the search optimises
report folds   {3,4}     ->  honest read on the tuned config   (Stage 6)
final_test               ->  untouched, unbiased arbiter        (Stage 8)
```

**Tracked per trial** (Optuna SQLite + MLflow): all hyperparameters, per-fold AP,
best iteration, duration, trial state (complete/pruned), dataset version via the
config chain, and the git SHA.

---

## 4. Performance analysis: when is a change real?

With only 2 report folds, the fold spread is a crude but honest noise floor.

> **Decision rule.** A configuration is only called an improvement if its gain on
> the **report folds** exceeds the fold spread. A gain inside the spread is recorded
> as *"not demonstrated"* — never as an improvement.

`run_hpo.py::_select` computes this automatically and writes
`improvement_exceeds_noise` into `hpo_results.json`, so the verdict cannot be
quietly upgraded in prose.

**Overfitting detection during the search itself:** compare the best trial's
*selection* AP against its *report* AP. A large positive gap means the search fitted
the selection folds rather than finding generalizable structure — the single most
common failure mode in small-data HPO, and the reason the split exists.

---

## 5. Model selection — not on validation AP alone

Criteria, in order:

1. **Generalization** — report-fold AP, with the noise-floor rule above.
2. **Stability** — fold spread. A configuration that wins on average but swings
   wildly across regions is worse for deployment than a slightly lower, steadier one.
3. **Robustness of mechanism** — does it still beat the Stage 3 rule baselines
   (terrain-only, rainfall-threshold)? A model that stops beating `terrain_only` is
   not earning its complexity regardless of AP.
4. **Calibration** — Stage 5 measured up to 3× region-dependent miscalibration.
   Calibrated probabilities become the routing edge penalty, so a better-ranked but
   worse-calibrated model may be the wrong choice for the product.
5. **Cost** — model size (`num_leaves` × trees) and inference latency. The corridor
   has 309k segments scored daily; a 10× larger ensemble for a within-noise gain is
   a bad trade.

---

## 6. Commands

```bash
make stage6         # run / resume the search (Optuna study persists to studies/*.db)
make stage6-fresh   # discard the study and search from scratch
make test           # includes tests/test_hpo.py
make mlflow-ui      # compare runs
```

Resuming is genuine: `optuna.create_study(..., load_if_exists=True)` counts finished
trials and runs only the remainder, so an interrupted search continues rather than
restarting.

---

## 7. Honest limits of this stage

- **2 report folds is a thin noise estimate.** It is the most honest thing available
  without spending the locked test set, but it cannot detect small real gains.
- **Selection and report folds share training data** (they partition the same dev
  set). The separation prevents optimising the reported score directly; it does not
  make the two fully independent. `final_test` remains the only clean arbiter.
- **The search cannot fix an information ceiling.** Stage 5 attributed the dominant
  errors to label quality and ~25 km daily rainfall resolution. HPO redistributes
  capacity; it does not add information. If the measured gain is small, that is
  consistent with the Stage 5 diagnosis and should be reported as such, not tuned
  harder.
