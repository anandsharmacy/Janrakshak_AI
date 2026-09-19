"""Stage 7 orchestrator — accuracy optimization.

    python -m sih_ml.train.run_optimize [conf/optimize_config.yaml]

Phases:
  P0  the bar            — Stage 6's selected config, 5 paired spatial folds
  P1  data optimization  — dedup, label pruning, weighting, hard/easy sample mining
  P2  augmentation       — rainfall jitter (strength sweep), naive noise, SMOTE
  P3  loss & model       — focal loss, terrain-stratified model
  P4  composite          — everything that won, combined and re-measured
  P5  ensemble           — LightGBM + logistic + rule, LOFO blend weights
  P6  prediction         — cross-fitted calibration, thresholds, PR trade-off
  P7  cost               — latency / memory / model size
  P8  priority + freeze  — ranked plan, final config, PREREGISTRATION.json

`final_test` is NOT opened here. Freezing the config and pre-registering the metric
list is the last thing this script does; `scripts/open_final_test.py` is the only
code that reads the locked split, and it refuses to run without that file.
"""
from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.models.dataset import load_data
from sih_ml.optimize import augment, calibrate, composite, data_opt, ensemble
from sih_ml.optimize import runtime as rt
from sih_ml.optimize import stratified, threshold
from sih_ml.optimize.harness import Arm, paired_delta, run_arm, verdict
from sih_ml.utils.common import (REPO_ROOT, Config, get_logger, git_sha, resolve,
                                 set_seed, write_manifest)

log = get_logger("stage7")


