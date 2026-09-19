# FINAL_MODEL — Stage 8 decision record

> **SUPERSEDED by `final_v2` — see [REMEDIATION.md](REMEDIATION.md).**
>
> The model described below, `final_v1` (config `5c8ab2326f9c5b5c`), is **known-leaked**
> and is retained only as a documented reference with its audit trail intact. Four
> findings in this document have since been root-caused and fixed:
>
> - **§4 is wrong and is retired.** The leak was a `| label_tier == "gold"` clause in
>   `_final_test` that overrode the block partition. With it removed, all 3 verified
>   labels move to dev: **the locked split now contains no verified labels, and the
>   "3 verified closures in the top 1.2%" claim is retired, not relocated.**
> - **§3's headline is wrong.** "Deleting rainfall makes the model rank better" was an
>   artifact of pooling two label populations. Once scope is controlled, **rainfall
>   contributes +0.1277 AP (15/15 fold-seed pairs)** — the model's largest single
>   contributor.
> - **§5's `id_exceed_*` defect is fixed** — 0 monotonicity violations, was 77.
> - **§7's steep-terrain failures are root-caused** to region transfer (dev ROC ≈0.75
>   vs test 0.630), not representation, capacity, calibration granularity or
>   architecture.
>
> Everything below is preserved unedited as the record of what was believed at the
> time. Read REMEDIATION.md for the current position.

The final model, why it was chosen, what it can and cannot do, and what must be true
before it is deployed.

Measured results: `reports/stage8/FINAL_VALIDATION_REPORT.md` and
`reports/stage7/FINAL_TEST_REPORT.md`. Methodology: `ACCURACY_OPTIMIZATION.md`.
This document does not restate numbers it does not need, so it cannot drift.

---

## 1. Final model selection

**Selected: `final_v1`** — LightGBM GBDT (4 leaves/tree, 1,199 trees) trained on all
dev rows with Stage 7's augmentation recipe, plus per-slope isotonic calibration.
Config hash `5c8ab2326f9c5b5c`.

### The candidates, and the axes they were judged on

| | Stage 3 baseline | Stage 4 | Stage 6 tuned (bar) | **Stage 7 composite (selected)** | ensemble | `composite/all_positive` |
|---|---|---|---|---|---|---|
| dev spatial-CV AP | 0.285 | 0.325 | 0.3506 | **0.3782** | 0.3732 | **0.3834** |
| cleared the decision rule | — | — | incumbent | **yes (5/5 folds)** | no (p=0.125) | **no (p=0.500, 2/5)** |
| replicated under fresh seeds | — | — | — | **yes, 3/3 seeds** | — | not tested |
| calibration (worst terrain stratum, dev) | — | — | 1.72× | **1.32×** | — | 15.7× |
| model size / latency | — | — | 594 KB / 2.77 µs | 709 KB / 3.37 µs | +logistic fit | smaller |

**Why this one.** It is the only candidate that improved a majority of folds with a
significant paired test *and* replicated under three fresh seeds *and* improved
calibration on the axis that can be corrected at inference.

**Why not the highest-AP candidate.** `composite/all_positive` scores highest on dev
(0.3834) and was rejected. It sits at p = 0.500 with 2 of 5 folds improving — a coin
flip — and it drops 30% of the negatives, which shifts the predicted base rate and
degrades worst-stratum calibration to 15.7×. Selecting it would have been picking the
largest number rather than the best-supported one, which is the failure this project
has guarded against since Stage 6.

**Why the cost column did not decide it.** The selected model is 19% larger and 22%
slower than the incumbent. Both score the entire 309,042-segment corridor in about a
second against a once-daily batch cadence, so latency has roughly 300× headroom and
is not a live constraint. This is the opposite of the Stage 6 decision, where size and
stability *were* the deciding factors because accuracy was at parity.

---

## 2. Final testing

The locked split was opened **once**, at the end of Stage 7, under a pre-registered
config hash and metric list. Stage 8 re-reads it for reporting only; every read is
recorded in `TEST_SET_LEDGER.json` with `kind`, and the count of *decision* openings
is asserted to remain 1 by `tests/test_final_model.py`.

Retraining from config + seed reproduced the recorded test AP **bit-identically**
(`0.376003011273`), which is the strongest available evidence that the artifact
analysed here is the artifact that produced the pre-registered number.

Plots and class-wise metrics are in `reports/stage8/`. Nothing was changed after the
test result was seen.

---

## 3. The finding that dominates this stage

**On the locked test set, deleting rainfall makes the model rank better.**
Ablating every rainfall input raises AP by +0.112 (130% of baseline); zeroing rainfall
raises it similarly. Ablating terrain changes nothing. The most valuable feature group
is *seasonality*.

