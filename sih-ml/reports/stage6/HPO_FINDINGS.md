# Stage 6 — Findings & Model Selection

Interpretation of the measured results in `HPO_REPORT.md` / `hpo_results.json`.
Methodology is in `../../FINETUNING_HPO_STRATEGY.md`. **`final_test` still locked.**

---

## 1. Headline: 40 trials of Bayesian HPO produced no demonstrated improvement

| experiment | selection folds {0,1,2} | **report folds {3,4}** (unseen by search) |
|---|---|---|
| E0 baseline (Stage 4 config) | 0.3984 | **0.2143 ± 0.0313** |
| E1 + P0 event-grouped ES | 0.3566 | **0.2029 ± 0.0255** |
| E2 Optuna best (29 complete / 11 pruned) | **0.4397** | **0.2168 ± 0.0216** |

- Margin of the tuned model over baseline on report folds: **+0.0025**
- Fold-spread noise floor: **0.0313**
- **Verdict: not demonstrated.** The gain is ~12× smaller than the noise.

## 2. The search overfit its own objective — and we caught it

The search lifted its objective by a lot and the honest read by almost nothing:

| | selection AP | report AP |
|---|---|---|
| E1 → E2 (effect of tuning) | **+0.0831** | **+0.0139** |

A **+23% relative** gain on the folds being optimised collapses to **+6.8%** on folds
the search never saw — and to **+1.2%** against the original baseline. Roughly **six-sevenths
of the apparent improvement was search overfitting.**

This is the single most important result of the stage, and it is only visible because
selection and report folds were separated *before* the search ran. Reporting the
Optuna best value (0.4397) as "the tuned model's performance" — the default in most
HPO write-ups — would have overstated it by **~2×**.

## 3. What the search actually chose is more informative than the score

| parameter | search range | chosen | position |
|---|---|---|---|
| `num_leaves` | 4 – 64 | **4** | **floor of the range** |
| `min_child_samples` | 10 – 400 | **364** | near ceiling |
| `reg_alpha` | 1e-3 – 20 | 1.98 | high |
| `min_split_gain` | 0 – 1 | 0.839 | near ceiling |
| `scale_pos_weight_mult` | 0.1 – 3.0 | **0.138** | near floor |
| `use_monotone` | {T, F} | **True** | constraints kept |

Given free rein, TPE drove the model to the **simplest, most heavily regularized
corner of the space it was allowed** — 4 leaves per tree with a 364-sample minimum,
essentially an ensemble of stumps. It wanted to go simpler than the range permitted.

This independently corroborates two earlier findings:
- **Stage 3:** logistic regression matched/beat the GBDT (AP 0.318 vs 0.247).
- **Stage 5:** in-sample AP 0.9999 vs held-out 0.29 — capacity was never the constraint.

Three independent lines of evidence now say the same thing: **this problem is
information-limited, not capacity-limited.** More model does not help.

Also notable: the search *kept* the monotone rainfall constraints (`use_monotone: True`),
settling the Stage 3 open question — they are not the handicap they were suspected of being.

## 4. The P0 fix costs a little accuracy and is still correct

E0 → E1 moves report AP from 0.2143 to 0.2029 (−0.0114, inside the ±0.031 noise).
So the event-grouped early-stopping split is, as Stage 5 predicted,
**accuracy-neutral-to-slightly-negative and methodologically necessary**.

Without it the search would have been scoring configurations against a validation
signal sitting at AP 0.999 — every trial would have looked identical. The fix is what
made Stage 6 a real experiment rather than a random walk. Keep it.

## 5. Fine-tuning: adapting the old model is useless or harmful; retraining wins

Out-of-time test (2019+), base model trained on ≤2015, adaptation window 2016–2018:

| stage | mechanism | AP | vs base |
|---|---|---|---|
| base (old period only) | — | 0.0951 | — |
| 0 frozen | reuse unchanged | 0.0951 | 0.0000 |
| 1 refit leaves | structure frozen, leaves recomputed | 0.0980 | +0.0029 |
| 2 continue boosting | new trees at 0.3× LR | **0.0823** | **−0.0128** |
| 3 **full retrain on train+adapt** | from scratch | **0.1952** | **+0.1001** |

**Retraining on all available data more than doubles out-of-time AP**, while both
"fine-tuning" approaches do essentially nothing (refit) or actively hurt
(continue-boosting).

The mechanism is intelligible: a GBDT's trees hard-code the *old* regime's split
thresholds. `refit()` can only rescale leaf outputs within that fixed structure, and
appended trees must fight the frozen ensemble's bias rather than replace it. Neither
can undo a structural shift — and Stage 5 already established the 2019+ period carries
a label-*source* shift (GLC → reliefweb), not just a temporal one.

**Conclusion: do not ship an incremental fine-tuning path for this model.** When new
data arrives, retrain. The training run takes ~2 minutes, so there is no operational
reason to prefer adaptation.

## 6. Model selection — and why the "losing" model is still the right pick

Against the Stage 6 criteria (§5 of the strategy doc):

| criterion | E0 baseline | E2 tuned | winner |
|---|---|---|---|
| 1. Generalization (report AP) | 0.2143 | 0.2168 | **tie** (inside noise) |
| 2. Stability (fold spread) | ±0.0313 | **±0.0216** | **E2** (31% tighter) |
| 3. Beats rule baselines | yes | yes | tie |
| 4. Calibration | not re-measured this stage | — | unresolved |
| 5. Cost (size / latency) | 24 leaves/tree | **4 leaves/tree** | **E2** (~6× smaller) |

**Selected: the E2 tuned configuration — explicitly *not* on accuracy grounds.**

Its accuracy advantage is not demonstrated and is not claimed. It is selected because
at **statistical parity** it is ~6× smaller per tree and ~31% more stable across
regions. For a system that must score 309k segments daily and whose Stage 5 error
analysis flagged region-to-region inconsistency, smaller and steadier at equal
accuracy is the better engineering choice.

If the next reviewer prefers E0 on the grounds that "no change is safer than an
unproven change", that is also defensible — the two are statistically
indistinguishable. What is *not* defensible is calling E2 an accuracy improvement.

**Carried forward to Stage 7:** `reports/stage6/best_params.json`.

## 7. Honest limits

- **2 report folds is a thin noise estimate.** It cannot resolve gains below ~0.03 AP.
  A true nested CV (HPO inside every outer fold) would be tighter but costs ~5× the
  compute; it is the right move if Stage 7 needs finer resolution.
- Selection and report folds partition the same dev set, so they are not fully
  independent. `final_test` remains the only clean arbiter.
- Calibration was not re-measured for the tuned config. Stage 5 found up to 3×
  region-dependent miscalibration, and a 4-leaf model will have a different
  probability distribution — **re-run the Stage 5 calibration analysis on the tuned
  config before it drives routing weights.**

## 8. What this means for the remaining stages

Stage 6 was worth running and its answer is mostly negative, which is a real result:
tuning is exhausted as a lever. The consistent signal across Stages 3, 5 and 6 is that
the ceiling is **information**, not model configuration.

Stage 7 (accuracy optimization) should therefore spend its effort on the Stage 5 P1/P2
items — higher-resolution rainfall and per-stratum calibration — and on ensembling
(LightGBM + logistic + rules), **not** on further hyperparameter search. The search
space has been explored; it does not contain the answer.
