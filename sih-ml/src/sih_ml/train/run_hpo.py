"""Stage 6 orchestrator — controlled experiments, HPO, fine-tuning, model selection.

    python -m sih_ml.train.run_hpo [conf/hpo_config.yaml]

Runs in stages so that one change is attributable at a time:
  E0  baseline (Stage 4 config) on selection + report folds        <- the bar
  E1  P0 fix alone: event-grouped early stopping, nothing else     <- isolates the fix
  E2  Optuna HPO (selection folds only), then report folds         <- the search
  E3  staged fine-tuning on the out-of-time split                  <- adaptation
  MS  model selection over all candidates, multi-criteria

`final_test` is not opened at any point.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import optuna
import pandas as pd

from sih_ml.models.dataset import load_data
from sih_ml.train import finetune, hpo, tracking
from sih_ml.utils.common import (Config, REPO_ROOT, get_logger, git_sha, resolve,
                                 set_seed, write_manifest)

log = get_logger("stage6")


def _mean_ap_over(data, cfg, folds, seed, spw_mult=1.0) -> dict:
    out = {}
    for f in folds:
        ap, it = hpo.fit_eval_fold(data, cfg, f, seed, spw_mult)
        out[f"fold_{f}"] = {"AP": ap, "best_iteration": it}
    aps = [v["AP"] for v in out.values()]
    out["mean_AP"] = float(np.nanmean(aps))
    out["std_AP"] = float(np.nanstd(aps))
    return out


def main(config_path: str | None = None) -> None:
    t0 = time.time()
    cfg_path = Path(config_path) if config_path else REPO_ROOT / "conf" / "hpo_config.yaml"
    if not cfg_path.is_absolute():
        cfg_path = REPO_ROOT / cfg_path
    data, cfg = load_data(cfg_path)
    set_seed(cfg.seed)

    hcfg, fcfg = cfg.hpo, cfg.finetune
    rdir = resolve(cfg, cfg.paths.reports)
    rdir.mkdir(parents=True, exist_ok=True)
    sel, rep = list(hcfg.selection_folds), list(hcfg.report_folds)
    log.info("selection folds %s | report folds %s (never seen by the search)", sel, rep)

    tracking.init_tracking(resolve(cfg, cfg.paths.mlruns))
    results: dict = {"git_sha": git_sha(), "selection_folds": sel, "report_folds": rep}

    with tracking.run(f"stage6_{int(t0)}", params={"model_version": cfg.model_version,
                                                   "n_trials": hcfg.n_trials},
                      tags={"stage": "6-hpo"}):
        # ---------------------------------------------------------------- E0
        log.info("=== E0: baseline config (Stage 4), row-split ES ===")
        cfg_e0 = Config({**dict(cfg), "cv": {**dict(cfg.cv), "es_split_mode": "row"}})
        e0 = {"selection": _mean_ap_over(data, cfg_e0, sel, cfg.seed),
              "report": _mean_ap_over(data, cfg_e0, rep, cfg.seed)}
        results["E0_baseline_row_es"] = e0
        log.info("E0  selection mean AP %.4f | report mean AP %.4f",
                 e0["selection"]["mean_AP"], e0["report"]["mean_AP"])

        # ---------------------------------------------------------------- E1
        log.info("=== E1: P0 fix only — event-grouped ES, same hyperparameters ===")
        e1 = {"selection": _mean_ap_over(data, cfg, sel, cfg.seed),
              "report": _mean_ap_over(data, cfg, rep, cfg.seed)}
        results["E1_event_grouped_es"] = e1
        log.info("E1  selection mean AP %.4f | report mean AP %.4f",
                 e1["selection"]["mean_AP"], e1["report"]["mean_AP"])

        # ---------------------------------------------------------------- E2
        log.info("=== E2: Optuna HPO (%d trials, selection folds only) ===", hcfg.n_trials)
        storage = resolve(cfg, cfg.paths.studies) / f"{hcfg.study_name}.db"
        study = hpo.run_study(data, cfg, hcfg, storage, seed=cfg.seed)
        best = study.best_trial
        best_cfg = hpo.params_to_cfg(cfg, best.params, cfg.lgbm.n_estimators,
                                     cfg.lgbm.early_stopping_rounds)
        spw_mult = best.params.get("scale_pos_weight_mult", 1.0)
        e2 = {
            "n_trials_total": len(study.trials),
            "n_complete": len([t for t in study.trials if t.state.name == "COMPLETE"]),
            "n_pruned": len([t for t in study.trials if t.state.name == "PRUNED"]),
            "best_params": best.params,
            "best_selection_AP": float(best.value),
            "best_fold_aps": best.user_attrs.get("fold_aps"),
            "report": hpo.evaluate_on_report_folds(data, best_cfg, hcfg, cfg.seed, spw_mult),
        }
        results["E2_hpo"] = e2
        log.info("E2  best selection AP %.4f | report mean AP %.4f",
                 e2["best_selection_AP"], e2["report"]["mean_AP"])
        tracking.log_metrics({"hpo_best_selection_AP": e2["best_selection_AP"],
                              "hpo_report_AP": e2["report"]["mean_AP"]})

        # trial history for the report
        hist = study.trials_dataframe(attrs=("number", "value", "state", "params", "duration"))
        hist.to_csv(rdir / "hpo_trials.csv", index=False)

        # ---------------------------------------------------------------- E3
        if fcfg.enabled:
            log.info("=== E3: staged fine-tuning on the out-of-time split ===")
            ft = finetune.run_temporal_finetune(data, best_cfg, fcfg, seed=cfg.seed)
            results["E3_finetune_temporal"] = ft
            pd.DataFrame(ft).to_csv(rdir / "finetune_stages.csv", index=False)

        # ---------------------------------------------------------------- selection
        results["model_selection"] = _select(results, best_cfg, data)
        (rdir / "hpo_results.json").write_text(json.dumps(results, indent=2, default=float))
        (rdir / "best_params.json").write_text(json.dumps(
            {"params": best.params, "lgbm": dict(best_cfg.lgbm)}, indent=2, default=float))
        write_manifest(resolve(cfg, "data/processed/manifests"), "hpo_v1",
                       {"best_params": best.params,
                        "report_mean_AP": e2["report"]["mean_AP"]})
        _plot(results, study, rdir)
        _write_report(results, rdir, hcfg)

    results["runtime_sec"] = round(time.time() - t0, 1)
    log.info("Stage 6 done in %.1fs -> %s", time.time() - t0, rdir)


def _select(results: dict, best_cfg: Config, data) -> dict:
    """Multi-criteria model selection — never on validation AP alone."""
    cands = {
        "E0_baseline": results["E0_baseline_row_es"]["report"]["mean_AP"],
        "E1_event_es": results["E1_event_grouped_es"]["report"]["mean_AP"],
        "E2_hpo_tuned": results["E2_hpo"]["report"]["mean_AP"],
    }
    spreads = {
        "E0_baseline": results["E0_baseline_row_es"]["report"]["std_AP"],
        "E1_event_es": results["E1_event_grouped_es"]["report"]["std_AP"],
        "E2_hpo_tuned": results["E2_hpo"]["report"]["std_AP"],
    }
    best_name = max(cands, key=cands.get)
    margin = cands[best_name] - cands["E0_baseline"]
    noise = max(spreads.values())
    return {
        "candidates_report_AP": cands,
        "candidates_report_std": spreads,
        "argmax": best_name,
        "margin_over_baseline": margin,
        "fold_spread_as_noise_floor": noise,
        "improvement_exceeds_noise": bool(abs(margin) > noise),
        "n_trees_tuned": int(best_cfg.lgbm.num_leaves),
        "decision_rule": (
            "Select the tuned config ONLY if its report-fold gain exceeds the fold "
            "spread AND it is not materially larger/slower. With 2 report folds the "
            "spread is a crude noise floor, so a gain inside it is reported as "
            "'not demonstrated', never as an improvement."
        ),
    }


def _plot(results: dict, study, rdir: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    # Optimization history.
    # ONLY complete trials. A pruned trial's `.value` is its last INTERMEDIATE score,
    # computed on a subset of the selection folds — mixing those in inflates the
    # curve (observed: pruned partials reached 0.52 vs a true best of 0.44) and
    # overstates the search.
    comp = [(t.number, t.value) for t in study.trials
            if t.state == optuna.trial.TrialState.COMPLETE and t.value is not None]
    pruned = [(t.number, t.value) for t in study.trials
              if t.state == optuna.trial.TrialState.PRUNED and t.value is not None]
    if comp:
        nums, vals = zip(*comp)
        fig, ax = plt.subplots(figsize=(7.5, 4))
        ax.plot(nums, vals, "o-", ms=3, label=f"complete trial (n={len(comp)})")
        ax.plot(nums, np.maximum.accumulate(vals), "-", c="crimson", label="best so far")
        if pruned:
            pn, pv = zip(*pruned)
            ax.scatter(pn, pv, marker="x", c="grey", s=25, alpha=.7,
                       label=f"pruned — PARTIAL score, not comparable (n={len(pruned)})")
        ax.set_xlabel("trial"); ax.set_ylabel("mean AP (selection folds)")
        ax.set_title("Optuna search history"); ax.legend(fontsize=7); ax.grid(alpha=.3)
        fig.savefig(rdir / "hpo_history.png", dpi=120, bbox_inches="tight"); plt.close(fig)

    # experiment comparison on REPORT folds
    ms = results["model_selection"]["candidates_report_AP"]
    err = results["model_selection"]["candidates_report_std"]
    fig, ax = plt.subplots(figsize=(6.5, 4))
    ax.bar(list(ms), list(ms.values()), yerr=[err[k] for k in ms], capsize=5,
           color=["#999", "#1f77b4", "#2ca02c"])
    for i, (k, v) in enumerate(ms.items()):
        ax.text(i, v, f"{v:.3f}", ha="center", va="bottom")
    ax.set_ylabel("mean AP on REPORT folds (unseen by the search)")
    ax.set_title("Controlled comparison — error bars are the fold spread")
    plt.setp(ax.get_xticklabels(), rotation=12, ha="right")
    fig.savefig(rdir / "experiment_comparison.png", dpi=120, bbox_inches="tight"); plt.close(fig)

    if "E3_finetune_temporal" in results:
        ft = pd.DataFrame(results["E3_finetune_temporal"])
        fig, ax = plt.subplots(figsize=(7.5, 4))
        ax.bar(ft["stage"], ft["AP"], color="#7f7fbf")
        for i, v in enumerate(ft["AP"]):
            ax.text(i, v, f"{v:.3f}", ha="center", va="bottom", fontsize=8)
        ax.set_ylabel("AP on out-of-time test (2019+)")
        ax.set_title("Staged fine-tuning — GBDT freeze/unfreeze analogues")
        plt.setp(ax.get_xticklabels(), rotation=20, ha="right", fontsize=8)
        fig.savefig(rdir / "finetune_stages.png", dpi=120, bbox_inches="tight"); plt.close(fig)


def _write_report(r: dict, rdir: Path, hcfg) -> None:
    ms = r["model_selection"]
    L = [
        "# Stage 6 — Fine-Tuning & HPO results", "",
        f"git `{r['git_sha']}` · selection folds {r['selection_folds']} · "
        f"report folds {r['report_folds']} (never seen by the search) · "
        "`final_test` still locked.", "",
        "All numbers measured. Improvements are only claimed where they exceed the "
        "fold-spread noise floor.", "",
        "## Controlled experiments (mean AP)", "",
        "| experiment | selection folds | **report folds** |", "|--|--|--|",
    ]
    for key, name in [("E0_baseline_row_es", "E0 baseline (row ES)"),
                      ("E1_event_grouped_es", "E1 + event-grouped ES (P0 fix)")]:
        L.append(f"| {name} | {r[key]['selection']['mean_AP']:.4f} | "
                 f"**{r[key]['report']['mean_AP']:.4f}** ± {r[key]['report']['std_AP']:.3f} |")
    e2 = r["E2_hpo"]
    L.append(f"| E2 HPO best ({e2['n_complete']} complete / {e2['n_pruned']} pruned) | "
             f"{e2['best_selection_AP']:.4f} | **{e2['report']['mean_AP']:.4f}** ± "
             f"{e2['report']['std_AP']:.3f} |")
    L += ["", "## Verdict", "",
          f"- argmax on report folds: **{ms['argmax']}**",
          f"- margin over baseline: **{ms['margin_over_baseline']:+.4f}**",
          f"- fold-spread noise floor: **{ms['fold_spread_as_noise_floor']:.4f}**",
          f"- exceeds noise: **{'YES' if ms['improvement_exceeds_noise'] else 'NO — not demonstrated'}**",
          "", f"> {ms['decision_rule']}", "",
          "## Best hyperparameters", "", "```json",
          json.dumps(e2["best_params"], indent=2), "```", ""]
    if "E3_finetune_temporal" in r:
        L += ["## Staged fine-tuning (out-of-time test, 2019+)", "",
              "| stage | AP | trees |", "|--|--|--|"]
        for s in r["E3_finetune_temporal"]:
            L.append(f"| {s['stage']} | {s['AP']:.4f} | {s['n_trees']:,} |")
        L += ["", "GBDT has no layers: stage 1 = `Booster.refit()` (tree structure frozen, "
              "leaf values recomputed), stage 2 = continue boosting at reduced LR, "
              "stage 3 = full retrain. See `finetune.py` docstring.", ""]
    L += ["## Artifacts", "",
          "`hpo_results.json` · `best_params.json` · `hpo_trials.csv` · "
          "`finetune_stages.csv` · `hpo_history.png` · `experiment_comparison.png` · "
          "`finetune_stages.png` · Optuna study `studies/*.db` (resumable)"]
    (rdir / "HPO_REPORT.md").write_text("\n".join(L))


if __name__ == "__main__":
    import sys

    main(sys.argv[1] if len(sys.argv) > 1 else None)
