"""Stage 6 — fine-tuning for a GBDT.

There are no layers to freeze in a gradient-boosted tree ensemble, so "progressive
unfreezing" has no literal equivalent. The honest analogues, in increasing order of
how much of the model is allowed to change:

  stage 0  frozen            reuse the base model unchanged                (control)
  stage 1  "head only"       Booster.refit(): keep every tree's STRUCTURE
                             (split features + thresholds) and recompute only the
                             LEAF VALUES on the target data. The learned structure
                             is frozen; the outputs adapt.
  stage 2  "partial unfreeze" continue boosting from the base model (init_model) at
                             a REDUCED learning rate — old trees stay fixed, new
                             trees are appended to correct the residual.
  stage 3  "full unfreeze"   retrain from scratch on the combined data       (control)

The experiment this targets is the measured temporal degradation from Stage 5
(spatial-CV AP 0.294 vs out-of-time AP 0.232): train on the old period, adapt to the
recent period, evaluate on the future. Nothing here touches `final_test`.
"""
from __future__ import annotations

import numpy as np
from sklearn.metrics import average_precision_score

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.train import cv
from sih_ml.utils.common import Config, get_logger

log = get_logger("finetune")


def _ap(y, p) -> float:
    return float(average_precision_score(y, p)) if np.asarray(y).sum() else float("nan")


def stage0_frozen(base: LGBMBaseline, data: Data, test_idx) -> dict:
    return {"stage": "0_frozen_base", "AP": _ap(data.y[test_idx], base.predict(data.X(test_idx))),
            "n_trees": int(base.booster_.num_trees())}


def stage1_refit_leaves(base: LGBMBaseline, data: Data, adapt_idx, test_idx,
                        decay_rate: float = 0.9) -> dict:
    """Freeze tree structure, recompute leaf values on the adaptation data."""
    import copy

    m = copy.deepcopy(base)
    m.booster_ = base.booster_.refit(
        data=data.X(adapt_idx)[base.features], label=data.y[adapt_idx],
        decay_rate=decay_rate,
    )
    return {"stage": "1_refit_leaves", "decay_rate": decay_rate,
            "AP": _ap(data.y[test_idx], m.predict(data.X(test_idx))),
            "n_trees": int(m.booster_.num_trees())}, m


def stage2_continue_boosting(base: LGBMBaseline, data: Data, adapt_idx, es_idx, test_idx,
                             cfg: Config, extra_rounds: int, lr_scale: float,
                             seed: int = 42) -> dict:
    """Append new trees on the adaptation data at a reduced learning rate."""
    p = dict(cfg.lgbm)
    p["learning_rate"] = float(cfg.lgbm.learning_rate) * lr_scale
    p["n_estimators"] = extra_rounds
    p["seed"] = seed
    m = LGBMBaseline(params=p, features=data.features, categorical=data.categorical,
                     monotone_increasing=list(cfg.lgbm.monotone_rainfall_features))
    spw = cv._scale_pos_weight(data.y[adapt_idx])
    m.fit(data.X(adapt_idx), data.y[adapt_idx], data.w[adapt_idx],
          data.X(es_idx), data.y[es_idx], data.w[es_idx],
          scale_pos_weight=spw, init_model=base.booster_, num_boost_round=extra_rounds)
    return {"stage": "2_continue_boosting", "lr_scale": lr_scale, "extra_rounds": extra_rounds,
            "AP": _ap(data.y[test_idx], m.predict(data.X(test_idx))),
            "n_trees": int(m.booster_.num_trees())}, m


def stage3_full_retrain(data: Data, train_idx, es_idx, test_idx, cfg: Config,
                        seed: int = 42) -> dict:
    """Control: throw the base model away and retrain on everything available."""
    p = dict(cfg.lgbm)
    p["seed"] = seed
    m = LGBMBaseline(params=p, features=data.features, categorical=data.categorical,
                     monotone_increasing=list(cfg.lgbm.monotone_rainfall_features))
    spw = cv._scale_pos_weight(data.y[train_idx])
    m.fit(data.X(train_idx), data.y[train_idx], data.w[train_idx],
          data.X(es_idx), data.y[es_idx], data.w[es_idx], scale_pos_weight=spw)
    return {"stage": "3_full_retrain",
            "AP": _ap(data.y[test_idx], m.predict(data.X(test_idx))),
            "n_trees": int(m.booster_.num_trees())}, m


def run_temporal_finetune(data: Data, cfg: Config, fcfg: Config, seed: int = 42) -> list[dict]:
    """The staged experiment, on the out-of-time split.

    base  = trained on temporal TRAIN (<=2015)
    adapt = temporal VAL (2016-2018)      <- what fine-tuning is allowed to see
    test  = temporal TEST (2019+)         <- never seen by any stage
    """
    tr, va, te = data.temporal_indices()
    log.info("temporal fine-tune: train=%d adapt=%d test=%d (pos_test=%d)",
             len(tr), len(va), len(te), int(data.y[te].sum()))

    # base model on the old period only
    m_tr, m_es = cv.make_es_split(data, tr, cfg, seed)
    base_res, base = stage3_full_retrain(data, tr[m_tr], tr[m_es], te, cfg, seed)
    base_res["stage"] = "base_old_period_only"
    results = [base_res]

    results.append(stage0_frozen(base, data, te))

    # split the adaptation window into fit / early-stop parts
    a_tr, a_es = cv.make_es_split(data, va, cfg, seed + 1)
    adapt_fit, adapt_es = va[a_tr], va[a_es]

    r1, _ = stage1_refit_leaves(base, data, adapt_fit, te, fcfg.refit_decay)
    results.append(r1)

    r2, _ = stage2_continue_boosting(base, data, adapt_fit, adapt_es, te, cfg,
                                     int(fcfg.continue_rounds), float(fcfg.continue_lr_scale), seed)
    results.append(r2)

    # control: retrain from scratch on train+adapt combined
    comb = np.concatenate([tr, va])
    c_tr, c_es = cv.make_es_split(data, comb, cfg, seed + 2)
    r3, _ = stage3_full_retrain(data, comb[c_tr], comb[c_es], te, cfg, seed)
    r3["stage"] = "3_full_retrain_on_train+adapt"
    results.append(r3)

    for r in results:
        log.info("  %-32s AP=%.4f  trees=%d", r["stage"], r["AP"], r["n_trees"])
    return results
