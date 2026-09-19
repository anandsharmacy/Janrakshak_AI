"""Publisher contract: what reaches the shared database, and what is refused.

Unit tests need nothing but pandas. The database tests run only when
SIH_TEST_DSN points at a Postgres with the ML migration applied (the local
Supabase stack), and each runs inside a transaction that is rolled back.
"""
from __future__ import annotations

import json
import os

import numpy as np
import pandas as pd
import pytest

from sih_ml.serve import publish as P


def _day(tmp_path, date="2025-08-05", n=6, tiers=None, **overrides):
    tiers = tiers or ["none", "none", "none", "alert", "human_review", "none"][:n]
    df = pd.DataFrame({
        "segment_id": [f"SEGT{i:04d}" for i in range(n)],
        "raw_score": np.linspace(0.001, 0.9, n),
        "p_calibrated": np.linspace(0.0, 0.5, n),
        "risk_percentile": np.linspace(1, 99.9, n),
        "steep": [False] * (n - 1) + [True],
        "tier": tiers,
        "tier_rank": np.arange(1, n + 1),
    })
    for k, v in overrides.items():
        df[k] = v
    d = tmp_path / f"date={date}"
    d.mkdir(parents=True)
    df.to_parquet(d / "scores.parquet", index=False)
    counts = pd.Series(tiers).value_counts().to_dict()
    run = {"date": date, "bundle_version": "test_v0", "bundle_hash": f"test{date}",
           "featurestore_schema_sha256": "x", "rain_feed_end": "2025-12-31", "n_segments": n,
           "tiers": {k: int(v) for k, v in counts.items()}, "drift": {}, "data_quality": {}}
    (d / "run.json").write_text(json.dumps(run))
    return run, df


# --------------------------------------------------------------------------- unit
def test_missing_day_is_input_error(tmp_path):
    with pytest.raises(P.PublishInputError, match="no batch output"):
        P.load_day(tmp_path, "2025-08-05")


def test_live_mode_refused_for_old_days():
    with pytest.raises(P.PublishInputError, match="--mode replay"):
        P.check_mode("live", "2025-08-05", today="2026-09-12")
    P.check_mode("replay", "2025-08-05", today="2026-09-12")
    P.check_mode("live", "2026-09-11", today="2026-09-12")
    with pytest.raises(P.PublishInputError):
        P.check_mode("forecast", "2026-09-11")


def test_score_rows_round_trip(tmp_path):
    _, df = _day(tmp_path)
    rows = list(P.score_rows(df, 7))
    assert len(rows) == len(df)
    assert rows[0] == (7, "SEGT0000", 0.001, 0.0, 1.0, False, "none", 1)
    assert [len(r) for r in rows] == [len(P.SCORE_COLUMNS)] * len(df)


@pytest.mark.parametrize("col,value,match", [
    ("raw_score", np.nan, "non-finite"),
    ("p_calibrated", 1.5, "out-of-range"),
    ("risk_percentile", -1.0, "out-of-range"),
    ("tier", "maybe", "unknown tiers"),
])
def test_score_rows_refuse_bad_values(tmp_path, col, value, match):
    _, df = _day(tmp_path)
    df.loc[2, col] = value
    with pytest.raises(P.PublishInputError, match=match):
        list(P.score_rows(df, 1))


def test_score_rows_refuse_duplicates(tmp_path):
    _, df = _day(tmp_path)
    df.loc[1, "segment_id"] = df.loc[0, "segment_id"]
    with pytest.raises(P.PublishInputError, match="duplicate"):
        list(P.score_rows(df, 1))


def test_segment_rows_ewkt_and_steep():
    seg = pd.DataFrame({"segment_id": ["A", "B", "C"], "lon": [88.5, 88.6, 88.7],
                        "lat": [27.1, 27.2, 27.3], "slope_mean_deg": [3.0, 10.0, np.nan],
                        "cell_index": [0, 1, 2]})
    rows = list(P.segment_rows(seg, steep_deg=10.0))
    assert rows[0] == ("A", "SRID=4326;POINT(88.5000000 27.1000000)", 3.0, False, 0)
    assert rows[1][3] is True                      # at the threshold counts as steep
    assert rows[2][2] is None and rows[2][3] is False


def test_segment_table_falls_back_to_centroids(tmp_path):
    pd.DataFrame({"segment_id": ["A", "B"], "cell_index": [0, 0],
                  "slope_mean_deg": [1.0, 2.0]}).to_parquet(tmp_path / "segments.parquet")
    cent = tmp_path / "cent.parquet"
    pd.DataFrame({"segment_id": ["A", "B"], "lon": [88.0, 88.1], "lat": [27.0, 27.1]}).to_parquet(cent)
    seg = P.segment_table(tmp_path, cent)
    assert seg.lon.tolist() == [88.0, 88.1]
    pd.DataFrame({"segment_id": ["A"], "lon": [88.0], "lat": [27.0]}).to_parquet(cent)
    with pytest.raises(P.PublishInputError, match="no coordinates"):
        P.segment_table(tmp_path, cent)