# --------------------------------------------------------------------------- #
# Arm catalogue
# --------------------------------------------------------------------------- #
def build_arms(cfg: Config) -> list[Arm]:
    o = cfg.optimize
    arms: list[Arm] = []

    # ---- P1 data -----------------------------------------------------------
    d = o.data
    if d.get("dedup", True):
        arms.append(Arm("data/dedup", "data", data_opt.make_dedup_arm(),
                        note="drop exact duplicate feature vectors (Stage 5 §8: 430 rows, 0 conflicts)"))
    for f in d.get("confidence_floors", []):
        arms.append(Arm(f"data/conf_floor_{f}", "data",
                        data_opt.make_confidence_floor_arm(float(f)),
                        note=f"drop positives with label_confidence < {f} (Stage 5 §4)"))
    for s in d.get("weight_schemes", []):
        arms.append(Arm(f"data/weight_{s}", "data", data_opt.make_weight_scheme_arm(s),
                        note=f"reshape Stage 2 confidence weights: {s}"))
    m = d.get("mining", {})
    if m.get("enabled", False):
        ni = int(m.get("inner_folds", 2))
        for a in m.get("hard_negative_alpha", []):
            arms.append(Arm(f"data/hard_neg_a{a}", "data",
                            data_opt.make_hard_negative_arm(cfg, float(a), ni),
                            note=f"upweight hardest negatives, alpha={a} (inner-CV mined)"))
        for fr in m.get("easy_negative_drop", []):
            arms.append(Arm(f"data/easy_neg_drop_{fr}", "data",
                            data_opt.make_easy_negative_drop_arm(cfg, float(fr), ni),
                            note=f"drop {fr:.0%} easiest negatives (inner-CV mined)"))
        for a in m.get("hard_positive_alpha", []):
            arms.append(Arm(f"data/hard_pos_a{a}", "data",
                            data_opt.make_hard_positive_arm(cfg, float(a), ni),
                            note=f"upweight hardest positives, alpha={a} (inner-CV mined)"))

    # ---- P2 augmentation ---------------------------------------------------
    a = o.augment
    for s in a.get("rainfall_jitter_sigma", []):
        arms.append(Arm(f"aug/rain_jitter_s{s}", "augment",
                        augment.make_rainfall_jitter_arm(float(s)),
                        note=f"multiplicative lognormal rainfall jitter sigma={s}, ID ratios+flags kept consistent"))
    best_sigma = (list(a.get("rainfall_jitter_sigma", [0.25])) or [0.25])[len(
        list(a.get("rainfall_jitter_sigma", [0.25]))) // 2]
    arms.append(Arm(f"aug/rain_jitter_append_s{best_sigma}", "augment",
                    augment.make_jitter_plus_original_arm(float(best_sigma)),
                    note="original rows + a jittered copy (2x training rows)"))
    for s in a.get("gaussian_all_sigma", []):
        arms.append(Arm(f"aug/gaussian_all_s{s}", "augment",
                        augment.make_gaussian_all_arm(float(s)),
                        note="independent noise on every numeric column, terrain included"))
    gs = a.get("gaussian_decompose_sigma")
    if gs:
        num = None  # resolved lazily against data.features inside the arm
        arms.append(Arm(f"aug/gaussian_terrain_only_s{gs}", "augment",
                        augment.make_gaussian_subset_arm(float(gs), augment.TERRAIN_COLS,
                                                         "terrain_only"),
                        note="noise on STATIC terrain/soil columns only — tests the anti-fingerprint mechanism"))
        arms.append(Arm(f"aug/gaussian_rain_only_s{gs}", "augment",
                        augment.make_gaussian_subset_arm(
                            float(gs), augment.RAIN_COLS + augment.ID_RATIO_COLS,
                            "rain_only"),
                        note="independent (physics-INconsistent) noise on rainfall columns only"))
        del num
    for k in a.get("smote_k", []):
        for fr in a.get("smote_frac", []):
            arms.append(Arm(f"aug/smote_k{k}_f{fr}", "augment",
                            augment.make_smote_arm(int(k), float(fr)),
                            note=f"within-spatial-block positive interpolation, +{fr:.0%} positives"))

    # ---- P3 loss -----------------------------------------------------------
    lo = o.loss
    for g in lo.get("focal_gamma", []):
        arms.append(Arm(f"loss/focal_g{g}", "loss", None, objective="focal",
                        objective_kwargs={"gamma": float(g),
                                          "alpha": float(lo.get("focal_alpha", 0.25))},
                        note=f"binary focal loss gamma={g} (targets Stage 5 §3 hard positives)"))
    return arms


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main(config_path: str | None = None) -> None:
    t0 = time.time()
    cfg_path = Path(config_path) if config_path else REPO_ROOT / "conf" / "optimize_config.yaml"
    if not cfg_path.is_absolute():
        cfg_path = REPO_ROOT / cfg_path
    data, cfg = load_data(cfg_path)
    set_seed(cfg.seed)

    o = cfg.optimize
    folds = list(o.eval_folds)
    rdir = resolve(cfg, cfg.paths.reports)
    rdir.mkdir(parents=True, exist_ok=True)
    R: dict = {"git_sha": git_sha(), "eval_folds": folds,
               "protocol": "paired per-fold deltas vs the Stage 6 bar; sign-flip permutation test"}

    # ---------------------------------------------------------------- P0 bar
    log.info("=== P0: the bar — Stage 6 selected configuration ===")
    bar = run_arm(data, cfg, Arm("bar/stage6_tuned", "baseline", None,
                                 note="Stage 6 E2 tuned config"), folds, cfg.seed)
    log.info("bar: mean AP %.4f ± %.4f  (%s)", bar["mean_AP"], bar["std_AP"],
             {f: round(v, 3) for f, v in bar["fold_ap"].items()})
    R["bar"] = _strip(bar)

    # ------------------------------------------------- P1-P3 individual arms
    arms = build_arms(cfg)
    log.info("=== P1-P3: %d individual arms ===", len(arms))
    results, rows = {"bar/stage6_tuned": bar}, []
    for i, arm in enumerate(arms, 1):
        res = run_arm(data, cfg, arm, folds, cfg.seed)
        dl = paired_delta(res, bar, folds, int(o.n_permutations), cfg.seed)
        v = verdict(dl, int(o.min_folds_improved), float(o.alpha))
        results[arm.name] = res
        rows.append({"arm": arm.name, "group": arm.group, "note": arm.note,
                     "mean_AP": res["mean_AP"], "std_AP": res["std_AP"],
                     "mean_delta": dl["mean_delta"], "p_value": dl["p_value"],
                     "folds_improved": dl["folds_improved"], "verdict": v,
                     "mean_train_rows": res["mean_train_rows"],
                     "mean_fit_sec": res["mean_fit_sec"],
                     "mean_best_iter": res["mean_best_iter"],
                     "deltas": dl["deltas"]})
        log.info("[%2d/%2d] %-32s AP %.4f  delta %+.4f  p=%.3f  %d/%d folds  -> %s",
                 i, len(arms), arm.name, res["mean_AP"], dl["mean_delta"],
                 dl["p_value"], dl["folds_improved"], dl["n_folds"], v)

    df = pd.DataFrame(rows).sort_values("mean_delta", ascending=False)
    df.to_csv(rdir / "arm_results.csv", index=False)
    R["arms"] = rows

    # --------------------------------------------------- P3c confirmation
    # See conf/optimize_config.yaml `confirm`: with 5 folds no arm can clear a
    # Bonferroni-corrected alpha, so the leading arms are REPLICATED under fresh
    # seeds instead. A fresh seed redraws the event-grouped early-stopping split and
    # the bagging/feature-sampling RNG, so an effect that survives is not an artifact
    # of one particular inner split.
    conf = o.get("confirm", {})
    if conf.get("enabled", False):
        # Union of "largest measured delta" and "cleared the decision rule" — these
        # are different sets, and the second is the one that gets shipped. Ranking
        # by delta alone would skip replicating the arms actually being selected.
        top = list(dict.fromkeys(
            list(df.head(int(conf.get("top_k", 4))).arm)
            + list(df[df.verdict == "improvement"].arm)))
        seeds = list(conf.get("seeds", []))
        log.info("=== P3c: replicating %d leading arms across %d extra seeds ===",
                 len(top), len(seeds))
        by_name = {a.name: a for a in arms}
        rep = []
        for s in seeds:
            b_s = run_arm(data, cfg, Arm("bar", "baseline", None), folds, s)
            for nm in top:
                r_s = run_arm(data, cfg, by_name[nm], folds, s)
                d_s = paired_delta(r_s, b_s, folds, int(o.n_permutations), s)
                rep.append({"seed": s, "arm": nm, "bar_AP": b_s["mean_AP"],
                            "arm_AP": r_s["mean_AP"], "mean_delta": d_s["mean_delta"],
                            "folds_improved": d_s["folds_improved"],
                            "deltas": d_s["deltas"]})
                log.info("  seed %-5s %-30s delta %+.4f  (%d/5 folds)",
                         s, nm, d_s["mean_delta"], d_s["folds_improved"])
        rdf = pd.DataFrame(rep)
        rdf.to_csv(rdir / "confirmation_seeds.csv", index=False)
        summary = []
        for nm in top:
            sub = rdf[rdf.arm == nm]
            orig = df[df.arm == nm].iloc[0]
            all_d = [x for row in sub.deltas for x in row] + list(orig.deltas)
            summary.append({
                "arm": nm, "seed0_delta": float(orig.mean_delta),
                "replicate_mean_delta": float(sub.mean_delta.mean()),
                "all_seeds_mean_delta": float(np.mean(all_d)),
                "fold_seed_pairs_improved": int(np.sum(np.array(all_d) > 0)),
                "fold_seed_pairs": len(all_d),
                "replicated": bool(sub.mean_delta.gt(0).all()),
            })
        R["confirmation"] = summary
        for s in summary:
            log.info("  %-30s seed0 %+.4f | replicates %+.4f | %d/%d fold-seed pairs up",
                     s["arm"], s["seed0_delta"], s["replicate_mean_delta"],
                     s["fold_seed_pairs_improved"], s["fold_seed_pairs"])

    # -------------------------------------------------------- P4 composite
    log.info("=== P4: composites ===")
    comps = _build_composites(cfg, df)
    R["composites"] = []
    comp_arm = None
    for arm_c, spec in comps:
        cres = run_arm(data, cfg, arm_c, folds, cfg.seed)
        cdl = paired_delta(cres, bar, folds, int(o.n_permutations), cfg.seed)
        cv_ = verdict(cdl, int(o.min_folds_improved), float(o.alpha))
        results[arm_c.name] = cres
        R["composites"].append({**_strip(cres), "spec": spec, "delta": cdl,
                                "verdict": cv_})
        log.info("%-26s AP %.4f  delta %+.4f  p=%.3f -> %s  [%s]",
                 arm_c.name, cres["mean_AP"], cdl["mean_delta"], cdl["p_value"], cv_,
                 ", ".join(spec))
        if comp_arm is None or cres["mean_AP"] > results[comp_arm.name]["mean_AP"]:
            comp_arm = arm_c
    if not comps:
        log.info("no arm produced a positive delta — composites skipped")
    # NOTE: `composite_spec` is deliberately NOT set here. Which composite gets
    # frozen must follow the SELECTED scorer (decided in P6 by the decision rule),
    # not whichever posts the highest AP — picking by AP here silently froze the
    # steps of `composite/all_positive` (p=0.499) into a config labelled
    # `composite/passed`, i.e. it would have trained a different model than the one
    # the report claims was selected. Set in P6 once selection has happened.

    # --------------------------------------------------------- P5 ensemble
    log.info("=== P5: ensemble (LOFO blend weights) ===")
    best_single = _best_candidate(results, R, bar)
    members = {"lgbm": best_single["oof"]}
    if cfg.optimize.ensemble.get("enabled", True):
        members["logistic"] = ensemble.logistic_oof(data, cfg, folds, cfg.seed)
        members["rain_x_terrain"] = ensemble.rule_scores(data, "rain_x_terrain")
        ens = ensemble.blend_oof(members, data, bar["fold_of"], folds,
                                 float(cfg.optimize.ensemble.weight_grid_step))
        edl = paired_delta(ens, bar, folds, int(o.n_permutations), cfg.seed)
        ev = verdict(edl, int(o.min_folds_improved), float(o.alpha))
        solo = ensemble.member_solo_ap(members, data, bar["fold_of"], folds)
        R["ensemble"] = {k: v for k, v in ens.items() if k != "oof"}
        R["ensemble"]["delta_vs_bar"] = edl
        R["ensemble"]["verdict"] = ev
        R["ensemble"]["member_solo"] = solo
        log.info("ensemble: AP %.4f  delta %+.4f  p=%.3f -> %s | solo: %s",
                 ens["mean_AP"], edl["mean_delta"], edl["p_value"], ev,
                 {k: round(v["mean_AP"], 3) for k, v in solo.items()})
        results["ensemble"] = {**ens, "name": "ensemble", "group": "ensemble",
                               "fold_of": bar["fold_of"], "model": bar["model"]}

    # ------------------------------------------------- P3b stratified model
    if cfg.optimize.stratified_model.get("enabled", True):
        log.info("=== P3b: terrain-stratified model (Stage 5 §1) ===")
        sd = float(cfg.optimize.stratified_model.slope_split_deg)
        st = stratified.run_stratified(data, cfg, folds, sd, cfg.seed)
        gl = stratified.restrict_to_steep(data, bar["oof"], bar["fold_of"], folds, sd)
        sdl = paired_delta(st, gl, folds, int(o.n_permutations), cfg.seed)
        R["stratified"] = {
            "slope_split_deg": sd, "n_steep_rows": st["n_steep_rows"],
            "steep_only_model": {"mean_AP": st["mean_AP"], "std_AP": st["std_AP"],
                                 "fold_ap": st["fold_ap"],
                                 "mean_train_rows": st["mean_train_rows"]},
            "global_model_on_same_rows": gl,
            "delta": sdl,
            "verdict": verdict(sdl, int(o.min_folds_improved), float(o.alpha)),
        }
        log.info("steep-only %.4f vs global-on-steep %.4f  delta %+.4f  p=%.3f -> %s",
                 st["mean_AP"], gl["mean_AP"], sdl["mean_delta"], sdl["p_value"],
                 R["stratified"]["verdict"])

    # ----------------------------------------- P6 calibration + thresholds
    log.info("=== P6: prediction optimization ===")
    final_oof, final_name = _final_scores(results, R, bar)
    R["selected_scorer"] = final_name
    # Freeze the steps of the composite that was actually SELECTED (or none, if the
    # incumbent held). This is the only place `composite_spec` is set.
    sel_comp = next((c for c in R.get("composites", []) if c["name"] == final_name), None)
    R["composite"] = sel_comp
    R["composite_spec"] = sel_comp["spec"] if sel_comp else []
    log.info("selected scorer: %s | frozen composite steps: %s",
             final_name, R["composite_spec"] or "(none — incumbent held)")
    # Persist the selected dev OOF scores. The final model's calibrator is fitted on
    # these (dev rows, disjoint from the locked test) rather than on the final
    # model's own training predictions, which would be in-sample and would look
    # perfectly calibrated while being useless.
    pd.DataFrame({
        "segment_id": data.panel["segment_id"], "date": data.panel["date"],
        "target": data.y, "fold": bar["fold_of"], "score": final_oof,
    }).query("fold >= 0").to_parquet(rdir / "oof_selected.parquet", index=False)
    cal = calibrate.compare_calibrators(
        data, final_oof, bar["fold_of"], folds,
        list(cfg.optimize.calibration.slope_bins))
    R["calibration"] = {k: {kk: vv for kk, vv in v.items()
                            if kk not in ("predictions", "table")}
                        for k, v in cal.items()}
    pd.DataFrame(cal["global_isotonic"]["table"]).assign(variant="global_isotonic") \
        .pipe(lambda a: pd.concat([
            a, pd.DataFrame(cal["per_slope_isotonic"]["table"]).assign(variant="per_slope_isotonic")])) \
        .to_csv(rdir / "calibration_comparison.csv", index=False)
    for k, v in R["calibration"].items():
        log.info("  %-20s ECE %.4f  worst-slope %.2fx  worst-region %.2fx",
                 k, v["global_ece"], v["worst_slope_ratio"], v["worst_region_ratio"])

    # Selection is on the TERRAIN axis only — that is the axis a calibrator can
    # actually condition on at inference time (see calibrate.compare_calibrators).
    cal_pick = ("per_slope_isotonic"
                if cal["per_slope_isotonic"]["worst_slope_ratio"]
                < cal["global_isotonic"]["worst_slope_ratio"] else "global_isotonic")
    R["calibration_selected"] = cal_pick
    p_cal = cal[cal_pick]["predictions"]

    # Calibrate the INCUMBENT under the same procedure. Ranking gains and calibration
    # quality are not the same axis and can move in opposite directions — arms that
    # change the training population (dropping negatives, reweighting) shift the
    # predicted base rate, which costs calibration while flattering AP. Measuring
    # both makes that trade explicit instead of letting it ride on the AP column.
    if final_name != "bar/stage6_tuned":
        cal_bar = calibrate.compare_calibrators(
            data, bar["oof"], bar["fold_of"], folds,
            list(cfg.optimize.calibration.slope_bins))
        R["calibration_incumbent"] = {
            k: {kk: vv for kk, vv in v.items() if kk not in ("predictions", "table")}
            for k, v in cal_bar.items()}
        log.info("  incumbent under %s: ECE %.4f  worst-slope %.2fx",
                 cal_pick, R["calibration_incumbent"][cal_pick]["global_ece"],
                 R["calibration_incumbent"][cal_pick]["worst_slope_ratio"])

    scored = np.isfinite(p_cal) & np.isin(bar["fold_of"], folds)
    y_s, p_s = data.y[scored], p_cal[scored]
    cc = threshold.cost_curve(y_s, p_s, list(cfg.optimize.threshold.cost_ratios),
                              float(cfg.optimize.threshold.fbeta))
    cc.to_csv(rdir / "threshold_cost_curve.csv", index=False)
    threshold.pareto_points(y_s, p_s).to_csv(rdir / "pr_pareto.csv", index=False)
    R["threshold_cost_curve"] = cc.to_dict("records")
    default_ratio = float(cfg.eval.cost_fn_over_fp)
    row = cc[cc.cost_fn_over_fp == default_ratio]
    thr = float(row.threshold.iloc[0]) if len(row) else 0.5
    R["operating_point"] = {"cost_fn_over_fp": default_ratio, "threshold": thr,
                            **threshold.operating_report(y_s, p_s, thr)}
    strata = calibrate.slope_stratum(data, list(cfg.optimize.calibration.slope_bins))
    threshold.per_stratum_thresholds(data, y_s, p_s, strata[scored], default_ratio) \
        .to_csv(rdir / "threshold_per_stratum.csv", index=False)
    log.info("  operating point @FN:FP=%g -> thr %.4f  P=%.3f R=%.3f F1=%.3f",
             default_ratio, thr, R["operating_point"]["precision"],
             R["operating_point"]["recall"], R["operating_point"]["f1"])

    # ------------------------------------------------------------- P7 cost
    log.info("=== P7: latency / memory / model size ===")
    R["runtime"] = {
        "bar (incumbent)": rt.profile(bar["model"], data.X(), cfg.optimize.runtime),
    }
    if final_name != "bar/stage6_tuned" and results.get(final_name, {}).get("model"):
        R["runtime"][f"{final_name} (selected)"] = rt.profile(
            results[final_name]["model"], data.X(), cfg.optimize.runtime)
    for k, v in R["runtime"].items():
        log.info("  %-32s %6s KB, %4d trees, %.2f us/row, %.2fs for %d segments",
                 k, v["model_kb"], v["n_trees"], v["per_row_us"],
                 v["full_corridor_sec"], v["deployment_segments"])

    # --------------------------------------------------- P8 priority + freeze
    R["priority"] = _priority_table(df, R)
    pd.DataFrame(R["priority"]).to_csv(rdir / "optimization_priority.csv", index=False)
    R["final_config"] = _freeze(cfg, R, rdir)

    (rdir / "optimize_results.json").write_text(json.dumps(R, indent=2, default=_js))
    write_manifest(resolve(cfg, "data/processed/manifests"), "optimize_v1",
                   {"selected_scorer": final_name, "calibration": cal_pick,
                    "bar_mean_AP": bar["mean_AP"]})
    _plots(R, df, cal, cc, rdir)
    _write_report(R, df, rdir, cfg)
    log.info("Stage 7 done in %.1fs -> %s", time.time() - t0, rdir)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
def _js(x):
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, (np.floating,)):
        return float(x)
    if isinstance(x, np.ndarray):
        return x.tolist()
    return str(x)


