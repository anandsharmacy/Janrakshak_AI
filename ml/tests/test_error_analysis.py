"""Stage 5 tests: the analysis functions must be correct, and the evaluation must
never touch the locked test split."""
import json

import numpy as np
import pandas as pd
import pytest

from sih_ml.eval import error_analysis as ea
from sih_ml.utils.common import REPO_ROOT, load_config_with_base, resolve

TRAIN_CFG = REPO_ROOT / "conf" / "train_config.yaml"


@pytest.fixture(scope="module")
def stage5_dir():
    mcfg = load_config_with_base(TRAIN_CFG)
    return resolve(mcfg, "reports/stage5")


# ------------------------------------------------------------------ unit tests
def test_safe_metrics_handles_degenerate_labels():
    """All-negative / all-positive strata must yield NaN, not a crash or a fake 0."""
    m = ea._safe_metrics(np.zeros(50, int), np.random.rand(50))
    assert np.isnan(m["AP"]) and np.isnan(m["ROC_AUC"])
    assert m["n"] == 50 and m["n_pos"] == 0


def test_safe_metrics_perfect_ranking():
    y = np.array([0] * 90 + [1] * 10)
    m = ea._safe_metrics(y, y.astype(float))
    assert m["AP"] == pytest.approx(1.0)
    assert m["base_rate"] == pytest.approx(0.10)


def test_cohens_d_sign_and_scale():
    a = pd.Series(np.random.default_rng(0).normal(10, 1, 500))
    b = pd.Series(np.random.default_rng(1).normal(9, 1, 500))
    d = ea._std_mean_diff(a, b)
    assert d > 0                      # a > b
    assert 0.5 < d < 1.5              # ~1 sd apart


def test_qbucket_survives_heavy_ties():
    """Rainfall is mostly zeros — qcut must not explode on duplicate edges."""
    s = pd.Series([0.0] * 900 + list(np.linspace(1, 50, 100)))
    out = ea._qbucket(s)
    assert len(out) == len(s)
    assert out.notna().all()


# ----------------------------------------------------- the locked-split guard
def test_error_analysis_excludes_locked_final_test():
    """The OOF predictions used for error analysis must contain ZERO rows from the
    locked final_test split. If this ever fails, Stage 8 is compromised."""
    mcfg = load_config_with_base(TRAIN_CFG)
    oof_path = resolve(mcfg, mcfg.paths.models) / mcfg.model_version / "oof_predictions.parquet"
    if not oof_path.exists():
        pytest.skip("run `make stage4` first")
    oof = pd.read_parquet(oof_path)
    folds = pd.read_parquet(resolve(mcfg, mcfg.paths.folds))
    merged = oof.merge(folds[["segment_id", "date", "final_test"]],
                       on=["segment_id", "date"], how="left")
    assert merged.final_test.sum() == 0, "LOCKED final_test rows leaked into error analysis"


def test_no_gold_labels_in_evaluation_set():
    """Corollary: all gold labels live in the locked split, so the evaluated
    positives are weak labels only. Documented so it is never forgotten."""
    mcfg = load_config_with_base(TRAIN_CFG)
    oof_path = resolve(mcfg, mcfg.paths.models) / mcfg.model_version / "oof_predictions.parquet"
    if not oof_path.exists():
        pytest.skip("run `make stage4` first")
    oof = pd.read_parquet(oof_path)
    assert (oof.label_tier == "gold").sum() == 0


# ------------------------------------------------------------ artifact checks
def test_stage5_artifacts_exist(stage5_dir):
    if not (stage5_dir / "error_analysis.json").exists():
        pytest.skip("run `make stage5` first")
    for f in ["EVALUATION_REPORT.md", "ERROR_ANALYSIS.md", "stratified_performance.csv",
              "per_event_detection.csv", "fn_vs_tp_probe.csv", "label_noise_probe.csv",
              "es_signal_saturation.csv", "es_leakage_units.csv",
              "worst_false_negatives.csv", "worst_false_positives.csv"]:
        assert (stage5_dir / f).exists(), f


def test_es_saturation_is_detected(stage5_dir):
    """The known defect must be surfaced, not silently passed over."""
    p = stage5_dir / "error_analysis.json"
    if not p.exists():
        pytest.skip("run `make stage5` first")
    r = json.loads(p.read_text())
    assert "es_signal" in r
    assert r["es_signal"]["mean_AP_earlystop"] > 0.95
    assert "SATURATED" in r["es_signal"]["verdict"]
    assert r["es_leakage_units"]["event_id"] == pytest.approx(1.0, abs=1e-6)


def test_generalization_gap_ordering(stage5_dir):
    """in-sample >= held-out region >= out-of-time. Any other ordering means
    something is wrong with the splits."""
    p = stage5_dir / "error_analysis.json"
    if not p.exists():
        pytest.skip("run `make stage5` first")
    g = json.loads(p.read_text())["generalization_gap"]
    assert (g["in_sample_dev"]["average_precision"]
            > g["held_out_spatial_oof"]["average_precision"]
            > g["out_of_time_test"]["average_precision"])
