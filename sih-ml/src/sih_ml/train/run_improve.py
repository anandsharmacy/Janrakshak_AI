"""Stage 10 — continuous improvement loop.

    python -m sih_ml.train.run_improve [conf/improve_config.yaml]

One campaign of the cycle

    Evaluate -> Analyze errors -> Identify bottleneck -> Change ONE variable ->
    Train -> Validate -> Compare -> Keep / Revert

  0. Reconstruct the champion — the registry's, or final_v2 on the first campaign —
     and VERIFY it reproduces its recorded per-seed dev AP and dev operating
     threshold exactly. Nothing is compared against a champion that is not provably
     the registered one. Experiments already decided against this champion, code and
     data are skipped, not re-run.
  1. Diagnose: re-measure every known error pattern on the champion's OOF.
  2. A/A: train the champion under 3 more seeds; the champion-vs-itself deltas set
     the noise floor every later decision must clear.
  3. Round 0: correctness fixes, each against the champion.
  4. Round 1: every backlog experiment against the same champion.
  5. Round 2: greedy composition of the accepted changes — each after the first is
     RE-MEASURED on top of the updated champion, because two changes that each help
     can overlap or conflict.
  6. Materialise the champion, measure its efficiency frontier and dev operating
     points, update the registry, write the report.

Every experiment and every decision is appended to the ledger. The locked split is
never read here — tests/test_improve.py asserts this module and the improve package
make no reference to it. A new champion is a DEV champion until a pre-registered
opening says otherwise.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.improve import candidate as C
from sih_ml.improve import decide as Dc
from sih_ml.improve import diagnose as Dg
from sih_ml.improve import efficiency as Ef
from sih_ml.improve.features import (LocalRainPercentiles, chirps_path, coverage_mask,
                                     rainfall_coverage_end)
from sih_ml.improve.ledger import Ledger, Registry, dumps, fingerprint, spec_hash
from sih_ml.models.calibration import Calibrator
from sih_ml.models.dataset import load_data
from sih_ml.optimize import calibrate as cal_mod
from sih_ml.optimize import runtime as rt
from sih_ml.optimize import threshold as thr_mod
from sih_ml.utils.common import REPO_ROOT, get_logger, resolve, set_seed

log = get_logger("stage10")


class Loop:
    def __init__(self, cfg_path: Path):
        self.data, self.cfg = load_data(cfg_path)
        set_seed(self.cfg.seed)
        ic = self.cfg.improve
        self.ic = ic
        self.folds, self.seeds, self.aa_seeds = list(ic.folds), list(ic.seeds), list(ic.aa_seeds)
        self.bins = list(ic.calibration_bins)
        self.lim = dict(ic.guardrails)
        self.rdir = resolve(self.cfg, self.cfg.paths.reports)
        self.rdir.mkdir(parents=True, exist_ok=True)
        self.ledger = Ledger(resolve(self.cfg, self.cfg.paths.ledger))
        self.registry = Registry(resolve(self.cfg, self.cfg.paths.registry))
        self.coverage = coverage_mask(self.data, self.cfg)
        self.pctl = LocalRainPercentiles(self.cfg)
        self.campaign = "c" + pd.Timestamp.now(tz="UTC").strftime("%Y%m%dT%H%M%SZ")
        self.fp = fingerprint([resolve(self.cfg, self.cfg.paths.panel),
                               resolve(self.cfg, self.cfg.paths.folds),
                               Path(chirps_path())])

    # ------------------------------------------------------------------ basics
    def build(self, state: dict, name: str) -> C.Candidate:
        return C.build_candidate(state, name, self.data, self.cfg,
                                 coverage=self.coverage, pctl=self.pctl)

    def dev_X(self, cand: C.Candidate):
        """Feature rows for timing — dev only, so even latency probes never touch the
        locked split's rows."""
        return cand.data.X(np.where(cand.data.dev_mask())[0])

    def run(self, cand: C.Candidate, seeds=None, keep_models=True) -> dict:
        t0 = time.time()
        r = C.run(cand, self.folds, seeds or self.seeds, keep_models)
        log.info("  %-34s mean AP %.4f  (%d fits, %.0fs)", cand.name, r["mean_AP"],
                 len(self.folds) * len(seeds or self.seeds), time.time() - t0)
        return r

    def cost(self, cand: C.Candidate, res: dict) -> dict:
        sizes, trees = [], []
        for m in res["models"].values():
            mem = Ef._members(m)
            sizes.append(sum(rt.model_size(x)["model_bytes"] for x in mem))
            trees.append(sum(int(x.best_iteration_ or 0) for x in mem))
        e = self.ic.efficiency
        lat = rt.latency(res["models"][self.folds[0]], self.dev_X(cand), int(e.latency_rows),
                         int(e.repeats), int(e.deployment_segments))
        return {"model_mb": float(np.mean(sizes)) / 1e6, "mean_trees": float(np.mean(trees)),
                "corridor_sec": float(lat["full_corridor_sec"]),
                "per_row_us": float(lat["per_row_us"])}

    def guard_metrics(self, cand: C.Candidate, res: dict) -> dict:
        p_cal = Dg.calibrated_oof(cand, res, self.folds, self.bins)
        ratios = Dg.worst_ratios(cand, p_cal, res["fold_of"], self.folds, self.bins)
        cal = Dg.terrain_cal_per_seed(cand, res, self.folds, self.bins)
        f0 = self.folds[0]
        return {**C.steep_roc(cand, res, float(self.lim["steep_slope_deg"])),
                "worst_terrain_cal_ratio": float(np.mean(list(cal.values()))),
                "worst_terrain_cal_ratio_per_seed": cal,
                "worst_region_cal_ratio": ratios["region"],
                "monotonicity_violations": C.monotonicity(cand, res["models"][f0],
                                                          res["va"][f0], seed=self.cfg.seed),
                **self.cost(cand, res)}

    def calibrate_noise(self, cand: C.Candidate, res: dict) -> dict:
        log.info("  A/A: %s under %s", cand.name, self.aa_seeds)
        r_aa = self.run(cand.with_eval_mask(cand.eval_mask, cand.name + " [A/A]"),
                        self.aa_seeds, keep_models=False)
        both = {**res, "ap": {**res["ap"], **r_aa["ap"]}, "oof": {**res["oof"], **r_aa["oof"]}}
        slope_deg = float(self.lim["steep_slope_deg"])
        metrics = {"steep_roc": C.steep_roc(cand, both, slope_deg)["steep_roc_per_seed"],
                   "cal_ratio": Dg.terrain_cal_per_seed(cand, both, self.folds, self.bins)}
        noise = Dc.aa_noise(both["ap"], self.seeds + self.aa_seeds,
                            self.folds, float(self.ic.noise_floor_quantile),
                            int(self.ic.min_folds_improved), float(self.ic.alpha), metrics)
        log.info("  A/A floors: AP %.4f | worst fold %.4f | steep ROC %.4f | terrain cal "
                 "%.3fx | Stage 7/9 rule false-positive rate %.0f%%",
                 noise["delta_floor"], noise["worst_fold_floor"], noise["steep_roc_floor"],
                 noise["cal_ratio_floor"], 100 * noise["old_rule_false_positive_rate"])
        self.ledger.append({"type": "aa_calibration", "campaign_id": self.campaign,
                            "champion": cand.name, "state_sha16": spec_hash(cand.state),
                            "seeds": self.seeds, "aa_seeds": self.aa_seeds,
                            "ap_aa": r_aa["ap"],
                            **{k: v for k, v in noise.items() if k != "splits"},
                            "fingerprint": self.fp})
        return noise

    # --------------------------------------------------------- starting point
    def starting_champion(self) -> dict:
        """Where this campaign starts: the registry's champion if it has been recorded
        with a state and per-seed AP (i.e. a previous campaign produced it), otherwise
        the Stage 9 champion. Either way it must reproduce its recorded numbers."""
        reg = self.registry.load()
        v = next((x for x in reg.get("versions", []) if x["version"] == reg.get("champion")), None)
        if v and v.get("state") and v.get("per_seed_AP"):
            return {"version": v["version"], "state": v["state"], "source": "registry",
                    "want_ap": {int(s): float(a) for s, a in v["per_seed_AP"].items()},
                    "want_thr": float(v["dev_threshold_fn_fp_20"])}
        ch = self.ic.champion
        sel = pd.read_csv(REPO_ROOT / ch.stage9_selection)
        prereg = json.loads((REPO_ROOT / ch.stage9_prereg).read_text())
        return {"version": ch.version, "state": C.initial_state(self.cfg), "source": "stage9",
                "want_ap": dict(zip(sel.seed.astype(int).tolist(), sel.v2_AP.astype(float).tolist())),
                "want_thr": float(prereg["final_config"]["operating_threshold"]),
                "config_sha256_16": prereg["config_sha256_16"]}

    def dev_threshold(self, cand: C.Candidate, res: dict, ratio: float) -> float:
        p_cal = cal_mod.cross_fitted_calibration(
            cand.data, res["oof"][self.seeds[0]], res["fold_of"], self.folds,
            cal_mod.slope_stratum(cand.data, list(self.cfg.optimize.calibration.slope_bins)))
        m = np.isfinite(res["oof"][self.seeds[0]])
        cc = thr_mod.cost_curve(cand.data.y[m], p_cal[m],
                                list(self.cfg.optimize.threshold.cost_ratios),
                                float(self.cfg.optimize.threshold.fbeta))
        return float(cc.loc[cc.cost_fn_over_fp == ratio, "threshold"].iloc[0])

    def per_seed_ap(self, res: dict) -> dict:
        return {s: float(np.mean([res["ap"][s][f] for f in self.folds])) for s in self.seeds}

    # --------------------------------------------------------- reproduction
    def verify_reproduction(self, cand: C.Candidate, res: dict, start: dict) -> dict:
        want, thr_want = start["want_ap"], start["want_thr"]
        got = self.per_seed_ap(res)
        ap_ok = all(abs(got[s] - want[s]) < 1e-12 for s in self.seeds)
        thr = self.dev_threshold(cand, res, float(self.cfg.eval.cost_fn_over_fp))
        out = {"type": "reproduction", "campaign_id": self.campaign,
               "champion": start["version"], "source": start["source"],
               "config_sha256_16": start.get("config_sha256_16"),
               "per_seed_AP_expected": want, "per_seed_AP_reproduced": got,
               "per_seed_AP_match": ap_ok, "dev_threshold_expected": thr_want,
               "dev_threshold_reproduced": thr, "dev_threshold_match": thr == thr_want,
               "ok": bool(ap_ok and thr == thr_want), "fingerprint": self.fp}
        self.ledger.append(out)
        return out

    # ------------------------------------------------------------ experiment
    def evaluate(self, exp: dict, champ: dict, round_no: int) -> dict:
        new_state = C.apply_change(champ["state"], dict(exp["change"]))
        name = exp["id"] if round_no < 2 else f"{exp['id']} (re-test on {champ['version']})"
        ch = self.build(new_state, name)
        base, r_base, g_base = champ["cand"], champ["res"], champ["guard"]
        eval_effect = None
        if not np.array_equal(ch.eval_mask, base.eval_mask):
            # the change alters WHICH rows are scored (a target correction): re-score the
            # champion on the challenger's rows so the comparison is on identical rows
            base, r_base = C.restrict(base, r_base, ch.eval_mask,
                                      f"{champ['version']} @ corrected rows")
            g_base = self.guard_metrics(base, r_base)
            eval_effect = {"champion_AP_original_rows": champ["res"]["mean_AP"],
                           "champion_AP_corrected_rows": r_base["mean_AP"],
                           "measurement_inflation": champ["res"]["mean_AP"] - r_base["mean_AP"],
                           "rows_removed_from_eval": int(champ["cand"].eval_mask.sum()
                                                         - ch.eval_mask.sum())}
        r_ch = self.run(ch)
        g_ch = self.guard_metrics(ch, r_ch)
        D = Dc.delta_table(r_ch["ap"], r_base["ap"], self.seeds, self.seeds, self.folds)
        cmp = Dc.compare(D, self.folds, int(self.ic.min_folds_improved),
                         float(self.ic.alpha), int(self.ic.n_permutations))
        fails = Dc.guardrail_failures(g_ch, g_base, cmp, champ["noise"], self.lim)
        decision, reason = Dc.decide(exp["kind"], cmp, fails, champ["noise"],
                                     float(self.ic.ni_margin_cap))
        log.info("  %-34s %s  delta %+.4f  folds %d/5  seeds %d/%d  p=%.3f  -> %s",
                 name, exp["kind"][:5], cmp["mean_delta"], cmp["folds_improved"],
                 cmp["seeds_positive"], cmp["n_seeds"], cmp["p_value"], decision)
        log.info("      %s", reason)
        entry = self.ledger.append({
            "type": "experiment", "campaign_id": self.campaign, "round": round_no,
            "id": exp["id"], "name": name, "kind": exp["kind"], "layer": exp["layer"],
            "bottleneck": exp["bottleneck"], "hypothesis": exp["hypothesis"],
            "evidence": exp["evidence"], "change": dict(exp["change"]),
            "champion_version": champ["version"],
            "champion_state": champ["state"], "challenger_state": new_state,
            "champion_state_sha16": spec_hash(champ["state"]),
            "challenger_state_sha16": spec_hash(new_state),
            "seeds": self.seeds, "folds": self.folds,
            "ap_champion": r_base["ap"], "ap_challenger": r_ch["ap"],
            "comparison": cmp, "eval_target_effect": eval_effect,
            "guardrails": {"champion": g_base, "challenger": g_ch, "failures": fails},
            "noise_floor": champ["noise"]["delta_floor"],
            "worst_fold_floor": champ["noise"]["worst_fold_floor"],
            "decision": decision, "reason": reason,
            "mean_best_iter": r_ch["mean_best_iter"], "fit_sec": r_ch["fit_sec"],
            "fingerprint": self.fp})
        entry["_cand"], entry["_res"], entry["_guard"], entry["_state"] = ch, r_ch, g_ch, new_state
        entry["mean_delta"] = cmp["mean_delta"]
        return entry

    def promote(self, champ: dict, entry: dict, version: str) -> dict:
        new = {"version": version, "state": entry["_state"], "cand": entry["_cand"],
               "res": entry["_res"], "guard": entry["_guard"],
               "lineage": [*champ["lineage"], {"id": entry["id"], "kind": entry["kind"],
                                                "reason": entry["reason"],
                                                "mean_delta": entry["mean_delta"]}]}
        new["noise"] = self.calibrate_noise(new["cand"], new["res"])
        self.ledger.append({"type": "promotion", "campaign_id": self.campaign,
                            "from": champ["version"], "to": version, "by": entry["id"],
                            "reason": entry["reason"], "state": new["state"],
                            "state_sha16": spec_hash(new["state"])})
        return new

    # --------------------------------------------------------------- artifact
    def train_final(self, cand: C.Candidate):
        dev = np.where(self.data.dev_mask() & cand.train_mask)[0]
        members = [C._fit_member(cand, dev, 0, int(self.cfg.seed), j)[0]
                   for j in range(int(cand.state["bag"]))]
        return members[0] if len(members) == 1 else C.BaggedModel(members)

    def save_artifact(self, version: str, champ: dict, model, extra: dict) -> Path:
        out = resolve(self.cfg, self.cfg.paths.models) / version
        out.mkdir(parents=True, exist_ok=True)
        for i, m in enumerate(Ef._members(model)):
            m.save(out / (f"model_{i}.txt" if len(Ef._members(model)) > 1 else "model.txt"))
        # per-slope isotonic calibrators fitted on dev OUT-OF-FOLD scores (Stage 9 rule)
        cand, res = champ["cand"], champ["res"]
        oof = res["oof"][self.seeds[0]]
        strata = cal_mod.slope_stratum(cand.data, self.bins)
        m = np.isfinite(oof)
        y = cand.data.y
        Calibrator("isotonic").fit(oof[m], y[m], float(y[m].mean())).save(out / "calibrator_pooled.pkl")
        for s in np.unique(strata[m]):
            sel = m & (strata == s)
            if sel.sum() >= 200 and y[sel].sum() >= 20:
                Calibrator("isotonic").fit(oof[sel], y[sel], float(y[sel].mean())).save(
                    out / f"calibrator_slope_{s}.pkl")
        card = {"version": version, "state": champ["state"],
                "config_sha256_16": spec_hash({"state": champ["state"],
                                               "lgbm": dict(cand.cfg.lgbm),
                                               "calibration_bins": self.bins}),
                "features": cand.data.features, "lineage": champ["lineage"],
                "fingerprint": self.fp, **extra}
        (out / "model_card.json").write_text(json.dumps(card, indent=2, default=str))
        return out


