# Stage 3 — Baseline Analysis

Companion to the auto-generated `BASELINE_REPORT.md` / `metrics.json`. This is the
hand-authored read: model selection rationale, over/underfitting diagnosis, two
methodological bugs the baseline run itself caught, what to record for comparison,
and the concrete Stage 4 plan.

## 1. Model selection

**Chosen: LightGBM GBDT**, evaluated against **logistic regression** (linear floor)
and **five non-learned rules** (majority class, rainfall ID-threshold, antecedent
rain, terrain-only, rain×terrain) on identical spatial-CV OOF rows.

Why GBDT for this problem: 49 mixed numeric/categorical features with heavy,
structured missingness (soil nodata, `surface`/`maxspeed` >90% missing), strong
nonlinear interactions (rain × slope × lithology), and a rare, noisy, weakly-labelled
target. Trees handle missing values and categoricals natively, need no scaling, model
interactions without manual feature crosses, and give per-split feature importance —
directly useful for the "explain every part of the build" SIH judging criterion.

**Random Forest** was considered and not run as a third full baseline: on this
imbalanced, small-positive-count problem it typically underperforms boosting (no
gradient correction of hard cases) and gives coarser-grained probabilities, at similar
compute cost. It remains a one-line addition (`sklearn.ensemble.RandomForestClassifier`
behind the same `Data`/CV harness) if Stage 4 wants a third comparison point.

**Result — the honest surprise:** on the primary metric (spatial-block CV, pooled
OOF), **logistic regression (AP 0.318) currently beats LightGBM (AP 0.247
calibrated)**. Both clear the terrain-only rule (0.189). This is a legitimate finding,
not a bug: with only ~2,000 positive segments concentrated in ~30 spatial blocks, a
heavily-regularised linear model generalises across held-out regions better than an
under-tuned GBDT, which has more ways to fit region-specific noise. **Do not read this
as "drop LightGBM"** — it reads as "Stage 4 HPO has a clear, non-trivial bar to clear,
and the linear model is the fallback/ensemble component if it doesn't."

## 2. Two bugs the baseline run itself caught (methodology, not just numbers)

Both were caught by the same discipline the project committed to in Stage 2: compare
splits against each other and be suspicious of anything that looks too good.

**(a) Block-holdout early stopping was too noisy to use.** First attempt held out 20%
of *training blocks* for early stopping. Result: 3 of 5 outer folds stopped after
1–6 boosting rounds — the inner block-holdout signal was too small and unrepresentative
to guide round selection. Fix: the inner early-stopping split is now a random
row sample **stratified by target**, not a block holdout — it only ever picks
`n_estimators`, never touches the outer (honest) evaluation, so it doesn't reintroduce
spatial leakage. See `train/cv.py:_inner_earlystop_split`.

**(b) LOECO leaked through repeat-offender segments.** After fix (a), LOECO
(leave-one-event-cluster-out) AP jumped to an implausible **0.77–0.89 mean** —
exactly the "too good to be true" signature flagged in the project's own research
(spatial-autocorrelation inflation). Root cause: `event_cluster_id` groups by
space+time, but a segment like `SEG291652` (a real repeat offender — 6+ positive
dates across the record) appears in *different* clusters. Static terrain features
(exact slope/elevation/aspect floats) are an unintentional per-segment fingerprint,
so a model with enough capacity partly memorizes "this exact terrain vector = risky"
instead of learning the rain-trigger relationship — and that memorization pays off
hugely when the same segment resurfaces in a different LOECO fold's validation set.
**Fix:** LOECO fold assignment now union-find-merges any two event clusters that
share a positive segment into one group before splitting (`train/cv.py:run_loeco_cv`
/ `_union_find_merge`), so no segment can appear in both train and val. After the
fix, LOECO AP (0.305) sits right next to spatial-CV AP (0.243–0.285) — consistent,
credible, and the number now in the report.

**Takeaway for every future split in this project:** if a "hold something out" metric
comes back dramatically higher than the spatial-block number, look for a repeat-entity
leak before believing it.

## 3. Overfitting / underfitting diagnosis

