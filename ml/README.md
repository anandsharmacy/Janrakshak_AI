# sih-ml — corridor disruption prediction (Chicken's Neck / Siliguri)

Per-road-segment-per-day prediction of rainfall-triggered landslide / flood road
disruption, + risk-aware routing. This repo is the **ML pipeline**; the raw data
tree lives in `../data2/training_data` (read-only, built by the acquisition
pipeline).

## Stage 2 — data pipeline (this stage)

```
raw sources (../data2)                  artifacts (data/processed/)
─────────────────────                   ───────────────────────────
COOLR/GLC, corridor landslides,   ─┐
reliefweb events, verified label   ├─►  labels_v1.parquet   tiered positives + strong negatives
                                  ─┘        + manifests/labels_v1.json
segment static + hydrology,        ─►  panel_v1.parquet    1 row / labelled segment-day, 49 features
CHIRPS daily rainfall                       + manifests/panel_v1.json
                                   ─►  folds_v1.parquet    spatial-block CV + out-of-time + LOECO + locked test
                                            + manifests/folds_v1.json
                                   ─►  reports/            label_qa.md, positives_review.csv,
                                                           label_map.png, split_diagnostics.md
```

### Run it

```bash
python scripts/run_stage2.py                 # labels -> panel -> splits -> QA
python -m pytest tests/ -q                    # leakage + schema + split contracts
```

Individual steps: `python -m sih_ml.labels.build_labels`,
`python -m sih_ml.features.build_panel`, `python -m sih_ml.splits.make_splits`,
`python -m sih_ml.labels.qa`.

### Config

Everything is in `conf/config.yaml` (paths, filters, ratios, split geometry).
`conf/feature_spec.yaml` declares column roles (target / meta / id / numeric /
categorical / cyclic / flag).

### Key design points

See **`DATA_DECISIONS.md`** for the full rationale. Highlights:

- Headline metric is **ranking (precision@k / AP) on spatially-held-out data**, not
  AUC — only ~115 independent positive clusters and 1 verified closure.
- **4-tier labels** (gold/silver/bronze/negative) with a confidence weight =
  `tier_prior · distance_decay · susceptibility_factor`.
- **Case-control negatives**: low-susceptibility ∧ >2 km from any hazard ∧
  season-matched dates, 10:1. Not "every unreported segment-day".
- **No random k-fold.** Spatial block CV with a 5 km buffer zone is primary;
  events are pinned to their modal block so they never straddle a split.
- **Leakage firewall**: rainfall features lagged 1 day, history lagged 30 days,
  all scaling/encoding fit inside the CV loop (`preprocess/transformers.py`).

## Stage 3 — baseline model

LightGBM GBDT, evaluated on spatial-block CV (primary), LOECO, and temporal OOT,
against a logistic-regression floor and 5 non-learned rules — all on identical OOF
rows. See **`reports/stage3/BASELINE_ANALYSIS.md`** for the model-selection
rationale, two leakage bugs the run itself caught and fixed (noisy block-holdout
early stopping; a repeat-offender-segment leak in LOECO), the honest finding that
logistic regression currently matches/beats LightGBM, and the Stage 4 priority list.
`reports/stage3/BASELINE_REPORT.md` + `metrics.json` carry the numbers.

```bash
brew install libomp                # once, macOS only — LightGBM needs OpenMP
make stage3                        # trains + evaluates + checkpoints + plots
```

Outputs: `models/baseline_v1/` (per-fold + final boosters, calibrator, OOF
predictions, model card) and `reports/stage3/` (report, analysis, metrics.json, plots).

## Stage 4 — training from scratch

