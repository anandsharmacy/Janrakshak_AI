# CONTINUOUS_IMPROVEMENT — Stage 10

The system that keeps improving the model after Stage 9, and the roadmap it runs.
Methodology and rules are here. **Measured results are in
`reports/stage10/IMPROVEMENT_REPORT.md`** (generated), every experiment is a line in
`reports/stage10/EXPERIMENT_LEDGER.jsonl`, and the current champion is named in
`models/registry.json`. §5–§7 below interpret one specific campaign and quote its
numbers. Re-read them against the report after any new campaign.

```bash
make stage10     # one campaign: verify champion -> diagnose -> A/A -> experiments -> promote
make test        # includes tests/test_improve.py (rules + the finished campaign)
```

---

## 0. What Stage 10 inherits, and what that rules out

Nine stages of evidence, each measured and none assumed:

| evidence | stage | consequence for the loop |
|---|---|---|
| 40 TPE trials found no demonstrated gain; search chose the 4-leaf floor | 6 | **no more hyperparameter search** — it is not in the backlog |
| logistic regression matched the GBDT; a steep-only model found nothing | 3, 7, 9 | **no architecture search** — capacity is not the constraint |
| in-sample AP ≫ out-of-fold AP; the only gains came from blurring static columns | 5, 7 | memorisation is a live bottleneck → regularisation experiments |
| steep ROC ≈ 0.75 in dev regions vs 0.63 on the held-out region | 9 | **region transfer is the dominant failure** → features that travel |
| rainfall contributes +0.128 AP (15/15) once leak and confound are removed | 9 | the rainfall signal is real, so rainfall-side features are worth testing |
| hard-positive mining hurt; the hardest positives are low-rain label noise | 5, 7 | hard-example *mining* is contraindicated — **not** in the backlog |
| ~25 km daily CHIRPS cannot resolve valley-scale triggering | 5, 7, 8, 9 | the largest lever is a **data acquisition**, outside any modelling loop |

Two things follow. The loop spends its budget only where earlier stages left a
measured, open question. And it has to be honest that the biggest remaining lever
(higher-resolution rainfall) isn't a modelling change at all, so no campaign can
pull it.

---

## 1. The loop

```
            ┌──────────────────────────────────────────────────────────────────┐
            ▼                                                                  │
 0 VERIFY champion ──► 1 DIAGNOSE ──► 2 A/A noise ──► 3 correctness ──► 4 backlog ──► 5 compose ──► 6 promote
   (reproduce its        (re-measure     (champion vs    (round 0)        (round 1,    (round 2,     registry +
    recorded AP bit-      every error     itself, 6                        each vs the   greedy,       artifact +
    for-bit, or abort)    pattern)        seeds)                           champion)     re-measured)  ledger
```

| step | what happens | code |
|---|---|---|
| **Evaluate** | champion rebuilt from its recorded *state* and required to reproduce its recorded per-seed dev AP (to 1e-12) and dev operating threshold (exact). On mismatch the campaign aborts | `run_improve.Loop.verify_reproduction` |
| **Analyze errors** | every known pattern re-measured on the champion's out-of-fold predictions: memorisation gap, region spread, steep ROC, low-rain misses, calibration, data integrity | `improve/diagnose.bottlenecks` |
| **Identify bottleneck** | each pattern maps to the layer a fix must come from and the backlog items that target it — declared in config, so the mapping can be challenged | `conf/improve_config.yaml: bottlenecks` |
| **Change one variable** | an experiment is a single change to the champion's state; `apply_change` refuses anything else | `improve/candidate.apply_change` |
| **Train** | 5 spatial folds × 3 seeds, identical ES splits and seeds on both sides | `improve/candidate.run` |
| **Validate** | paired deltas, A/A-calibrated rule, guardrails beyond AP | `improve/decide` |
| **Compare / keep / revert** | ACCEPT → promoted; NOT DEMONSTRATED / REJECT → reverted, reason recorded | `run_improve.main` |

**Reproducible and tracked.** Every ledger line carries a hash of every source
file (the repo has no git), a hash of the panel, folds and CHIRPS inputs, library
versions and platform, both sides' per-(seed, fold) AP, the guardrail readings, the
decision and the reason in words. `test_published_decisions_follow_the_rule`
recomputes every decision from the raw AP in the ledger, so the verdicts and the
numbers cannot drift apart.