| Signal | Reading |
|---|---|
| Fold best-iterations: `{0: 17, 1: 19, 2: 1200, 3: 1200, 4: 1200}` | **Bimodal, not one regime.** Folds 0/1 overfit almost immediately (val PR-AUC peaks in <20 rounds) — those held-out blocks are terrain/rainfall regimes poorly represented in the rest of the corridor. Folds 2–4 never trigger early stopping at all (ran to the 1200-round cap) — those blocks are more similar to training and the model is plausibly still **underfit** there; raising `n_estimators`/lowering `learning_rate` is a direct Stage 4 lever. |
| Spatial-CV AP std (0.106) ≈ 40% of the mean (0.285) | The metric is dominated by *which* region is held out, not by model quality alone. Any Stage 4 claim of improvement must be checked against this spread — a 0.02 AP gain is noise. |
| LOECO (0.305) ≈ spatial CV (0.243–0.285), both ≫ temporal OOT (0.162) | Consistent generalisation gap between "new region" and "new time + new label source", not a leakage artefact (post-fix). This is the expected order and a good calibration check for future changes. |
| LightGBM (cal) 0.247 < logistic 0.318 | LightGBM is **not yet overfitting the outer evaluation** (regularisation is working) but is **underfitting relative to what the data supports** — the linear model extracts more signal with fewer parameters. Points at hyperparameter search + feature curation, not "add more regularisation". |
| `terrain_only` rule (AP 0.189, ROC 0.770) vs LightGBM (AP 0.247, ROC 0.813) | The gap is real but modest — confirms the hills-vs-plains confound (flagged in Stage 2 `DATA_DECISIONS.md` §9.6) is only partially resolved by the matched hard-negative donut. `slope_mean_deg` / `upslope_basin_area_km2` are still the top-2 gain features. |
| Calibration: ECE 0.032 raw → 0.000 after isotonic on the calibration fold | Isotonic calibration is doing its job on the fold it was fit on (expected — always re-check ECE on a *held-out* calibration slice before trusting deployed probabilities; the current number is in-sample for the calibrator). |

**Net read:** this is a **high-variance, moderately-underfit baseline**, not an
overfit one. The fix is not "more regularization" — it's (a) genuine hyperparameter
search now that the CV harness is leak-safe, (b) more/better features, (c) possibly
fewer, more separable label tiers.

## 4. What to record for every future model (comparison ledger)

Every subsequent run (Stage 4 HPO, Stage 5+ accuracy work) must report, at minimum,
the same table as `metrics.json` so numbers are comparable apples-to-apples:

- **Primary:** spatial-CV pooled AP + per-fold mean±std (never just one number)
- **Secondary:** LOECO AP, temporal-OOT AP (both, not just the best one)
- ROC-AUC, Brier, ECE (raw and calibrated)
- precision@{10,50,100,200}, lift@{1,5,10}%
- Rule-baseline AP (majority, rainfall-threshold, terrain-only) **from the same OOF
  rows** — the bar to clear, not a one-time reference
- Fold best-iteration list (over/underfit signal)
- `n_positive_clusters`, `n_positive_segments` used (sample-size honesty)
- Feature importance top-15 (drift-check: if `hist_events_*`-style leaky features
  creep back in, importance ranking will show it immediately)

This baseline's numbers (**spatial-CV AP 0.243 pooled / 0.285±0.106 per-fold mean,
LOECO 0.305, temporal-OOT 0.162, logistic-regression floor 0.318**) are the numbers
every future change must beat, on the *same* metric, not a cherry-picked one.

## 5. Next experiments (Stage 4 priorities, in order)

1. **Hyperparameter search on the now leak-safe harness.** Nested CV: inner search
   on `num_leaves`, `max_depth`, `min_child_samples`, `reg_alpha/lambda`,
   `learning_rate` × `n_estimators` via the spatial folds' training blocks; outer =
   the 5 spatial folds for reporting. Search objective = **mean per-fold AP**, not
   pooled AP (pooled is dominated by the largest fold).
2. **Explain the logistic-vs-GBDT gap before trusting either.** Fit LightGBM with
   `num_leaves` swept down to 4–8 (near-linear) — if performance recovers toward
   0.318, the earlier config was still too flexible for this N; if it doesn't, the
   gap is about feature representation (e.g. LightGBM's monotone constraints on
   10 rainfall features may be too rigid given label noise — ablate them).
3. **Ensemble the two.** A simple rank-average or stacked (logistic-meta-learner
   on [LightGBM_p, terrain_only, rain_x_terrain]) predictor is cheap and often beats
   either alone in this low-N regime — try it before more GBDT tuning.
4. **Revisit the monotone-constraint list.** Currently 10 rainfall features forced
   non-decreasing. Ablate to the 3 most physically certain (`rain_7d_mm`,
   `rain_30d_mm`, `api_mm`) and compare.
5. **`hist_events_*` ablation, properly gated this time.** Stage 2 flagged these as
   spatial-CV-leaky and Stage 3 excluded them from the model entirely. Re-test them
   **only** in the temporal-OOT model (where the leakage mechanism doesn't apply)
   to see if they help the deployment-realistic split.
6. **Threshold policy review.** Current cost-optimal point (FN=20×FP) gives
   P=0.13/R=0.97 — extremely recall-heavy, 53,633 false positives on 60k negatives.
   Before demo, get a domain-informed cost ratio (or show the Pareto curve, per the
   compass doc's "fast-vs-reliable" framing) rather than defaulting to 20×.
7. **Bigger structural lever, if 1–6 plateau:** revisit Stage 2 negative sampling
   (the terrain-only rule is still doing real work — 0.189 AP) and the persistence
   window / accuracy-radius choices in label snapping, since those set the ceiling
   any model can reach.

## 6. Explicit non-goals for Stage 3

- No claim of a "final" model — this is the number to beat.
- No deployment threshold decision — the cost ratio here is a placeholder.
- `final_test` (the locked spatial hold-out + gold rows) was **not** touched by this
  run. It stays locked until Stage 8.