def _strip(res: dict) -> dict:
    return {k: v for k, v in res.items() if k not in ("oof", "fold_of", "model")}


def _composite_from(cfg: Config, names: list[str], label: str):
    """Turn a list of arm names into one composite Arm.

    Within each family only the single best-ranked variant is taken (the caller
    passes them in rank order): stacking `gaussian_all_s0.1` on top of
    `gaussian_all_s0.4` would just be noise at sigma 0.5, and two confidence floors
    would be the stricter one applied twice.
    """
    m = cfg.optimize.data.get("mining", {})
    ni = int(m.get("inner_folds", 2))
    filters, weights, features, rows, spec, seen = [], [], [], [], [], set()

    def fam(n: str) -> str:
        for f in ("data/conf_floor", "data/weight_", "data/hard_neg", "data/hard_pos",
                  "data/easy_neg_drop", "data/dedup", "aug/rain_jitter_append",
                  "aug/rain_jitter_s", "aug/gaussian_terrain_only", "aug/gaussian_rain_only",
                  "aug/gaussian_all", "aug/smote", "loss/focal"):
            if n.startswith(f):
                return f
        return n

    objective, objective_kwargs = None, {}
    for name in names:
        f = fam(name)
        if f in seen:
            continue
        seen.add(f)
        try:
            if name == "data/dedup":
                filters.append(composite.filter_dedup())
            elif f == "data/conf_floor":
                filters.append(composite.filter_confidence(float(name.rsplit("_", 1)[1])))
            elif f == "data/easy_neg_drop":
                filters.append(composite.filter_easy_negatives(cfg, float(name.rsplit("_", 1)[1]), ni))
            elif f == "data/weight_":
                weights.append(composite.weight_scheme(name.rsplit("_", 1)[1]))
            elif f == "data/hard_neg":
                weights.append(composite.weight_hard_negatives(cfg, float(name.split("_a")[1]), ni))
            elif f == "data/hard_pos":
                weights.append(composite.weight_hard_positives(cfg, float(name.split("_a")[1]), ni))
            elif f == "aug/rain_jitter_append":
                rows.append(composite.rows_jitter_append(float(name.split("_s")[1])))
            elif f == "aug/rain_jitter_s":
                features.append(composite.feature_rainfall_jitter(float(name.split("_s")[1])))
            elif f == "aug/gaussian_terrain_only":
                features.append(composite.feature_gaussian_subset(
                    float(name.split("_s")[1]), augment.TERRAIN_COLS))
            elif f == "aug/gaussian_rain_only":
                features.append(composite.feature_gaussian_subset(
                    float(name.split("_s")[1]), augment.RAIN_COLS + augment.ID_RATIO_COLS))
            elif f == "aug/gaussian_all":
                features.append(composite.feature_gaussian_all(float(name.split("_s")[1])))
            elif f == "aug/smote":
                p = name.split("_k")[1]
                rows.append(composite.rows_smote(int(p.split("_f")[0]), float(p.split("_f")[1])))
            elif f == "loss/focal":
                objective, objective_kwargs = "focal", {
                    "gamma": float(name.split("_g")[1]),
                    "alpha": float(cfg.optimize.loss.get("focal_alpha", 0.25))}
            else:
                continue
        except (ValueError, IndexError):
            continue
        spec.append(name)
    if not spec:
        return None, []
    # in-place jitter + jitter-append would apply the same perturbation twice
    if any(s.startswith("aug/rain_jitter_append") for s in spec):
        features = [f for f, s in zip(features, spec) if not s.startswith("aug/rain_jitter_s")]
        spec = [s for s in spec if not s.startswith("aug/rain_jitter_s")]
    return Arm(label, "composite",
               composite.make_composite_arm(filters, weights, features, rows),
               objective=objective, objective_kwargs=objective_kwargs,
               note="combined: " + ", ".join(spec)), spec


