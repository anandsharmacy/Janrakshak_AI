# ACCURACY_OPTIMIZATION — Stage 7

Methodology and decision rules. **Measured results live in
`reports/stage7/OPTIMIZATION_REPORT.md` / `optimize_results.json`** and the
interpretation in `reports/stage7/OPTIMIZATION_FINDINGS.md` — this document does
not restate them, so it cannot drift out of sync with the numbers.

---

## 0. What Stage 7 inherited, and what that rules out

Three stages now agree on the same diagnosis, from independent evidence:

| stage | evidence | conclusion |
|---|---|---|
| 3 | logistic regression matched/beat the GBDT | usable structure is largely additive |
| 5 | in-sample AP 0.9999 vs held-out 0.29 | capacity was never the constraint |
| 6 | 40 TPE trials → no demonstrated gain; search chose `num_leaves = 4`, the floor | tuning is exhausted |

So Stage 7 does **not** re-run hyperparameter search, and it does not look for a
better model class. Stage 6's own closing instruction was to spend the effort on
data, calibration and ensembling instead. What remained genuinely untested were the
Stage 5 P1–P7 items and the brief's data/augmentation/loss axes.

One Stage 5 item is explicitly **out of scope and stays open**: P1, higher-resolution
rainfall (GPM IMERG at 0.1°, half-hourly). It is a data-acquisition project, not a
modelling change, and Stage 5 named it the only change likely to move the headline
materially. Nothing in Stage 7 substitutes for it.

---

## 1. The evaluation protocol, and why it changed from Stage 6

Stage 6 split folds into selection `{0,1,2}` and report `{3,4}`, and stated its own
limit: with 2 report folds it could not resolve anything below ~0.03 AP. Stage 7 has
~25 candidate arms and needs finer resolution than that, so it uses a different
instrument:

> **Paired per-fold deltas over all 5 spatial folds.** Every arm runs on the same
> folds with the same seeds and the same event-grouped early-stopping splits. The
> fold-to-fold variance that dominates absolute AP (folds range roughly 0.2–0.6) is
> then *common to both sides* and cancels in the difference. What is tested is the
> delta, not the score.

Significance is a **sign-flip permutation test** on the 5 paired differences.

### The limit of that instrument, stated up front

With 5 folds the smallest attainable two-sided p-value is `2/2⁵ = 0.0625`. Therefore:

- A Bonferroni-corrected threshold across ~25 arms (α ≈ 0.004) is **unreachable by
  construction**. No arm in this stage can be certified family-wise. Anyone reading
  a single `p = 0.061` row as "significant" is reading it wrong.
- At uncorrected α = 0.10, roughly 2–3 of 25 arms are expected to "pass" by chance.

The honest remedy is not a better p-value, it is **replication**: the leading arms
and every arm that cleared the rule are re-run under fresh seeds, which redraw the
event-grouped ES split and the bagging RNG. An effect that survives that is not an
artifact of one inner split. It is still not a family-wise-corrected result, and the
report says so.

### The decision rule

> An arm is called an **improvement** only if its mean paired delta is positive,
> **at least 4 of 5 folds improve**, and `p < 0.10`. Anything else is recorded as
> *"not demonstrated"* — never as an improvement. `harness.verdict()` computes this,
> and a test asserts the published verdicts match the rule, so the JSON and the prose
> cannot drift apart.

Consistency is required *alongside* significance because a single fold swinging
hugely can carry a mean delta on its own, and a model that helps one region while
hurting four is not an improvement for a corridor-wide deployment.

---

## 2. The leakage firewall

Stage 7's central structural guarantee is that **an arm may only transform a fold's
training rows**:

```
arm.transform(data, tr_idx, fold, seed) -> TrainSet(X, y, w)
```

It never receives the held-out fold (that is what is being measured) or the
early-stopping rows (that is the inner validation signal Stage 5 spent a whole stage
restoring). `harness.fit_one_fold` is the single caller, and a test asserts the arm
receives exactly `tr_idx` and nothing else.

### The subtle one: mining

Hard-negative mining needs a per-row difficulty score. The obvious source — Stage 5's
pooled OOF predictions — is **wrong**. In spatial CV each row is validated once; a
training row of fold *k* was validated by some model *j ≠ k*, and model *j* trained on
blocks that include fold *k*'s held-out blocks. Fold *k*'s validation labels therefore
reach fold *k*'s training weights, and the bias flatters.

