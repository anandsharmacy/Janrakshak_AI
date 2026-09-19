"""Stage 6 — Optuna hyperparameter optimization with selection/report fold separation.

Design decisions that keep this honest:
  * The inner early-stopping split is EVENT-GROUPED (Stage 5 P0). Searching against
    the old row-split signal (AP 0.999) would rank every config identically.
  * The objective is the mean held-out AP over SELECTION folds only. REPORT folds
    are never seen by the search, so they give an unbiased read on the tuned config.
  * The locked `final_test` is not touched at any point.
  * Studies persist to SQLite, so a search can be stopped and resumed.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import optuna
from sklearn.metrics import average_precision_score

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.train import cv
from sih_ml.utils.common import Config, get_logger

log = get_logger("hpo")
optuna.logging.set_verbosity(optuna.logging.WARNING)


def _suggest(trial: optuna.Trial, space: dict) -> dict:
    out = {}
    for name, spec in space.items():
        t = spec["type"]
        if t == "int":
            out[name] = trial.suggest_int(name, spec["low"], spec["high"],
                                          log=spec.get("log", False))
        elif t == "float":
            out[name] = trial.suggest_float(name, spec["low"], spec["high"],
                                            log=spec.get("log", False))
        elif t == "categorical":
            out[name] = trial.suggest_categorical(name, spec["choices"])
        else:
            raise ValueError(f"unknown param type {t!r} for {name}")
    return out


def params_to_cfg(base_cfg: Config, params: dict, n_estimators: int,
                  early_stopping_rounds: int) -> Config:
    """Fold a trial's suggestions into a full config the CV runners understand."""
    cfg = dict(base_cfg)
    lgbm = dict(base_cfg.lgbm)
    for k, v in params.items():
        if k in ("use_monotone", "scale_pos_weight_mult"):
            continue
        lgbm[k] = v
    lgbm["n_estimators"] = n_estimators
    lgbm["early_stopping_rounds"] = early_stopping_rounds
    if not params.get("use_monotone", True):
        lgbm["monotone_rainfall_features"] = []
    cfg["lgbm"] = lgbm
    return Config(cfg)


def fit_eval_fold(data: Data, cfg: Config, fold: int, seed: int,
                  spw_mult: float = 1.0) -> tuple[float, int]:
    """Train on a fold's training blocks, score its held-out blocks. Returns (AP, best_iter)."""
    tr_all, va = data.spatial_fold_indices(fold, drop_buffer=cfg.cv.drop_buffer_rows)
    m_tr, m_es = cv.make_es_split(data, tr_all, cfg, seed + fold)
    tr, es = tr_all[m_tr], tr_all[m_es]

    p = dict(cfg.lgbm)
    p["seed"] = seed + fold
    model = LGBMBaseline(params=p, features=data.features, categorical=data.categorical,
                         monotone_increasing=list(cfg.lgbm.monotone_rainfall_features))
    spw = cv._scale_pos_weight(data.y[tr]) * spw_mult if cfg.lgbm.auto_scale_pos_weight else None
    model.fit(data.X(tr), data.y[tr], data.w[tr],
              data.X(es), data.y[es], data.w[es], scale_pos_weight=spw)
    pred = model.predict(data.X(va))
    ap = float(average_precision_score(data.y[va], pred)) if data.y[va].sum() else float("nan")
    return ap, int(model.best_iteration_)


def make_objective(data: Data, base_cfg: Config, hcfg: Config, seed: int):
    space = dict(hcfg.space)
    sel_folds = list(hcfg.selection_folds)

    def objective(trial: optuna.Trial) -> float:
        params = _suggest(trial, space)
        cfg = params_to_cfg(base_cfg, params, hcfg.search_n_estimators,
                            hcfg.search_early_stopping_rounds)
        spw_mult = params.get("scale_pos_weight_mult", 1.0)
        aps, iters = [], []
        for i, f in enumerate(sel_folds):
            ap, best_it = fit_eval_fold(data, cfg, f, seed, spw_mult)
            aps.append(ap)
            iters.append(best_it)
            # report intermediate value so the pruner can kill hopeless trials early
            trial.report(float(np.nanmean(aps)), step=i)
            if trial.should_prune():
                raise optuna.TrialPruned()
        trial.set_user_attr("fold_aps", aps)
        trial.set_user_attr("best_iters", iters)
        trial.set_user_attr("mean_best_iter", int(np.mean(iters)))
        return float(np.nanmean(aps))

    return objective


def run_study(data: Data, base_cfg: Config, hcfg: Config, storage_path: Path,
              seed: int = 42) -> optuna.Study:
    storage_path.parent.mkdir(parents=True, exist_ok=True)
    sampler = (optuna.samplers.TPESampler(seed=seed, multivariate=True)
               if hcfg.sampler == "tpe" else optuna.samplers.RandomSampler(seed=seed))
    pruner = (optuna.pruners.MedianPruner(n_startup_trials=8, n_warmup_steps=1)
              if hcfg.pruner == "median" else optuna.pruners.NopPruner())
    study = optuna.create_study(
        direction="maximize", sampler=sampler, pruner=pruner,
        study_name=hcfg.study_name, storage=f"sqlite:///{storage_path}",
        load_if_exists=True,   # <- resumable
    )
    done = len([t for t in study.trials if t.state.is_finished()])
    remaining = max(0, hcfg.n_trials - done)
    log.info("study '%s': %d trials already done, running %d more",
             hcfg.study_name, done, remaining)
    if remaining:
        study.optimize(make_objective(data, base_cfg, hcfg, seed),
                       n_trials=remaining, timeout=hcfg.timeout_sec,
                       show_progress_bar=False,
                       callbacks=[_log_cb])
    return study


def _log_cb(study: optuna.Study, trial: optuna.trial.FrozenTrial) -> None:
    if trial.state == optuna.trial.TrialState.COMPLETE:
        log.info("trial %3d  AP=%.4f  (best %.4f)  %s",
                 trial.number, trial.value or float("nan"), study.best_value,
                 {k: (round(v, 4) if isinstance(v, float) else v)
                  for k, v in trial.params.items()})
    elif trial.state == optuna.trial.TrialState.PRUNED:
        log.info("trial %3d  pruned", trial.number)


def evaluate_on_report_folds(data: Data, cfg: Config, hcfg: Config, seed: int,
                             spw_mult: float = 1.0) -> dict:
    """Honest read: folds the search never optimised against."""
    out = {}
    for f in list(hcfg.report_folds):
        ap, best_it = fit_eval_fold(data, cfg, f, seed, spw_mult)
        out[f"fold_{f}"] = {"AP": ap, "best_iteration": best_it}
    aps = [v["AP"] for v in out.values()]
    out["mean_AP"] = float(np.nanmean(aps))
    out["std_AP"] = float(np.nanstd(aps))
    return out