def _build_composites(cfg: Config, df: pd.DataFrame):
    """Two composites, because "which arms to combine" is itself a choice.

      composite/passed       — only arms that cleared the decision rule. The
                               principled combination.
      composite/all_positive — every arm with a positive measured delta, even ones
                               inside the noise. Tests whether many small consistent
                               effects accumulate, or whether they overlap.
    """
    ranked = df.sort_values("mean_delta", ascending=False)
    passed = [r.arm for _, r in ranked.iterrows() if r.verdict == "improvement"]
    positive = [r.arm for _, r in ranked.iterrows()
                if r.mean_delta > 0 and r.verdict != "regression"]
    out = []
    a1, s1 = _composite_from(cfg, passed, "composite/passed")
    if a1 is not None:
        out.append((a1, s1))
    a2, s2 = _composite_from(cfg, positive, "composite/all_positive")
    if a2 is not None and s2 != s1:
        out.append((a2, s2))
    return out


def _best_candidate(results: dict, R: dict, bar: dict) -> dict:
    """Promote a candidate over the bar ONLY if it cleared the decision rule.

    Selecting the highest mean AP regardless of verdict is the exact failure this
    project has been guarding against since Stage 6 — it is how a within-noise
    difference becomes "the best model". Among candidates that DID clear the rule,
    the higher AP wins; if none did, the incumbent stays. `composite/all_positive`
    is the live example: it posts the highest AP of anything measured (0.3834) at
    p=0.499 with 2/5 folds improved, and promoting it on that basis would ship a
    coin flip — one that also drops 30% of the negatives and wrecks calibration.
    """
    cands = [("bar/stage6_tuned", bar, "incumbent")]
    for c in R.get("composites", []):
        r = results.get(c["name"])
        if r is not None:
            cands.append((c["name"], r, c["verdict"]))
    passed = [(n, r) for n, r, v in cands if v == "improvement"]
    if not passed:
        return bar
    return max([r for _, r in passed], key=lambda r: r["mean_AP"])


