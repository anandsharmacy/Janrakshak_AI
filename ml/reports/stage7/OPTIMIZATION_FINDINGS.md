# Stage 7 — Findings: what actually moved the model, and what didn't

Interpretation of the measured results in `OPTIMIZATION_REPORT.md` /
`optimize_results.json`. Methodology is in `../../ACCURACY_OPTIMIZATION.md`.
**Every number here is measured.** Recommendations are marked **[REC]**.

Protocol reminder: paired per-fold deltas over all 5 spatial folds against the
Stage 6 bar (mean AP **0.3506 ± 0.1607**), exact sign-flip permutation test,
decision rule = *delta > 0 AND ≥4/5 folds improve AND p < 0.10*.

---

## 1. Headline: 2 of 25 arms cleared the rule, and the winner was the arm predicted to lose

| arm | mean AP | Δ vs bar | p | folds+ | verdict |
|---|---|---|---|---|---|
| `aug/gaussian_all_s0.1` | 0.3787 | **+0.0282** | 0.0625 | **5/5** | **improvement** |
| `aug/smote_k5_f0.5` | 0.3678 | **+0.0173** | 0.0625 | **5/5** | **improvement** |
| `composite/passed` (both) | 0.3782 | **+0.0276** | 0.0625 | **5/5** | **improvement** ← selected |
| `loss/focal_g1.5` / `g2.0` | 0.3812 | +0.0307 | 0.125 | 4/5 | not demonstrated |
| `composite/all_positive` | **0.3834** | +0.0328 | 0.500 | 2/5 | not demonstrated |

Two things to read carefully:

1. **The highest AP measured in the entire stage (0.3834) was not selected.** It sits
   at p ≈ 0.5 with a minority of folds improving. Selecting it would have been the
   exact failure Stage 6 was built to prevent.
2. **`p = 0.0625` is the floor, not a strong result.** With 5 folds it is the
   smallest attainable two-sided p-value. See §7.

## 2. The augmentation result contradicts what was written in the code

`gaussian_all` — independent Gaussian noise on **every** numeric column, terrain
included — was implemented as the *contrast arm*, explicitly documented as the one
expected to lose, on the argument that the Copernicus DEM is exact at segment scale
so jittering it fabricates terrain. Meanwhile the carefully physics-preserving
rainfall jitter (single multiplicative factor across all windows, ID ratios scaled,
exceedance flags recomputed) was expected to win.

The measurement went the other way:

| arm | Δ vs bar | folds+ |
|---|---|---|
| `aug/gaussian_all_s0.1` (terrain jittered) | **+0.0282** | **5/5** |
| `aug/rain_jitter_s0.1` (physics-preserving) | +0.0029 | 4/5 |
| `aug/rain_jitter_s0.25` | −0.0124 | 2/5 |
| `aug/rain_jitter_s0.5` | −0.0179 | 2/5 |
| `aug/rain_jitter_append_s0.25` (2× rows) | −0.0115 | 1/5 |

**Why the prediction was wrong.** It answered a question about realism when the
binding constraint was memorisation. Noise on a feature is not only a claim about
measurement error — it is also a **regulariser that prevents the tree from splitting
on an exact value**. Three earlier measurements say that is precisely this model's
problem: Stage 5's in-sample AP 0.9999 vs held-out 0.29, Stage 3's LOECO leak through
repeat-offender segments, and 464 segments carrying more than one event. Static
terrain columns are an effectively unique per-segment fingerprint, and blurring them
does not model DEM error — it **destroys the fingerprint**.

### The decomposition supports that mechanism, but does not prove it

| arm (σ = 0.1) | Δ vs bar | folds+ |
|---|---|---|
| all numeric columns | +0.0282 | 5/5 |
| **static terrain/soil only** | **+0.0252** (89% of the effect) | 2/5 |
| rainfall columns only | +0.0031 (11%) | 4/5 |

Terrain-only recovers nearly all of the *mean* effect and rainfall-only almost none,
which is what the anti-fingerprint explanation predicts. But terrain-only improves
only 2 of 5 folds, so the attribution is **suggestive, not established** — the
decomposition is under-powered. Stated plainly rather than rounded up into a story.

### Strength sweep: mean gain and consistency move in opposite directions

