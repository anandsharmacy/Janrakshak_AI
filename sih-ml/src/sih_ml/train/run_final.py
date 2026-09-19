"""Stage 8 orchestrator — final model validation.

    python -m sih_ml.train.run_final [conf/optimize_config.yaml]

Stage 8 **selects nothing and changes nothing.** The locked test set was opened once
at the end of Stage 7 under pre-registration; that opening is the project's single
unbiased estimate. This script:

  P0  verifies the frozen config hash still matches PREREGISTRATION.json
  P1  retrains it and checks the recorded test AP reproduces bit-for-bit
  P2  final testing: class-wise metrics, confusion, PR/ROC, reliability, group tables
  P3  robustness: counterfactual rainfall, ablation, noise, edge cases, monotonicity
  P4  generalization: train/ES/OOF/test on one axis, leakage audit, dataset bias
  P5  production readiness: scalability, gates, optimization advice
  P6  model card + deliverables

A config hash mismatch aborts. The run is recorded in the test-set ledger as a
`report` read, kept distinct from the single `decision` opening, so the audit trail
shows plainly that no second selection took place.
"""
from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, precision_recall_fscore_support

from sih_ml.eval.metrics import ranking_report
from sih_ml.final import audit, plots, readiness, robustness
from sih_ml.final import readiness as rd
from sih_ml.models.dataset import load_data
from sih_ml.optimize import runtime as rt
from sih_ml.train import final_test as ft
from sih_ml.utils.common import (REPO_ROOT, get_logger, git_sha, resolve, set_seed)

log = get_logger("stage8")


def _js(x):
    if isinstance(x, np.integer):
        return int(x)
    if isinstance(x, np.floating):
        return float(x)
    if isinstance(x, (np.ndarray, pd.Series)):
        return x.tolist()
    if isinstance(x, pd.DataFrame):
        return x.to_dict("records")
    return str(x)