def _final_scores(results: dict, R: dict, bar: dict):
    """Pick the scorer used for calibration/threshold work: the ensemble if it was
    demonstrated, else the best candidate that cleared the decision rule."""
    if R.get("ensemble", {}).get("verdict") == "improvement":
        return results["ensemble"]["oof"], "ensemble"
    b = _best_candidate(results, R, bar)
    return b["oof"], b["name"]


# Effort / compute are ENGINEERING JUDGEMENTS, not measurements; gain is measured.
_EFFORT = {
    "data/dedup": ("low", "trivial"), "data/conf_floor": ("low", "trivial"),
    "data/weight": ("low", "trivial"), "data/hard_neg": ("medium", "3x train"),
    "data/easy_neg_drop": ("medium", "3x train"), "data/hard_pos": ("medium", "3x train"),
    "aug/rain_jitter_append": ("low", "2x train"), "aug/rain_jitter": ("low", "trivial"),
    "aug/gaussian_all": ("low", "trivial"), "aug/smote": ("medium", "1.2x train"),
    "loss/focal": ("medium", "1.3x train"),
}


def _priority_table(df: pd.DataFrame, R: dict) -> list[dict]:
    out = []
    for _, r in df.iterrows():
        key = next((k for k in _EFFORT if r.arm.startswith(k)), None)
        eff, comp = _EFFORT.get(key, ("medium", "unknown"))
        out.append({"item": r.arm, "measured_delta_AP": round(float(r.mean_delta), 5),
                    "p_value": round(float(r.p_value), 4),
                    "verdict": r.verdict, "effort": eff, "compute": comp,
                    "fit_sec_per_fold": round(float(r.mean_fit_sec), 2)})
    if R.get("ensemble"):
        out.append({"item": "ensemble (lgbm+logistic+rule)",
                    "measured_delta_AP": round(R["ensemble"]["delta_vs_bar"]["mean_delta"], 5),
                    "p_value": round(R["ensemble"]["delta_vs_bar"]["p_value"], 4),
                    "verdict": R["ensemble"]["verdict"], "effort": "medium",
                    "compute": "+1 logistic fit per fold", "fit_sec_per_fold": None})
    cal = R.get("calibration", {})
    if cal:
        g = cal.get("global_isotonic", {}).get("worst_slope_ratio", float("nan"))
        s = cal.get("per_slope_isotonic", {}).get("worst_slope_ratio", float("nan"))
        out.append({"item": "per-stratum calibration (Stage 5 P2)",
                    "measured_delta_AP": 0.0,
                    "p_value": None,
                    "verdict": (f"worst terrain-stratum miscalibration {g:.2f}x -> "
                                f"{s:.2f}x (ranking-neutral, routing-critical)"),
                    "effort": "low", "compute": "negligible", "fit_sec_per_fold": None})
    return out