**Continuous.** A campaign starts from the registry champion, not from a fixed
config. An experiment already decided against the same champion state, code and
data is skipped rather than re-run. It re-opens automatically when any of those
change, and new data is the intended trigger. Re-running a decided comparison until
it passes is the quietest way to promote noise, and the loop makes that impossible
by construction.

---

## 2. Decision rules

### Three kinds of experiment, three rules

| kind | question | ACCEPT when |
|---|---|---|
| **correctness** | is something *wrong* (a data bug, an escaped constraint)? | no demonstrated regression and no guardrail breach. Adopted on correctness grounds; Stage 9's monotonicity fix is the precedent |
| **superiority** | does the change make the model *better*? | Stage 7/9 rule on fold-averaged deltas (Δ > 0, ≥ 4/5 folds, exact p < 0.10) **and** Δ > 0 under every seed **and** Δ > the A/A noise floor **and** no guardrail breach |
| **simplification** | can a component be *removed* at no cost? | non-inferior: Δ ≥ −min(A/A floor, 0.01), fewer than 4/5 folds worse, ≤ 1 seed below the margin, no guardrail breach |

Simplifications get their own rule because demanding superiority from a removal
would keep dead weight forever. A component that earns nothing costs variance,
code and explanation. The 0.01 cap exists because the first smoke run *accepted*
removing a component at −0.020 AP against a wide 2-split noise floor. A noise floor
can license ignoring small effects, never large ones.

### The A/A noise floor — the instrument's own resolution, measured

The champion is trained under 3 extra seeds. Every split of the 6 seeds into two
groups of 3 is a comparison of **the model against itself**, and any delta it shows
is seed noise (ES split, bagging RNG, augmentation noise). Over those 20 ordered
splits the loop records:

- **AP floor**: the 90th percentile of |Δ mean AP|. A superiority claim must exceed it.
- **worst-fold floor**: how far one region's AP swings on noise alone. The region
  guardrail fires only beyond it.
- **steep-ROC and calibration floors**: the same idea for each guardrail metric. A
  guardrail must not fire on noise any more than an AP claim may pass on it.
- the **empirical false-positive rate of the Stage 7/9 rule**: how often the old
  rule called the model better than itself.

Earlier stages argued their resolution from the fold count (Stage 6: "~0.03";
Stage 7: "p ≥ 0.0625 by construction"). The A/A floor measures it directly, on the
current champion, every campaign.

### Guardrails — "never chase validation accuracy alone"

Every challenger must hold all of these, whatever its AP:

| guardrail | fails when | why it exists |
|---|---|---|
| region | worst fold-averaged Δ below −(A/A worst-fold floor) | a model that helps four regions and hurts one is not a corridor-wide improvement |
| steep terrain | steep ROC drops more than max(0.01, A/A floor) | the roads that close are steep; global AP is carried by plains-vs-hills |
| calibration | worst terrain stratum worsens by more than max(0.25×, A/A floor), or crosses the 1.5× gate the champion passes | probabilities become the routing penalty `W = dist·(1 + λ·P)`, and AP cannot see calibration |
| monotonicity | any score decrease when rainfall rises (flags *and* engineered rainfall features re-derived) | the Stage 9 gate; a new derived feature must not escape it the way `id_exceed_*` did |
| cost | corridor pass > 300 s or artifact > 50 MB | the deployment gates |

---

## 3. What each error pattern says the next experiment should be

Re-measured on the champion every campaign (report §2). The layer column is the
point: it says where a fix can come from before anyone reaches for a model change.

| pattern | measured on the champion | layer a fix must come from | backlog item |
|---|---|---|---|
| **data integrity** — rows dated past the CHIRPS record carry fabricated dry rainfall | 4,463 dev rows, all negatives | data | D1 (correctness) |
| **region transfer** — skill does not travel between valleys | fold AP spread; locked-split steep ROC 0.63 vs dev ≈ 0.75 | data (rainfall resolution) › features › training | X3 climate-relative rainfall, X4 seed bagging |
| **steep terrain** — weak discrimination where roads close | steep vs non-steep ROC | data (rainfall resolution) | X3 |
| **memorisation** — static columns as a segment fingerprint | in-sample / OOF AP ratio | training (regularisation) | X2 coarse static bins; S2 tests whether the noise still earns its place |
| **missed positives** — misses are the low-rain rows | FN vs TP median rain | labels (dates, triggers) › rainfall resolution › loss | X1 focal loss. *Not* hard-positive mining, which Stage 7 showed hurts |
| **calibration transfer** — probabilities do not survive a new region | worst region stratum | post-processing on **local** history | none — not fixable from dev (§7 roadmap) |