# --------------------------------------------------------------------------- #
def main(config_path: str | None = None) -> None:
    t0 = time.time()
    cfg_path = Path(config_path) if config_path else REPO_ROOT / "conf" / "improve_config.yaml"
    if not cfg_path.is_absolute():
        cfg_path = REPO_ROOT / cfg_path
    L = Loop(cfg_path)
    ic = L.ic
    exps = [dict(e) for e in ic.experiments]
    for e in exps:                       # fail fast on a malformed or multi-variable change
        C.apply_change(C.initial_state(L.cfg), dict(e["change"]))
    R: dict = {"campaign_id": L.campaign, "fingerprint": L.fp,
               "rainfall_record_end": str(rainfall_coverage_end(L.cfg).date())}
    log.info("=== Stage 10 campaign %s | code %s | data %s ===", L.campaign,
             L.fp["code_sha16"], L.fp["data_sha16"])

    # 0 ------------------------------------------------------ reconstruct champion
    start = L.starting_champion()
    log.info("=== 0: reconstruct %s (from %s) and verify ===", start["version"], start["source"])
    state = start["state"]
    cand = L.build(state, start["version"])
    res = L.run(cand)
    R["start"] = {k: v for k, v in start.items() if k != "state"}
    R["reproduction"] = L.verify_reproduction(cand, res, start)
    log.info("  per-seed AP match: %s | dev threshold %.12f vs %.12f -> %s",
             R["reproduction"]["per_seed_AP_match"],
             R["reproduction"]["dev_threshold_reproduced"],
             R["reproduction"]["dev_threshold_expected"], R["reproduction"]["ok"])
    if not R["reproduction"]["ok"]:
        raise RuntimeError(f"champion reconstruction does not reproduce {start['source']} — "
                           "refusing to measure anything against it")
    champ = {"version": start["version"], "state": state, "cand": cand, "res": res,
             "guard": L.guard_metrics(cand, res), "lineage": []}

    # Questions already answered are not asked again. An experiment decided against
    # the same champion state, code and data in a completed campaign is skipped; it
    # re-opens only when one of those changes (new data is the usual reason).
    # Re-running a decided comparison until it passes is how noise gets promoted.
    aborted = {r["campaign_id"] for r in L.ledger.read() if r.get("type") == "campaign_aborted"}
    decided = {(r["id"], r["champion_state_sha16"], r["fingerprint"]["data_sha16"],
                r["fingerprint"]["code_sha16"]): r
               for r in L.ledger.read()
               if r.get("type") == "experiment" and r["campaign_id"] not in aborted}
    R["skipped"] = []

    def runnable(e: dict, ch: dict) -> bool:
        key = (e["id"], spec_hash(ch["state"]), L.fp["data_sha16"], L.fp["code_sha16"])
        if key in decided:
            prev = decided[key]
            R["skipped"].append({"id": e["id"], "why": f"already decided in {prev['campaign_id']}: "
                                 f"{prev['decision']} — {prev['reason']}"})
            log.info("  skip %s: decided in %s (%s)", e["id"], prev["campaign_id"], prev["decision"])
            return False
        try:
            C.apply_change(ch["state"], dict(e["change"]))
        except ValueError as err:
            R["skipped"].append({"id": e["id"], "why": f"not applicable to {ch['version']}: {err}"})
            log.info("  skip %s: not applicable (%s)", e["id"], err)
            return False
        return True

    # 1 ------------------------------------------------------------- diagnose
    log.info("=== 1: bottlenecks on %s ===", champ["version"])
    R["bottlenecks_before"] = Dg.bottlenecks(cand, res, L.folds, L.seeds, L.bins,
                                             float(L.lim["steep_slope_deg"]),
                                             float(ic.cost_fn_over_fp), L.coverage)
    # 2 --------------------------------------------------------------- A/A
    log.info("=== 2: A/A noise calibration ===")
    champ["noise"] = L.calibrate_noise(cand, res)
    R["noise"] = {"initial": {k: v for k, v in champ["noise"].items()}}

    entries = []
    # 3 ------------------------------------------------------- round 0: correctness
    log.info("=== 3: round 0 — correctness fixes ===")
    n_versions = 0
    for e in [x for x in exps if int(x["round"]) == 0]:
        if not runnable(e, champ):
            continue
        ent = L.evaluate(e, champ, 0)
        entries.append(ent)
        if ent["decision"] == Dc.ACCEPT:
            n_versions += 1
            champ = L.promote(champ, ent, f"{champ['version']}+{e['id']}")
    R["noise"]["round1"] = {k: v for k, v in champ["noise"].items()}

    # 4 ----------------------------------------------------- round 1: the backlog
    log.info("=== 4: round 1 — backlog against %s ===", champ["version"])
    r1 = [L.evaluate(e, champ, 1) for e in exps
          if int(e["round"]) == 1 and runnable(e, champ)]
    entries += r1

    # 5 ------------------------------------------------- round 2: greedy composition
    log.info("=== 5: round 2 — compose accepted changes ===")
    accepted = Dc.rank_accepted([e for e in r1 if e["decision"] == Dc.ACCEPT])
    budget = int(ic.max_accepts_per_campaign)
    for i, ent in enumerate(accepted):
        if len(champ["lineage"]) - n_versions >= budget:
            log.info("  accept budget (%d) reached — %s deferred to next campaign", budget, ent["id"])
            break
        if i > 0:
            try:
                ent = L.evaluate(next(x for x in exps if x["id"] == ent["id"]), champ, 2)
            except ValueError as err:          # change no longer applicable
                log.info("  %s not composable with %s: %s", ent["id"], champ["version"], err)
                continue
            entries.append(ent)
            if ent["decision"] != Dc.ACCEPT:
                continue
        champ = L.promote(champ, ent, f"{champ['version']}+{ent['id']}")

    # 6 ------------------------------------------------- materialise the champion
    changed = bool(champ["lineage"])
    version = _next_version(start["version"]) if changed else start["version"]
    log.info("=== 6: champion = %s (%s) ===", version,
             " + ".join(x["id"] for x in champ["lineage"]) or "unchanged")
    R["bottlenecks_after"] = Dg.bottlenecks(champ["cand"], champ["res"], L.folds, L.seeds,
                                            L.bins, float(L.lim["steep_slope_deg"]),
                                            float(ic.cost_fn_over_fp), L.coverage)
    p_cal = Dg.calibrated_oof(champ["cand"], champ["res"], L.folds, L.bins)
    ops = Dg.operating_points(champ["cand"], p_cal, float(L.lim["steep_slope_deg"]),
                              tuple(ic.operating_coverage))
    ops.to_csv(L.rdir / "operating_points.csv", index=False)
    R["operating_points"] = ops.to_dict("records")
    m = np.isfinite(p_cal)
    cc = thr_mod.cost_curve(champ["cand"].data.y[m], p_cal[m],
                            list(L.cfg.optimize.threshold.cost_ratios),
                            float(L.cfg.optimize.threshold.fbeta))
    cc.to_csv(L.rdir / "dev_cost_curve.csv", index=False)
    R["dev_cost_curve"] = cc.to_dict("records")

    model = None
    if start["source"] == "stage9":
        # final_v2 was frozen by Stage 9 but never written to disk; keep it on record
        model = L.train_final(cand)
        L.save_artifact(start["version"], {**champ, "cand": cand, "res": res,
                                           "state": state, "lineage": []}, model,
                        {"status": "reconstructed by Stage 10 from config + seed",
                         "stage9_config_sha256_16": ic.champion.config_sha256_16})
    if changed:
        model = L.train_final(champ["cand"])
        L.save_artifact(version, champ, model, {
            "status": "DEV champion — not evaluated on the locked split",
            "release_requirement": ("pre-registration + a recorded opening of the locked "
                                    "split (the Stage 7 procedure)"),
            "dev_operating_threshold_fn_fp_10": float(
                cc.loc[cc.cost_fn_over_fp == 10, "threshold"].iloc[0])})
    elif model is None:
        model = L.train_final(cand)

    # 7 ------------------------------------------------------------- efficiency
    log.info("=== 7: efficiency frontier on %s ===", version)
    e = ic.efficiency
    trunc = Ef.truncation_frontier(champ["cand"].data, champ["res"], tuple(e.tree_fractions))
    dev_X = L.dev_X(champ["cand"])
    art = Ef.artifact_cost(model, dev_X, tuple(e.tree_fractions),
                           int(e.latency_rows), int(e.repeats), int(e.deployment_segments))
    frontier = trunc.drop(columns=["fold_AP"]).merge(art, on="tree_fraction")
    frontier.to_csv(L.rdir / "efficiency_frontier.csv", index=False)
    corridor = dev_X.sample(int(e.deployment_segments), replace=True,
                            random_state=int(L.cfg.seed)).reset_index(drop=True)
    grid = Ef.threads_batch_grid(model, corridor, tuple(e.threads), tuple(e.batches))
    grid.to_csv(L.rdir / "threads_batch_grid.csv", index=False)
    R["efficiency"] = {"frontier": frontier.to_dict("records"), "threads_batch": grid.to_dict("records"),
                       "peak_predict_mb_corridor": Ef.peak_predict_mb(model, corridor)}

    # 8 ---------------------------------------------------------------- registry
    reg = L.registry.load()
    reg = L.registry.ensure_version(reg, {
        "version": "final_v1", "config_sha256_16": "5c8ab2326f9c5b5c",
        "status": "known-leaked, superseded", "record": "reports/stage7/PREREGISTRATION.json"})
    if start["source"] == "stage9":
        reg = L.registry.ensure_version(reg, {
            "version": ic.champion.version, "config_sha256_16": ic.champion.config_sha256_16,
            "status": "champion", "record": str(ic.champion.stage9_prereg),
            "artifact": f"models/{ic.champion.version}/", "state": state,
            "per_seed_AP": L.per_seed_ap(res),
            "dev_threshold_fn_fp_20": R["reproduction"]["dev_threshold_reproduced"],
            "dev_mean_AP": float(res["mean_AP"]),
            "locked_split": "opened (Stage 9), see REMEDIATION.md"})
    if reg.get("champion") is None:
        reg["champion"] = start["version"]
    if changed:
        reg = L.registry.promote(reg, {
            "version": version, "status": "champion (dev)", "parent": start["version"],
            "state": champ["state"], "lineage": champ["lineage"],
            "artifact": f"models/{version}/", "campaign_id": L.campaign,
            # what the next campaign must reproduce before it measures anything
            "per_seed_AP": L.per_seed_ap(champ["res"]),
            "dev_threshold_fn_fp_20": L.dev_threshold(champ["cand"], champ["res"], 20.0),
            "dev_mean_AP_on_its_rows": float(champ["res"]["mean_AP"]),
            "locked_split": "NOT opened — release requires pre-registration"},
            "; ".join(f"{x['id']}: {x['reason']}" for x in champ["lineage"]))
    reg["last_campaign"] = {"id": L.campaign, "experiments": len(entries),
                            "accepted": [x["id"] for x in champ["lineage"]],
                            "ledger": str(L.cfg.paths.ledger)}
    L.registry.save(reg)
    R["registry"] = reg

    # 9 ------------------------------------------------------------------ report
    R["experiments"] = [{k: v for k, v in x.items() if not k.startswith("_")} for x in entries]
    R["champion"] = {"version": version, "state": champ["state"], "lineage": champ["lineage"],
                     "guard": champ["guard"], "mean_AP": champ["res"]["mean_AP"]}
    (L.rdir / "improve_results.json").write_text(dumps(R))
    _plots(R, L.rdir)
    _write_report(R, L)
    log.info("Stage 10 done in %.1fs -> %s", time.time() - t0, L.rdir)