| σ | Δ vs bar | folds+ |
|---|---|---|
| 0.05 | +0.0125 | 4/5 |
| **0.10** | **+0.0282** | **5/5** |
| 0.20 | +0.0288 | 4/5 |
| 0.40 | +0.0330 | 3/5 |

Larger σ keeps raising the average while breaking fold consistency — folds 0 and 2
gain hugely, folds 3 and 4 turn negative. That is the signature of a
high-variance intervention, and it is why the decision rule requires consistency as
well as a mean. **σ = 0.1 is the only setting that clears it.**

**[REC]** Ship σ = 0.1. Do not chase the larger σ numbers; they are regionally
unstable, which is the worst property for a corridor-wide deployment.

## 3. Focal loss: the largest single-arm gain, and it does not clear the rule

| γ | Δ vs bar | folds+ |
|---|---|---|
| 1.0 | −0.0003 | 4/5 |
| **1.5** | **+0.0307** | 4/5 |
| **2.0** | **+0.0307** | 4/5 |
| 3.0 | +0.0000 | 4/5 |

γ ∈ {1.5, 2.0} posts the biggest single-arm delta in the stage. It fails only on
fold consistency (4/5, p = 0.125). The per-fold detail explains why: γ=1.5 improves
folds 0, 2, 3, 4 by +0.014 to +0.057 and loses **−0.005** on fold 1. For γ=1.0 and
γ=3.0 that same fold-1 loss becomes **−0.14**, which is what erases their means.

So the entire focal result is a story about one region, and the γ window that works
is narrow. It is a real candidate that this fold count cannot resolve.

**[REC]** Re-test focal γ≈1.5–2.0 as the first item of any future stage that gains
more folds or more labels. Do not ship it on 4/5 folds.

*(γ=1.5 and γ=2.0 reporting identical means to 4 decimals is a coincidence — their
per-fold deltas differ; verified, not a duplicated run.)*

## 4. What did nothing — the negative results are the bulk of the stage

| arm | Δ vs bar | reading |
|---|---|---|
| `data/dedup` | −0.0019 | Stage 5 §8 already measured 0 conflicting duplicates. Confirmed null. |
| `data/conf_floor_0.25` / `0.35` | +0.0057 / −0.0020 | Pruning the near-unlearnable labels (Stage 5 P3) does not help. |
| `data/weight_uniform` / `sqrt` / `square` | +0.0050 / +0.0042 / −0.0003 | **Stage 2's confidence weighting earns nothing measurable** — discarding it entirely costs nothing. |
| `data/hard_neg_a1.0` / `a3.0` | +0.0013 / +0.0041 | Model-driven hard-negative mining ≈ 0, even with a leak-safe inner-CV prospector. |
| `data/easy_neg_drop_0.3` | +0.0092 | Largest data-side effect, still 4/5 and p=0.125. |
| `data/hard_pos_a1.0` | **−0.0087** | **Upweighting the hardest positives HURTS.** |

That last row is the informative one. Stage 5 §3 diagnosed the hardest positives as
near-zero-rain events — non-rainfall triggers, date errors, or rain CHIRPS never
saw — i.e. **label noise**. If that diagnosis is right, difficult-positive mining
should upweight noise and lose. It lost. The technique the brief asks for is
contraindicated *here*, for a reason the error analysis predicted in advance.

**[REC]** Drop hard-positive mining from the roadmap. Its failure is evidence *for*
the Stage 5 label-quality diagnosis, and the fix is better labels, not better weighting.

## 5. Two structural hypotheses tested, both rejected

**Terrain-stratified model** (Stage 5 §1 predicted this might be the big one). On
slope ≥ 10° rows only:

| model | mean AP |
|---|---|
| global model, restricted to steep rows | **0.3718** |
| dedicated steep-only model | 0.3687 |

Δ = **−0.0031**, p = 1.000. The hypothesis was that a single model burns its capacity
on the easy plains/hills boundary and a steep-only model would be forced to find
within-hill structure. **It found none.** That is not a modelling failure — it is
further evidence that the within-hill signal is genuinely absent at CHIRPS's ~25 km
daily resolution, exactly Stage 5's diagnosis.

**Ensemble** (LightGBM + logistic + `rain_x_terrain`, leave-one-fold-out weights):
mean AP 0.3732, Δ = **+0.0227**, p = 0.125 → not demonstrated. Solo members:
LightGBM 0.378, logistic 0.330, rule 0.165.