def main(config_path: str | None = None) -> None:
    t0 = time.time()
    cfg_path = Path(config_path) if config_path else REPO_ROOT / "conf" / "optimize_config.yaml"
    if not cfg_path.is_absolute():
        cfg_path = REPO_ROOT / cfg_path
    data, cfg = load_data(cfg_path)
    set_seed(cfg.seed)

    s7 = resolve(cfg, cfg.paths.reports)
    rdir = REPO_ROOT / "reports" / "stage8"
    rdir.mkdir(parents=True, exist_ok=True)

    # ---------------------------------------------------------------- P0 guard
    prereg = json.loads((s7 / "PREREGISTRATION.json").read_text())
    results7 = json.loads((s7 / "FINAL_TEST_RESULTS.json").read_text())
    ledger_path = REPO_ROOT / cfg.final_test.ledger
    ledger = json.loads(ledger_path.read_text())
    fin = prereg["final_config"]
    h = hashlib.sha256(json.dumps(fin, sort_keys=True, default=str).encode()).hexdigest()[:16]
    if h != prereg["config_sha256_16"]:
        raise SystemExit(f"ABORT: frozen config hash drifted "
                         f"({prereg['config_sha256_16']} -> {h}). Stage 8 must analyse "
                         "the artifact that was pre-registered, not a changed one.")
    decisions = [o for o in ledger["openings"] if o.get("kind", "decision") == "decision"]
    log.info("frozen config %s verified | test-set decision openings: %d",
             h, len(decisions))
    R: dict = {"git_sha": git_sha(), "config_sha256_16": h,
               "decision_openings": len(decisions),
               "selected_model": fin["scorer"], "composite_steps": fin["composite_steps"]}

    # ------------------------------------------------- P1 reproduce the model
    log.info("=== P1: retraining the frozen configuration (reproducibility check) ===")
    model, tr_idx, es_idx = ft.train_final(data, cfg, prereg, cfg.seed)
    te = data.final_test_index()
    raw = model.predict(data.X(te))
    pooled, per = ft.fit_dev_calibrator(cfg, prereg, data, s7)
    from sih_ml.optimize import calibrate as cal_mod
    strata_all = cal_mod.slope_stratum(data, list(cfg.optimize.calibration.slope_bins))
    p = ft.apply_calibrator(raw, strata_all[te], pooled, per)
    y = data.y[te]
    ap = float(average_precision_score(y, p))

    rep_check = rd.reproducibility_check(
        data, cfg, prereg, cfg.seed,
        reference_ap=results7["metrics"]["average_precision"], te_idx=te, observed_ap=ap)
    R["reproducibility"] = rep_check
    log.info("  recorded AP %.12f | recomputed %.12f | bit-identical: %s",
             rep_check["ledger_average_precision"], ap, rep_check["bit_identical"])
    if not rep_check["bit_identical"]:
        log.warning("  RETRAIN DID NOT REPRODUCE THE RECORDED NUMBER — investigate "
                    "before trusting any Stage 8 conclusion")

    thr = float(fin["operating_threshold"])

    # ------------------------------------------------------- P2 final testing
    log.info("=== P2: final testing on the locked split (reporting only) ===")
    m = ranking_report(y, p, ks=tuple(cfg.eval.precision_at_k),
                       lifts=tuple(cfg.eval.top_frac_for_lift))
    yhat = (p >= thr).astype(int)
    pr, rc_, f1, sup = precision_recall_fscore_support(y, yhat, labels=[0, 1],
                                                      zero_division=0)
    classwise = pd.DataFrame({
        "class": ["0 — no disruption", "1 — disruption"],
        "precision": pr, "recall": rc_, "f1": f1, "support": sup,
        "predicted_count": [int((yhat == 0).sum()), int((yhat == 1).sum())],
    })
    classwise.to_csv(rdir / "classwise_metrics.csv", index=False)
    m.update(robustness.steep_metrics(data, te, p))
    R["test_metrics"] = m
    R["classwise"] = classwise.to_dict("records")
    log.info("  steep terrain (slope>=10): AP %.4f lift %.2fx ROC %.4f",
             m.get("steep_AP", float("nan")), m.get("steep_AP_over_base", float("nan")),
             m.get("steep_roc_auc", float("nan")))
    log.info("  AP %.4f  ROC %.4f | class1 P=%.3f R=%.3f F1=%.3f",
             m["average_precision"], m["roc_auc"], pr[1], rc_[1], f1[1])

    cm = plots.confusion_matrix_plot(y, p, thr, rdir / "confusion_matrix.png")
    plots.pr_roc_plot(y, p, rdir / "pr_curve.png", rdir / "roc_curve.png")
    plots.reliability_plot(y, p, rdir / "reliability.png")
    plots.score_distribution_plot(y, p, thr, rdir / "score_distribution.png")
    R["confusion"] = cm

    # ------------------------------------------------- P4 generalization first
    # (run before robustness so the leakage finding is available to interpret it)
    log.info("=== P4: generalization, leakage and bias audits ===")
    lk = audit.leakage_audit(data)
    R["leakage_audit"] = lk
    log.info("  exact row overlap %d | shared positive events %d | shared segments %d/%d",
             lk["exact_row_overlap"], len(lk["shared_positive_event_ids"]),
             lk["n_shared_segments"], lk["n_test_segments"])
    for a in lk["shared_segment_detail"]:
        log.warning("  SHARED SEGMENT %s: %d train rows (%d positive, %d events) vs "
                    "%d test rows (%d positive, tiers %s)", a["segment_id"],
                    a["train_rows"], a["train_positive_rows"], a["train_distinct_events"],
                    a["test_rows"], a["test_positive_rows"], a["test_tiers"])

    gen = audit.generalization_table(data, model, tr_idx, es_idx,
                                     s7 / "oof_selected.parquet", te, p)
    gen.to_csv(rdir / "generalization.csv", index=False)
    R["generalization"] = gen.to_dict("records")
    for _, r in gen.iterrows():
        log.info("  %-22s n=%6d base=%.4f AP=%.4f  lift=%.2fx", r["split"], r["n"],
                 r["base_rate"], r["AP"], r["AP_over_base"])

    # Why the test number looks the way it does — composition, not just geography.
    lss = audit.label_source_shift(data)
    lss.to_csv(rdir / "label_source_shift.csv", index=False)
    R["label_source_shift"] = lss.to_dict("records")
    rsc = audit.rainfall_signal_check(data)
    rsc.to_csv(rdir / "rainfall_signal.csv", index=False)
    R["rainfall_signal"] = rsc.to_dict("records")
    log.info("  rainfall alone (rain_7d) ROC: dev %.4f -> test %.4f",
             float(rsc.loc[rsc.feature == "rain_7d_mm", "dev_roc"].iloc[0]),
             float(rsc.loc[rsc.feature == "rain_7d_mm", "test_roc"].iloc[0]))
    for _, r in lss[lss.split == "locked test"].iterrows():
        log.info("    test positives %-24s %5d (%.0f%%)  mean rain_7d %.1f mm",
                 r["label_source"], r["n_positives"], 100 * r["share_of_positives"],
                 r["mean_rain_7d_mm"])

    bias = audit.bias_analysis(data, te, p)
    bias.to_csv(rdir / "group_performance.csv", index=False)
    R["bias_analysis"] = bias.to_dict("records")
    plots.group_performance_plot(bias, rdir / "group_performance.png")
    plots.generalization_plot(gen, rdir / "generalization.png")

    # ---------------------------------------------------------- P3 robustness
    log.info("=== P3: robustness of the frozen model ===")
    gold = (data.panel["label_tier"].to_numpy()[te] == "gold")
    cf = robustness.counterfactual_rainfall(data, model, te, highlight_mask=gold)
    R["counterfactual_rainfall"] = cf
    log.info("  zero-rain counterfactual: AP %.4f -> %.4f | positives retain %.1f%% "
             "of their score", cf["AP_observed"], cf["AP_zero_rain"],
             100 * cf["positives_median_retained_frac"])
    if "highlight" in cf:
        log.info("  GOLD rows retain %s of score with rain removed",
                 [f"{x:.1%}" for x in cf["highlight"]["retained_frac"]])

    abl = robustness.feature_group_ablation(data, model, te)
    abl.to_csv(rdir / "feature_ablation.csv", index=False)
    R["feature_ablation"] = abl.to_dict("records")
    for _, r in abl.iterrows():
        log.info("  ablate %-20s AP %.4f (%+.4f, %.0f%% of baseline)",
                 r["group"], r["AP"], r["delta"], r["pct_of_baseline"])

    pert = robustness.perturbation_sweep(data, model, te, seed=cfg.seed)
    pert.to_csv(rdir / "perturbation_sweep.csv", index=False)
    R["perturbation_sweep"] = pert.to_dict("records")

    ec = robustness.edge_cases(data, model, te, thr)
    ec.to_csv(rdir / "edge_cases.csv", index=False)
    R["edge_cases"] = ec.to_dict("records")

    uc = robustness.unseen_category_probe(data, model, te)
    uc.to_csv(rdir / "unseen_categories.csv", index=False)
    R["unseen_categories"] = uc.to_dict("records")

    mono_cols = list(cfg.lgbm.monotone_rainfall_features)
    mono = pd.concat([
        robustness.monotonicity_check(data, model, te, mono_cols, seed=cfg.seed,
                                      update_exceed_flags=True),
        robustness.monotonicity_check(data, model, te, mono_cols, seed=cfg.seed,
                                      update_exceed_flags=False),
    ], ignore_index=True)
    mono.to_csv(rdir / "monotonicity.csv", index=False)
    R["monotonicity"] = mono.to_dict("records")
    for flag in (True, False):
        sub = mono[mono.exceed_flags_updated == flag]
        log.info("  monotonicity (id_exceed flags %s): violations %s",
                 "recomputed" if flag else "held fixed", list(sub.violations))

    rcv = robustness.risk_coverage(y, p)
    rcv.to_csv(rdir / "risk_coverage.csv", index=False)
    R["risk_coverage"] = rcv.to_dict("records")

    fails = robustness.failure_cases(data, te, p, thr)
    fails["worst_false_negatives"].to_csv(rdir / "worst_false_negatives.csv", index=False)
    fails["worst_false_positives"].to_csv(rdir / "worst_false_positives.csv", index=False)
    R["failure_counts"] = {"n_fn": fails["n_fn"], "n_fp": fails["n_fp"]}
    plots.robustness_plot(pert, abl, rcv, rdir / "robustness.png")

    # ---------------------------------------------------- P5 production ready
    log.info("=== P5: production readiness ===")
    runtime = rt.profile(model, data.X(), cfg.optimize.runtime)
    R["runtime"] = runtime
    scal = rd.scalability(model, data.X(), segments=int(cfg.optimize.runtime.deployment_segments))
    scal.to_csv(rdir / "scalability.csv", index=False)
    R["scalability"] = scal.to_dict("records")

    cal_t = pd.DataFrame(results7["calibration_on_test"])
    w = cal_t[cal_t.stratum != "all"].pred_over_obs
    worst_ratio = float(np.max(np.maximum(w, 1 / w))) if len(w) else float("nan")
    rb = {
        "worst_test_stratum_ratio": worst_ratio,
        "pct_at_sigma_025": float(pert.loc[pert.sigma == 0.25, "pct_of_clean"].iloc[0])
        if (pert.sigma == 0.25).any() else float("nan"),
        "retained_frac": cf["positives_median_retained_frac"],
        "bit_identical": rep_check["bit_identical"],
    }
    gates = rd.deployment_gates({**m, **{"recall": rc_[1]}}, rb, runtime)
    gates.to_csv(rdir / "deployment_gates.csv", index=False)
    R["deployment_gates"] = gates.to_dict("records")
    n_pass = int(gates["pass"].sum())
    log.info("  deployment gates: %d/%d pass", n_pass, len(gates))
    for _, g in gates[~gates["pass"]].iterrows():
        log.warning("  GATE FAILED — %s: %s (threshold %s)", g["gate"], g["measured"],
                    g["threshold"])
    R["optimization_advice"] = rd.optimization_advice(runtime)

    # ------------------------------------------------------------ P6 record
    ledger["openings"].append({
        "utc": pd.Timestamp.utcnow().isoformat(), "kind": "report",
        "config_sha256_16": h, "git_sha": R["git_sha"],
        "average_precision": ap, "n_rows": int(len(te)),
        "note": "Stage 8 reporting/robustness read — no selection, config unchanged",
    })
    ledger_path.write_text(json.dumps(ledger, indent=2))

    (rdir / "final_validation.json").write_text(json.dumps(R, indent=2, default=_js))
    _write_report(R, rdir, cfg, prereg, classwise, gen, bias, abl, pert, ec, mono,
                  rcv, gates, scal, lk, cf, lss, rsc)
    _write_model_card(R, rdir, prereg, model, tr_idx, es_idx)
    log.info("Stage 8 done in %.1fs -> %s", time.time() - t0, rdir)