def _next_version(v: str) -> str:
    import re
    m = re.fullmatch(r"(.*_v)(\d+)", v)
    return f"{m.group(1)}{int(m.group(2)) + 1}" if m else f"{v}_next"


# --------------------------------------------------------------------------- #
# Reporting
# --------------------------------------------------------------------------- #
KIND_COLOR = {"correctness": "#2a78d6", "superiority": "#eb6834", "simplification": "#1baf7a"}
INK, INK2, GRID = "#0b0b0b", "#52514e", "#e6e5e0"


def _plots(R: dict, rdir: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.size": 9, "axes.edgecolor": INK2, "axes.labelcolor": INK2,
                         "xtick.color": INK2, "ytick.color": INK2, "text.color": INK})

    ex = R["experiments"]
    floor = R["noise"]["round1"]["delta_floor"]
    fig, ax = plt.subplots(figsize=(8.2, 0.42 * len(ex) + 1.4))
    ax.axvspan(-floor, floor, color=GRID, zorder=0, lw=0)
    ax.axvline(0, color=INK2, lw=0.8, zorder=1)
    for i, e in enumerate(ex[::-1]):
        seeds = [r["mean_delta"] for r in e["comparison"]["per_seed"]]
        c = KIND_COLOR[e["kind"]]
        ax.plot([min(seeds), max(seeds)], [i, i], color=c, lw=2, solid_capstyle="round", zorder=2)
        ax.scatter([e["mean_delta"]], [i], s=46, color=c, edgecolor="white", lw=1.5, zorder=3)
        ax.text(1.01, i, e["decision"], transform=ax.get_yaxis_transform(), va="center",
                fontsize=8, color=INK if e["decision"] == "ACCEPT" else INK2,
                fontweight="bold" if e["decision"] == "ACCEPT" else "normal")
    ax.set_yticks(range(len(ex)))
    ax.set_yticklabels([e["name"] for e in ex[::-1]])
    ax.set_xlabel("Δ mean AP vs champion (dot = mean of 3 seeds, line = seed range)")
    ax.set_title(f"Stage 10 experiments — grey band = A/A noise floor (±{floor:.4f})",
                 loc="left", fontsize=10)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.grid(axis="x", color=GRID, lw=0.6)
    handles = [plt.Line2D([], [], marker="o", ls="", color=c, label=k) for k, c in KIND_COLOR.items()]
    ax.legend(handles=handles, loc="lower left", bbox_to_anchor=(0, 1.04), ncol=3,
              frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(rdir / "experiment_deltas.png", dpi=150)
    plt.close(fig)

    fr = pd.DataFrame(R["efficiency"]["frontier"])
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(8.2, 3.0))
    a1.plot(fr.n_trees, fr.pct_of_full_AP, color=KIND_COLOR["correctness"], lw=2, marker="o", ms=5)
    a1.set_xlabel("trees in the full-dev artifact")
    a1.set_ylabel("% of full-model AP (out-of-fold)")
    a1.set_title("Accuracy retained", loc="left", fontsize=10)
    a2.plot(fr.n_trees, fr.full_corridor_sec, color=KIND_COLOR["correctness"], lw=2, marker="o", ms=5)
    a2.set_xlabel("trees in the full-dev artifact")
    a2.set_ylabel("seconds per corridor pass (1 core)")
    a2.set_title("Latency (gate: 300 s)", loc="left", fontsize=10)
    for a in (a1, a2):
        for s in ("top", "right"):
            a.spines[s].set_visible(False)
        a.grid(color=GRID, lw=0.6)
        a.set_ylim(bottom=0)
    fig.tight_layout()
    fig.savefig(rdir / "efficiency_frontier.png", dpi=150)
    plt.close(fig)


