# REMEDIATION — Stage 9 root-cause reports and revalidation

Fixes for the four findings raised against `final_v1`. Produces **`final_v2`**
(config `5aed65f3f8729060`). `final_v1` (`5c8ab2326f9c5b5c`) is **retained, not
overwritten**, documented below as known-leaked and superseded.

Measured results: `reports/stage9/`. Run `make stage9` (~4 min).

> **Bias disclosure, stated once and applying to every test number below.** This is
> not an unbiased first read in the way `final_v1`'s opening was. The remediation was
> *prompted* by findings obtained from reading the v1 test set. Every fix rests on
> dev-side measurement or label metadata, never on a test score, and the test region
> was deliberately **not** re-drawn — but the direction of investigation was
> test-informed and no protocol undoes that. Treat the v2 test number as a strong
> check, not a virgin estimate.

---

## A — Root cause of the leak

**The spatial partition was never broken; a predicate override bypassed it.**
`splits/make_splits.py::_final_test` read
`df.spatial_block_id.isin(held_blocks) | (df.label_tier == "gold")`. The held blocks
that run were `BLK_009_005, BLK_004_006, BLK_005_004, BLK_006_008, BLK_004_007`. All
3 gold rows sit in **`BLK_005_006`, which is not among them**, so the OR-clause lifted
exactly 3 rows out of a 4,424-row block whose remaining 4,421 rows stayed in training
— including **15 positive rows of the same segment, `SEG291652`, across 5 distinct
events** spanning 2010–2023. Block assignment, event pinning and the buffer logic all
behaved correctly; the membership rule simply wasn't a function of the block. Evidence:
`gold rows whose block is NOT held: 3 of 3`, and the 3 rows are the only ones of 103,246
that changed side when the clause was removed.

**Structural fix, not a patch for one segment.** Two changes. (1) The OR-clause is
gone: locked-test membership is now a function of the block alone — any predicate on a
row attribute (tier, source, date, hazard) can cut across blocks, so none is permitted.
(2) A second, *latent* path was found and closed: because positives are re-pinned to
their event's modal block, 4 of 61,872 segments have rows in more than one block, and
if one such block were held and the other not, that segment would straddle the
boundary. Held-out units are now whole **block-components** under union-find over
"shares a segment or an event" (114 blocks → 113 components; a single 2-block merge, so
the insurance is nearly free). The original block-level draw is preserved and only
*expanded* to components — re-sampling the test region after seeing it fail would be
post-hoc selection.

**Automated gate.** `splits.assert_no_split_leakage` runs inside `make_splits` and
**raises** on any shared segment, positive event or block. The previous leak survived
three stages because the check was a one-off analysis performed afterwards.
`tests/test_splits.py` asserts the gate exists, is called by `main()`, and raises.

**Did any of the "3 verified closures in top 1.2%" claim survive? No — none.** With the
clause removed, `BLK_005_006` stays in dev and all 3 gold rows go with it. **The locked
test set now contains zero verified labels and the claim is retired, not relocated.**
The Stage 8 canary that pinned the *presence* of the leak has served its purpose and is
replaced by the permanent invariant (`test_no_segment_leakage_into_the_locked_split`).

---

## B — Root cause of the composition confound

**It is not a date-attribution artifact, and it is not "news events aren't real".** The
inverted rainfall relationship comes from news-scraped labels whose *dates are not
rainfall-trigger dates*, for which four independent lines of evidence exist — the class
boundary being **provenance**, fixed before any rainfall value is read:

1. **Their trigger field is a constant.** All 26 `corridor_landslides` rows read
   `rainfall_or_flood`; all 4 `reliefweb_events` read `unknown`. A column with one
   value is a pipeline default, not a per-event attribution. *(An earlier draft of this
   analysis treated `rainfall_or_flood` as a recorded rainfall attribution and was
   wrong; checking whether the column varies is what caught it.)*
2. **Location accuracy is `place_level` for every row** (±15 km), against COOLR's
   100 m – 25 km with real variation.
