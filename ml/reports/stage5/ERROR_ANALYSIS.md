# Stage 5 — Error Analysis: why the model fails and what to change

Hand-authored interpretation of `EVALUATION_REPORT.md` / `error_analysis.json`.
**Every number here is measured** from held-out model outputs. Recommendations are
labelled **[REC]** and carry no numbers unless they were measured in a diagnostic.

**The locked `final_test` split was not opened.** It holds 8,277 rows / 1,344
positives / all 3 gold labels. Using it to choose improvements would make Stage 8's
number meaningless. Everything below uses the 94,969 spatial-CV OOF rows (each
scored by a model that never trained on it) plus a fresh out-of-time fit.

> **Every positive evaluated here is a weak label.** The OOF set contains
> 4,560 bronze + 3,483 silver positives and **zero gold** — the only 3 verified
> road closures are inside the locked split. Read every number below as
> "performance against silver/bronze labels", not against ground truth.

---

## 1. Headline: the model is not what the global number suggests

| evaluation | AP | ROC-AUC | what it means |
|---|---|---|---|
| in-sample (dev) | **0.999** | 1.000 | scored on rows it trained on |
| held-out **region** (spatial OOF) | **0.294** | 0.856 | new blocks |
| out-of-time (2019+) | **0.232** | 0.852 | new period + new label source |

Base rate 0.085. So the model is ~3.5× chance on new terrain and ~2.7× on new time.
That is a real signal, honestly measured — and it is nowhere near the in-sample 0.999.

### The finding that matters most

Global AP is dominated by separating **plains from hills** — a distinction the
routing layer already knows for free. Within the terrain where decisions actually
matter, the model barely beats chance:

| stratum | n | positives | AP | base rate | **lift** |
|---|---|---|---|---|---|
| slope 18.8–55.0° (steepest quartile) | 23,741 | 4,353 | 0.298 | 0.183 | **1.63×** |
| elevation 527–5069 m (highest quartile) | 23,742 | 4,350 | 0.312 | 0.183 | **1.70×** |
| `trunk` roads | 1,429 | 657 | 0.776 | 0.460 | **1.69×** |
| `primary` roads | 1,223 | 243 | 0.394 | 0.199 | **1.98×** |
| — contrast — | | | | | |
| elevation 0.7–32.8 m (flattest) | 23,743 | 111 | 0.167 | 0.005 | 35.7× |
| slope 1.5–2.5° | 23,746 | 165 | 0.198 | 0.007 | 28.5× |

The impressive 35.7× lift is an artifact of a 0.005 base rate — it means "the model
knows the plains are safe". The steep-terrain lift of **1.63×** is the number that
describes operational value on the roads that actually close.

**[REC]** Report *within-stratum* lift on steep terrain as a headline metric
alongside global AP. Global AP on this panel overstates usefulness.

---

## 2. A training-process defect: early stopping has no validation signal

Measured three ways per fold:

| | mean AP |
|---|---|
| TRAIN rows | 0.9999 |
| **EARLY-STOPPING rows** | **0.9992** |
| held-out blocks | 0.3247 |

The early-stopping set — the thing that decides when to stop training — is scored at
**AP 0.999**. It is fully memorized, so it emits no stopping signal. That is why all
five folds ran to the round cap in Stage 4, and why raising the cap to 5000 didn't
help.

**Root cause, measured.** Share of ES positives whose unit also appears among TRAIN
positives:

| unit | overlap |
|---|---|
| segment | 98.9% |
| block + date | 99.9% |
| **event_id** | **100.0%** |
| spatial block | 100.0% |

Stage 2 snaps one event to up to 20 segments × 3 persistence days = **up to 60 panel
rows per event**. A *random row* split therefore splits every event across train and
ES. The model sees the event in training and recognises its block-date-rainfall
signature in the ES set. This is a Stage 4 training-process choice interacting with a
Stage 2 label-structure property.

### Two diagnostic experiments (run, not assumed)

| inner ES split | ES AP | held-out AP | mean best_iter |
|---|---|---|---|
| random rows (current) | 0.999 | **0.325 ± 0.139** | 1198 (all at cap) |
| grouped by **segment** | 0.990 | 0.325 ± 0.168 | ~1195 (still at cap) |
| grouped by **event_id** | 0.716 | 0.295 ± 0.147 | 952 (varies: 27–1200) |

Two honest conclusions:

1. **Segment grouping is not enough.** Even at 0% segment overlap the ES set still
   scores 0.99 — because within a block, segments share the same CHIRPS rainfall
   cell, lithology and terrain class. The memorised unit is the *event*, not the
   segment.
2. **Fixing it does not improve accuracy today** (0.295 vs 0.325 is inside the
   ±0.14 fold spread). It restores a *usable* validation signal (0.999 → 0.716).
   That matters because **Stage 6 HPO is impossible against a saturated signal** —
   every hyperparameter would look identical.