def _f(x, fmt="{:.4f}"):
    try:
        return fmt.format(x) if x is not None and np.isfinite(x) else "—"
    except (TypeError, ValueError):
        return str(x)


def _write_report(R: dict, L: Loop) -> None:
    rp = R["reproduction"]
    n0, n1 = R["noise"]["initial"], R["noise"]["round1"]
    L_ = [
        "# Stage 10 — Continuous improvement: campaign results", "",
        f"Campaign `{R['campaign_id']}` · code `{R['fingerprint']['code_sha16']}` · "
        f"data `{R['fingerprint']['data_sha16']}` · LightGBM "
        f"{R['fingerprint']['env']['lightgbm']} · {R['fingerprint']['env']['machine']}", "",
        "Generated by `make stage10`. Dev spatial CV only — **the locked split was not read.** "
        "Interpretation and roadmap: `CONTINUOUS_IMPROVEMENT.md`. Every row below is a line "
        "in `EXPERIMENT_LEDGER.jsonl`.", "",
        f"## 0 — Champion reconstruction (`{R['start']['version']}`, verified against "
        f"{'Stage 9' if R['start']['source'] == 'stage9' else 'its registry record'})", "",
        f"| seed | Stage 9 v2 AP | reproduced | |", "|--|--|--|--|",
    ]
    for s in L.seeds:
        a, b = rp["per_seed_AP_expected"][s], rp["per_seed_AP_reproduced"][s]
        L_.append(f"| {s} | {a:.12f} | {b:.12f} | {'exact' if abs(a - b) < 1e-12 else 'MISMATCH'} |")
    L_ += ["", f"Pre-registered dev operating threshold `{rp['dev_threshold_expected']:.12f}` → "
           f"reproduced `{rp['dev_threshold_reproduced']:.12f}` "
           f"({'exact' if rp['dev_threshold_match'] else 'MISMATCH'}).", "",
           "## 1 — A/A noise calibration (champion vs itself, 6 seeds → 20 ordered splits)", "",
           "| champion | noise floor (q90 |Δ|) | worst-fold floor | max |Δ| | Stage 7/9 rule false-positive rate |",
           "|--|--|--|--|--|",
           f"| {R['start']['version']} | {n0['delta_floor']:.4f} | {n0['worst_fold_floor']:.4f} | "
           f"{n0['max_abs_mean_delta']:.4f} | {100 * n0['old_rule_false_positive_rate']:.0f}% |"]
    if n1 is not n0 and n1["delta_floor"] != n0["delta_floor"]:
        L_.append(f"| round-1 champion | {n1['delta_floor']:.4f} | {n1['worst_fold_floor']:.4f} | "
                  f"{n1['max_abs_mean_delta']:.4f} | {100 * n1['old_rule_false_positive_rate']:.0f}% |")

    L_ += ["", "## 2 — Bottlenecks (champion before → after this campaign)", "",
           "| pattern | metric | before | after |", "|--|--|--|--|"]
    b0, b1 = R["bottlenecks_before"], R["bottlenecks_after"]
    rows = [("memorisation", "in-sample / OOF AP", b0["memorisation"]["ratio"], b1["memorisation"]["ratio"]),
            ("memorisation", "OOF AP (seed 42)", b0["memorisation"]["oof_AP"], b1["memorisation"]["oof_AP"]),
            ("region", "worst fold AP", b0["region"]["worst_fold_AP"], b1["region"]["worst_fold_AP"]),
            ("region", "fold AP spread", b0["region"]["spread"], b1["region"]["spread"]),
            ("region", "worst region calibration ×", b0["region"]["worst_region_cal_ratio"], b1["region"]["worst_region_cal_ratio"]),
            ("steep", "steep ROC (OOF)", b0["steep"]["steep_roc"], b1["steep"]["steep_roc"]),
            ("steep", "non-steep ROC (OOF)", b0["steep"]["non_steep_roc"], b1["steep"]["non_steep_roc"]),
            ("steep", "steep lift@10%", b0["steep"]["steep_lift@10pct"], b1["steep"]["steep_lift@10pct"]),
            ("missed positives", "FN median 1-day rain (mm)", b0["missed_positives"]["fn_median_rain_1d"], b1["missed_positives"]["fn_median_rain_1d"]),
            ("missed positives", "TP median 1-day rain (mm)", b0["missed_positives"]["tp_median_rain_1d"], b1["missed_positives"]["tp_median_rain_1d"]),
            ("missed positives", "FN share on a dry day (<1 mm)", b0["missed_positives"]["fn_share_dry_day"], b1["missed_positives"]["fn_share_dry_day"]),
            ("calibration", "worst terrain stratum ×", b0["calibration"]["worst_terrain_cal_ratio"], b1["calibration"]["worst_terrain_cal_ratio"]),
            ("data integrity", "dev rows beyond rainfall record", b0["data_integrity"]["dev_rows_beyond_rainfall_record"],
             b1["data_integrity"]["dev_rows_beyond_rainfall_record"])]
    for p, mname, a, b in rows:
        fmt = "{:,.0f}" if "rows" in mname else "{:.4f}"
        L_.append(f"| {p} | {mname} | {_f(a, fmt)} | {_f(b, fmt)} |")
    L_ += ["", "Rows evaluated differ between the two columns if a correctness fix changed the "
           "target; see §3.", "",
           "## 3 — Experiments", "",
           "| # | experiment | kind | layer | Δ AP | folds+ | seeds+ | p | worst fold | steep ROC Δ | "
           "cal × | decision |", "|--|--|--|--|--|--|--|--|--|--|--|--|"]
    for i, e in enumerate(R["experiments"], 1):
        c, g = e["comparison"], e["guardrails"]
        L_.append(f"| {i} | `{e['name']}` | {e['kind']} | {e['layer']} | {c['mean_delta']:+.4f} | "
                  f"{c['folds_improved']}/5 | {c['seeds_positive']}/{c['n_seeds']} | "
                  f"{c['p_value']:.3f} | {c['worst_fold_delta']:+.4f} | "
                  f"{g['challenger']['steep_roc'] - g['champion']['steep_roc']:+.4f} | "
                  f"{g['challenger']['worst_terrain_cal_ratio']:.2f} | **{e['decision']}** |")
    L_ += ["", "### Reasons (verbatim from the ledger)", ""]
    for e in R["experiments"]:
        L_.append(f"- **{e['name']}** — {e['reason']}")
        if e.get("eval_target_effect"):
            t = e["eval_target_effect"]
            L_.append(f"  - target correction: champion AP {t['champion_AP_original_rows']:.4f} on the "
                      f"original rows → {t['champion_AP_corrected_rows']:.4f} on the corrected rows "
                      f"({t['rows_removed_from_eval']:,} rows removed from evaluation); "
                      f"measurement inflation **{t['measurement_inflation']:+.4f}** AP")
    if R.get("skipped"):
        L_ += ["", "### Not run this campaign", ""]
        L_ += [f"- `{x['id']}` — {x['why']}" for x in R["skipped"]]
    L_ += ["", "### Cost of each challenger", "",
           "| experiment | trees (mean fold model) | size MB | corridor s | monotonicity violations |",
           "|--|--|--|--|--|"]
    for e in R["experiments"]:
        g = e["guardrails"]["challenger"]
        L_.append(f"| `{e['name']}` | {g['mean_trees']:.0f} | {g['model_mb']:.2f} | "
                  f"{g['corridor_sec']:.2f} | {g['monotonicity_violations']} |")

    ch = R["champion"]
    L_ += ["", "## 4 — Champion", "",
           f"**{ch['version']}** — " + (" → ".join(["final_v2", *[x["id"] for x in ch["lineage"]]])
                                        if ch["lineage"] else "unchanged from final_v2"), ""]
    for x in ch["lineage"]:
        L_.append(f"- `{x['id']}` ({x['kind']}): {x['reason']}")
    L_ += ["", "## 5 — Efficiency frontier (full-dev artifact; accuracy out-of-fold)", "",
           "| tree fraction | trees | size KB | µs/row | corridor s | % of full AP | Δ AP | worst fold Δ |",
           "|--|--|--|--|--|--|--|--|"]
    for r in R["efficiency"]["frontier"]:
        L_.append(f"| {r['tree_fraction']:.2f} | {r['n_trees']} | {r['model_kb']} | {r['per_row_us']} | "
                  f"{r['full_corridor_sec']} | {r['pct_of_full_AP']:.1f}% | {r['delta_vs_full']:+.4f} | "
                  f"{r['worst_fold_delta']:+.4f} |")
    L_ += ["", "### Threads × batch size, one full corridor pass (309,042 rows)", "",
           "| threads | " + " | ".join(f"batch {b:,}" for b in L.ic.efficiency.batches) + " |",
           "|--|" + "--|" * len(L.ic.efficiency.batches)]
    g = pd.DataFrame(R["efficiency"]["threads_batch"])
    for t in L.ic.efficiency.threads:
        vals = [g[(g.threads == t) & (g.batch_rows == b)].corridor_sec.iloc[0]
                for b in L.ic.efficiency.batches]
        L_.append(f"| {t} | " + " | ".join(f"{v:.3f} s" for v in vals) + " |")
    L_ += ["", f"Peak Python allocation scoring the whole corridor in one call: "
           f"{R['efficiency']['peak_predict_mb_corridor']} MB.", "",
           "## 6 — Dev operating points (cross-fitted per-slope calibration, seed 42)", "",
           "Optimistic by construction: dev lift was 4.5× where the locked split gave 2.2×. "
           "Use to choose k, then validate on the next pre-registered opening.", "",
           "| population | coverage | alerts | precision | recall | lift |", "|--|--|--|--|--|--|"]
    for r in R["operating_points"]:
        L_.append(f"| {r['population']} | {100 * r['coverage']:.1f}% | {r['alerts']:,} | "
                  f"{r['precision']:.3f} | {r['recall']:.3f} | {r['lift']:.2f}× |")
    L_ += ["", "![experiments](experiment_deltas.png)", "", "![frontier](efficiency_frontier.png)", ""]
    (L.rdir / "IMPROVEMENT_REPORT.md").write_text("\n".join(L_))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
