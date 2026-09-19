"""Open the locked `final_test` split — ONCE — and report the pre-registered metrics.

This is the only module in the repository permitted to read `final_test`. Every
other stage is guarded by tests that fail if it is touched.

The protocol, and why each part exists
--------------------------------------
1. **Pre-registration is mandatory.** `reports/stage7/PREREGISTRATION.json` must
   already exist. It pins a hash of the final configuration and the exact list of
   metrics, written before any test row was read. Without it, "the test number" is
   just whichever variant happened to look best after the fact.

2. **The ledger records every opening.** `TEST_SET_LEDGER.json` accumulates an entry
   per run with the config hash and the resulting AP. A second opening is not
   blocked — sometimes a genuine bug must be fixed — but it is *recorded*, and the
   report says how many times the split has been read. An unbiased estimate comes
   from opening it once; the ledger makes any departure from that visible instead of
   invisible.

3. **Nothing is selected here.** No threshold search, no calibrator choice, no
   config variation. Every such decision was frozen in the pre-registration and is
   read back out of it.

4. **The calibrator is fitted on dev out-of-fold scores**, not on the final model's
   own training predictions — the latter are in-sample and would look perfectly
   calibrated while transferring nothing.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score

from sih_ml.eval.metrics import ranking_report
from sih_ml.models.calibration import Calibrator
from sih_ml.models.dataset import Data, load_data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.optimize import calibrate as cal_mod
from sih_ml.optimize.harness import identity_trainset
from sih_ml.train import cv
from sih_ml.utils.common import (REPO_ROOT, Config, get_logger, git_sha, resolve,
                                 set_seed)

log = get_logger("stage7.final")


def _rebuild_arm(cfg: Config, steps: list[str]):
    """Reconstruct the winning training-row transform from the frozen step list."""
    if not steps:
        return None
    from sih_ml.train.run_optimize import _composite_from
    arm, _ = _composite_from(cfg, steps, "final/frozen")
    return arm


def train_final(data: Data, cfg: Config, prereg: dict, seed: int):
    """Fit the frozen configuration on ALL dev rows (everything except final_test)."""
    fin = prereg["final_config"]
    dev = np.where(data.dev_mask())[0]
    m_tr, m_es = cv.make_es_split(data, dev, cfg, seed)
    tr, es = dev[m_tr], dev[m_es]

    arm = _rebuild_arm(cfg, fin.get("composite_steps", []))
    ts = (arm.transform if arm and arm.transform else identity_trainset)(data, tr, 0, seed)

    p = dict(fin["lgbm"])
    p["seed"] = seed
    fobj = None
    if arm is not None and arm.objective == "focal":
        from sih_ml.optimize.losses import make_focal_objective
        fobj = make_focal_objective(**arm.objective_kwargs)

    model = LGBMBaseline(p, data.features, data.categorical,
                         list(p.get("monotone_rainfall_features", [])))
    spw = None if fobj is not None else (
        cv._scale_pos_weight(ts.y) * float(p.get("scale_pos_weight_mult", 1.0)))
    model.fit(ts.X, ts.y, ts.w, data.X(es), data.y[es], data.w[es],
              scale_pos_weight=spw, fobj=fobj)
    log.info("final fit: %d train rows (%d pos), %d ES rows, best_iter=%d",
             len(ts.y), int(ts.y.sum()), len(es), model.best_iteration_)
    return model, tr, es


def fit_dev_calibrator(cfg: Config, prereg: dict, data: Data, rdir: Path):
    """Fit the frozen calibrator variant on the Stage 7 dev OOF scores."""
    oof_path = rdir / "oof_selected.parquet"
    if not oof_path.exists():
        log.warning("no oof_selected.parquet — shipping uncalibrated scores")
        return None, None
    oof = pd.read_parquet(oof_path)
    bins = list(cfg.optimize.calibration.slope_bins)
    variant = prereg["final_config"].get("calibration", "global_isotonic")

    key = pd.MultiIndex.from_frame(data.panel[["segment_id", "date"]])
    oof_key = pd.MultiIndex.from_frame(oof[["segment_id", "date"]])
    pos = pd.Series(np.arange(len(data.panel)), index=key).reindex(oof_key).to_numpy()
    slope_all = cal_mod.slope_stratum(data, bins)
    strata = slope_all[pos.astype(int)]

    y, s = oof["target"].to_numpy(int), oof["score"].to_numpy(float)
    prior = float(y.mean())
    pooled = Calibrator("isotonic").fit(s, y, prior, None)
    if variant != "per_slope_isotonic":
        return pooled, None
    per = {}
    for st in np.unique(strata):
        m = strata == st
        if m.sum() >= 200 and y[m].sum() >= 20:
            per[int(st)] = Calibrator("isotonic").fit(s[m], y[m], float(y[m].mean()), None)
    log.info("per-slope calibrators fitted for strata %s (pooled fallback elsewhere)",
             sorted(per))
    return pooled, per


def apply_calibrator(p: np.ndarray, strata: np.ndarray, pooled, per) -> np.ndarray:
    if pooled is None:
        return p
    out = pooled.transform(p)
    if per:
        for st, c in per.items():
            m = strata == st
            if m.any():
                out[m] = c.transform(p[m])
    return out


def main(config_path: str | None = None, force: bool = False) -> None:
    cfg_path = Path(config_path) if config_path else REPO_ROOT / "conf" / "optimize_config.yaml"
    if not cfg_path.is_absolute():
        cfg_path = REPO_ROOT / cfg_path
    data, cfg = load_data(cfg_path)
    set_seed(cfg.seed)
    rdir = resolve(cfg, cfg.paths.reports)

    prereg_path = rdir / "PREREGISTRATION.json"
    if not prereg_path.exists():
        raise SystemExit(
            f"REFUSING to open the locked test set: {prereg_path} does not exist.\n"
            "Run `make stage7` first — it freezes the configuration and the metric "
            "list BEFORE any test row is read. Opening the test without that file "
            "would make the number unfalsifiable."
        )
    prereg = json.loads(prereg_path.read_text())
    fin = prereg["final_config"]
    h = hashlib.sha256(json.dumps(fin, sort_keys=True, default=str).encode()).hexdigest()[:16]
    if h != prereg["config_sha256_16"]:
        log.warning("config hash drift: pre-registered %s, recomputed %s",
                    prereg["config_sha256_16"], h)

    ledger_path = REPO_ROOT / cfg.final_test.ledger
    ledger = json.loads(ledger_path.read_text()) if ledger_path.exists() else {"openings": []}
    n_prior = len(ledger["openings"])
    if n_prior:
        log.warning("=" * 78)
        log.warning("THE LOCKED TEST SET HAS ALREADY BEEN OPENED %d TIME(S).", n_prior)
        log.warning("Prior: %s", [(o["utc"][:19], o["config_sha256_16"],
                                   round(o["average_precision"], 4))
                                  for o in ledger["openings"]])
        log.warning("This run is NOT an unbiased estimate. Report it as a re-opening.")
        log.warning("=" * 78)

    # ------------------------------------------------------------------ train
    log.info("training the frozen configuration on all dev rows")
    model, tr, es = train_final(data, cfg, prereg, cfg.seed)

    # ------------------------------------------------- OPEN THE LOCKED SPLIT
    te = data.final_test_index()
    log.info("opening final_test: %d rows, %d positives (%d gold)", len(te),
             int(data.y[te].sum()),
             int((data.panel["label_tier"].to_numpy()[te] == "gold").sum()))
    raw = model.predict(data.X(te))

    bins = list(cfg.optimize.calibration.slope_bins)
    pooled, per = fit_dev_calibrator(cfg, prereg, data, rdir)
    strata_all = cal_mod.slope_stratum(data, bins)
    p = apply_calibrator(raw, strata_all[te], pooled, per)
    y = data.y[te]

    # --------------------------------------------- pre-registered metrics only
    rep = ranking_report(y, p, ks=tuple(cfg.eval.precision_at_k),
                         lifts=tuple(cfg.eval.top_frac_for_lift))
    thr = float(fin.get("operating_threshold") or 0.5)
    yhat = (p >= thr).astype(int)
    tp = int(((yhat == 1) & (y == 1)).sum()); fp = int(((yhat == 1) & (y == 0)).sum())
    fn = int(((yhat == 0) & (y == 1)).sum()); tn = int(((yhat == 0) & (y == 0)).sum())
    prec = tp / max(1, tp + fp); rec = tp / max(1, tp + fn)
    rep["frozen_threshold"] = thr
    rep.update({"tp": tp, "fp": fp, "fn": fn, "tn": tn, "precision": prec,
                "recall": rec, "f1": 2 * prec * rec / max(1e-9, prec + rec)})

    # steep terrain — the Stage 5 §1 metric that actually describes operational value
    steep = np.nan_to_num(data.panel["slope_mean_deg"].to_numpy(float)[te], nan=0.0) >= 10.0
    if steep.sum() and y[steep].sum():
        base = float(y[steep].mean())
        k = max(1, int(0.10 * steep.sum()))
        top = np.argsort(-p[steep])[:k]
        rep["steep_AP"] = float(average_precision_score(y[steep], p[steep]))
        rep["steep_base_rate"] = base
        rep["steep_lift@10pct"] = float(y[steep][top].mean() / base) if base else float("nan")
        rep["steep_n"] = int(steep.sum())
        rep["steep_roc_auc"] = (float(roc_auc_score(y[steep], p[steep]))
                                if 0 < y[steep].sum() < steep.sum() else float("nan"))

    cal_tab = _test_calibration_table(data, te, y, p, bins)

    # gold rows — the only verified labels in the project
    gold = data.panel["label_tier"].to_numpy()[te] == "gold"
    rep["n_gold"] = int(gold.sum())
    if gold.sum():
        rep["gold_scores"] = [float(x) for x in p[gold]]
        rep["gold_percentile"] = [float((p < x).mean()) for x in p[gold]]

    # ----------------------------------------------------------------- record
    out = {
        "opened_utc": pd.Timestamp.utcnow().isoformat(),
        "opening_number": n_prior + 1,
        "config_sha256_16": prereg["config_sha256_16"],
        "git_sha": git_sha(),
        "n_test_rows": int(len(te)), "n_test_pos": int(y.sum()),
        "dev_estimate": prereg.get("dev_estimate", {}),
        "metrics": rep,
        "calibration_on_test": cal_tab.to_dict("records"),
    }
    (rdir / "FINAL_TEST_RESULTS.json").write_text(json.dumps(out, indent=2, default=float))
    cal_tab.to_csv(rdir / "final_test_calibration.csv", index=False)

    ledger["openings"].append({
        "utc": out["opened_utc"],
        # "decision" = an opening whose result could influence a choice. Stage 8's
        # reporting reads are recorded as kind="report" so the count of genuine
        # decision openings stays visible and stays at one.
        "kind": "decision",
        "config_sha256_16": prereg["config_sha256_16"],
        "git_sha": out["git_sha"], "average_precision": rep["average_precision"],
        "n_rows": int(len(te)),
    })
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    ledger_path.write_text(json.dumps(ledger, indent=2))

    mdir = resolve(cfg, cfg.paths.models) / "final_v1"
    mdir.mkdir(parents=True, exist_ok=True)
    model.save(mdir / "final_model.txt")
    if pooled is not None:
        pooled.save(mdir / "calibrator_pooled.pkl")
        for st, c in (per or {}).items():
            c.save(mdir / f"calibrator_slope_{st}.pkl")
    (mdir / "model_card.json").write_text(json.dumps({
        "model": "LightGBM + per-slope isotonic calibration",
        "frozen_config": prereg["final_config"],
        "config_sha256_16": prereg["config_sha256_16"],
        "trained_on": "all dev rows (everything outside the locked final_test)",
        "n_train_rows": int(len(tr)), "n_earlystop_rows": int(len(es)),
        "best_iteration": int(model.best_iteration_),
        "test_metrics": rep,
        "intended_use": ("per-road-segment-per-day disruption risk for the "
                         "Chicken's Neck / Siliguri corridor; output feeds the "
                         "routing edge penalty W = dist*(1 + lambda*P)"),
        "known_limitations": [
            "All training positives are WEAK labels (silver/bronze); only 3 verified "
            "closures exist and they are in this test split.",
            "Region calibration does not transfer: predicted/observed varies ~3.5x "
            "across spatial folds and cannot be corrected at inference.",
            "Rainfall is CHIRPS ~25 km daily and cannot resolve valley-scale "
            "cloudbursts; Stage 5 attributed the dominant false-negative mode to this.",
            "The FN:FP = 20 cost ratio behind the threshold is an unvalidated "
            "placeholder; Stage 7 measured FN:FP = 10 as strictly better.",
        ],
    }, indent=2, default=float))
    _write_report(out, prereg, cal_tab, rdir, n_prior)

    log.info("=" * 78)
    log.info("FINAL TEST  AP=%.4f  ROC=%.4f  Brier=%.4f  ECE=%.4f",
             rep["average_precision"], rep["roc_auc"], rep["brier"], rep["ece"])
    log.info("            P@100=%.3f  lift@10pct=%.2fx  steep AP=%.4f",
             rep.get("precision@100", float("nan")), rep.get("lift@10pct", float("nan")),
             rep.get("steep_AP", float("nan")))
    log.info("            at frozen threshold %.4f: P=%.3f R=%.3f F1=%.3f",
             thr, prec, rec, rep["f1"])
    log.info("=" * 78)


def _test_calibration_table(data: Data, te, y, p, bins) -> pd.DataFrame:
    s = np.nan_to_num(data.panel["slope_mean_deg"].to_numpy(float)[te], nan=0.0)
    rows = []
    for i in range(len(bins) - 1):
        lo, hi = bins[i], bins[i + 1]
        m = (s >= lo) & (s < hi)
        if m.sum() < 30:
            continue
        obs = float(y[m].mean())
        rows.append({"stratum": f"slope [{lo:g}, {hi:g})", "n": int(m.sum()),
                     "n_pos": int(y[m].sum()), "predicted": float(p[m].mean()),
                     "observed": obs,
                     "pred_over_obs": float(p[m].mean() / obs) if obs > 0 else np.nan})
    rows.append({"stratum": "all", "n": int(len(y)), "n_pos": int(y.sum()),
                 "predicted": float(p.mean()), "observed": float(y.mean()),
                 "pred_over_obs": float(p.mean() / y.mean()) if y.mean() else np.nan})
    return pd.DataFrame(rows)


def dev_reference(rdir: Path) -> dict:
    """Dev-side AP / ROC / base rate for the selected scorer, from its saved OOF.

    Reads only dev rows, so it can be recomputed any time without touching the
    locked split.
    """
    p = rdir / "oof_selected.parquet"
    if not p.exists():
        return {}
    oof = pd.read_parquet(p)
    y, s = oof["target"].to_numpy(int), oof["score"].to_numpy(float)
    if not y.sum():
        return {}
    return {"AP": float(average_precision_score(y, s)),
            "roc_auc": float(roc_auc_score(y, s)),
            "base_rate": float(y.mean()), "n": int(len(y))}


def render_report(cfg_path: str | None = None) -> None:
    """Re-render FINAL_TEST_REPORT.md from the SAVED results JSON.

    Exists so the write-up can be corrected without re-opening the locked split —
    re-running `main()` to fix prose would append a second entry to the ledger and
    destroy the one property the split was held back for.
    """
    from sih_ml.utils.common import load_config_with_base
    cfg = load_config_with_base(Path(cfg_path) if cfg_path
                                else REPO_ROOT / "conf" / "optimize_config.yaml")
    rdir = resolve(cfg, cfg.paths.reports)
    out = json.loads((rdir / "FINAL_TEST_RESULTS.json").read_text())
    prereg = json.loads((rdir / "PREREGISTRATION.json").read_text())
    cal_tab = pd.DataFrame(out["calibration_on_test"])
    _write_report(out, prereg, cal_tab, rdir, out["opening_number"] - 1)
    log.info("re-rendered FINAL_TEST_REPORT.md from saved results (test NOT reopened)")


def _write_report(out: dict, prereg: dict, cal_tab: pd.DataFrame, rdir: Path,
                  n_prior: int) -> None:
    m = out["metrics"]
    dev = out["dev_estimate"].get("spatial_cv_mean_AP")
    ref = dev_reference(rdir)
    L = [
        "# Stage 7/8 — Final model on the locked test set", "",
        f"Opened **{out['opened_utc'][:19]} UTC** · opening #{out['opening_number']} · "
        f"config `{out['config_sha256_16']}` · git `{out['git_sha']}`", "",
    ]
    if n_prior:
        L += ["> **This is not the first opening of the locked split.** The number "
              "below is therefore no longer an unbiased estimate — every prior "
              "opening is recorded in `TEST_SET_LEDGER.json`.", ""]
    else:
        L += ["This split has been held out since Stage 2 and was read for the first "
              "time by this run. The configuration and this metric list were frozen "
              "in `PREREGISTRATION.json` beforehand.", ""]
    L += [f"Test set: **{out['n_test_rows']:,} rows**, {out['n_test_pos']:,} positives, "
          f"{m.get('n_gold', 0)} gold (verified) labels.", "",
          "## Headline", "", "| metric | value |", "|--|--|",
          f"| **Average precision (PR-AUC)** | **{m['average_precision']:.4f}** |",
          f"| ROC-AUC | {m['roc_auc']:.4f} |",
          f"| Brier | {m['brier']:.4f} |", f"| ECE | {m['ece']:.4f} |",
          f"| base rate | {m['base_rate']:.4f} |"]
    if dev and ref:
        gap = m["average_precision"] - dev
        dev_lift = ref["AP"] / ref["base_rate"]
        test_lift = m["average_precision"] / m["base_rate"]
        L += ["", "### Dev vs test — read the base rates before the APs", "",
              "| | dev (spatial-CV OOF) | locked test |", "|--|--|--|",
              f"| rows | {ref['n']:,} | {out['n_test_rows']:,} |",
              f"| base rate | {ref['base_rate']:.4f} | **{m['base_rate']:.4f}** |",
              f"| average precision (pooled) | {ref['AP']:.4f} | {m['average_precision']:.4f} |",
              f"| **AP / base rate** | **{dev_lift:.2f}×** | **{test_lift:.2f}×** |",
              f"| ROC-AUC (base-rate independent) | {ref['roc_auc']:.4f} | "
              f"**{m['roc_auc']:.4f}** |", "",
              f"*(The pre-registered dev figure, {dev:.4f}, is the **mean of the five "
              f"per-fold APs** — the quantity the decision rule used. {ref['AP']:.4f} "
              "is the **pooled** OOF AP, which is the like-for-like comparator for a "
              "single test pool. Both are quoted so neither can be swapped in for the "
              "other.)*", "",
              f"Raw AP barely moves ({dev:.4f} → {m['average_precision']:.4f}, "
              f"{gap:+.4f}) and that is **a coincidence, not evidence of transfer**. "
              f"The locked split is {m['base_rate'] / ref['base_rate']:.1f}× denser in "
              "positives than the dev panel — it holds all 3 gold labels and was built "
              "as a spatially separate block set — and average precision scales with "
              "the base rate, so the same AP means substantially *less* skill there.", "",
              f"The base-rate-free comparisons both show real degradation: lift over "
              f"chance **{dev_lift:.2f}× → {test_lift:.2f}×**, ROC-AUC "
              f"**{ref['roc_auc']:.4f} → {m['roc_auc']:.4f}**.", "",
              "That gap mixes two causes that cannot be separated with one test split: "
              "selection bias (the dev number was used to choose among ~25 arms) and "
              "genuine distribution shift (a different region, a different label mix). "
              "Quoting the flat AP as \"the model generalizes\" would be the single "
              "most misleading sentence available here.", ""]
    L += ["", "## Ranking", "", "| k | precision@k | recall@k |", "|--|--|--|"]
    for k in (10, 50, 100, 200):
        if f"precision@{k}" in m:
            L.append(f"| {k} | {m[f'precision@{k}']:.3f} | {m[f'recall@{k}']:.3f} |")
    L += ["", "| top fraction | lift |", "|--|--|"]
    for f in (1, 5, 10):
        if f"lift@{f}pct" in m:
            L.append(f"| {f}% | {m[f'lift@{f}pct']:.2f}× |")
    if "steep_AP" in m:
        sl = m["steep_AP"] / m["steep_base_rate"] if m["steep_base_rate"] else float("nan")
        L += ["", "## Steep terrain (slope ≥ 10°) — the operational number", "",
              "Stage 5 §1 established that global AP is inflated by separating plains "
              "from hills, which routing already knows for free. This is the subset "
              "where decisions actually happen.", "",
              f"- rows: **{m['steep_n']:,}**, base rate **{m['steep_base_rate']:.4f}**",
              f"- AP **{m['steep_AP']:.4f}** → lift over chance **{sl:.2f}×**",
              f"- **ROC-AUC {m.get('steep_roc_auc', float('nan')):.4f}**",
              f"- lift in the top 10% of scores: **{m['steep_lift@10pct']:.2f}×**", "",
              f"**This is the weakest result in the report and the most important one.** "
              f"A ROC-AUC of {m.get('steep_roc_auc', float('nan')):.3f} on steep terrain "
              "is close to chance (0.5): once the model is confined to the roads that "
              "actually fail, it can barely rank them. The healthy-looking global "
              "numbers above are carried by telling plains from hills.", "",
              "Stage 5 measured 1.63× steep-terrain lift on dev and flagged it as the "
              "finding that mattered most; the locked test confirms it independently. "
              "This is the number a judge should be shown, and it is the number that "
              "higher-resolution rainfall (Stage 5 P1) is meant to move.", ""]
    L += ["## At the frozen operating threshold", "",
          f"threshold **{m['frozen_threshold']:.4f}** (frozen before opening; "
          "derived from the FN:FP cost policy, which is still unvalidated)", "",
          "| | value |", "|--|--|",
          f"| precision | {m['precision']:.3f} |", f"| recall | {m['recall']:.3f} |",
          f"| F1 | {m['f1']:.3f} |",
          f"| TP / FP / FN / TN | {m['tp']} / {m['fp']} / {m['fn']} / {m['tn']} |", ""]
    if m.get("n_gold"):
        pcts = m["gold_percentile"]
        L += ["## The 3 verified labels", "",
              f"The only *verified* road closures in the entire project sit in this "
              f"split. They scored at percentiles "
              + ", ".join(f"**{x:.2%}**" for x in pcts)
              + f" — all three in the **top {100 * (1 - min(pcts)):.1f}%** of "
              f"{out['n_test_rows']:,} test rows.", "",
              "This is the most encouraging number in the project and it carries "
              "**no statistical weight whatsoever**: n = 3. It is reported because "
              "these are the only ground-truth labels that exist, and suppressing "
              "them would be as dishonest as over-claiming them. It is consistent "
              "with the model being useful at the top of the ranking; it is not "
              "evidence of it.", ""]
    L += ["## Calibration on the test set", "",
          "| stratum | n | pos | predicted | observed | pred/obs |", "|--|--|--|--|--|--|"]
    for _, r in cal_tab.iterrows():
        L.append(f"| {r.stratum} | {r.n:,} | {r.n_pos:,} | {r.predicted:.4f} | "
                 f"{r.observed:.4f} | {r.pred_over_obs:.2f}× |")
    allrow = cal_tab[cal_tab.stratum == "all"]
    overall = float(allrow.pred_over_obs.iloc[0]) if len(allrow) else float("nan")
    w = cal_tab[cal_tab.stratum != "all"].pred_over_obs
    worst = float(np.max(np.maximum(w, 1 / w))) if len(w) else float("nan")
    L += ["", "**The per-slope calibration fix does not survive the region shift.** "
          f"Cross-fitted *within* dev it brought the worst terrain stratum to 1.32× "
          f"(Stage 7 §6); on the locked split the worst stratum is **{worst:.2f}×**, "
          f"the model under-predicts overall at **{overall:.2f}×**, and test ECE is "
          f"{m['ece']:.4f} against 0.0193 on dev.", "",
          "This is the documented limitation arriving exactly as predicted: a "
          "calibrator can condition on terrain, which travels with the row, but not "
          "on *region* — a model scoring a new area cannot look up its own base rate. "
          "**Calibrated probabilities should not be trusted as absolute risk on "
          "unseen terrain**, which directly constrains the routing penalty "
          "`W = dist·(1 + λ·P)`. Use the ranking; re-fit the calibrator on local "
          "history before trusting the magnitude.", ""]
    L += ["", "## Frozen configuration", "", "```json",
          json.dumps(prereg["final_config"], indent=2, default=str), "```", ""]
    (rdir / "FINAL_TEST_REPORT.md").write_text("\n".join(L))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
