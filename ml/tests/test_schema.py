import numpy as np
import pandas as pd

from sih_ml.preprocess.transformers import load_feature_spec, model_feature_columns


def test_panel_has_all_spec_columns(panel):
    spec = load_feature_spec()
    missing = [c for c in model_feature_columns(spec) if c not in panel.columns]
    assert not missing, missing


def test_target_binary(panel):
    assert set(panel.target.unique()) <= {0, 1}


def test_confidence_range(labels):
    c = labels.label_confidence
    assert c.between(0, 1).all()


def test_sample_weight_range(panel):
    assert panel.sample_weight.between(0.0, 1.0).all()


def test_soil_nodata_handled(panel):
    # rows flagged soil_is_missing must actually have NaN soil
    miss = panel[panel.soil_is_missing == 1]
    assert miss.soil_clay_0_5cm_pct.isna().all()


def test_no_duplicate_segment_days(panel):
    assert not panel.duplicated(["segment_id", "date"]).any()


def test_dtypes_reasonable(panel):
    assert pd.api.types.is_datetime64_any_dtype(panel.date)
    assert np.issubdtype(panel.slope_mean_deg.dtype, np.floating)