3. **The date-lag hypothesis is refuted by measurement.** If a news date lagged a real
   rainfall trigger, a *longer* antecedent window would recover the signal. Measured
   ROC by window, positives-of-source vs all negatives:

   | source | 1d | 3d | 7d | 15d | 30d |
   |---|---|---|---|---|---|
   | `coolr_glc` | 0.597 | 0.651 | **0.659** | 0.653 | 0.650 |
   | `corridor_landslides` | 0.508 | 0.505 | 0.466 | 0.419 | **0.402** |
   | `reliefweb_events` | 0.314 | 0.198 | 0.166 | 0.254 | 0.298 |

   COOLR rises to a peak at 7 days and plateaus — the physical antecedent-rainfall
   signature. The news sources get monotonically **worse** as the window lengthens,
   which is the opposite of a lag.
4. **They are drier than the negative sample at every window** (7-day median 29.8 mm
   for corridor vs 49.6 mm for negatives). Negatives are season-matched and include a
   matched hard-negative donut, so they sit on rainy days by construction; positives
   drier than that are not trigger-day rows.

Consistent with news reports capturing **ongoing closures and aftermath** rather than
trigger days — NH-10 closures after the October 2023 Teesta flooding persisted for
months, and the 4 `reliefweb_events` are the only `hazard='flood'` events in the whole
dataset, all in Oct/Dec, 0% in monsoon, one with 0.7 mm of rain in the preceding 30
days. *(The specific attribution to the 4 Oct 2023 South Lhonak outburst is an
inference from coordinates and timing, not a field in the data, and is labelled as
such. Points 1–3 stand on recorded metadata alone.)*

**Decisions taken.** Scope the model to rain-attributable positives and report the rest
as a named slice (they remain real closures the product must handle — a rainfall-feature
model simply cannot predict them). The locked split is **not** re-drawn; every metric is
reported broken out by source instead, so a composition confound cannot hide inside an
aggregate again. Points 3–4 do consult rainfall; that is not circular because the class
boundary is provenance, decided independently — rainfall behaviour *explains* the split
rather than defining it.

### The central question, answered

**Does a genuine rainfall-driven signal exist once leak and confound are removed?**

# YES.

Out-of-fold across 5 spatial folds × 3 seeds, paired per-fold deltas, in-scope target:

| | AP with rainfall | AP with every rainfall input deleted | Δ | fold-seed pairs |
|---|---|---|---|---|
| in-scope target | **0.4023** | 0.2747 | **+0.1277** | **15 / 15** |

**Rainfall contributes +0.1277 AP — a 46% relative lift — improving every one of 15
fold-seed pairs, with the `improvement` verdict on all three seeds independently.** It
is the model's single largest contributor. Stage 8's "deleting rainfall raises AP by
+0.112" was entirely an artifact of pooling two populations: on `coolr_glc` positives
rainfall helps by +0.1057 (15/15); on news-derived positives it hurts by −0.1387 (3/15).

### A secondary question the data forced open

Scoping the *evaluation* target is settled. Whether to also drop out-of-scope positives
from *training* is separate, and a single-seed head-to-head suggested the opposite of
what the rationale predicted — so it was tested at the full rigor bar, both arms scored
on identical in-scope rows:

| | dev AP (5 folds × 3 seeds) |
|---|---|
| scoped training | **0.4023** |
| unscoped training | 0.3836 |
| Δ | **+0.0187**, replicated on 3/3 seeds, 10/15 fold-seed pairs |

Scoped training wins on dev, so it is kept. **This disagrees with the single test-set
observation** (v1 recipe 0.2525 vs v2 0.2146 on identical rows). Fifteen dev
observations outweigh one test observation, and switching the design because of a
test-set result is precisely the post-hoc selection this protocol forbids — but the
disagreement is real and is recorded rather than smoothed over.

---

## C — Root cause of the monotonicity bug

**The constraint machinery was never broken; three derived features were escaping it.**
`id_exceed_1d/3d/7d` are computed as `id_ratio_* >= 1`, i.e. monotone step functions of
features that *are* constrained, but were absent from `monotone_rainfall_features`.
Raising rainfall could therefore flip a flag the model had learned a negative
relationship with and lower the score. The diagnostic that isolated it: **77 violations
when the flags are recomputed, 0 when they are held fixed** — LightGBM was enforcing
every constraint it was given.

**Fix:** the three flags are added to the constraint set. They are kept rather than
dropped because they encode the published intensity-duration threshold crossing, which
is the domain rule the feature design rests on; dropping them as redundant with
`id_ratio_*` was the alternative and is recorded as the option not taken.

