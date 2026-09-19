"""Stage 4 tests: determinism, resume contract, early-stopping metric wiring,
checkpoint integrity. Run `make stage4` first for the artifact-dependent ones.
"""
import json
import shutil
from pathlib import Path

import numpy as np
import pytest

from sih_ml.models.dataset import load_data
from sih_ml.models.lgbm_baseline import LGBMBaseline
from sih_ml.train import cv
from sih_ml.utils.common import REPO_ROOT, Config, load_config_with_base, resolve

TRAIN_CFG = REPO_ROOT / "conf" / "train_config.yaml"


@pytest.fixture(scope="module")
def train_data():
    return load_data(TRAIN_CFG)


def _small_fold(data, mcfg, rounds=30):
    """A deliberately tiny fit so these tests stay fast."""
    tr_all, va = data.spatial_fold_indices(0, drop_buffer=True)
    blocks = data.panel["spatial_block_id"].to_numpy()[tr_all]
    m_tr, m_es = cv._inner_earlystop_split(blocks, 0.15, 42, y=data.y[tr_all])
    cfg = dict(mcfg)
    cfg["lgbm"] = dict(mcfg.lgbm)
    cfg["lgbm"]["n_estimators"] = rounds
    return tr_all[m_tr], tr_all[m_es], va, Config(cfg)


# --------------------------------------------------------------- config wiring
def test_stage4_uses_pr_auc_early_stopping():
    """The declared primary metric must be the one driving early stopping.
    LightGBM otherwise also tracks binary_logloss and stops on whichever goes
    stale first — which silently truncated folds 0/1 in Stage 3."""
    mcfg = load_config_with_base(TRAIN_CFG)
    assert mcfg.lgbm.early_stopping_metric == "pr_auc"
    m = LGBMBaseline(dict(mcfg.lgbm), ["a"], [])
    assert m._lgb_params(None)["metric"] == "None"


def test_stage3_config_unchanged_for_reproducibility():
    """Stage 3's config must keep the old behaviour so its published numbers
    remain reproducible."""
    base = load_config_with_base(REPO_ROOT / "conf" / "model_baseline.yaml")
    assert base.lgbm.get("early_stopping_metric", "both") == "both"
    m = LGBMBaseline(dict(base.lgbm), ["a"], [])
    assert "metric" not in m._lgb_params(None)


def test_train_config_inherits_base():
    """Stage 4 overrides only a handful of keys; everything else must come from
    conf/model_baseline.yaml via the deep merge."""
    mcfg = load_config_with_base(TRAIN_CFG)
    assert mcfg.model_version == "training_v1"          # overridden (top level)
    assert mcfg.paths.reports == "reports/stage4"       # overridden (nested)
    assert mcfg.cv.n_spatial_folds == 5                 # inherited section
    assert mcfg.eval.primary_metric == "average_precision"
    # lgbm: Stage 4 sets only early_stopping_metric + n_estimators — the rest of
    # the base block must survive the merge rather than replacing it wholesale.
    assert mcfg.lgbm.early_stopping_metric == "pr_auc"  # overridden
    assert mcfg.lgbm.num_leaves == 24                   # inherited
    assert mcfg.lgbm.monotone_rainfall_features         # inherited (non-empty)


# --------------------------------------------------------------- determinism
def test_same_seed_same_predictions(train_data):
    data, mcfg = train_data
    tr, es, va, cfg = _small_fold(data, mcfg, rounds=25)
    m1 = cv._fit_fold(data, tr, es, cfg, seed=7)
    m2 = cv._fit_fold(data, tr, es, cfg, seed=7)
    np.testing.assert_allclose(m1.predict(data.X(va)), m2.predict(data.X(va)), rtol=0, atol=0)