**[REC — P0]** Group the inner early-stopping split by `event_id` (positives) +
random (negatives), mirroring the LOECO fix from Stage 3. Prerequisite for Stage 6,
not a performance fix. Effort: ~1 hour.

---

## 3. Why we miss events (false negatives)

At the operating threshold, 356 of 8,043 positives are missed. Cohen's *d* between
caught and missed positives:

| feature | TP median | FN median | Cohen's d |
|---|---|---|---|
| slope_mean_deg | 19.7 | 17.4 | +0.57 |
| api_mm (antecedent index) | 134.3 | 86.9 | +0.54 |
| rain_15d_mm | 171.2 | 132.9 | +0.52 |
| label_confidence | 0.526 | 0.456 | +0.51 |
| rain_30d_mm | 358.0 | 218.2 | +0.49 |
| id_ratio_3d | 0.521 | 0.258 | +0.49 |
| rain_3d_mm | 37.2 | 18.4 | +0.49 |
| **rain_1d_mm** | **5.49** | **0.43** | +0.43 |

**The events we miss are the ones that happened without rain.** Missed positives
have a median of **0.43 mm** of rain on the day before, against 5.49 mm for caught
ones — and lower antecedent rainfall across every window.

A rainfall-triggered-landslide model cannot predict a landslide that had no rain.
So each missed positive is one of:
- **a non-rainfall-triggered event** mislabelled as rain-triggered (Stage 2 kept
  GLC triggers including `unknown`),
- **a date error** in the label (news-derived dates often lag the event),
- **real rain that CHIRPS missed** — the grid here is ~25 km and daily, which cannot
  resolve a valley-scale cloudburst.

Missed positives also carry systematically lower `label_confidence` (d = +0.51),
consistent with the label-quality story below.

---

## 4. Is the ceiling the model or the labels?

Ranking quality recomputed using only positives of a given label quality, against
the same negatives (so APs are comparable):

| label_confidence bucket | n_pos | ROC-AUC | lift |
|---|---|---|---|
| [0, 0.25) | 174 | **0.688** | 1.5× |
| [0.25, 0.35) | 343 | 0.798 | 2.6× |
| [0.35, 0.5) | 3,283 | 0.858 | 4.1× |
| [0.5, 1.0] | 4,243 | **0.865** | 4.3× |

ROC-AUC is base-rate independent, so this rise from 0.688 → 0.865 is a genuine
signal-quality difference, not an artifact. **The lowest-confidence positives are
close to unlearnable** (ROC 0.688 ≈ weak noise).

Caveat: `label_confidence` is itself derived from snap distance and tier, so this is
partly circular — it shows the model agrees with our own uncertainty estimate. The
snap-distance probe alone was *not* monotone (ROC 0.854 / 0.865 / 0.826 / 0.858
across distance buckets), so distance alone does not explain it.

**[REC]** Treat the bottom confidence bucket as a separate ablation arm rather than
deleting it — 174 positives is a meaningful fraction of a label-starved dataset.

---

## 5. False positives: two hypotheses tested, both rejected

At the operating threshold there are **34,004 FPs (39.1% of all negatives)** —
because the cost policy (one missed closure = 20 false alarms) drives recall to
0.956 at precision 0.184.

| hypothesis | measured | verdict |
|---|---|---|
| FPs are chronic repeat-offender segments | worst 10% of segments = **22.6%** of FPs (top 1% = 3.2%) | **rejected** — FPs are diffuse across 19,625 segments |
| FPs are actually unlabelled real events | only **1.1%** of FPs fall within 10 km and 7 days of a labelled event | **rejected** — they are not near-misses |

So the FPs are genuine over-prediction spread thinly, consistent with §1: weak
discrimination *within* risky terrain. They are not a labelling artifact and cannot
be explained away.

**[REC]** The 39% FP rate is mostly a *policy* choice, not a model defect. The
FN=20×FP ratio was a placeholder from Stage 3 and has never been validated with a
domain expert. Present the precision/recall Pareto curve and let MDoNER choose the
operating point.

---

## 6. Calibration does not transfer across regions

| stratum | predicted / observed |
|---|---|
| spatial fold 3 | **2.59×** (over-predicts) |
| spatial fold 4 | 1.25× |
| spatial fold 2 | 0.92× |
| spatial folds 0 / 1 | 0.70× / 0.68× (under-predicts) |
| slope 0–1.5° (flattest) | **3.02×** |
| slope 1.5–2.5° | 1.97× |
| slope > 2.5° | 0.92–0.99× (good) |
| monsoon / dry season | 1.03× / 0.86× (good) |

One global isotonic calibrator is wrong by up to **3×** depending on region and
terrain. Seasonal calibration is fine; spatial calibration is not.

This matters specifically for the product: calibrated probabilities become the
routing edge penalty `W = dist·(1 + λ·P)`. A 3× inflated probability on flat roads
systematically over-penalises safe plains routes.

**[REC — P2]** Fit the calibrator per terrain stratum (or add slope/region as
calibrator inputs). Low effort, directly improves the downstream routing use.