def _freeze(cfg: Config, R: dict, rdir: Path) -> dict:
    """Freeze the final configuration and pre-register the test-set protocol.

    Written BEFORE any locked-test row is read. The hash pins exactly what will be
    trained and exactly which metrics will be reported, so the Stage 8 number
    cannot be quietly reshaped after seeing it.
    """
    sel = R.get("selected_scorer", "")
    if sel == "ensemble":
        src = R.get("ensemble", R["bar"])
    elif R.get("composite") and R["composite"]["name"] == sel:
        src = R["composite"]
    else:
        src = R["bar"]
    final = {
        "lgbm": dict(cfg.lgbm),
        # Round count for the final all-dev fit. Early stopping still runs (on an
        # event-grouped split of dev), so this is an upper bound, not a hard count.
        "n_estimators_final": int(cfg.lgbm.n_estimators),
        "cv_mean_best_iter": float(src.get("mean_best_iter", 0)),
        "cv": {"es_split_mode": cfg.cv.get("es_split_mode", "event"),
               "drop_buffer_rows": cfg.cv.drop_buffer_rows},
        "scorer": sel,
        "ensemble_weights": (R.get("ensemble", {}).get("consensus_weights")
                             if R.get("selected_scorer") == "ensemble" else None),
        "calibration": R.get("calibration_selected"),
        "operating_threshold": R.get("operating_point", {}).get("threshold"),
        "cost_fn_over_fp": R.get("operating_point", {}).get("cost_fn_over_fp"),
        "composite_steps": R.get("composite_spec", []),
    }
    blob = json.dumps(final, sort_keys=True, default=_js).encode()
    h = hashlib.sha256(blob).hexdigest()[:16]
    prereg = {
        "config_sha256_16": h,
        "frozen_utc": pd.Timestamp.utcnow().isoformat(),
        "git_sha": R["git_sha"],
        "final_config": final,
        "dev_estimate": {
            # must be the SELECTED scorer's own CV score — quoting any other
            # candidate's number here would make the dev-vs-test gap meaningless
            "scorer": sel,
            "spatial_cv_mean_AP": float(src["mean_AP"]),
            "spatial_cv_std_AP": float(src.get("std_AP", float("nan"))),
            "incumbent_mean_AP": float(R["bar"]["mean_AP"]),
            "note": ("This CV number is optimistically biased: it was used to SELECT "
                     "among ~25 arms. The locked final_test exists to measure that bias."),
        },
        "metrics_to_report": [
            "average_precision", "roc_auc", "brier", "ece",
            "precision@10", "precision@50", "precision@100", "precision@200",
            "recall@10", "recall@50", "recall@100", "recall@200",
            "lift@1pct", "lift@5pct", "lift@10pct",
            "precision/recall/f1 at the frozen threshold",
            "steep-terrain (slope>=10deg) AP and lift",
            "per-stratum predicted/observed calibration ratio",
        ],
        "rule": ("The locked split is opened ONCE, by scripts/open_final_test.py. "
                 "No configuration, threshold, calibrator or feature may change "
                 "after this file is written. If the test number disappoints, that "
                 "is the result — it is not a reason to re-open the search."),
    }
    (rdir / "PREREGISTRATION.json").write_text(json.dumps(prereg, indent=2, default=_js))
    log.info("froze final config sha=%s -> PREREGISTRATION.json", h)
    return final