Worth noting against Stage 3, where logistic *beat* LightGBM (0.318 vs 0.247): with
the Stage 6 tuned config plus Stage 7's regularisation, the GBDT is now clearly ahead.
The blend's inability to help is consistent with the two models having converged on
the same information rather than complementary information.

## 6. Calibration — the one unambiguous win, and it is not visible in AP

Cross-fitted (fold *k* calibrated by the other folds), on the selected scorer:

| variant | global ECE | worst **terrain** stratum | worst **region** stratum |
|---|---|---|---|
| uncalibrated | 0.0396 | 1.16× | 3.10× |
| global isotonic | 0.0196 | **2.71×** | 3.39× |
| **per-slope isotonic** ← selected | **0.0193** | **1.32×** | 3.50× |

The flattest slope band is **47,052 rows — half the panel**. A global calibrator
over-predicts its risk by **2.71×**; per-slope calibration brings it to **1.32×**,
with in-band ECE 5.4× better (0.0098 → 0.0018). This is Stage 5's P2 item, delivered.

It matters because it is **invisible to AP**. Calibration is monotone, so ranking is
unchanged — but the product turns these probabilities into a routing edge penalty
`W = dist·(1 + λ·P)`, and a 2.7× inflated probability on half the corridor's roads
systematically over-penalises the safe plains route. AP cannot see that error; the
routing recommendation changes anyway.

**The two axes are reported separately on purpose.** Terrain is a property of the row
being scored, so a calibrator can condition on it at inference. *Which region* is not
knowable for a new area — a model deployed on unseen terrain cannot look up its own
base rate — so the ~3.5× region miscalibration is a **residual limitation to
disclose, not a target to optimise**. Pooling both into one "worst stratum" number
would hide a real fix behind an unfixable one.

Note also these numbers are *worse* than Stage 5's, and should be: Stage 5 fitted its
calibrator on the rows it then scored.

## 7. The statistical limit of this stage, stated plainly

With 5 folds the sign-flip test has **2⁵ = 32** possible sign patterns, so the
smallest attainable two-sided p-value is **2/32 = 0.0625**. Therefore:

- A Bonferroni-corrected threshold across 25 arms (α ≈ 0.004) is **unreachable by
  construction.** No arm in this stage is family-wise significant, including the two
  that "passed".
- At uncorrected α = 0.10, roughly 2–3 of 25 arms are expected to pass by chance.
  **Exactly 2 did.** That is not proof they are noise, but it is the null's
  prediction, and it must be stated next to the result.

The permutation test enumerates all 32 patterns exactly rather than sampling — Monte
Carlo sampling was printing p = 0.0619, *below the floor the same test guarantees*.

### Seed replication is the honest remedy

Fresh seeds redraw the event-grouped early-stopping split and the bagging RNG:

| arm | seed-0 Δ | replicate mean Δ (3 seeds) | fold×seed pairs improved |
|---|---|---|---|
| `aug/gaussian_all_s0.4` | +0.0330 | +0.0334 | 12/20 |
| `aug/gaussian_all_s0.2` | +0.0288 | +0.0322 | 14/20 |
| `aug/gaussian_all_s0.1` | +0.0282 | +0.0176 | 13/20 |
| `loss/focal_g1.5` | +0.0307 | +0.0207 | 16/20 |
| `loss/focal_g2.0` | +0.0307 | +0.0186 | 16/20 |
| `aug/smote_k5_f0.5` | +0.0173 | +0.0147 | 16/20 |

**Every leading arm replicates positively in the mean under all three fresh seeds.**
None reaches the fold-level consistency its seed-0 run suggested — `gaussian_all_s0.1`
drops from 5/5 to 13/20 across seeds, and its replicate mean is ~40% smaller than its
seed-0 delta. Read together: the direction is real, the magnitude is soft, and the
5/5 that cleared the decision rule was partly luck of one split.

**This is the most important caveat in the stage.** The selected configuration is a
modest, replicated, direction-stable improvement — not a 0.35 → 0.38 step change.

## 8. Cost — the selected model is larger and slower, and it does not matter