def test_different_seed_different_predictions(train_data):
    """Sanity: the seed actually does something (guards against a silently
    ignored seed making the determinism test vacuous)."""
    data, mcfg = train_data
    tr, es, va, cfg = _small_fold(data, mcfg, rounds=25)
    p1 = cv._fit_fold(data, tr, es, cfg, seed=7).predict(data.X(va))
    p2 = cv._fit_fold(data, tr, es, cfg, seed=99).predict(data.X(va))
    assert not np.allclose(p1, p2)


# --------------------------------------------------------------- resume
def test_resume_from_checkpoint_continues(train_data, tmp_path):
    """A resumed fold must CONTINUE from its checkpoint, not restart.

    Note the resume contract (verified empirically, documented in
    TRAINING_STRATEGY.md): resumed training is NOT bit-identical to one
    uninterrupted run, because bagging/feature-sampling RNG restarts at the
    boundary. It is for crash recovery, not for reproducing a specific run."""
    data, mcfg = train_data
    tr, es, va, cfg = _small_fold(data, mcfg, rounds=40)
    ck = tmp_path / "ck"
    m1 = cv._fit_fold_tracked(data, tr, es, cfg, 42, ckpt_dir=ck,
                              fold_name="fold_0", checkpoint_every=10)
    prog = json.loads((ck / "fold_0_progress.json").read_text())
    assert prog["iteration"] >= 10
    m2 = cv._fit_fold_tracked(data, tr, es, cfg, 42, ckpt_dir=ck,
                              fold_name="fold_0", checkpoint_every=10)
    assert m2.booster_.current_iteration() > m1.booster_.current_iteration()


def test_checkpoint_files_are_loadable(train_data, tmp_path):
    data, mcfg = train_data
    tr, es, va, cfg = _small_fold(data, mcfg, rounds=25)
    ck = tmp_path / "ck"
    cv._fit_fold_tracked(data, tr, es, cfg, 42, ckpt_dir=ck,
                         fold_name="fold_0", checkpoint_every=10)
    import lightgbm as lgb
    for p in ck.glob("fold_0_ckpt_*.txt"):
        b = lgb.Booster(model_file=str(p))
        assert b.current_iteration() > 0


# --------------------------------------------------------------- curves
def test_train_curve_recorded_and_excluded_from_early_stopping(train_data):
    data, mcfg = train_data
    tr, es, va, cfg = _small_fold(data, mcfg, rounds=25)
    m = cv._fit_fold_tracked(data, tr, es, cfg, 42)
    assert "es" in m.eval_history_
    # name MUST be exactly "training" or LightGBM will let it drive early stopping
    assert "training" in m.eval_history_
    assert len(m.eval_history_["es"]["pr_auc"]) > 0


# --------------------------------------------------------------- artifacts
def test_stage4_artifacts_and_consistency():
    mcfg = load_config_with_base(TRAIN_CFG)
    rdir = resolve(mcfg, mcfg.paths.reports)
    mdir = resolve(mcfg, mcfg.paths.models) / mcfg.model_version
    if not (rdir / "metrics.json").exists():
        pytest.skip("run `make stage4` first")
    m = json.loads((rdir / "metrics.json").read_text())
    assert 0 <= m["spatial_cv"]["mean_AP"] <= 1
    assert m["spatial_cv"]["pooled"]["roc_auc"] < 0.97, "suspiciously high — check for leakage"
    assert (mdir / "final.txt").exists()
    assert (mdir / "model_card.json").exists()
    for k in range(mcfg.cv.n_spatial_folds):
        assert (rdir / f"training_curve_fold{k}.png").exists()


def test_checkpoints_cleaned_after_success():
    mcfg = load_config_with_base(TRAIN_CFG)
    ck = resolve(mcfg, mcfg.paths.checkpoints) / mcfg.model_version
    if not (resolve(mcfg, mcfg.paths.reports) / "metrics.json").exists():
        pytest.skip("run `make stage4` first")
    if mcfg.training.clean_checkpoints_on_success:
        assert not ck.exists(), "checkpoints should be removed after a successful run"