def test_coverage_polygons_are_cell_boxes():
    polys = P.coverage_polygons(["25.625_87.125", "25.625_87.375", "25.875_87.125"])
    assert len(polys) == 3
    assert polys[0] == ("POLYGON((87.0 25.5,87.25 25.5,87.25 25.75,87.0 25.75,87.0 25.5))")


# ------------------------------------------------------------------------ database
DSN = os.environ.get("SIH_TEST_DSN")
db = pytest.mark.skipif(not DSN, reason="set SIH_TEST_DSN to run publisher database tests")


@pytest.fixture
def conn():
    psycopg = pytest.importorskip("psycopg")
    c = psycopg.connect(DSN)
    # Open the outer transaction now: psycopg only turns conn.transaction() into a
    # SAVEPOINT when one is already in progress — otherwise it would COMMIT.
    c.execute("select 1")
    try:
        yield c
    finally:
        c.rollback()
        c.close()


@pytest.fixture
def bundle(tmp_path):
    b = tmp_path / "bundle"
    b.mkdir()
    (b / "manifest.json").write_text(json.dumps({"version": "test_v0"}))
    (b / "policy.json").write_text(json.dumps({"steep_slope_deg": 10.0,
                                               "primary_output": "risk_percentile",
                                               "probability_caveat": "test"}))
    return b


def _current(conn):
    with conn.cursor() as cur:
        cur.execute("select id, score_date::text from public.ml_batch_runs where is_current")
        return cur.fetchone()


@db
def test_fixture_rolls_back(tmp_path, bundle):
    """Guards the guard: a test publish must not survive the test."""
    psycopg = pytest.importorskip("psycopg")
    _day(tmp_path, "2025-08-11")
    with psycopg.connect(DSN) as c:
        c.execute("select 1")
        P.publish_run(c, tmp_path, bundle, "2025-08-11", "replay", set_current=False)
        c.rollback()
    with psycopg.connect(DSN) as c:
        n = c.execute("select count(*) from public.ml_batch_runs where score_date = '2025-08-11'").fetchone()[0]
    assert n == 0


@db
def test_publish_run_attaches_and_becomes_current(conn, tmp_path, bundle):
    _day(tmp_path, "2025-08-06")
    out = P.publish_run(conn, tmp_path, bundle, "2025-08-06", "replay")
    assert out["rows"] == 6 and out["current"] is True
    assert _current(conn)[1] == "2025-08-06"
    with conn.cursor() as cur:
        cur.execute("select count(*), count(*) filter (where tier = 'alert') "
                    "from public.ml_segment_scores where run_id = %s", (out["run_id"],))
        assert cur.fetchone() == (6, 1)


@db
def test_publish_run_is_idempotent(conn, tmp_path, bundle):
    _day(tmp_path, "2025-08-07")
    first = P.publish_run(conn, tmp_path, bundle, "2025-08-07", "replay")
    again = P.publish_run(conn, tmp_path, bundle, "2025-08-07", "replay")
    assert again["already_published"] is True and again["run_id"] == first["run_id"]


@db
def test_tier_mismatch_publishes_nothing(conn, tmp_path, bundle):
    import psycopg
    before = _current(conn)
    run, _ = _day(tmp_path, "2025-08-08")
    run["tiers"] = {"none": 6}                    # run.json disagrees with the rows
    (tmp_path / "date=2025-08-08" / "run.json").write_text(json.dumps(run))
    with pytest.raises(psycopg.Error, match="tier counts"):
        P.publish_run(conn, tmp_path, bundle, "2025-08-08", "replay")
    assert _current(conn) == before
    with conn.cursor() as cur:
        cur.execute("select count(*) from public.ml_batch_runs where score_date = '2025-08-08'")
        assert cur.fetchone()[0] == 0


@db
def test_set_current_switches_back(conn, tmp_path, bundle):
    _day(tmp_path, "2025-08-09")
    _day(tmp_path, "2025-08-10")
    P.publish_run(conn, tmp_path, bundle, "2025-08-09", "replay")
    P.publish_run(conn, tmp_path, bundle, "2025-08-10", "replay")
    assert _current(conn)[1] == "2025-08-10"
    P.set_current(conn, "2025-08-09")
    assert _current(conn)[1] == "2025-08-09"


def test_featurestore_round_trips_lonlat(tmp_path):
    """A store saved with centroids hands them to the publisher without the fallback file."""
    from sih_ml.serve.featurestore import FeatureStore
    schema = {"features": ["r1", "s1"], "rainfall_cols": ["r1"], "season_cols": ["s1"]}
    rain = pd.DataFrame({"25.625_87.125": [1.0]}, index=pd.DatetimeIndex(["2025-08-01"]))
    fs = FeatureStore(np.array(["A", "B"]), np.zeros((2, 2)), np.array(["25.625_87.125"]),
                      np.array([0, 0]), np.array([1.0, 12.0]), rain, schema,
                      {"schema_sha256": "x"}, lonlat=np.array([[88.1, 27.1], [88.2, 27.2]]))
    fs.save(tmp_path)
    seg = P.segment_table(tmp_path, centroids=tmp_path / "does-not-exist.parquet")
    assert seg[["lon", "lat"]].to_numpy().tolist() == [[88.1, 27.1], [88.2, 27.2]]