`data_opt.inner_oof_scores` instead cross-fits a small **prospector** model strictly
inside the fold's own training rows, grouped by `event_id` (one event produces up to
60 panel rows, so a random split would leak the same way Stage 5's ES split did). It
costs extra fits per fold and is worth it.

### Mass preservation

Mining arms multiply weights (`w *= 1 + α·rank`), which also raises total negative
mass by ≈ α/2 — silently changing the effective class balance and learning rate. The
arm would then confound *"better-chosen weight"* with *"more weight"*. Every mining
and weight-scheme arm therefore **renormalises to the original total mass**, making it
a clean test of *which* rows get the weight.

---

## 3. Augmentation for a tabular hazard panel

There is no flip/crop/rotate, and that is not an oversight: this panel has no spatial
invariance to exploit. Absolute location *is* the signal — a segment's lithology,
slope and rainfall cell are its identity — so a mirrored segment is a fabricated one,
not another valid one.

Two families are tested, and the contrast between them is the point:

**Physics-preserving (`rain_jitter`).** Rainfall is the one axis with genuine measured
uncertainty: CHIRPS is ~25 km and daily, and Stage 5 attributed part of the dominant
false-negative mode to "real rain that CHIRPS missed". Rainfall columns are windowed
integrals of one process and `id_ratio_*` are derived from them, so a *single*
multiplicative factor per row is applied across every window, the ID ratios scale with
it, and the `id_exceed_*` flags are **recomputed** — jittering one window alone would
emit a row whose 1-day total contradicts its 3-day total. Terrain, dates and
categoricals are held exactly.

**Deliberately not physics-preserving (`gaussian_all`).** Independent noise on every
numeric column, terrain included — what generic "add noise to tabular data" advice
produces. It was written into the code as the arm **expected to lose**.

It did not lose. The write-up in `augment.py` records that the stated prediction was
wrong and why: noise on a feature is not only a claim about measurement error, it is
also a **regulariser that prevents the tree from splitting on an exact value**. Static
terrain columns form a per-segment fingerprint, and Stages 3 and 5 both measured the
model memorising it (in-sample AP 0.9999; a LOECO leak through repeat-offender
segments; 464 segments carrying more than one event). Blurring those columns does not
model DEM error — it destroys the fingerprint.

`gaussian_terrain_only` and `gaussian_rain_only` decompose the effect so that
explanation is tested rather than told as a story, and a **strength sweep** across
several σ characterises where the trade between mean gain and fold consistency sits.

**SMOTE** is restricted to within-`spatial_block_id` positive pairs: vanilla SMOTE
would interpolate a Sikkim landslide with a Bihar flood and emit terrain that exists
nowhere. Categoricals take the seed row's value; synthetic rows inherit the mean
parent confidence weight, so fabricated data never outranks observed data.

---

## 4. Loss

**Binary focal loss is the only alternative objective implemented**, because it is the
only one with a measured reason: Stage 5 §3 found the missed positives are
systematically the low-rainfall ones — the hard examples — and focal loss is precisely
the loss that down-weights easy examples. Hinge, MSE and ranking losses have no such
support in the error analysis and would be cargo-culting.

Two things are easy to get wrong and are handled explicitly in `losses.py`:

1. **LightGBM does not apply `sample_weight` to a custom objective.** The closure must
   multiply grad/hess by `dataset.get_weight()` itself, or Stage 2's label-confidence
   weights are silently discarded.
2. **`scale_pos_weight` has no effect either.** Class imbalance is carried by focal
   `alpha`, so the harness passes `scale_pos_weight=None` whenever an objective is
   supplied.

A custom objective also makes LightGBM emit **raw margins, not probabilities**, so
`LGBMBaseline.predict` applies the sigmoid when `raw_score_` is set — otherwise every
downstream probability, calibrator and threshold would be on the wrong scale. The
gradient is verified against a numerical derivative and against the γ=0 reduction to
weighted cross-entropy in `tests/test_optimize.py`.

---

## 5. Prediction-side optimization