**Result: 0 violations at every tested rainfall multiplier (1.25×, 1.5×, 2×, 4×), with
the flags recomputed.** Accuracy impact is nil and is reported as such: +0.0015 /
+0.0228 / +0.0050 across three seeds, `not demonstrated` on all three. This is a
correctness fix, not an accuracy fix, and folding it in cost nothing.

---

## D — Root cause of the steep-terrain gate failures

**Not under-representation, not calibration granularity, not architecture — it is
region transfer.** Four hypotheses tested in order:

1. **Under-representation: rejected.** Steep terrain (≥10°) is 41.0% of dev rows and
   carries **89.3% of dev positives**. It is the dominant population, so sampling or
   weighting is not the lever.
2. **Insufficient signal within steep terrain: rejected.** Used directly as ranking
   scores on dev in-scope rows, rainfall features are *stronger* inside steep terrain
   than across all terrain — `api_mm` ROC **0.727** (vs 0.669 overall), `rain_7d`
   **0.711** (vs 0.672) — while `slope_mean_deg` collapses to 0.511 and
   `elevation_mean` to 0.498. Terrain carries no information *within* the steep range;
   rainfall carries more.
3. **Model under-fitting steep terrain: rejected.** On dev out-of-fold the full model
   reaches steep ROC **0.751 / 0.763 / 0.756** across three seeds, beating the best
   single feature (0.727). It is extracting more than any one input.
4. **A dedicated steep-only model: rejected, consistently.** −0.0232 / −0.0916 /
   −0.0621 across three seeds, 0–1 of 5 folds favouring it, one seed a clear
   `regression`. This re-confirms the Stage 7 result on clean, de-leaked data.

**So the root cause is the gap between dev and test, not a deficiency inside dev:** the
model achieves steep ROC ≈ 0.75 on dev regions and **0.630** on the held-out region.
The steep-terrain failure is a *generalization* failure across regions, which is the
same ceiling every other strand of this project has hit — ~25 km daily rainfall cannot
resolve valley-scale triggering, so the relationships learned in one valley do not
transfer to the next.

Calibration bin granularity was also tested and rejected on dev evidence: splitting the
steep range into six bins made worst-stratum transfer **worse** (1.24× vs 1.04× coarse),
so the coarse binning is kept.

**Consequence for the pilot, not a threshold change.** The gates stay where they are.
**Steep-terrain segments are excluded from the autonomous top-k ranking pilot** until
higher-resolution rainfall is available; they remain scored and shown to a human.

---

## E — Revalidation

Model selection re-run at the original rigor bar: paired per-fold deltas over 5 spatial
folds × 3 seeds, exact sign-flip permutation test, same decision rule
(Δ > 0 **and** ≥4/5 folds **and** p < 0.10). Threshold chosen on dev out-of-fold
predictions before the locked split was read. New config hash `5aed65f3f8729060`;
`final_v1` preserved at `reports/stage7/PREREGISTRATION.json`.

### All 12 gates, before and after

| gate | threshold | v1 | | v2 | |
|---|---|---|---|---|---|
| beats chance on held-out ground | AP / base rate > 2.0 | 2.32× | PASS | 2.20× | PASS |
| top-of-ranking precision | precision@100 ≥ 0.50 | 0.810 | PASS | **0.290** | **FAIL** |
| recall at the operating threshold | ≥ 0.80 | 0.926 | PASS | **0.955** | PASS |
| STEEP-TERRAIN discrimination | steep ROC-AUC ≥ 0.70 | 0.624 | FAIL | 0.630 | **FAIL** |
| steep-terrain lift | ≥ 2.0× | 1.44× | FAIL | 1.43× | **FAIL** |
| probability calibration transfers | worst terrain stratum ≤ 1.5× | 2.20× | FAIL | 2.65× | **FAIL** |
| survives rainfall forecast error | ≥ 80% of clean AP at σ = 0.25 | 97.3% | PASS | 99.5% | PASS |
| rainfall is actually driving the prediction | positives lose ≥ 30% of score | 92.9% | PASS | 95.9% | PASS |
| daily corridor scoring fits the batch window | < 300 s | 1.03 s | PASS | 1.02 s | PASS |
| artifact size is deployable | < 50 MB | 0.69 MB | PASS | 0.69 MB | PASS |
| reproducible from config + seed | retrain reproduces test AP | bit-identical | PASS | bit-identical | PASS |
| **rainfall monotonicity enforced end-to-end** | 0 violations, flags recomputed | *(new gate)* | — | **0 violations** | **PASS** |