| config | model | trees | leaves/tree | µs/row | full 309k corridor | peak predict mem |
|---|---|---|---|---|---|---|
| bar (incumbent) | 594.1 KB | 1009 | 4.0 | 2.77 | 0.86 s | 7.15 MB |
| **composite/passed (selected)** | 709.1 KB | 1199 | 4.0 | 3.37 | 1.04 s | 7.15 MB |

The selected model is **19% larger and 22% slower**. The mechanism is
straightforward: SMOTE adds ~2,000 synthetic positives and the Gaussian noise makes
each split less decisive, so early stopping runs 190 rounds longer before the
event-grouped validation signal stalls.

Both score the **entire 309k-segment corridor in about one second**, against a daily
batch cadence. Latency is nowhere near a binding constraint here, so this cost is
accepted rather than traded against the accuracy gain. Note this is the opposite of
the Stage 6 situation, where a size/stability advantage was the *reason* for the
selection — here the cost column simply does not bind.

> An earlier draft of this table reported the selected model as *smaller and faster*
> (499 KB / 2.27 µs). That was the runtime profiler measuring `composite/all_positive`
> — the highest-AP candidate — rather than the selected one, the same max-AP-instead-of-
> verdict bug described in §12. Corrected here.

Single-machine dev-box measurement, valid for comparing configurations. Re-measure on
the deployment target before promising a latency SLA.

## 9. The operating point is a policy choice, and the current default is not the best one

| FN:FP | threshold | precision | recall | F1 | FP rate of negatives |
|---|---|---|---|---|---|
| 5 | 0.1642 | 0.236 | 0.700 | 0.353 | 21.0% |
| **10** | 0.0737 | **0.212** | **0.901** | **0.343** | 31.0% |
| 20 *(current default)* | 0.0567 | 0.206 | 0.911 | 0.335 | 32.6% |
| 50 | 0.0245 | 0.168 | 0.963 | 0.286 | 44.1% |

The F3-optimal threshold coincides exactly with FN:FP = 10.

**Measured finding: FN:FP = 10 dominates the inherited default of 20.** It gives up
**1 point of recall** (0.901 vs 0.911) in exchange for **1,341 fewer false alarms**.
The 20:1 ratio was a Stage 3 placeholder and has still never been validated with
MDoNER.

Top-of-ranking quality at the frozen threshold: **precision@10 = 0.90**,
precision@50 = 0.82, precision@100 = 0.83.

**[REC]** Take the cost table to MDoNER and let them choose. If no decision is
available before the demo, switch the default from 20 to 10 — it is strictly better
on this evidence.

## 10. What Stage 7 did *not* do

- **It did not re-run hyperparameter search.** Stage 6 established that lever is
  exhausted, and nothing here contradicts it.
- **It did not implement test-time augmentation.** The honest tabular analogue —
  averaging predictions over rainfall perturbations — is a smoothing operation over a
  monotone model, and the training-side jitter arms already measure whether that
  smoothing helps (it does not). Implementing it separately would be the same
  experiment with a new label.
- **It did not address Stage 5 P1 — higher-resolution rainfall (GPM IMERG, 0.1°,
  half-hourly).** This remains the single change most likely to move the headline,
  and it is a data-acquisition project, not a modelling one. Three separate Stage 7
  results now point at it: the steep-only model found no within-hill signal, the
  hardest positives are unlearnable label noise, and the only gains available came
  from *regularising away memorisation* rather than from extracting more signal.

## 11. The locked test set — opened once, and what it says

Full report in `FINAL_TEST_REPORT.md`; opening recorded in `TEST_SET_LEDGER.json`
(**openings: 1**).

| | dev (pooled OOF) | **locked test** |
|---|---|---|
| rows | 94,969 | 8,277 |
| base rate | 0.0847 | **0.1624** |
| average precision | 0.3791 | **0.3760** |
| **AP / base rate** | **4.48×** | **2.32×** |
| **ROC-AUC** | **0.8564** | **0.7879** |

**Do not read the flat AP as successful transfer.** The locked split is 1.9× denser
in positives (it holds all 3 gold labels and a spatially separate block set), and AP
scales with base rate — so an equal AP there means materially *less* skill. Both
base-rate-free comparisons show real degradation: lift over chance nearly halves
(4.48× → 2.32×) and ROC-AUC drops 0.86 → 0.79. That gap mixes selection bias (the dev
number chose among ~25 arms) with genuine distribution shift, and one test split
cannot separate them.