**Calibration is cross-fitted.** A calibrator scored on the rows it was fitted on
always looks well-calibrated; Stage 5's up-to-3× figure was measured that way. Here
fold *k* is calibrated by a model fitted on the other folds, which is also how it
would run in production (fit on history, apply to today) — so the measurement matches
the deployment, and the numbers are *worse* than Stage 5's for that reason.

The two miscalibration axes are reported **separately**, because only one is fixable:

| axis | fixable at inference? | why |
|---|---|---|
| terrain (slope stratum) | **yes** | slope is a property of the row being scored, so a calibrator can condition on it |
| region (spatial fold) | **no** | a model deployed on a new area cannot look up its own base rate |

Pooling them into one "worst stratum" number hides a real fix behind an unfixable one.
Selection is therefore on the terrain axis; region miscalibration is a residual
limitation to disclose. This matters more than AP for the product: calibrated
probabilities become the routing edge penalty `W = dist·(1 + λ·P)`, and an inflated
probability on flat roads over-penalises safe plains routes — a *ranking-neutral* error
that AP cannot see and that changes the recommendation anyway.

**Thresholds are published, not baked in.** Stage 5 §5 measured a 39% false-positive
rate and attributed it to policy: the FN = 20 × FP ratio is a Stage 3 placeholder never
validated with MDoNER. Tuning the model against an arbitrary constant would be
optimising noise, so Stage 7 reports the full cost sweep and the PR Pareto curve and
hands the operating point to the domain owner with its consequences attached.

**Ensemble weights are chosen leave-one-fold-out.** Picking blend weights on the same
OOF rows you then report is selection-on-evaluation and always produces a "gain".
Fold *k*'s blended score uses weights fitted on folds ≠ *k*. Members are combined as
within-fold percentile ranks, since they live on incomparable scales and AP depends
only on ordering.

**Test-time augmentation is not implemented.** The honest tabular analogue — average
predictions over rainfall perturbations — is a smoothing operation over a monotone
model, and the training-side jitter arms already measure whether that smoothing helps.
Implementing it as a separate "technique" would be the same experiment with a new
label. It is listed here rather than quietly omitted.

---

## 6. Selection is not on AP

The brief's own warning ("do not artificially optimise for the validation set") has a
specific failure mode in this stage, and the code guards it: `_best_candidate`
promotes a candidate over the incumbent **only if it cleared the decision rule**, not
if it merely posts the highest AP. The composite built from every positive-delta arm
is the live example — it posts the highest AP of anything measured, at p ≈ 0.5 with a
minority of folds improving, and it also drops 30% of the negatives, which shifts the
predicted base rate and damages calibration. Promoting it on AP alone would ship a
coin flip with worse routing weights.

Criteria, in order: **demonstrated generalization** (decision rule) → **stability**
(fold consistency, seed replication) → **calibration** (terrain axis) → **cost**
(model size, latency for 309k daily segments) → AP as a tiebreak among survivors.

---

## 7. The locked test set

`final_test` has been held out since Stage 2 and is opened **exactly once**:

```
1. All optimization decided on dev data.                       (make stage7)
2. Config + metric list frozen -> PREREGISTRATION.json, hashed. (end of stage7)
3. Test opened once -> TEST_SET_LEDGER.json records it.        (make stage7-final-test)
```

`scripts/open_final_test.py` is the only code permitted to read it, and it **refuses
to run** without the pre-registration file. A test asserts every other Stage 7 module
is free of any reference to `final_test`. The ledger accumulates an entry per opening
with the config hash: a second opening is not blocked — sometimes a real bug must be
fixed — but it is *recorded*, and the report states the opening number so the reader
knows whether they are looking at an unbiased estimate.

The pre-registration also records the dev estimate and states plainly that it is
optimistically biased by having been used to select among ~25 arms. **The gap between
it and the test number is the measurement of that bias**, and it is the most honest
number this project produces.

> If the test result disappoints, that is the result. It is not a reason to reopen the
> search — and the ledger means doing so anyway would be visible.

---

## 8. Commands

```bash
make stage7             # full arm ladder; freezes the config, does NOT open the test
make stage7-final-test  # opens the locked split ONCE, under pre-registration
make test               # includes tests/test_optimize.py
```