**v1: 8 of 11. v2: 8 of 12** (one gate added by fix C, which it passes).

### Test metrics by label source — B's standing requirement

| stratum | n | pos | base rate | AP | lift | ROC |
|---|---|---|---|---|---|---|
| all | 8,274 | 1,341 | 0.1621 | 0.3366 | 2.08× | 0.7537 |
| **IN SCOPE (rain-attributable)** | 7,674 | 741 | 0.0966 | 0.2146 | **2.22×** | **0.7699** |
| OUT OF SCOPE (not rain-attributable) | 7,533 | 600 | 0.0796 | 0.2146 | 2.69× | 0.7338 |
| `coolr_glc` | 7,674 | 741 | 0.0966 | 0.2146 | 2.22× | 0.7699 |
| `corridor_landslides` | 7,413 | 480 | 0.0648 | 0.1207 | 1.86× | 0.7471 |
| `reliefweb_events` | 7,053 | 120 | 0.0170 | 0.3259 | 19.16× | 0.6802 |

The 19× lift on `reliefweb_events` is a base-rate artifact (base 0.017) and its ROC is
the lowest of any slice — exactly the kind of number that looked impressive inside an
aggregate and is why source-stratified reporting is now mandatory.

### Did v2 improve the deployable numbers? No.

Stated plainly because it is the result. On identical in-scope test rows, both trained
on the rebuilt split:

| | AP | lift | ROC | precision@100 |
|---|---|---|---|---|
| v1 recipe (unscoped training) | 0.2525 | 2.62× | 0.7816 | 0.450 |
| **v2 (scoped + monotonicity fix)** | 0.2146 | 2.22× | 0.7699 | 0.320 |

**v1's headline numbers were inflated by the confound, and v2's are the honest ones on
a harder, cleaner target** — `precision@100` falls 0.810 → 0.450 from the target change
alone (removing 600 news positives concentrated in a 77%-positive block, where top-100
ranking was near-trivial), then 0.450 → 0.320 from scoped training. But v2 is not
*better*, and on this one test region the v1 recipe ranks slightly higher.

What Stage 9 delivered is **correctness and a settled scientific question**, not
accuracy: the leak is gone and structurally prevented, the monotonicity bug is fixed,
the steep-terrain failure is root-caused to region transfer, and the project's central
premise is now confirmed with a number (+0.1277 AP, 15/15).

### Re-derived deployment recommendation

The v1 recommendation does **not** survive unchanged — `precision@100` fell from 0.810
to 0.290, and that was the basis for the top-1–2% selective-ranking pilot.

- **Still not ready for autonomous deployment.** 4 of 12 gates fail.
- **The selective-ranking pilot must be narrowed, not just inherited.** Top-of-ranking
  precision is no longer 0.81; re-derive the operating coverage from
  `reports/stage9/dev_cost_curve.csv` before committing to a top-k, and validate the
  chosen k on dev rather than assuming v1's.
- **Exclude steep-terrain segments from any autonomous ranking** until rainfall
  resolution improves — D shows the model reaches ROC 0.75 on steep terrain in known
  regions and 0.63 in a new one.
- **Ship the ranking, not the probability.** Calibration transfer got *worse*
  (2.20× → 2.65×); re-fit the calibrator on local history before any probability drives
  the routing penalty `W = dist·(1 + λ·P)`.
- **Keep FN:FP = 10 over 20** (Stage 7 measurement, unchanged); it remains unvalidated
  with MDoNER and should be settled with them.
- **Human review on every alert**, unchanged.
- **New:** non-rain-attributable disruptions (GLOF aftermath, prolonged closures) are
  now explicitly out of model scope and need a separate detector. They are ~13% of test
  positives and the product still has to handle them.

---

## Version record

| version | config | status |
|---|---|---|
| `final_v1` | `5c8ab2326f9c5b5c` | **known-leaked, superseded.** Retained at `reports/stage7/PREREGISTRATION.json` with its full audit trail. |
| **`final_v2`** | **`5aed65f3f8729060`** | current. `reports/stage9/PREREGISTRATION_V2.json`. |