---

## 4. Test-set policy

The locked split is **not** read by Stage 10 at all. `test_improve.py` asserts that
no Stage 10 file names it and that the Stage 7 ledger records no Stage 10 opening.
A promoted model is a **dev champion** and the registry says so
(`locked_split: NOT opened`).

The locked split has already been opened for two decisions (v1 in Stage 7, v2 in
Stage 9), and its region has shaped every investigation since. A third opening would
confirm little. The honest next arbiter is a **fresh holdout**: events after the
current data window, frozen before any campaign sees them (roadmap P1). A release
then follows the Stage 7 procedure against that holdout: pre-register the config,
open once, record the opening.

---

## 5. Campaign `c20260912T022646Z` — what the loop measured

Full tables: `reports/stage10/IMPROVEMENT_REPORT.md`. One earlier campaign
(`c20260912T021324Z`) was stopped after round 0 to fix two code defects. Its ledger
lines are kept and marked `campaign_aborted`, and nothing from it was acted on.

**The instrument.** The champion reproduced Stage 9 exactly: per-seed AP to 1e-12 and
the pre-registered threshold bit-for-bit. The A/A floors measured on it:

| | AP (q90 \|Δ\|) | worst fold | steep ROC | terrain calibration |
|---|---|---|---|---|
| final_v2 | 0.0130 | 0.0442 | 0.0063 | 0.20× |
| final_v2 + D1 | 0.0124 | 0.0396 | 0.0086 | 0.015× |

**So seed noise alone moves mean AP by up to ±0.012.** That is the same size as
most effects claimed in Stages 7 and 9. With 5 folds the old rule's empirical
false-positive rate was 0–5% on these splits, low only because it effectively
demands 5/5 folds. The floor is the stricter and more informative bar.

| experiment | kind | Δ AP | decision | why |
|---|---|---|---|---|
| D1 rainfall coverage | correctness | −0.0014 | **ACCEPT** | fabricated rows removed; accuracy effect nil (not a gain, not a loss) |
| X1 focal γ=1.5 | superiority | −0.0053 | not demonstrated | inside noise; 0/3 seeds positive. Stage 7's +0.031 did not survive the clean target |
| X2 coarse static bins | superiority | −0.0085 | not demonstrated | the anti-fingerprint mechanism is already saturated by the noise augmentation |
| X3 climate-relative rainfall | superiority | −0.0028 | not demonstrated | 1/5 folds. Region transfer is not fixed by re-expressing the same 25 km rainfall |
| X4 seed bagging ×3 | superiority | +0.0044 | **REJECT** | calibration guardrail: worst terrain stratum 1.04× → 1.41×, and the gain is inside noise |
| S1 remove SMOTE | simplification | −0.0099 | **REJECT** | steep ROC −0.013. SMOTE still earns its place on steep terrain |
| S2 remove Gaussian noise | simplification | −0.0288 | **REJECT** | worst region −0.072 AP, steep ROC −0.020. The recipe's key component, confirmed |
| S3 uniform weights | simplification | −0.0110 | **REJECT** | 4/5 folds worse. Stage 7's "confidence weights earn nothing" no longer holds on the clean target |

**Champion: `final_v3` = `final_v2` + D1.** Bottlenecks before → after: dev rows
beyond the rainfall record 4,455 → 0; everything else unchanged within noise.

Three things this campaign establishes that nothing earlier did:

1. **The Stage 7 recipe is justified component by component on the clean target.**
   Removing any piece fails. S3 even reverses a Stage 7 null: label-confidence
   weights now matter.
2. **Model-side levers are exhausted at this data resolution.** Four independent
   hypotheses, one per open bottleneck, all landed inside ±0.012 AP. Together with
   Stage 6 (HPO), Stages 3 and 7 (architecture) and Stage 9 (steep-only model), no
   model-side change remains with an evidence-backed reason to expect a gain.
