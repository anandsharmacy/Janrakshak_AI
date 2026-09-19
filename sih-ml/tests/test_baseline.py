"""Stage 3 baseline tests: leakage in CV, checkpoint round-trip, calibration sanity.

These run against whatever is currently in models/baseline_v1/ + reports/stage3/ —
run `make stage3` first if they're missing.
"""
import json

import numpy as np
import pandas as pd
import pytest

from sih_ml.models.dataset import load_data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.models.calibration import Calibrator
from sih_ml.utils.common import resolve


def _paths():
    data, mcfg = load_data()
    mdir = resolve(mcfg, mcfg.paths.models) / mcfg.model_version
    rdir = resolve(mcfg, mcfg.paths.reports)
    return data, mcfg, mdir, rdir


def test_checkpoint_roundtrip():
    data, mcfg, mdir, rdir = _paths()
    if not (mdir / "final.txt").exists():
        pytest.skip("run `make stage3` first")
    m = LGBMBaseline.load(mdir / "final.txt")
    assert set(m.features) == set(data.features)
    p = m.predict(data.X(np.arange(min(500, len(data.panel)))))
    assert np.isfinite(p).all()
    assert ((p >= 0) & (p <= 1)).all()


def test_fold_checkpoints_exist():
    _, mcfg, mdir, _ = _paths()
    if not mdir.exists():
        pytest.skip("run `make stage3` first")
    for k in range(mcfg.cv.n_spatial_folds):
        assert (mdir / f"fold_{k}.txt").exists()
        assert (mdir / f"fold_{k}.meta.json").exists()


def test_calibrator_roundtrip():
    _, mcfg, mdir, _ = _paths()
    if not (mdir / "calibrator.pkl").exists():
        pytest.skip("run `make stage3` first")
    cal = Calibrator.load(mdir / "calibrator.pkl")
    p = np.array([0.01, 0.05, 0.1, 0.3, 0.6, 0.9])
    q = cal.transform(p)
    assert np.isfinite(q).all()
    assert ((q > 0) & (q < 1)).all()
    # monotone: calibration must preserve rank order (isotonic by construction)
    assert (np.diff(q) >= -1e-9).all()


def test_oof_predictions_no_label_leak():
    """Every OOF row's fold must be a VAL fold for that row — i.e. a row is only
    ever scored by a model that did not train on it."""
    _, mcfg, mdir, _ = _paths()
    p = mdir / "oof_predictions.parquet"
    if not p.exists():
        pytest.skip("run `make stage3` first")
    oof = pd.read_parquet(p)
    folds = pd.read_parquet(resolve(mcfg, mcfg.paths.folds))
    m = oof.merge(folds, on=["segment_id", "date"], suffixes=("", "_f"))
    for k in range(mcfg.cv.n_spatial_folds):
        rows_in_fold_k = m[m.spatial_fold == k]
        if rows_in_fold_k.empty:
            continue
        assert (rows_in_fold_k[f"spatial_role_f{k}"] == "val").all()


def test_metrics_json_sane():
    _, _, _, rdir = _paths()
    p = rdir / "metrics.json"
    if not p.exists():
        pytest.skip("run `make stage3` first")
    m = json.loads(p.read_text())
    sp = m["spatial_cv"]
    assert 0 <= sp["pooled"]["average_precision"] <= 1
    assert sp["pooled"]["average_precision"] > m["rule_baselines"]["majority_class"]["average_precision"]
    # honest-AUC sanity per the project's own compass doc: >0.97 spatial ROC-AUC on
    # this label-scarce a dataset is a red flag, not a win
    assert sp["pooled"]["roc_auc"] < 0.97


def test_final_model_round_count_not_pinned_to_cap():
    """If every fold hits the n_estimators cap, the search range is too small —
    this doesn't fail the build but should be visibly reported."""
    _, mcfg, _, rdir = _paths()
    p = rdir / "metrics.json"
    if not p.exists():
        pytest.skip("run `make stage3` first")
    m = json.loads(p.read_text())
    iters = list(m["fold_best_iters"].values())
    capped = sum(i >= mcfg.lgbm.n_estimators for i in iters)
    # not a hard assertion — record-only. Fails loudly so it's never silently ignored.
    if capped == len(iters):
        pytest.fail("every fold hit the n_estimators cap — raise n_estimators in Stage 4")