# --------------------------------------------------------------------------- #
def _write_report(R, rdir: Path, cfg, prereg, classwise, gen, bias, abl, pert, ec,
                  mono, rcv, gates, scal, lk, cf, lss, rsc) -> None:
    m = R["test_metrics"]
    L = [
        "# Stage 8 — Final Model Validation", "",
        f"Frozen config `{R['config_sha256_16']}` · git `{R['git_sha']}` · "
        f"test-set **decision openings: {R['decision_openings']}**", "",
        "Stage 8 selects nothing. The locked split was opened once, under "
        "pre-registration, at the end of Stage 7; everything here is descriptive "
        "analysis of that frozen artifact. The config hash is verified on entry and a "
        "mismatch aborts the run.", "",
        "## 1. Reproducibility", "",
        f"- recorded test AP: `{R['reproducibility']['ledger_average_precision']:.12f}`",
        f"- retrained from config + seed: `{R['reproducibility']['recomputed_average_precision']:.12f}`",
        f"- **bit-identical: {R['reproducibility']['bit_identical']}**", "",
        f"> {R['reproducibility']['caveat']}", "",
        "## 2. Final test results", "",
        "| metric | value |", "|--|--|",
        f"| average precision | **{m['average_precision']:.4f}** |",
        f"| ROC-AUC | {m['roc_auc']:.4f} |",
        f"| Brier | {m['brier']:.4f} |", f"| ECE | {m['ece']:.4f} |",
        f"| base rate | {m['base_rate']:.4f} |",
        f"| **AP / base rate** | **{m['average_precision'] / m['base_rate']:.2f}×** |",
        "", "### Class-wise", "",
        "| class | precision | recall | F1 | support | predicted |", "|--|--|--|--|--|--|",
    ]
    for r in classwise.to_dict("records"):
        L.append(f"| {r['class']} | {r['precision']:.3f} | {r['recall']:.3f} | "
                 f"{r['f1']:.3f} | {r['support']:,} | {r['predicted_count']:,} |")
    c = R["confusion"]
    L += ["", f"Confusion @ threshold {prereg['final_config']['operating_threshold']:.4f}: "
          f"TP {c['tp']:,} · FP {c['fp']:,} · FN {c['fn']:,} · TN {c['tn']:,}", "",
          "Plots: `confusion_matrix.png` · `pr_curve.png` · `roc_curve.png` · "
          "`reliability.png` · `score_distribution.png`", "",
          "## 3. Generalization", "",
          "| split | n | base rate | AP | lift over chance | ROC-AUC |", "|--|--|--|--|--|--|"]
    for r in gen.to_dict("records"):
        L.append(f"| {r['split']} | {r['n']:,} | {r['base_rate']:.4f} | {r['AP']:.4f} | "
                 f"**{r['AP_over_base']:.2f}×** | {r['roc_auc']:.4f} |")
    L += ["", "Lift over chance is the comparable column — these splits have very "
          "different base rates and AP scales with the base rate.", "",
          "## 4. Leakage audit", "",
          f"- exact (segment, date) overlap dev↔test: **{lk['exact_row_overlap']}**",
          f"- shared positive `event_id`s: **{len(lk['shared_positive_event_ids'])}**",
          f"- shared `segment_id`s: **{lk['n_shared_segments']} of {lk['n_test_segments']}** test segments",
          f"- shared spatial blocks: {lk['n_shared_blocks']} of {lk['n_test_blocks']}", ""]
    for a in lk["shared_segment_detail"]:
        L += [f"> **`{a['segment_id']}`** — {a['train_rows']} training rows "
              f"({a['train_positive_rows']} positive, across {a['train_distinct_events']} "
              f"distinct events) and {a['test_rows']} test rows "
              f"({a['test_positive_rows']} positive, tiers {a['test_tiers']}). "
              f"Nearest training row is {a['min_days_between']} days away.", ""]
    L += ["## 4b. Why the test number looks the way it does", "",
          "`final_test` was defined in Stage 2 as a set of spatial blocks **plus every "
          "gold label**, with no constraint on label-source mix. The split therefore "
          "differs from dev in *what kind of positive it contains*, not only in where "
          "it is:", "",
          "| split | label source | positives | share | mean rain 7d |", "|--|--|--|--|--|"]
    for r in lss.to_dict("records"):
        L.append(f"| {r['split']} | {r['label_source']} | {r['n_positives']:,} | "
                 f"{r['share_of_positives']:.0%} | {r['mean_rain_7d_mm']:.1f} mm |")
    L += ["", "### Rainfall as a standalone ranking score (no model)", "",
          "| feature | dev ROC | test ROC | dev pos/neg mm | test pos/neg mm |",
          "|--|--|--|--|--|"]
    for r in rsc.to_dict("records"):
        L.append(f"| {r['feature']} | {r['dev_roc']:.4f} | **{r['test_roc']:.4f}** | "
                 f"{r['dev_mean_pos']:.1f} / {r['dev_mean_neg']:.1f} | "
                 f"{r['test_mean_pos']:.1f} / {r['test_mean_neg']:.1f} |")
    L += ["", "**On the locked test split, rainfall carries no usable signal and the "
          "longer windows are inverted** — disrupted days had *less* rain than "
          "undisrupted ones. On dev the same features sit at ROC 0.59–0.65. This is "
          "the single most important line in the report: the input the entire problem "
          "framing rests on does not separate the classes on held-out ground.", "",
          "## 5. Robustness", "",
          "### 5.1 Counterfactual: delete the rainfall", "",
          f"- AP with observed rainfall: **{cf['AP_observed']:.4f}**",
          f"- AP with every rainfall input zeroed: **{cf['AP_zero_rain']:.4f}**",
          f"- positives retain a median **{cf['positives_median_retained_frac']:.1%}** "
          "of their score with the rain removed", ""]
    if "highlight" in cf:
        hl = cf["highlight"]
        L += [f"For the {hl['n']} verified (gold) rows specifically:", "",
              "| | observed | zero rainfall |", "|--|--|--|"]
        for i in range(hl["n"]):
            L.append(f"| score | {hl['score_observed'][i]:.4f} | {hl['score_zero_rain'][i]:.4f} |")
        L.append("| percentile | " + ", ".join(f"{x:.1%}" for x in hl["percentile_observed"])
                 + " | " + ", ".join(f"{x:.1%}" for x in hl["percentile_zero_rain"]) + " |")
        L.append("")
    L += ["### 5.2 Feature-group ablation", "",
          "| group blanked | AP | Δ | % of baseline |", "|--|--|--|--|"]
    for r in abl.to_dict("records"):
        L.append(f"| {r['group']} | {r['AP']:.4f} | {r['delta']:+.4f} | "
                 f"{r['pct_of_baseline']:.0f}% |")
    L += ["", "### 5.3 Sensitivity to rainfall error (inference-time noise)", "",
          "| σ | AP | % of clean | ROC-AUC |", "|--|--|--|--|"]
    for r in pert.to_dict("records"):
        L.append(f"| {r['sigma']:.2f} | {r['AP']:.4f} | {r['pct_of_clean']:.1f}% | "
                 f"{r['roc_auc']:.4f} |")
    L += ["", "Deployment scores a rainfall *forecast*, not an observation, so this "
          "curve is the realistic operating condition rather than a stress test.", "",
          "### 5.4 Edge cases", "",
          "| case | n | base rate | AP | lift | recall | precision |", "|--|--|--|--|--|--|--|"]
    for r in ec.to_dict("records"):
        L.append(f"| {r['case']} | {r['n']:,} | {r['base_rate']:.4f} | {r['AP']:.4f} | "
                 f"{r['AP_over_base']:.2f}× | {r['recall']:.3f} | {r['precision']:.3f} |")
    L += ["", "### 5.5 Monotonicity of the rainfall constraints", "",
          "| rain × | violations | rate | mean score |", "|--|--|--|--|"]
    for r in mono.to_dict("records"):
        L.append(f"| {r['rain_multiplier']:.2f} | {r['violations']} | "
                 f"{r['violation_rate']:.4f} | {r['mean_score']:.4f} |")
    L += ["", "### 5.6 Selective prediction (alert on the top X%)", "",
          "| coverage | alerts | precision | recall | lift |", "|--|--|--|--|--|"]
    for r in rcv.to_dict("records"):
        L.append(f"| {r['coverage']:.0%} | {r['n_alerts']:,} | {r['precision']:.3f} | "
                 f"{r['recall']:.3f} | {r['lift']:.2f}× |")
    L += ["", "## 6. Performance by group", "",
          "| group | n | base rate | AP | lift | ROC-AUC |", "|--|--|--|--|--|--|"]
    for r in bias.to_dict("records"):
        L.append(f"| {r['group_type']}: {r['group']} | {r['n']:,} | {r['base_rate']:.4f} | "
                 f"{r['AP']:.4f} | {r['AP_over_base']:.2f}× | {r['roc_auc']:.4f} |")
    L += ["", "## 7. Production readiness", "",
          f"- model size **{R['runtime']['model_kb']} KB** "
          f"({R['runtime']['n_trees']} trees, {R['runtime']['total_leaves']} leaves)",
          f"- **{R['runtime']['per_row_us']} µs/row**, "
          f"{R['runtime']['rows_per_sec']:,} rows/s single-core",
          f"- full corridor ({R['runtime']['deployment_segments']:,} segments): "
          f"**{R['runtime']['full_corridor_sec']} s**",
          f"- peak prediction memory {R['runtime']['predict_peak_mb']} MB", "",
          "### Scalability", "",
          "| rows | median s | µs/row | rows/s | projected corridor |", "|--|--|--|--|--|"]
    for r in scal.to_dict("records"):
        L.append(f"| {r['n_rows']:,} | {r['median_sec']:.4f} | {r['per_row_us']} | "
                 f"{r['rows_per_sec']:,} | {r['projected_corridor_sec']} s |")
    n_pass = int(gates["pass"].sum())
    L += ["", f"### Deployment gates — **{n_pass} of {len(gates)} pass**", "",
          "| gate | threshold | measured | pass | why it exists |", "|--|--|--|--|--|"]
    for r in gates.to_dict("records"):
        L.append(f"| {r['gate']} | {r['threshold']} | **{r['measured']}** | "
                 f"{'PASS' if r['pass'] else '**FAIL**'} | {r['why']} |")
    L += ["", "### Inference optimization", "",
          "| technique | recommended | reason | revisit if |", "|--|--|--|--|"]
    for o in R["optimization_advice"]:
        L.append(f"| {o['technique']} | {'YES' if o['recommended'] else 'no'} | "
                 f"{o['reason']} | {o['revisit_if']} |")
    L += ["", "## 8. Artifacts", "",
          "`models/final_v1/` — booster, calibrators, model card · "
          "`reports/stage8/` — this report, `final_validation.json`, per-probe CSVs, plots · "
          "`reports/stage7/PREREGISTRATION.json` + `TEST_SET_LEDGER.json` — the audit trail."]
    (rdir / "FINAL_VALIDATION_REPORT.md").write_text("\n".join(L))


