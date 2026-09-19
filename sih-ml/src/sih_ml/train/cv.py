"""Cross-validation runners for the baseline.

Three evaluation regimes, each producing pooled out-of-fold predictions:
  * spatial   — Stage 2 spatial-block folds (PRIMARY), 5 km buffer honoured
  * loeco     — grouped K-fold over event_cluster_id (leave-events-out)
  * temporal  — the single out-of-time train/val/test split

All model-fitting transforms happen here, on the training rows only.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupKFold

from sih_ml.models.dataset import Data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.utils.common import get_logger

log = get_logger("cv")


def _inner_earlystop_split(block_ids: np.ndarray, frac: float, seed: int, y: np.ndarray | None = None):
    """Random row sample (stratified by target when given) held out for early
    stopping / choosing the round count. Deliberately NOT a block holdout: this
    split only picks n_estimators, it never touches the outer (honest) evaluation,
    and a block holdout here made the ES signal too small/noisy (3/5 outer folds
    stopped after <10 rounds). See DATA_DECISIONS / BASELINE_ANALYSIS."""
    rng = np.random.default_rng(seed)
    n = len(block_ids)
    if y is None:
        is_es = rng.random(n) < frac
    else:
        is_es = np.zeros(n, dtype=bool)
        for cls in np.unique(y):
            idx = np.where(y == cls)[0]
            n_es = max(1, int(round(frac * len(idx))))
            is_es[rng.choice(idx, size=n_es, replace=False)] = True
    return ~is_es, is_es


def event_grouped_es_split(events: np.ndarray, y: np.ndarray, frac: float, seed: int):
    """Stage 5 P0 FIX — hold out whole EVENTS for early stopping.

    Stage 2 snaps one event to <=20 segments x 3 persistence days, so one event
    produces up to 60 panel rows. A random ROW split therefore put rows of the
    SAME event on both sides: measured overlap was 100% by event_id, and the
    early-stopping set scored AP 0.999 (fully memorised) -> no stopping signal at
    all, which is why every fold ran to the round cap.

    Here positives are grouped by event_id and negatives split randomly (they
    carry no event). Measured effect (reports/stage5/ERROR_ANALYSIS.md S2):
    ES AP 0.999 -> 0.716, held-out AP unchanged within noise. It does not raise
    accuracy; it makes the validation signal REAL, which is what HPO needs.
    """
    rng = np.random.default_rng(seed)
    is_es = np.zeros(len(y), dtype=bool)

    pos = np.where(y == 1)[0]
    if len(pos):
        ev = np.array(sorted(pd.unique(events[pos])))
        rng.shuffle(ev)
        es_ev = set(ev[:max(1, int(round(frac * len(ev))))])
        is_es[pos] = np.array([events[i] in es_ev for i in pos])

    neg = np.where(y == 0)[0]
    if len(neg):
        n_es = max(1, int(round(frac * len(neg))))
        is_es[rng.choice(neg, size=min(n_es, len(neg)), replace=False)] = True
    return ~is_es, is_es


def make_es_split(data: Data, idx: np.ndarray, mcfg, seed: int):
    """Dispatch the inner early-stopping split by config.

    cv.es_split_mode: "event" (Stage 5 P0 fix, default from Stage 6 onward)
                      "row"   (Stage 3/4 behaviour, kept so their numbers reproduce)
    """
    mode = mcfg.cv.get("es_split_mode", "row") if hasattr(mcfg.cv, "get") else "row"
    frac = mcfg.cv.inner_earlystop_block_frac
    if mode == "event":
        events = data.panel["event_id"].astype(str).to_numpy()[idx]
        return event_grouped_es_split(events, data.y[idx], frac, seed)
    blocks = data.panel["spatial_block_id"].to_numpy()[idx]
    return _inner_earlystop_split(blocks, frac, seed, y=data.y[idx])


def _scale_pos_weight(y: np.ndarray) -> float:
    npos = max(1, int(y.sum()))
    nneg = max(1, int(len(y) - y.sum()))
    return max(1e-3, nneg / npos)


def _fit_fold(data: Data, tr_idx, es_idx, mcfg, seed) -> LGBMBaseline:
    p = dict(mcfg.lgbm)
    p["seed"] = seed
    model = LGBMBaseline(
        params=p, features=data.features, categorical=data.categorical,
        monotone_increasing=list(mcfg.lgbm.monotone_rainfall_features),
    )
    Xtr, ytr, wtr = data.X(tr_idx), data.y[tr_idx], data.w[tr_idx]
    Xes, yes, wes = data.X(es_idx), data.y[es_idx], data.w[es_idx]
    spw = _scale_pos_weight(ytr) if mcfg.lgbm.auto_scale_pos_weight else None
    model.fit(Xtr, ytr, wtr, Xes, yes, wes, scale_pos_weight=spw)
    return model


def _fit_fold_tracked(data: Data, tr_idx, es_idx, mcfg, seed, ckpt_dir=None, fold_name="fold",
                      checkpoint_every=50) -> LGBMBaseline:
    """Like _fit_fold but tracks the train-vs-val curve and supports crash-resume
    via a periodic checkpoint. See TRAINING_STRATEGY.md for the resume contract
    (NOT bit-identical to an uninterrupted run — verified empirically)."""
    import json
    from pathlib import Path

    from sih_ml.models.lgbm_baseline import periodic_checkpoint_callback

    p = dict(mcfg.lgbm)
    p["seed"] = seed
    model = LGBMBaseline(
        params=p, features=data.features, categorical=data.categorical,
        monotone_increasing=list(mcfg.lgbm.monotone_rainfall_features),
    )
    Xtr, ytr, wtr = data.X(tr_idx), data.y[tr_idx], data.w[tr_idx]
    Xes, yes, wes = data.X(es_idx), data.y[es_idx], data.w[es_idx]
    spw = _scale_pos_weight(ytr) if mcfg.lgbm.auto_scale_pos_weight else None

    init_model, extra_cb = None, None
    if ckpt_dir is not None:
        ckpt_dir = Path(ckpt_dir)
        ckpt_dir.mkdir(parents=True, exist_ok=True)
        progress = ckpt_dir / f"{fold_name}_progress.json"
        if progress.exists():
            info = json.loads(progress.read_text())
            resume_path = ckpt_dir / info["path"]
            if resume_path.exists():
                log.info("resuming %s from checkpoint round %d (%s)",
                         fold_name, info["iteration"], resume_path.name)
                init_model = str(resume_path)
        extra_cb = [periodic_checkpoint_callback(
            str(ckpt_dir / (fold_name + "_ckpt_{iteration}.txt")),
            every=checkpoint_every, progress_json=str(progress),
        )]

    model.fit(Xtr, ytr, wtr, Xes, yes, wes, scale_pos_weight=spw,
             track_train_curve=True, init_model=init_model, extra_callbacks=extra_cb)
    return model


def run_spatial_cv_tracked(data: Data, mcfg, seed: int = 42, ckpt_root=None, checkpoint_every=50):
    """Spatial-CV training with MLflow logging, train/val curves, and crash-resume
    checkpoints — the Stage 4 'training from scratch' entry point. Same fold
    definitions and metric as run_spatial_cv (Stage 3); this adds the training
    infrastructure around it."""
    from pathlib import Path

    from sih_ml.train import tracking

    n = len(data.panel)
    oof = np.full(n, np.nan)
    fold_of = np.full(n, -1)
    models, best_iters, histories = {}, {}, {}
    for k in range(mcfg.cv.n_spatial_folds):
        fold_name = f"fold_{k}"
        tr_all, va = data.spatial_fold_indices(k, drop_buffer=mcfg.cv.drop_buffer_rows)
        m_tr, m_es = make_es_split(data, tr_all, mcfg, seed + k)
        tr_idx, es_idx = tr_all[m_tr], tr_all[m_es]

        ckpt_dir = Path(ckpt_root) / fold_name if ckpt_root else None
        with tracking.run(fold_name, params={"fold": k, "n_train": len(tr_idx),
                                             "n_earlystop": len(es_idx), **dict(mcfg.lgbm)},
                          nested=True):
            model = _fit_fold_tracked(data, tr_idx, es_idx, mcfg, seed + k,
                                      ckpt_dir=ckpt_dir, fold_name=fold_name,
                                      checkpoint_every=checkpoint_every)
            oof[va] = model.predict(data.X(va))
            fold_of[va] = k
            ap = _safe_ap(data.y[va], oof[va])
            tracking.log_curve(model.eval_history_)
            tracking.log_metrics({"val_AP": ap, "best_iteration": model.best_iteration_,
                                  "n_val": len(va), "pos_val": int(data.y[va].sum())})
        models[k] = model
        best_iters[k] = model.best_iteration_
        histories[k] = model.eval_history_
        log.info("spatial fold %d: n_tr=%d n_val=%d pos_val=%d best_iter=%d val_AP=%.3f",
                 k, len(tr_idx), len(va), int(data.y[va].sum()), model.best_iteration_, ap)
    return {"oof": oof, "fold_of": fold_of, "models": models, "best_iters": best_iters,
            "histories": histories}


def run_spatial_cv(data: Data, mcfg, seed: int = 42):
    n = len(data.panel)
    oof = np.full(n, np.nan)
    fold_of = np.full(n, -1)
    models, best_iters = {}, {}
    for k in range(mcfg.cv.n_spatial_folds):
        tr_all, va = data.spatial_fold_indices(k, drop_buffer=mcfg.cv.drop_buffer_rows)
        m_tr, m_es = make_es_split(data, tr_all, mcfg, seed + k)
        tr_idx, es_idx = tr_all[m_tr], tr_all[m_es]
        model = _fit_fold(data, tr_idx, es_idx, mcfg, seed + k)
        oof[va] = model.predict(data.X(va))
        fold_of[va] = k
        models[k] = model
        best_iters[k] = model.best_iteration_
        ap = _safe_ap(data.y[va], oof[va])
        log.info("spatial fold %d: n_tr=%d n_val=%d pos_val=%d best_iter=%d val_AP=%.3f",
                 k, len(tr_idx), len(va), int(data.y[va].sum()), model.best_iteration_, ap)
    return {"oof": oof, "fold_of": fold_of, "models": models, "best_iters": best_iters}


def _union_find_merge(pairs: list[tuple]) -> dict:
    parent: dict = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for a, b in pairs:
        union(a, b)
    return {k: find(k) for k in parent}


def run_loeco_cv(data: Data, mcfg, n_splits: int = 10, seed: int = 42):
    """Leave-one-event-cluster-out, merged with repeat-offender segments.

    Positives are folded by event_cluster_id, BUT a segment that shows up as a
    positive in more than one cluster (e.g. SEG291652, a repeat offender) would
    otherwise sit in both train and val — since its static terrain features are
    an exact per-segment fingerprint, the model can "memorize" that segment
    instead of learning the general rain-trigger relationship. This is caught by
    comparing to the spatial-block CV number: LOECO AP jumping far above it is
    the tell (see BASELINE_ANALYSIS.md). Fix: union-find every cluster that
    shares a segment_id into one group before assigning folds.
    Negatives (all cluster -1) are folded by a random K-way split so every fold
    gets a proportional negative sample."""
    rng = np.random.default_rng(seed)
    dev = np.where(data.dev_mask())[0]
    y = data.y[dev]
    clusters = data.loeco_groups()[dev]
    segs = data.panel["segment_id"].to_numpy()[dev]

    pos_rel = np.where(y == 1)[0]
    neg_rel = np.where(y == 0)[0]

    # merge clusters that share a repeat-offender segment
    seg_to_clusters: dict = {}
    for c, s in zip(clusters[pos_rel], segs[pos_rel]):
        seg_to_clusters.setdefault(s, set()).add(c)
    merge_pairs = [(sorted(cs)[0], c) for cs in seg_to_clusters.values() if len(cs) > 1 for c in cs]
    root_of = _union_find_merge(merge_pairs)

    pos_clusters = np.array(sorted(pd.unique(clusters[pos_rel])))
    group_of_cluster = {c: root_of.get(c, c) for c in pos_clusters}
    groups = np.array(sorted(set(group_of_cluster.values())))
    rng.shuffle(groups)
    grp_fold = {g: i % n_splits for i, g in enumerate(groups)}
    cl_fold = {c: grp_fold[group_of_cluster[c]] for c in pos_clusters}
    pos_fold = np.array([cl_fold[c] for c in clusters[pos_rel]])
    neg_fold = rng.integers(0, n_splits, size=len(neg_rel))

    fold_assign = np.full(len(dev), -1)
    fold_assign[pos_rel] = pos_fold
    fold_assign[neg_rel] = neg_fold

    oof = np.full(len(data.panel), np.nan)
    for i in range(n_splits):
        va = dev[fold_assign == i]
        tr_all = dev[fold_assign != i]
        m_tr, m_es = make_es_split(data, tr_all, mcfg, seed + i)
        model = _fit_fold(data, tr_all[m_tr], tr_all[m_es], mcfg, seed + 100 + i)
        oof[va] = model.predict(data.X(va))
        log.info("loeco fold %d: n_val=%d pos_val=%d AP=%.3f",
                 i, len(va), int(data.y[va].sum()), _safe_ap(data.y[va], oof[va]))
    return {"oof": oof}


def run_spatial_cv_linear(data: Data, mcfg, seed: int = 42):
    """Logistic-regression baseline over the same spatial folds (for comparison)."""
    from sih_ml.models.linear_baseline import LinearBaseline

    oof = np.full(len(data.panel), np.nan)
    for k in range(mcfg.cv.n_spatial_folds):
        tr, va = data.spatial_fold_indices(k, drop_buffer=mcfg.cv.drop_buffer_rows)
        m = LinearBaseline(data.spec, C=0.1, seed=seed + k)
        m.fit(data.X(tr), data.y[tr], data.w[tr])
        oof[va] = m.predict(data.X(va))
        log.info("linear fold %d: n_val=%d AP=%.3f", k, len(va), _safe_ap(data.y[va], oof[va]))
    return {"oof": oof}


def run_temporal(data: Data, mcfg, seed: int = 42):
    tr, va, te = data.temporal_indices()
    model = _fit_fold(data, tr, va, mcfg, seed + 7)
    pred = {"val": (va, model.predict(data.X(va))),
            "test": (te, model.predict(data.X(te)))}
    log.info("temporal: n_tr=%d n_val=%d n_test=%d pos_test=%d test_AP=%.3f",
             len(tr), len(va), len(te), int(data.y[te].sum()),
             _safe_ap(data.y[te], pred["test"][1]))
    return {"model": model, "pred": pred}


def fit_final(data: Data, mcfg, n_estimators: int, seed: int = 42) -> LGBMBaseline:
    """Train on ALL dev data with a fixed round count (mean of fold best_iters).
    No early stopping — a tiny block holdout is used only to satisfy the API."""
    dev = np.where(data.dev_mask())[0]
    blocks = data.panel["spatial_block_id"].to_numpy()[dev]
    m_tr, m_es = _inner_earlystop_split(blocks, 0.1, seed)
    p = dict(mcfg.lgbm)
    p["n_estimators"] = int(n_estimators)
    p["early_stopping_rounds"] = 10 ** 9      # effectively disabled
    p["seed"] = seed
    model = LGBMBaseline(p, data.features, data.categorical,
                         list(mcfg.lgbm.monotone_rainfall_features))
    spw = _scale_pos_weight(data.y[dev[m_tr]])
    model.fit(data.X(dev[m_tr]), data.y[dev[m_tr]], data.w[dev[m_tr]],
              data.X(dev[m_es]), data.y[dev[m_es]], data.w[dev[m_es]], scale_pos_weight=spw)
    model.best_iteration_ = int(n_estimators)
    return model


def _safe_ap(y, p):
    from sklearn.metrics import average_precision_score
    return float(average_precision_score(y, p)) if np.asarray(y).sum() else float("nan")
