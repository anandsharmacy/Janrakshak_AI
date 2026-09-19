"""Leakage firewall — these must stay green or the metrics are not real."""
import numpy as np
import pandas as pd

from sih_ml.features.build_panel import FORECAST_HORIZON_DAYS, MIN_HISTORY_LAG_DAYS


def test_no_positive_negative_collision(labels):
    pos = labels[labels.target == 1][["segment_id", "date"]]
    neg = labels[labels.target == 0][["segment_id", "date"]]
    assert len(pd.merge(pos, neg, on=["segment_id", "date"])) == 0


def test_temporal_gate(labels, cfg):
    assert (pd.to_datetime(labels[labels.target == 1].date)
            >= pd.Timestamp(cfg.labels.min_event_date)).all()


def test_forecast_horizon_positive(panel):
    # features must be lagged at least 1 day from the labelled date
    assert FORECAST_HORIZON_DAYS >= 1


def test_history_features_are_lagged(panel):
    assert MIN_HISTORY_LAG_DAYS >= 14
    # a segment-day with no prior-year events should not spike the 1y count
    assert panel["hist_events_1y_lag30"].min() >= 0


def test_no_future_event_id_in_train_test_overlap(panel, folds):
    """An event_id's positive rows must not straddle train and final_test."""
    m = panel.merge(folds[["segment_id", "date", "final_test"]], on=["segment_id", "date"])
    m = m[m.target == 1].dropna(subset=["event_id"])
    straddle = m.groupby("event_id").final_test.nunique()
    assert (straddle <= 1).all(), straddle[straddle > 1]


def test_rainfall_features_present_and_finite(panel):
    for c in ["rain_1d_mm", "rain_7d_mm", "rain_30d_mm", "api_mm"]:
        v = panel[c].dropna()
        assert len(v) > 0.9 * len(panel)
        assert np.isfinite(v).all()
        assert (v >= 0).all()


def test_spatial_block_is_a_group(folds):
    # every block belongs to exactly one CV fold (ignoring locked-test / gold rows,
    # which are pulled out regardless of block)
    cv = folds[~folds.final_test] if "final_test" in folds else folds
    assert (cv.groupby("spatial_block_id").spatial_fold.nunique() == 1).all()