def _write_model_card(R, rdir: Path, prereg, model, tr_idx, es_idx) -> None:
    gates = pd.DataFrame(R["deployment_gates"])
    card = {
        "model_name": "sih-ml corridor disruption — final_v1",
        "version": "final_v1",
        "config_sha256_16": R["config_sha256_16"],
        "git_sha": R["git_sha"],
        "task": ("binary classification: will this road segment be disrupted by a "
                 "rainfall-triggered landslide/flood on this day"),
        "architecture": "LightGBM GBDT (4 leaves/tree) + per-slope isotonic calibration",
        "training_data": {"rows": int(len(tr_idx)), "earlystop_rows": int(len(es_idx)),
                          "trees": int(model.best_iteration_)},
        "training_recipe": R["composite_steps"],
        "test_metrics": R["test_metrics"],
        "generalization": R["generalization"],
        "deployment_gates_passed": f"{int(gates['pass'].sum())}/{len(gates)}",
        "failed_gates": gates.loc[~gates["pass"], "gate"].tolist(),
        "runtime": R["runtime"],
        "reproducibility": R["reproducibility"],
        "intended_use": ("daily batch scoring of corridor road segments; output feeds "
                         "the risk-aware routing edge penalty W = dist*(1 + lambda*P)"),
        "out_of_scope": [
            "per-incident timing or severity prediction",
            "non-rainfall-triggered disruption (earthquake, construction, accident)",
            "absolute risk on terrain outside the training corridor",
            "any use where a missed closure endangers life without human review",
        ],
        "known_limitations": [
            "All training positives are WEAK labels; the only 3 verified closures are "
            "in the test split and sit on the one segment that also appears in "
            "training (as a positive, 15 times) — their top-1% ranking survives "
            "deleting rainfall entirely, so it reflects segment identity, not skill.",
            "On the locked test split rainfall carries NO usable signal and the longer "
            "windows are inverted (7d ROC 0.46); ablating rainfall RAISES AP by 0.112. "
            "Headline skill there comes from seasonality, hydrology and road class.",
            "Near-chance discrimination on steep terrain (ROC 0.624, lift 1.44x) — "
            "which is where routing decisions actually are.",
            "Per-slope calibration does not transfer across regions (worst stratum "
            "1.32x within dev -> 2.20x on unseen ground). Do not drive the routing "
            "penalty with absolute probabilities on new terrain.",
            "id_exceed_1d/3d/7d are derived from monotone-constrained features but are "
            "themselves unconstrained: more rain can lower the score (77 violations).",
            "CHIRPS ~25 km daily rainfall cannot resolve valley-scale cloudbursts.",
            "The FN:FP = 20 cost ratio behind the threshold is an unvalidated "
            "placeholder; FN:FP = 10 measured strictly better.",
            "One test region, 6 spatial blocks, one of them 77% positive — a single "
            "split cannot separate selection bias from distribution shift.",
        ],
        "deployment_recommendation": (
            "NOT ready for autonomous deployment (3 of 11 gates fail, all concerning "
            "steep terrain and calibration transfer). Suitable for a decision-support "
            "pilot: ship the RANKING not the probability, operate in selective mode on "
            "the top 1-2% of segment-days (precision 0.72-0.81), and keep a human in "
            "the loop on every alert."
        ),
    }
    (rdir / "model_card.json").write_text(json.dumps(card, indent=2, default=_js))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