The hardened training pipeline around the Stage 3 config: MLflow tracking, per-round
train/val curves, crash-resume checkpoints, determinism guarantees. See
**`TRAINING_STRATEGY.md`** for the full methodology — including the GBDT↔neural-net
vocabulary mapping (what's real vs genuinely N/A), the verified resume contract, and
the two monitoring-caught bugs (a curve-tracking valid set silently influencing early
stopping; early stopping driven by logloss instead of the declared PR-AUC primary
metric — worth **+0.039 mean AP** when fixed).

```bash
make stage4          # train (auto-resumes if a previous run was interrupted)
make stage4-clean    # discard checkpoints, force a fresh run
make mlflow-ui       # browse experiment history
```

Current: spatial-CV mean AP **0.325 ± 0.139** (Stage 3 baseline: 0.285 ± 0.106);
logistic-regression reference 0.318. `final_test` still locked.

## Stage 5 — evaluation & error analysis

`make stage5` (~21s). Runs on held-out OOF + out-of-time data; **never opens the
locked `final_test`** (guard test enforces this). See
**`reports/stage5/ERROR_ANALYSIS.md`** for the interpretation and the ranked fix plan.

Two findings dominate:

1. **Early stopping has no validation signal.** AP on the early-stopping rows is
   **0.999** vs **0.325** on held-out blocks. Measured cause: **100% of ES positives
   belong to an event that also has training rows** — one event produces up to 60
   panel rows (≤20 snapped segments × 3 days), so a random row split always splits
   it. Diagnostics show segment-grouping is insufficient; event-grouping restores the
   signal (0.999→0.716) but is accuracy-neutral. It unblocks Stage 6 HPO.
2. **Global AP overstates usefulness.** Within the steepest slope quartile lift is
   only **1.63×**; the headline number is carried by separating plains from hills,
   which routing already knows.

Generalization gap (measured): in-sample **0.999** → new region **0.294** → new time
**0.232**.

## Stage 6 — fine-tuning & HPO

`make stage6` (resumable Optuna study) · methodology in
**`FINETUNING_HPO_STRATEGY.md`** · measured results in `reports/stage6/HPO_REPORT.md`.

**Sequencing matters here.** HPO was impossible before Stage 5's P0 fix: the inner
early-stopping set scored AP 0.999 (100% event overlap with train), so every
configuration would have looked identical. Stage 6 lands that fix first
(`cv.es_split_mode: "event"`), then searches.

Controlled ladder, one change at a time: **E0** Stage 4 baseline → **E1** P0 fix
alone → **E2** Optuna TPE search → **E3** staged fine-tuning.

Two anti-overfitting guards, plus the locked test set as a third:

```
selection folds {0,1,2}  ->  what the search optimises
report folds   {3,4}     ->  honest read on the tuned config   (Stage 6)
final_test               ->  untouched, unbiased arbiter        (Stage 8)
```

A gain is only called an improvement if it **exceeds the fold-spread noise floor**;
`hpo_results.json` records that verdict as a boolean so it can't be upgraded in prose.

GBDTs have no layers to freeze, so fine-tuning uses the real analogues:
`Booster.refit()` (structure frozen, leaf values recomputed) → continue boosting at
reduced LR → full retrain. Parameters with no GBDT equivalent (optimizer, LR
scheduler, batch size, dropout) are documented as such rather than invented —
`subsample` and `colsample_bytree` are the genuine analogues and *are* searched.

## Stage 7 — accuracy optimization

`make stage7` (~15 min) · methodology in **`ACCURACY_OPTIMIZATION.md`** · measured
results in `reports/stage7/OPTIMIZATION_REPORT.md` · interpretation in
`reports/stage7/OPTIMIZATION_FINDINGS.md`.

Stage 6 closed by ruling out more hyperparameter search, so Stage 7 spends its
effort on data, augmentation, loss, ensembling and calibration instead. ~25 arms,
each a transform of a fold's **training rows only** — never the held-out fold, never
the early-stopping rows (`optimize/harness.py` is the single enforcement point).

**The instrument changed.** Stage 6 compared two means over 2 report folds and could
not resolve anything below ~0.03 AP. Stage 7 uses **paired per-fold deltas over all
5 folds** with identical seeds and ES splits, so fold variance cancels in the
difference, plus a sign-flip permutation test:

```
improvement  <=>  mean delta > 0  AND  >=4/5 folds improve  AND  p < 0.10
```

With 5 folds the smallest attainable p is `2/2^5 = 0.0625`, so a Bonferroni
correction across 25 arms is **unreachable by construction** — the report says so,
and the leading arms are **replicated under fresh seeds** instead of being declared
winners on one split.

Selection is not on AP: `_best_candidate` promotes a challenger only if it cleared
the decision rule. The highest-AP configuration measured in the whole stage is
deliberately *not* selected — it sits at p≈0.5 and damages calibration.

```bash
make stage7             # arm ladder; freezes the config, does NOT open the test
make stage7-final-test  # opens the locked split ONCE, under pre-registration
```

### The locked test set

`final_test` has been held out since Stage 2 and is opened exactly once:

```
1. all optimization decided on dev data              make stage7
2. config + metric list frozen, hashed               -> reports/stage7/PREREGISTRATION.json
3. test opened once, opening recorded                make stage7-final-test
                                                     -> reports/stage7/TEST_SET_LEDGER.json
```

`scripts/open_final_test.py` is the only code that may read it and **refuses to run**
without the pre-registration file; a test asserts every other Stage 7 module is free
of any `final_test` reference.

**Result (opening #1, config `5c8ab2326f9c5b5c`)** — full write-up in
`reports/stage7/FINAL_TEST_REPORT.md`:

| | dev (pooled OOF) | locked test |
|--|--|--|
| base rate | 0.0847 | **0.1624** |
| average precision | 0.3791 | 0.3760 |
| **AP / base rate** | **4.48×** | **2.32×** |
| **ROC-AUC** | **0.8564** | **0.7879** |

The flat AP is **not** evidence of transfer — the locked split is 1.9× denser in
positives and AP scales with base rate. The base-rate-free views both show real
degradation. On steep terrain (slope ≥ 10°, where the decisions actually are) the
model is close to chance: **ROC-AUC 0.624**, lift 1.44×. The 3 verified closures —
the only ground truth in the project — scored in the top 1.2%, which is encouraging
and statistically worthless at n=3. Per-slope calibration did not survive the region
shift (worst stratum 1.32× on dev → 2.20× on test), so **use the ranking on new
terrain and re-fit the calibrator on local history before trusting probabilities.**

## Stage 8 — final model validation

`make stage8` (~10 s) · decision record in **`FINAL_MODEL.md`** · measured results in
`reports/stage8/FINAL_VALIDATION_REPORT.md`.

**Stage 8 selects nothing.** The locked split was opened once under pre-registration
at the end of Stage 7; that opening is the project's single unbiased estimate. Stage 8
verifies the frozen config hash on entry (mismatch aborts), retrains to confirm the
recorded number reproduces **bit-identically**, then runs final testing, robustness,
generalization and readiness analysis on that frozen artifact. Its test reads are
logged as `kind="report"` and a test asserts *decision* openings stay at 1.

### The two findings that dominate

**1. Deleting rainfall makes the model rank better.** Ablating every rainfall input
raises test AP by **+0.112** (130% of baseline); ablating terrain changes nothing. Used
as a standalone score with no model, rainfall does not separate the classes on that
split and the long windows are **inverted** (7-day ROC **0.46**, vs 0.65 on dev) —
disrupted days there had *less* rain. Cause: `final_test` was defined as spatial blocks
*plus every gold label* with no constraint on label source, so its positives are ~45%
news-derived (13–48 mm mean rain) against ~10% in dev.

**2. The gold-label result from Stage 7 does not hold.** `SEG291652` is the only 1 of
4,392 test segments that also appears in training — as a positive, **15 times across 5
events** — and it carries all 3 gold labels. With rainfall deleted entirely their
percentile rank barely moves (99.29→99.11). Their top-1% position is segment identity,
not rainfall skill. Corrected in `FINAL_MODEL.md` §4.

### Verdict: 8 of 11 deployment gates pass

Failing: steep-terrain ROC **0.624** (gate 0.70), steep-terrain lift **1.44×** (gate
2.0×), calibration transfer **2.20×** (gate 1.5×). **Not ready for autonomous
deployment**; suitable for a decision-support pilot that ships the *ranking* not the
probability, alerts on the top 1–2% (precision 0.72–0.81), and keeps a human in the
loop. No inference optimization recommended — 709 KB, ~1 s for the full corridor.

```bash
make stage8
```

## Stage 9 — remediation

`make stage9` · **`REMEDIATION.md`**. Fixes the locked-split leak, scopes the model to
rain-attributable labels, fixes monotonicity, and root-causes the steep-terrain
failure to region transfer. Produces `final_v2`; `final_v1` is retained as known-leaked.

## Stage 10 — continuous improvement loop

`make stage10` · methodology and roadmap in **`CONTINUOUS_IMPROVEMENT.md`** · results in
`reports/stage10/IMPROVEMENT_REPORT.md` · every decision in
`reports/stage10/EXPERIMENT_LEDGER.jsonl` · current champion in `models/registry.json`.

A campaign verifies that the champion reproduces its recorded numbers bit-for-bit,
re-measures every known error pattern, and calibrates an **A/A noise floor** (the
champion against itself under fresh seeds: ±0.012 AP). It then runs one-variable
experiments under three rules (correctness / superiority / simplification) with
guardrails on region, steep terrain, calibration, monotonicity and cost. Decided
experiments are never re-run on unchanged data.

Campaign 1 found a data defect: 4,463 dev rows were dated past the end of the CHIRPS
record and carried fabricated dry rainfall. The fix (D1) was adopted → **`final_v3`**.
Every other experiment was not demonstrated (inside noise) or rejected by a
guardrail, and every recipe component was confirmed.

## Stage 11 — deployment

**`DEPLOYMENT.md`** · measurements in `reports/stage11/` · code in `src/sih_ml/serve/`.

A daily corridor batch (309,042 segments in ~1 s) plus a read API (gunicorn), on one
CPU VM. The pipeline was optimized (feature store, numpy path, JSON calibrators) with
**bit-identical** outputs. Every model-side optimization was measured and rejected
or not needed:
- **tree truncation** re-ranks the corridor (Spearman 0.85) despite non-inferior AP;
- **Treelite** is 8.5× faster but wrong on 2,795 rows with missing inputs;
- **ONNX** is equivalent but gains nothing here;
- **FP16/INT8** have no CPU tree kernel;
- **distillation** is dominated by truncation;
- **TensorRT** has no GPU to run on and nothing to gain.

```bash
make bundle && make deploy-venv && make score DATE=2025-08-15 && make serve
```

## Layout

```
conf/            config.yaml, feature_spec.yaml
src/sih_ml/
  labels/        events.py, build_labels.py, qa.py
  features/      rainfall.py, build_panel.py
  preprocess/    transformers.py           (in-fold pipeline)
  splits/        make_splits.py
  models/        dataset.py, baselines.py (rules), lgbm_baseline.py,
                 linear_baseline.py, calibration.py
  train/         cv.py (spatial/LOECO/temporal CV), run_baseline.py,
                 train_from_scratch.py, tracking.py (MLflow),
                 hpo.py (Optuna), finetune.py, run_hpo.py,
                 run_optimize.py (Stage 7), final_test.py (locked split)
  optimize/      harness.py (arm contract + paired tests), data_opt.py (mining),
                 augment.py, losses.py (focal), ensemble.py, calibrate.py,
                 threshold.py, stratified.py, composite.py, runtime.py
  eval/          metrics.py, plots.py, error_analysis.py, run_error_analysis.py
  final/         audit.py, robustness.py, readiness.py, rainfall_probe.py (Stages 8-9)
  improve/       candidate.py, decide.py, diagnose.py, efficiency.py, features.py,
                 ledger.py                  (Stage 10 loop; runner: train/run_improve.py)
  serve/         bundle.py, featurestore.py, predictor.py, validate.py, batch.py,
                 api.py, feed.py, monitor.py, build.py, benchmark.py   (Stage 11)
  utils/         common.py, geo.py
deploy/          requirements.txt, gunicorn.conf.py, Dockerfile, ops/ (systemd, alerts)
scripts/         run_stage2.py … run_stage10.py, open_final_test.py, stage2_gate.py,
                 bench_runtimes.py, load_test.py, load_suite.py
tests/           test_no_leakage.py, test_schema.py, test_splits.py,
                 test_baseline.py, test_training_pipeline.py,
                 test_error_analysis.py, test_hpo.py, test_optimize.py,
                 test_final_model.py, test_remediation.py, test_improve.py, test_serve.py
data/
  interim/       centroids, susceptibility, dedup events  (cache)
  processed/     labels_v1 / panel_v1 / folds_v1 + manifests/
reports/         QA + diagnostics
```

## Environment

Python 3.14 venv at `../data2/other_files/venv`. Extra deps installed on top of the
acquisition env: `scikit-learn scipy pyyaml matplotlib pytest lightgbm`. See
`requirements.txt`. LightGBM needs OpenMP on macOS: `brew install libomp`, then run
with `DYLD_LIBRARY_PATH=/opt/homebrew/opt/libomp/lib` (the `Makefile` sets this).

## Concurrency warning

`../data2` is edited by another agent + live Jupyter kernels. `build_labels` hashes
every source and compares to `data/processed/manifests/sources.lock.json` — a drift
warning means **re-run the whole pipeline** before trusting any artifact.