This is not a modelling bug. Used directly as a ranking score with no model involved,
rainfall does not separate the classes on that split — the longer accumulation windows
are **inverted** (7-day ROC 0.46, API ROC 0.42), and disrupted days there had *less*
rain on average than undisrupted ones. On dev the same features sit at ROC 0.59–0.65.

**The cause is label composition, not geography.** `final_test` was defined in Stage 2
as a set of spatial blocks *plus every gold label*, with no constraint on label source.
The result is a split whose positives are ~45% news-derived (`corridor_landslides` at
48 mm mean 7-day rain, `reliefweb_events` at 13 mm) against ~10% in dev, where COOLR
events at ~101 mm dominate. Stage 5 §3 predicted this failure mode — "news-derived
dates often lag the event" — and the locked split is where it became measurable.

Two consequences, and they pull in opposite directions:

- The test number **understates** generalization to the extent that those positives
  carry wrong dates, because no model can predict rain-triggered failure on a dry day.
- But we **cannot correct for it**, because the labels good enough to check against
  are the three gold ones, and those have their own problem (§4).

---

## 4. The gold labels do not support the claim made in Stage 7

Stage 7 reported the 3 verified closures scoring in the top 1.2% as "the most
encouraging number in the project". Stage 8's leakage audit undermines that:

- `SEG291652` is the **only one of 4,392 test segments that also appears in training**.
- It appears there as a **positive 15 times across 5 distinct events**.
- It carries **all 3 gold labels**.
- Its static terrain columns are identical across all those rows — a per-segment
  fingerprint the model demonstrably memorises (Stage 3 lost a LOECO experiment to
  this mechanism; Stage 7's largest gain came from blurring exactly these columns).

The decisive test: with **rainfall deleted entirely**, the three gold rows keep their
percentile rank — 99.29/99.15/99.07 → **99.11/99.03/99.03**. Their absolute scores
collapse to 12% of their original value, but their *position at the top of the ranking
does not move*.

**Their top-1% ranking is segment identity, not rainfall skill.** The Stage 7 framing
was wrong and is corrected here. `tests/test_final_model.py` pins this so a future data
rebuild that fixes the overlap will fail loudly and force the reports to be revisited.

The rest of the split is clean: 0 exact row overlap, 0 shared positive `event_id`s,
1 shared segment out of 4,392.

---

## 5. Robustness — what is actually solid

| probe | result | reading |
|---|---|---|
| rainfall forecast error (σ = 0.25) | 97% of clean AP retained | **not reassuring** — it survives rainfall noise because rainfall is barely used |
| unseen categorical levels | no errors, ≤ 0.023 AP loss | degrades gracefully; safe against new OSM values |
| monotone rainfall constraints | **0 violations** with derived flags held fixed | LightGBM is enforcing them correctly |
| `id_exceed_*` derived flags | 77 violations when recomputed | **real defect** — these are derived from constrained features but are themselves unconstrained, so more rain can lower the score |
| selective prediction, top 1% | precision **0.807**, lift 4.97× | the one genuinely strong operational result |
| dry season vs monsoon | lift 5.21× vs **1.61×** | it discriminates best when there is no rain — the same story as §3 |
| steep terrain (slope ≥ 10°) | **ROC 0.624**, lift 1.44× | near chance where the decisions actually are |

**[FIX]** Add `id_exceed_1d/3d/7d` to `lgbm.monotone_rainfall_features`, or drop them
as redundant with `id_ratio_*`. Cheap, and it closes a real inconsistency.

---

## 6. Generalization

| split | n | base rate | AP | lift over chance |
|---|---|---|---|---|
| train (in-sample) | 80,688 | 0.0843 | 0.7731 | 9.17× |
| early-stopping | 14,281 | 0.0870 | 0.7291 | 8.38× |
| dev spatial-CV OOF | 94,969 | 0.0847 | 0.3791 | 4.48× |
| **locked test** | 8,277 | 0.1624 | 0.3760 | **2.32×** |

Lift over chance is the comparable column — the splits have very different base rates
and AP scales with base rate. The near-equal *raw* AP on the last two rows is a
coincidence of that, not evidence of transfer.

**Overfitting is reduced but not solved.** Stage 5 measured the old configuration at
in-sample AP 0.9999; Stage 7's regularisation brought it to 0.7731, which is real
evidence the augmentation did what it claimed. A 9.17× → 2.32× decline across the
chain still indicates substantial fitting to the training distribution.

---

## 7. Production readiness — 8 of 11 gates pass

Passing: beats chance, top-of-ranking precision, recall at threshold, survives
rainfall error, corridor scoring time, artifact size, reproducibility, and
"rainfall drives the prediction" (positives lose 93% of score without rain — though
§3 shows the *ranking* does not follow).

**Failing, and these are the ones that matter:**

1. **Steep-terrain discrimination — ROC 0.624 against a 0.70 gate.** The roads that
   actually close are all steep. Global AP is carried by telling plains from hills,
   which the routing layer already knows for free.
2. **Steep-terrain lift 1.44× against a 2.0× gate.** Same finding, expressed as value.
3. **Calibration does not transfer — worst terrain stratum 2.20× against a 1.5×
   gate.** Within dev, cross-fitted per-slope calibration reached 1.32×; on unseen
   ground it does not hold.

### Recommendation

**Not ready for autonomous deployment.** It is ready for a **decision-support pilot**
under these conditions:

- **Ship the ranking, not the probability.** Top-1% precision is 0.807; per-stratum
  calibration does not survive a region change, so probabilities must not drive the
  routing penalty `W = dist·(1 + λ·P)` on unseen terrain until a calibrator is
  re-fitted on local history.
- **Operate in selective mode** — alert on the top 1–2% of segment-days (precision
  0.72–0.81) rather than at the cost-optimal threshold, which flags 32.6% of negatives.
- **Change the cost default from FN:FP = 20 to 10.** Stage 7 measured it as strictly
  better: 1 point of recall for 1,341 fewer false alarms. The 20:1 figure is an
  unvalidated Stage 3 placeholder and should be settled with MDoNER regardless.
- **Human review on every alert.** The steep-terrain gate failure means the model
  cannot be trusted to rank *within* hill roads without a person in the loop.

### Inference optimization: none recommended

The model is 709 KB and scores the full corridor in ~1 s single-core against a daily
batch. Quantization, pruning, ONNX/TensorRT and GPU inference each add a toolchain, a
numerical-equivalence risk and a second artifact to version, in exchange for nothing
measurable. `reports/stage8/final_validation.json` records the threshold at which each
would become worth revisiting. The real pipeline cost is feature assembly, not
inference: **cache the static terrain/soil/road columns and recompute only the daily
rainfall block.**

---

## 8. Deliverables

| item | location |
|---|---|
| final model + calibrators | `models/final_v1/` |
| model card | `models/final_v1/model_card.json`, `reports/stage8/model_card.json` |
| frozen configuration | `reports/stage7/PREREGISTRATION.json` (hash `5c8ab2326f9c5b5c`) |
| test report | `reports/stage7/FINAL_TEST_REPORT.md` |
| validation + robustness report | `reports/stage8/FINAL_VALIDATION_REPORT.md` |
| per-probe measurements | `reports/stage8/*.csv`, `final_validation.json` |
| plots | `reports/stage8/*.png` |
| audit trail | `reports/stage7/TEST_SET_LEDGER.json` |
| experiment record | `mlruns/` (MLflow), `studies/*.db` (Optuna) |
| version | `final_v1` · config `5c8ab2326f9c5b5c` · seed 42 |

---

## 9. Known limitations

1. **All training positives are weak labels.** The only 3 verified closures are in the
   test split, and they are compromised by segment overlap (§4).
2. **Rainfall carries no usable signal on the locked test split** and is inverted in
   the longer windows (§3). The model's headline skill there comes from seasonality,
   hydrology and road class.
3. **Near-chance discrimination on steep terrain** (ROC 0.624) — where the decisions
   are.
4. **Calibration does not transfer across regions** (2.20× worst stratum).
5. **~25 km daily CHIRPS rainfall cannot resolve valley-scale cloudbursts.** Named by
   Stage 5 as the dominant false-negative driver and unaddressed since.
6. **One test region, 6 spatial blocks**, one of them 77% positive. A single split
   cannot separate selection bias from distribution shift.
7. **`id_exceed_*` flags are unconstrained** while their parent features are monotone
   (§5).
8. **The FN:FP = 20 cost ratio has never been validated** with the domain owner.
9. **Reproducibility is pinned to this machine and these library versions.**
   LightGBM/OpenMP version or CPU architecture changes can alter floating-point
   summation order.

---

## 10. The one thing that would change the picture

Every independent line of evidence across Stages 3, 5, 6, 7 and 8 says the same thing,
and Stage 8 says it most bluntly: **this problem is information-limited.** Tuning is
exhausted, capacity is not the constraint, a dedicated steep-terrain model finds
nothing, and the rainfall input does not separate the classes on held-out ground.

The unaddressed Stage 5 **P1** remains the only change likely to move the number that
matters: **higher-resolution rainfall — GPM IMERG at 0.1°, half-hourly** — paired with
a labelling pass that fixes the date reliability of the news-derived positives. That
is a data-acquisition project, not a modelling one, and no amount of further modelling
substitutes for it.