---

## 7. Per-event detection — the operational view

146 events evaluated. Best rank achieved by any of the event's segments on its day:

- **top-1: 46.6%** · **top-10: 89.0%** · top-50: 98.6% · top-100: 100%
- median best rank **2** out of a median **63** rows scored that day

> **Caveat, stated plainly:** the panel contains only labelled rows (positives +
> sampled negatives), not all 309k corridor segments. Ranking 2nd of 63 is *not*
> ranking 2nd of 309,042. This is an optimistic proxy, valid for comparing models
> against each other, invalid as a deployment guarantee.

**[REC]** Before the demo, re-run this against the *full* segment set for a sample
of event dates. That is the number a judge will actually ask about, and the current
one will not survive the question.

---

## 8. Data quality: clean

| check | value |
|---|---|
| duplicate feature vectors | 430 (215 groups) |
| duplicate groups with **conflicting labels** | **0** |
| rows with all rainfall NaN | 0 |
| soil NODATA rate (overall / pos / neg) | 2.3% / 1.6% / 2.4% |
| positive segments with >1 event | **464 of 1,780** (max **12** events on one segment) |

No label contradictions, no missing-rainfall rows. The repeat-offender structure
(464 segments, one with 12 events) is the same property that caused the Stage 3
LOECO leak and this stage's ES saturation — it is inherent to the corridor (the same
few mountain roads really do fail repeatedly), not a bug.

Incidentally, `soil NODATA` is itself predictive (AP 0.323, lift 5.5×) — the Stage 2
decision to add a missingness flag rather than silently impute was correct.

---

## 9. Root-cause attribution

| finding | root cause | layer |
|---|---|---|
| ES signal saturated (100% event overlap) | random row split of a panel where 1 event ⇒ ≤60 rows | **training process** (driven by Stage 2 label structure) |
| lift only 1.63× within steep terrain | rainfall at ~25 km daily cannot resolve valley-scale triggering | **data / features** |
| FNs are near-zero-rain events | non-rain triggers, date errors, or rain CHIRPS missed | **data / labels** |
| lowest-confidence labels ≈ unlearnable | location + date uncertainty in weak labels | **data / labels** |
| in-sample AP 0.9999 | capacity unconstrained relative to real signal | **model / training** |
| calibration off by up to 3× | single global calibrator | **training / post-processing** |
| 39% FP rate | unvalidated FN=20×FP cost policy | **policy, not model** |

Note what is *not* on this list: preprocessing and architecture. The data pipeline is
clean (§8) and the architecture choice is not the binding constraint — Stage 3 showed
logistic regression is competitive, which is itself evidence that the ceiling is
information, not model class.

---

## 10. Improvement plan, ranked

Ranked by (expected impact × confidence) ÷ effort. **Impact figures are predictions,
not measurements**, except where a diagnostic was actually run.

| # | Action | Layer | Effort | Expected impact | Evidence |
|---|---|---|---|---|---|
| **P0** | Group inner ES split by `event_id` | training | ~1 h | **Neutral on accuracy (measured: 0.295 vs 0.325, inside noise)** — but unblocks Stage 6 | §2 diagnostics |
| **P1** | Higher-resolution rainfall (GPM IMERG 0.1°, half-hourly) + sub-daily intensity features | data | high | Largest expected gain — directly targets the measured FN driver and the weak steep-terrain lift | §1, §3 |
| **P2** | Per-stratum calibration (terrain / region) | training | ~2 h | Fixes measured 3× miscalibration; improves routing weights immediately | §6 |
| **P3** | Ablate the lowest label_confidence bucket | data | ~1 h | Removes 174 near-noise positives (ROC 0.688); may raise precision | §4 |
| **P4** | Re-tune capacity/regularization once P0 gives a real signal | model | ~4 h | Unknown until P0 — in-sample 0.9999 says there is room | §1, §2 |
| **P5** | Validate the FN:FP cost ratio with MDoNER; publish the Pareto curve | policy | ~1 h | Changes the 39% FP rate without touching the model | §5 |
| **P6** | Report within-steep-terrain lift as headline | reporting | ~1 h | Honesty; prevents over-claiming in the pitch | §1 |
| **P7** | Re-run per-event detection against all 309k segments | evaluation | ~3 h | Replaces an optimistic proxy with the real number | §7 |

**Do P0, P2, P5, P6 first** — all cheap, all either unblock Stage 6 or correct a
measured error. **P1 is the only change likely to move the headline metric
materially**, and it is a data-acquisition project, not a modelling one.

## 11. What this stage did *not* find

Stated so these aren't re-litigated later:
- No label contradictions or duplicate-label conflicts (§8).
- No evidence that FPs are unlabelled real events (§5) — 1.1%.
- No evidence that segment-level memorization drives the ES problem (§2) — it's
  event-level.
- No seasonal calibration problem (§6) — only spatial/terrain.
- No preprocessing defects.
