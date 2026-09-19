"""Stage 5 orchestrator — evaluation + error analysis on genuinely held-out data.

    python -m sih_ml.eval.run_error_analysis [conf/train_config.yaml]

Uses the Stage 4 spatial-CV OOF predictions (every row scored by a model that did
not train on it) plus a fresh temporal out-of-time fit and in-sample scores.
The locked `final_test` split is deliberately NOT opened — see ERROR_ANALYSIS.md.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.eval import error_analysis as ea
from sih_ml.eval import plots
from sih_ml.eval.metrics import confusion_at, cost_optimal_threshold, ranking_report
from sih_ml.models.dataset import load_data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.train import cv
from sih_ml.utils.common import REPO_ROOT, get_logger, resolve, set_seed

log = get_logger("stage5")

META_COLS = ["segment_id", "date", "target", "label_tier", "label_confidence", "hazard",
             "label_source", "event_id", "persist_day", "snap_dist_m", "seg_lon", "seg_lat"]


def main(config_path: str | None = None) -> None:
    t0 = time.time()
    cfg_path = Path(config_path) if config_path else REPO_ROOT / "conf" / "train_config.yaml"
    if not cfg_path.is_absolute():
        cfg_path = REPO_ROOT / cfg_path
    data, mcfg = load_data(cfg_path)
    set_seed(mcfg.seed)

    mdir = resolve(mcfg, mcfg.paths.models) / mcfg.model_version
    rdir = resolve(mcfg, "reports/stage5")
    rdir.mkdir(parents=True, exist_ok=True)

    # ---------------------------------------------------------------- assemble
    oof = pd.read_parquet(mdir / "oof_predictions.parquet")
    keep = [c for c in data.panel.columns if c not in ("p_raw", "p_cal")]
    df = oof[["segment_id", "date", "p_raw", "p_cal", "spatial_fold"]].merge(
        data.panel[keep], on=["segment_id", "date"], how="left", suffixes=("", "_panel"))
    log.info("OOF joined: %d rows, %d positives, tiers=%s",
             len(df), int(df.target.sum()), df.label_tier.value_counts().to_dict())

    # operating threshold from the Stage 4 cost policy, recomputed on these rows
    thr_info = cost_optimal_threshold(df.target.to_numpy(int), df.p_cal.to_numpy(float),
                                      mcfg.eval.cost_fn_over_fp, mcfg.eval.fbeta)
    thr = thr_info["cost_threshold"]
    cm = confusion_at(df.target.to_numpy(int), df.p_cal.to_numpy(float), thr)
    log.info("operating threshold %.4f -> P=%.3f R=%.3f (TP=%d FP=%d FN=%d)",
             thr, cm["precision"], cm["recall"], cm["tp"], cm["fp"], cm["fn"])

    results: dict = {"operating_point": {**thr_info, "confusion": cm},
                     "cost_fn_over_fp": mcfg.eval.cost_fn_over_fp,
                     "overall_oof": ranking_report(df.target.to_numpy(int),
                                                   df.p_cal.to_numpy(float))}

    # ---------------------------------------------------------- A: strata
    log.info("A. stratified performance")
    strat = ea.stratified_performance(df)
    strat.to_csv(rdir / "stratified_performance.csv", index=False)
    results["n_strata_reported"] = int(len(strat))

    # ---------------------------------------------------------- B: per-event
    log.info("B. per-event detection")
    per_event, det = ea.per_event_detection(df)
    per_event.to_csv(rdir / "per_event_detection.csv", index=False)
    results["per_event_detection"] = det

    # ---------------------------------------------------------- C: FN vs TP
    log.info("C. false-negative probe")
    fnp = ea.fn_vs_tp_probe(df, thr)
    fnp.to_csv(rdir / "fn_vs_tp_probe.csv", index=False)

    # ---------------------------------------------------------- D: FP structure
    log.info("D. false-positive structure")
    fp_by_seg, fp_sum = ea.fp_structure(df, thr)
    fp_by_seg.head(200).to_csv(rdir / "fp_top_segments.csv", index=False)
    results["false_positives"] = fp_sum

    # ---------------------------------------------------------- E: label noise
    log.info("E. label-noise ceiling probe")
    noise = ea.label_noise_probe(df)
    noise.to_csv(rdir / "label_noise_probe.csv", index=False)

    # ---------------------------------------------------------- F: data quality
    log.info("F. data-quality scan")
    dq = ea.data_quality_scan(df, data.features)
    results["data_quality"] = dq

    # ---------------------------------------------------------- G: train/val/test
    log.info("G. in-sample vs held-out vs out-of-time")
    final = LGBMBaseline.load(mdir / "final.txt")
    dev = np.where(data.dev_mask())[0]
    p_insample = final.predict(data.X(dev))
    gap = {
        "in_sample_dev": ranking_report(data.y[dev], p_insample),
        "held_out_spatial_oof": ranking_report(df.target.to_numpy(int), df.p_cal.to_numpy(float)),
    }
    tp_res = cv.run_temporal(data, mcfg, seed=mcfg.seed)
    te_idx, te_pred = tp_res["pred"]["test"]
    gap["out_of_time_test"] = ranking_report(data.y[te_idx], te_pred)
    results["generalization_gap"] = gap

    # ------------------------------------------------- G2: early-stopping integrity
    log.info("G2. early-stopping signal integrity")
    fold_models = {k: LGBMBaseline.load(mdir / f"fold_{k}.txt")
                   for k in range(mcfg.cv.n_spatial_folds)
                   if (mdir / f"fold_{k}.txt").exists()}
    if fold_models:
        sat = ea.es_signal_saturation(data, mcfg, fold_models)
        sat.to_csv(rdir / "es_signal_saturation.csv", index=False)
        results["es_signal"] = {
            "mean_AP_train": float(sat.AP_train.mean()),
            "mean_AP_earlystop": float(sat.AP_earlystop.mean()),
            "mean_AP_heldout_blocks": float(sat.AP_heldout_blocks.mean()),
            "verdict": ("SATURATED — early stopping has no usable validation signal"
                        if sat.AP_earlystop.mean() > 0.95 else "usable"),
        }
    leak = ea.es_leakage_units(data, mcfg)
    leak.to_csv(rdir / "es_leakage_units.csv", index=False)
    results["es_leakage_units"] = {
        c.replace("es_pos_share_seen_in_train__", ""): float(leak[c].mean())
        for c in leak.columns if c.startswith("es_pos_share")
    }

    # ---------------------------------------------------------- H: calibration
    log.info("H. calibration by stratum")
    # NOTE: do NOT stratify calibration by label_tier — tier determines the target
    # (bronze/silver are 100% positive by construction), so it is degenerate.
    df = df.assign(season=np.where(df.is_monsoon == 1, "monsoon", "dry"),
                   slope_q=ea._qbucket(df.slope_mean_deg))
    cal = pd.concat([
        ea.calibration_by_stratum(df, "spatial_fold").rename(columns={"spatial_fold": "value"}).assign(stratum="spatial_fold"),
        ea.calibration_by_stratum(df, "season").rename(columns={"season": "value"}).assign(stratum="season"),
        ea.calibration_by_stratum(df, "slope_q").rename(columns={"slope_q": "value"}).assign(stratum="slope_quartile"),
    ])
    cal.to_csv(rdir / "calibration_by_stratum.csv", index=False)
    results["calibration_spread"] = {
        "max_over_prediction_ratio": float(cal.ratio_pred_over_obs.max()),
        "min_over_prediction_ratio": float(cal.ratio_pred_over_obs.min()),
        "note": "ratio = mean predicted / observed rate; 1.0 is perfect. Spread across "
                "regions means one global calibrator does not transfer.",
    }

    # ---------------------------------------------------------- misclassified samples
    pos = df[df.target == 1]
    worst_fn = pos.nsmallest(300, "p_cal")[META_COLS + ["p_cal", "rain_3d_mm", "api_mm",
                                                        "slope_mean_deg", "spatial_fold"]]
    worst_fn.to_csv(rdir / "worst_false_negatives.csv", index=False)
    fp_rows = df[(df.target == 0) & (df.p_cal >= thr)]
    fp_rows.nlargest(300, "p_cal")[META_COLS + ["p_cal", "rain_3d_mm", "api_mm",
                                                "slope_mean_deg", "spatial_fold"]] \
        .to_csv(rdir / "worst_false_positives.csv", index=False)

    # ---------------------------------------------------------- plots
    plots.confusion(cm, rdir / "confusion_operating_point.png")
    _plot_event_detection(per_event, rdir / "per_event_detection.png")
    _plot_strata(strat, rdir / "strata_ap.png")
    _plot_gap(gap, rdir / "generalization_gap.png")

    (rdir / "error_analysis.json").write_text(json.dumps(results, indent=2, default=float))
    _write_report(results, strat, per_event, fnp, fp_by_seg, noise, dq, gap, cm, thr, rdir, df)
    log.info("Stage 5 done in %.1fs -> %s", time.time() - t0, rdir)


# --------------------------------------------------------------------------- #
def _plot_event_detection(per_event: pd.DataFrame, out: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    if per_event.empty:
        return
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ks = np.arange(1, 201)
    frac = [(per_event.best_rank <= k).mean() for k in ks]
    ax.plot(ks, frac)
    for k in (1, 10, 50, 100):
        f = (per_event.best_rank <= k).mean()
        ax.annotate(f"top-{k}: {f:.0%}", (k, f), fontsize=8,
                    xytext=(5, -10), textcoords="offset points")
    ax.set_xlabel("k (rank among rows scored that day)")
    ax.set_ylabel("fraction of real events detected")
    ax.set_title("Per-event detection — would we have flagged it?")
    ax.set_ylim(0, 1); ax.grid(alpha=.3)
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def _plot_strata(strat: pd.DataFrame, out: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    d = strat.dropna(subset=["AP"])
    show = d[d.stratum.isin(["label_tier", "season", "rain_3d_quartile",
                             "slope_quartile", "label_source", "spatial_fold"])]
    if show.empty:
        return
    fig, ax = plt.subplots(figsize=(8, max(4, 0.28 * len(show))))
    labels = show.stratum + " = " + show.value
    ax.barh(labels, show.AP)
    ax.axvline(show.base_rate.median(), ls="--", c="grey", label="median base rate (chance)")
    ax.set_xlabel("average precision"); ax.legend(fontsize=8)
    ax.set_title("Ranking quality by stratum (held-out OOF)")
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def _plot_gap(gap: dict, out: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    names = list(gap.keys())
    aps = [gap[n]["average_precision"] for n in names]
    fig, ax = plt.subplots(figsize=(6.5, 4))
    bars = ax.bar(names, aps, color=["#888", "#1f77b4", "#d62728"])
    for b, v in zip(bars, aps):
        ax.text(b.get_x() + b.get_width() / 2, v, f"{v:.3f}", ha="center", va="bottom")
    ax.set_ylabel("average precision")
    ax.set_title("Generalization gap: in-sample -> new region -> new time")
    plt.setp(ax.get_xticklabels(), rotation=15, ha="right")
    fig.savefig(out, dpi=120, bbox_inches="tight"); plt.close(fig)


def _write_report(results, strat, per_event, fnp, fp_by_seg, noise, dq, gap, cm, thr, rdir, df) -> None:
    o = results["overall_oof"]
    det = results["per_event_detection"]
    fps = results["false_positives"]
    L = [
        "# Stage 5 — Evaluation & Error Analysis", "",
        "All numbers below are MEASURED from actual model outputs on held-out data "
        "(Stage 4 spatial-CV OOF + a fresh out-of-time fit + in-sample scores). "
        "Recommendations are clearly marked as such. The locked `final_test` split "
        "was NOT opened.", "",
        "## 0. Evaluation set", "",
        f"- Held-out OOF rows: **{o['n']:,}**, positives **{o['n_pos']:,}**, "
        f"base rate **{o['base_rate']:.4f}**",
        "- Tier composition: " + ", ".join(f"{k}={v}" for k, v in df.label_tier.value_counts().items()),
        "- **Zero gold-tier positives here** — all 3 verified labels sit inside the "
        "locked test split. Every positive evaluated below is a weak (silver/bronze) label.", "",
        "## 1. Headline metrics (held-out OOF)", "",
        f"| metric | value |", "|--|--|",
        f"| Average precision (PRIMARY) | **{o['average_precision']:.3f}** |",
        f"| ROC-AUC | {o['roc_auc']:.3f} |",
        f"| Brier | {o['brier']:.4f} |",
        f"| ECE | {o['ece']:.4f} |",
        f"| precision@50 | {o['precision@50']:.3f} |",
        f"| lift@1% | {o['lift@1pct']:.1f}x |",
        f"| chance (base rate) | {o['base_rate']:.4f} |", "",
        f"At the cost-optimal operating point (policy: one missed closure costs as much "
        f"as {results['cost_fn_over_fp']} false alarms), threshold **{thr:.4f}**: "
        f"precision **{cm['precision']:.3f}**, recall **{cm['recall']:.3f}** "
        f"(TP {cm['tp']:,} · FP {cm['fp']:,} · FN {cm['fn']:,} · TN {cm['tn']:,}).", "",
        "## 2. Generalization gap (the overfitting/underfitting read)", "",
        "| evaluation | AP | ROC-AUC | interpretation |", "|--|--|--|--|",
    ]
    interp = {
        "in_sample_dev": "model scored on data it trained on",
        "held_out_spatial_oof": "new REGION (spatial blocks held out)",
        "out_of_time_test": "new TIME + new label source (hardest)",
    }
    for k, v in gap.items():
        L.append(f"| {k} | {v['average_precision']:.3f} | {v['roc_auc']:.3f} | {interp.get(k,'')} |")
    L += ["",
          f"In-sample AP {gap['in_sample_dev']['average_precision']:.3f} vs held-out "
          f"{gap['held_out_spatial_oof']['average_precision']:.3f} = the cost of moving to "
          "an unseen region; the further drop to "
          f"{gap['out_of_time_test']['average_precision']:.3f} out-of-time is the cost of "
          "moving to a new period AND a different label source (GLC -> reliefweb).", "",
          "## 3. Per-event detection — *would we have flagged the real event?*", "",
          f"- Events evaluated: **{det['n_events']}**",
          f"- Detected in **top-1**: {det['frac_detected_in_top1']:.1%} · "
          f"**top-10**: {det['frac_detected_in_top10']:.1%} · "
          f"**top-50**: {det['frac_detected_in_top50']:.1%} · "
          f"**top-100**: {det['frac_detected_in_top100']:.1%}",
          f"- Median best rank: **{det['median_best_rank']:.0f}** out of a median "
          f"**{det['median_scored_per_day']:.0f}** rows scored that day", "",
          "> **Caveat, stated plainly:** the panel holds only labelled rows (positives + "
          "sampled negatives), not all 309k corridor segments. So this is rank-within-the-"
          "scored-sample, an OPTIMISTIC proxy for live deployment. It is the right shape of "
          "metric for comparing models, not a deployment guarantee.", "",
          "## 4. Where the model is strong vs weak", "",
          "Full table: `stratified_performance.csv`. Strata where AP collapses toward the "
          "base rate have no usable signal.", "", "| stratum | value | n | pos | AP | base rate | lift |",
          "|--|--|--|--|--|--|--|"]
    key_strata = strat.dropna(subset=["AP"]).sort_values("lift_vs_chance", ascending=False)
    for _, r in pd.concat([key_strata.head(8), key_strata.tail(8)]).iterrows():
        L.append(f"| {r.stratum} | {r.value} | {r.n:,} | {r.n_pos} | {r.AP:.3f} | "
                 f"{r.base_rate:.3f} | {r.lift_vs_chance:.1f}x |")
    L += ["", "## 5. Why we miss (false negatives)", "",
          "Cohen's *d* between caught (TP) and missed (FN) positives — full table "
          "`fn_vs_tp_probe.csv`, worst cases `worst_false_negatives.csv`.", "",
          "| feature | TP median | FN median | Cohen's d |", "|--|--|--|--|"]
    for _, r in fnp.head(8).iterrows():
        L.append(f"| {r.feature} | {r.tp_median:.3g} | {r.fn_median:.3g} | "
                 f"{r.cohens_d_tp_minus_fn:+.2f} |")
    L += ["", "## 6. False-positive structure", "",
          f"- FPs: **{fps['n_fp']:,}** ({fps['fp_rate_among_negatives']:.1%} of negatives)",
          f"- Concentration: the worst 10% of segments account for "
          f"**{fps.get('top10pct_segments_share_of_fp', float('nan')):.1%}** of all FPs "
          f"(top 1%: {fps.get('top1pct_segments_share_of_fp', float('nan')):.1%}) — "
          "see `fp_top_segments.csv`"]
    nearkey = [k for k in fps if k.startswith("frac_fp_within")]
    if nearkey:
        L.append(f"- **{fps[nearkey[0]]:.1%}** of FPs fall within 10 km and 7 days of a "
                 "labelled real event — these are plausibly UNLABELLED positives "
                 "(inventory incompleteness), not model errors.")
    L += ["", "## 7. Is the ceiling the model or the labels?", "",
          "Ranking quality recomputed using only positives of a given label quality, "
          "against the same negative set (`label_noise_probe.csv`):", "",
          "| probe | bucket | n_pos | AP | lift |", "|--|--|--|--|--|"]
    for _, r in noise.iterrows():
        L.append(f"| {r.probe} | {r.bucket} | {r.n_pos} | {r.AP:.3f} | {r.lift_vs_chance:.1f}x |")
    if "es_signal" in results:
        s = results["es_signal"]
        L += ["", "## 7b. Early-stopping signal integrity (training-process defect)", "",
              f"- mean AP on TRAIN rows: **{s['mean_AP_train']:.3f}**",
              f"- mean AP on the EARLY-STOPPING rows: **{s['mean_AP_earlystop']:.3f}**",
              f"- mean AP on HELD-OUT blocks: **{s['mean_AP_heldout_blocks']:.3f}**",
              f"- verdict: **{s['verdict']}**", "",
              "Share of ES positives whose unit also appears among TRAIN positives "
              "(`es_leakage_units.csv`):", "", "| unit | overlap |", "|--|--|"]
        for k, v in results["es_leakage_units"].items():
            L.append(f"| {k} | {v:.1%} |")
        L += ["", "Because one event generates up to 60 panel rows (≤20 snapped segments × 3 "
              "persistence days), a RANDOM ROW split always puts rows of the same event on "
              "both sides — so the early-stopping score measures memorization, not "
              "generalization.", ""]
    L += ["", "## 8. Data-quality scan", "", "| check | value |", "|--|--|"]
    for k, v in dq.items():
        L.append(f"| {k} | {v:,} |" if isinstance(v, int) else f"| {k} | {v:.4f} |")
    L += ["", "## 9. Artifacts", "",
          "`stratified_performance.csv` · `per_event_detection.csv` · `fn_vs_tp_probe.csv` · "
          "`fp_top_segments.csv` · `label_noise_probe.csv` · `calibration_by_stratum.csv` · "
          "`worst_false_negatives.csv` · `worst_false_positives.csv` · `error_analysis.json` · "
          "plots (`per_event_detection.png`, `strata_ap.png`, `generalization_gap.png`, "
          "`confusion_operating_point.png`)", "",
          "Interpretation, root-cause attribution and the ranked improvement plan are in "
          "`ERROR_ANALYSIS.md` (hand-authored from these numbers)."]
    (rdir / "EVALUATION_REPORT.md").write_text("\n".join(L))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