3. **Seed bagging shows why "never chase AP alone" is enforced in code.** It posted
   the only positive delta, and it would have shipped a 1.41× miscalibration into the
   routing penalty.

## 6. Final model selection — the criteria, in order

A challenger replaces the champion only by passing each gate in order. Later criteria
break ties among survivors and can never rescue a failure earlier in the list.

1. **Reproducibility.** It rebuilds from state + seed and reproduces its own numbers.
2. **Correctness.** Guardrails: monotonicity 0 violations; calibration within tolerance
   and not crossing the 1.5× gate; cost within the deployment gates.
3. **Generalisation.** Decision rule on fold-averaged deltas, replicated on every seed,
   above the A/A floor. For removals, non-inferiority.
4. **Robustness.** No region (fold) loses more than the A/A worst-fold floor. Steep-terrain
   ROC is held, because the roads that close are steep.
5. **Real-world reliability.** Calibration by terrain stratum is held, and so is the
   data-integrity fix (no rows beyond the rainfall record).
6. **Cost.** Inference latency and memory: a tiebreak only, since the gates have
   about 300× headroom (Stage 11 measures this).
7. **Simplicity.** Fewer components wins a tie.
8. **AP.** Last. It is the metric most exposed to selection noise.

## 7. Roadmap — highest impact first, and when to stop

Ordered by expected impact on the metric that matters (steep-terrain skill on
unseen ground) × confidence ÷ effort. Impact entries are predictions, except where
marked measured.

| # | item | layer | why now | success criterion |
|---|---|---|---|---|
| **P0** | Rebuild the panel with the fixed `rainfall.py`, and clamp negative sampling dates to the rainfall record | data | D1 is corrected by a mask; the source must stop producing the rows | panel_v2 has 0 rows beyond the record; `test_panel_v1_defect_is_pinned_and_masked` is retired |
| **P1** | **Fresh holdout**: freeze all events after the current window before any campaign sees them | evaluation | the locked split has been read for two decisions; no clean arbiter is left | a pre-registered opening on data no stage has touched |
| **P2** | **Higher-resolution rainfall: GPM IMERG 0.1°, half-hourly**, plus sub-daily intensity features | data | every line of evidence points here (Stages 5, 7, 8, 9, 10: X3's null is the latest) | steep-terrain ROC on spatial CV clears its A/A floor over final_v3; later, the fresh holdout |
| **P3** | Date audit of news-derived positives: bring the `corridor_landslides` / `reliefweb` events back into scope where a trigger date can be fixed | labels | 1,380 positives excluded by provenance; Stage 5: misses are low-rain rows | in-scope positives up, with the rainfall-signal probe still +Δ on each source |
| **P4** | Local recalibration loop: refit per-slope calibrators on operational history each season | post-processing | the only fix for region calibration (2.65× on the locked split) | worst terrain stratum ≤ 1.5× on the next season's data |
| **P5** | Validate FN:FP with MDoNER; set alert/review capacity per day | policy | Stage 11 measures 3.5k alerts + 21k reviews/day at the dev threshold | an agreed top-N per tier |
| P6 | Re-open X1 (focal) and X4 (bagging, with its calibrator refitted) **after P2** | training | both are noise-limited, not refuted; better inputs change the question | the Stage 10 rule, on the new data |
| — | not on the roadmap: more HPO, new architectures, hard-positive mining, TTA | — | measured null or contraindicated (Stages 6, 7, 10) | — |

**When to stop optimising.** A campaign on unchanged data has now been run, and
every backlog item on the modelling side has been decided. The loop's own skip
rule means another `make stage10` on this data does nothing new, by design. Stop
modelling campaigns until one of these changes:

- **the data fingerprint** (P0, P2, P3). New inputs re-open decided questions
  automatically;
- **the A/A floor** shrinks enough to resolve the effects in question (more folds,
  more labels);
- **a new, evidence-backed hypothesis** enters the backlog with a named error pattern.

Until then, effort goes to P0–P5, which are data, evaluation and policy work. The
ceiling here is information, not modelling, and nine stages have now measured that
from every side.