**The steep-terrain number is the one that matters, and it is poor.** On slope ≥ 10°
(4,586 rows, base rate 0.2564): AP 0.3689 → lift **1.44×**, **ROC-AUC 0.6242**,
top-10% lift 1.35×. A ROC of 0.62 is close to chance. Confined to the roads that
actually fail, the model can barely rank them — the healthy global numbers are
carried by telling plains from hills, exactly as Stage 5 §1 measured on dev and now
confirmed independently on held-out ground.

**The 3 verified closures scored at the 98.8th, 98.8th and 99.1st percentiles** — all
in the top 1.2%. This is the most encouraging number in the project and carries no
statistical weight at n=3. Reported because they are the only ground truth that
exists; suppressing them would be as dishonest as over-claiming them.

**Calibration did not survive the region shift.** Within dev, cross-fitted per-slope
calibration reached 1.32× on the worst terrain stratum; on the locked split the worst
stratum is **2.20×**, the model under-predicts overall at **0.71×**, and ECE roughly
doubles (0.0193 → 0.0469). This is the §6 limitation arriving exactly as predicted: a
calibrator conditions on terrain, which travels with the row, but not on *region*.
**Use the ranking on new terrain; do not trust the probability magnitude** until a
calibrator is re-fitted on local history — which directly constrains the routing
penalty `W = dist·(1 + λ·P)`.

At the frozen threshold: precision 0.284, recall 0.926, F1 0.435 (TP 1244 / FP 3133 /
FN 100 / TN 3800). Top of ranking: **precision@10 = 1.00**, @50 = 0.84, @100 = 0.81.

**Nothing was changed after this number was seen.** The configuration, threshold,
calibrator and metric list were frozen and hashed (`5c8ab2326f9c5b5c`) before the
split was read, and the hash reproduced exactly across independent runs.

## 12. Honest summary

Stage 7 produced a **small, replicated, direction-stable improvement** (+0.028 AP,
5/5 folds at seed 0, +0.018 under replication) from a source nobody predicted, plus a
**material calibration fix** (2.71× → 1.32× on half the corridor) that AP cannot see
but the routing layer depends on. It also produced ~20 well-measured null results that
close off whole branches of the roadmap.

The overall picture is unchanged from Stages 3, 5 and 6: **this problem is
information-limited.** Every Stage 7 gain came from stopping the model memorising
what it already had, and none came from extracting more signal — because there is not
more signal in ~25 km daily rainfall.

## 13. Three defects this stage found in its own code

Recorded because each one would have silently produced a *better-looking* result.

**1. Selection by AP instead of by verdict (twice).** `_best_candidate` picked the
highest mean AP regardless of the decision rule, and had promoted
`composite/all_positive` — highest AP measured (0.3834) at **p = 0.500 with 2/5 folds
improving**, and which drops 30% of negatives, shifting the predicted base rate and
pushing worst-slope miscalibration to **15.7×**. The same max-AP logic then leaked
into two more places: `composite_spec`, so the pre-registration read
`scorer: composite/passed` while carrying the **ten steps of
`composite/all_positive`** — `open_final_test.py` would have trained a different model
than the one the report claimed was selected, detectable only by diffing two JSON
fields — and the runtime profiler, which produced the incorrect size/latency numbers
noted in §8. Fixed at all three sites; `test_frozen_steps_belong_to_the_selected_scorer`
and `test_selected_scorer_cleared_the_decision_rule` now pin it.

**2. Monte Carlo permutation p-values below the test's own floor.** Sampling 20,000
sign patterns from a space of **32** returned p = 0.0619 where the exact value is
2/32 = 0.0625 — printing a p-value below the floor the same test guarantees. Now
enumerated exhaustively whenever 2ⁿ ≤ n_perm, which is both exact and seed-independent.

**3. Mining arms inflated total weight instead of redistributing it.**
`w *= 1 + α·rank` raised total negative mass from 43.7k to 102.8k at α=3, silently
changing the effective class balance and learning rate. The arm would have been
testing "more negative weight" confounded with "better-chosen negative weight". All
mining and weight-scheme arms now renormalise to the original mass.