# --------------------------------------------------------------------------- #
# Plots + report
# --------------------------------------------------------------------------- #
def _plots(R: dict, df: pd.DataFrame, cal: dict, cc: pd.DataFrame, rdir: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    # 1. paired deltas with per-fold scatter
    d = df.sort_values("mean_delta")
    fig, ax = plt.subplots(figsize=(9, max(4, 0.32 * len(d))))
    colors = {"improvement": "#2ca02c", "regression": "#d62728",
              "not demonstrated": "#999999", "invalid": "#cccccc"}
    ax.barh(d.arm, d.mean_delta, color=[colors.get(v, "#999") for v in d.verdict])
    for i, (_, r) in enumerate(d.iterrows()):
        for x in r.deltas:
            ax.plot(x, i, "k.", ms=3, alpha=.5)
    ax.axvline(0, c="k", lw=1)
    ax.set_xlabel("paired delta in AP vs the Stage 6 bar (dots = individual folds)")
    ax.set_title("Stage 7 — every arm, paired against the same 5 spatial folds")
    ax.tick_params(labelsize=7)
    fig.savefig(rdir / "arm_deltas.png", dpi=120, bbox_inches="tight"); plt.close(fig)

    # 2. augmentation strength sweep
    aug = df[df.arm.str.startswith("aug/rain_jitter_s")].copy()
    if len(aug):
        aug["sigma"] = aug.arm.str.split("_s").str[-1].astype(float)
        aug = aug.sort_values("sigma")
        fig, ax = plt.subplots(figsize=(6, 4))
        ax.errorbar(aug.sigma, aug.mean_delta, yerr=aug.std_AP, marker="o", capsize=4)
        ax.axhline(0, c="k", lw=1, ls="--")
        ax.set_xlabel("rainfall jitter sigma (lognormal)")
        ax.set_ylabel("paired delta in AP")
        ax.set_title("Augmentation strength sweep")
        ax.grid(alpha=.3)
        fig.savefig(rdir / "augmentation_strength.png", dpi=120, bbox_inches="tight"); plt.close(fig)

    # 3. calibration: the two axes side by side — one is fixable, one is not
    names = list(cal)
    fig, ax = plt.subplots(figsize=(7.5, 4))
    x = np.arange(len(names)); wbar = 0.38
    slope = [cal[k]["worst_slope_ratio"] for k in names]
    region = [cal[k]["worst_region_ratio"] for k in names]
    ax.bar(x - wbar / 2, slope, wbar, label="worst TERRAIN stratum (fixable at inference)",
           color="#2ca02c")
    ax.bar(x + wbar / 2, region, wbar, label="worst REGION stratum (not knowable for a new area)",
           color="#bbbbbb")
    for xi, v in zip(x - wbar / 2, slope):
        ax.text(xi, v, f"{v:.2f}x", ha="center", va="bottom", fontsize=8)
    for xi, v in zip(x + wbar / 2, region):
        ax.text(xi, v, f"{v:.2f}x", ha="center", va="bottom", fontsize=8)
    ax.axhline(1.0, c="k", ls="--", lw=1)
    ax.set_xticks(x); ax.set_xticklabels(names, rotation=10, ha="right", fontsize=8)
    ax.set_ylabel("worst predicted / observed")
    ax.set_title("Calibration transfer (cross-fitted) — terrain vs region")
    ax.legend(fontsize=7)
    fig.savefig(rdir / "calibration_variants.png", dpi=120, bbox_inches="tight"); plt.close(fig)

    # 4. PR trade-off with the cost points marked
    pareto = pd.read_csv(rdir / "pr_pareto.csv")
    fig, ax = plt.subplots(figsize=(6.5, 4.5))
    ax.plot(pareto.recall, pareto.precision, lw=1.5)
    for _, r in cc.iterrows():
        ax.plot(r.recall, r.precision, "o", ms=7)
        ax.annotate(f"FN:FP={r.cost_fn_over_fp}", (r.recall, r.precision),
                    fontsize=7, xytext=(4, 4), textcoords="offset points")
    ax.set_xlabel("recall"); ax.set_ylabel("precision")
    ax.set_title("Precision/recall trade-off — the operating point is a POLICY choice")
    ax.grid(alpha=.3)
    fig.savefig(rdir / "pr_tradeoff.png", dpi=120, bbox_inches="tight"); plt.close(fig)


def _write_report(R: dict, df: pd.DataFrame, rdir: Path, cfg: Config) -> None:
    bar = R["bar"]
    L = [
        "# Stage 7 — Accuracy Optimization results", "",
        f"git `{R['git_sha']}` · folds {R['eval_folds']} · "
        "**`final_test` not opened by this run.**", "",
        "Protocol: every arm runs on the SAME 5 spatial folds with the SAME seeds and "
        "early-stopping splits, and is compared to the bar by **paired per-fold "
        "deltas** with a sign-flip permutation test. With 5 folds the smallest "
        "attainable two-sided p is 0.0625, so the test can reject noise but cannot "
        "certify a small effect — it is reported, not leaned on.", "",
        f"**The bar** (Stage 6 selected config): mean AP **{bar['mean_AP']:.4f} ± "
        f"{bar['std_AP']:.4f}** over folds "
        + ", ".join(f"{f}:{v:.3f}" for f, v in bar["fold_ap"].items()) + "", "",
        "## Every arm, ranked by measured delta", "",
        "| arm | mean AP | delta | p | folds+ | verdict |", "|--|--|--|--|--|--|",
    ]
    for _, r in df.iterrows():
        L.append(f"| `{r.arm}` | {r.mean_AP:.4f} | **{r.mean_delta:+.4f}** | "
                 f"{r.p_value:.3f} | {r.folds_improved}/5 | {r.verdict} |")
    for c in R.get("composites", []):
        L.append(f"| `{c['name']}` | {c['mean_AP']:.4f} | "
                 f"**{c['delta']['mean_delta']:+.4f}** | {c['delta']['p_value']:.3f} | "
                 f"{c['delta']['folds_improved']}/5 | {c['verdict']} |")
    if R.get("ensemble"):
        e = R["ensemble"]
        L.append(f"| `ensemble` | {e['mean_AP']:.4f} | "
                 f"**{e['delta_vs_bar']['mean_delta']:+.4f}** | "
                 f"{e['delta_vs_bar']['p_value']:.3f} | "
                 f"{e['delta_vs_bar']['folds_improved']}/5 | {e['verdict']} |")
    L += ["", "### Multiplicity — read this before believing any single row", "",
          f"{len(df)} arms were tested at alpha = {float(cfg.optimize.alpha)}. With 5 "
          "folds the sign-flip test bottoms out at **p = 2/2⁵ = 0.0625**, so a "
          f"Bonferroni-corrected threshold ({float(cfg.optimize.alpha)}/{len(df)} = "
          f"{float(cfg.optimize.alpha)/max(1,len(df)):.4f}) is **unreachable by "
          "construction** — no arm here can be certified family-wise. At uncorrected "
          f"alpha, ~{len(df) * float(cfg.optimize.alpha):.1f} of these arms are "
          "expected to 'pass' by chance alone. That is why the leading arms are "
          "replicated under fresh seeds below rather than declared winners here.", ""]
    if R.get("confirmation"):
        L += ["## Seed replication of the leading arms", "",
              "A fresh seed redraws the event-grouped early-stopping split and the "
              "bagging RNG. An effect that survives is not an artifact of one inner "
              "split — it is still not a family-wise-corrected result.", "",
              "| arm | seed-0 delta | replicate mean delta | fold×seed pairs improved | replicated |",
              "|--|--|--|--|--|"]
        for s in R["confirmation"]:
            L.append(f"| `{s['arm']}` | {s['seed0_delta']:+.4f} | "
                     f"{s['replicate_mean_delta']:+.4f} | "
                     f"{s['fold_seed_pairs_improved']}/{s['fold_seed_pairs']} | "
                     f"{'YES' if s['replicated'] else 'no'} |")
        L.append("")
    L += ["", "## Ensemble members (solo, same folds)", ""]
    if R.get("ensemble"):
        L += ["| member | mean AP |", "|--|--|"]
        for k, v in R["ensemble"]["member_solo"].items():
            L.append(f"| {k} | {v['mean_AP']:.4f} |")
        L += ["", f"Consensus blend weights: `{R['ensemble']['consensus_weights']}`",
              "", "Weights are chosen leave-one-fold-out, so no fold is scored by a "
              "weight fitted on it.", ""]
    if R.get("stratified"):
        s = R["stratified"]
        L += ["## Terrain-stratified model (Stage 5 §1)", "",
              f"On slope >= {s['slope_split_deg']}° rows only "
              f"({s['n_steep_rows']:,} rows in the panel):", "",
              "| model | mean AP |", "|--|--|",
              f"| global model, restricted to steep rows | {s['global_model_on_same_rows']['mean_AP']:.4f} |",
              f"| dedicated steep-only model | {s['steep_only_model']['mean_AP']:.4f} |",
              "", f"delta **{s['delta']['mean_delta']:+.4f}** (p={s['delta']['p_value']:.3f}) "
              f"-> **{s['verdict']}**", ""]
    L += ["## Calibration (cross-fitted)", "",
          "| variant | global ECE | Brier | worst TERRAIN stratum | worst REGION stratum |",
          "|--|--|--|--|--|"]
    for k, v in R["calibration"].items():
        L.append(f"| {k} | {v['global_ece']:.4f} | {v['global_brier']:.4f} | "
                 f"**{v['worst_slope_ratio']:.2f}×** | {v['worst_region_ratio']:.2f}× |")
    L += ["", f"Selected: **{R['calibration_selected']}**, on the terrain axis.", "",
          "Global ECE is not the headline — a global calibrator minimises it by "
          "construction. The worst-stratum ratio is what Stage 5 §6 flagged and what "
          "the routing penalty `W = dist·(1 + λ·P)` is actually exposed to.", "",
          "The two axes are separated because only one is fixable at inference: "
          "terrain is a property of the row being scored, so a calibrator can "
          "condition on it; *which region* is not knowable for a new area, so region "
          "miscalibration is a residual limitation to disclose, not a target to "
          "optimise. Cross-fitting is also why these numbers are worse than Stage 5's "
          "— Stage 5 fitted its calibrator on the rows it then scored.", "",
          "## Operating point / cost sensitivity", "",
          "| FN:FP | threshold | precision | recall | F1 | FP rate of negatives |",
          "|--|--|--|--|--|--|"]
    for r in R["threshold_cost_curve"]:
        L.append(f"| {r['cost_fn_over_fp']} | {r['threshold']:.4f} | "
                 f"{r['precision']:.3f} | {r['recall']:.3f} | {r['f1']:.3f} | "
                 f"{r['fp_rate_of_neg']:.1%} |")
    op = R["operating_point"]
    L += ["", f"Shipped default is FN:FP = {op['cost_fn_over_fp']:g} "
          f"(threshold {op['threshold']:.4f}, precision {op['precision']:.3f}, "
          f"recall {op['recall']:.3f}) — **inherited from Stage 3 and still not "
          "validated with MDoNER.** The table is the hand-off.", "",
          "## Cost", "", "| config | model KB | trees | leaves | µs/row | full corridor |",
          "|--|--|--|--|--|--|"]
    for k, v in R["runtime"].items():
        L.append(f"| {k} | {v['model_kb']} | {v['n_trees']} | {v['total_leaves']} | "
                 f"{v['per_row_us']} | {v['full_corridor_sec']}s for "
                 f"{v['deployment_segments']:,} segments |")
    L += ["", "## Frozen configuration", "",
          "`PREREGISTRATION.json` pins the final config hash and the exact metric "
          "list **before** any locked-test row is read. Open the test with:", "",
          "```bash", "make stage7-final-test", "```", ""]
    (rdir / "OPTIMIZATION_REPORT.md").write_text("\n".join(L))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
