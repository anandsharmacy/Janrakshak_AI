"""Stage 11 serving contract tests.

The serving path is only allowed to be faster than the training path, never
different from it. These tests pin: feature parity with the training panel, bit-
identical predictions and calibration, bundle integrity, input validation, the output
policy, the batch job's guarantees and the API's error contract.

Skipped until the deployment artifacts exist (`python -m sih_ml.serve.build`).
"""
from __future__ import annotations

import ast
import io
import json
import shutil

import numpy as np
import pandas as pd
import pytest

from sih_ml.utils.common import REPO_ROOT

BUNDLE = REPO_ROOT / "deploy" / "bundles" / "current"
STORE = REPO_ROOT / "deploy" / "featurestore"
pytestmark = pytest.mark.skipif(not (BUNDLE / "manifest.json").exists(),
                                reason="run `python -m sih_ml.serve.build` first")
DATE = "2025-08-15"


@pytest.fixture(scope="module")
def bundle():
    from sih_ml.serve.bundle import Bundle
    return Bundle.load(BUNDLE)


@pytest.fixture(scope="module")
def store(bundle):
    from sih_ml.serve.featurestore import FeatureStore
    return FeatureStore.load(STORE, bundle.schema)


@pytest.fixture(scope="module")
def panel_sample():
    from sih_ml.models.dataset import load_data
    data, _ = load_data(REPO_ROOT / "conf" / "improve_config.yaml")
    P = data.panel.iloc[np.where(data.dev_mask())[0]]
    P = P[P.date <= "2025-12-31"]
    dates = np.random.default_rng(1).choice(P.date.unique(), 40, replace=False)
    return P[P.date.isin(dates)]


# ------------------------------------------------------------------- parity
def test_feature_parity_with_panel(bundle, store, panel_sample):
    """Every feature of every sampled training row, rebuilt by the serving store."""
    for d, g in panel_sample.groupby("date"):
        pos, missing = store.positions(g.segment_id.to_numpy())
        assert not missing
        Xs = store.matrix(pd.Timestamp(d), rows=pos)
        for j, c in enumerate(bundle.features):
            if c in bundle.schema["categorical"]:
                lv = pd.Index(bundle.schema["category_levels"][c])
                v = lv.get_indexer(g[c].astype(str).to_numpy()).astype(float)
                v[v < 0] = np.nan
            else:
                v = g[c].to_numpy(float)
            a = Xs[:, j]
            assert ((a == v) | (np.isnan(a) & np.isnan(v))).all(), (str(d), c)


def test_predictions_bit_identical_to_training_path(bundle, store, panel_sample):
    from sih_ml.models.lgbm_baseline import LGBMBaseline
    m = LGBMBaseline.load(REPO_ROOT / "models" / bundle.version / "model.txt")
    g = panel_sample
    rows = np.concatenate([store.positions(x.segment_id.to_numpy())[0] for _, x in g.groupby("date")])
    Xs = np.vstack([store.matrix(pd.Timestamp(d), rows=store.positions(x.segment_id.to_numpy())[0])
                    for d, x in g.groupby("date")])
    ordered = pd.concat([x for _, x in g.groupby("date")])
    assert len(rows) == len(ordered)
    assert np.array_equal(m.predict(ordered[m.features]), bundle.booster.predict(Xs))


def test_json_calibration_equals_pickled_calibrators(bundle):
    from sih_ml.models.calibration import Calibrator
    from sih_ml.optimize.calibrate import slope_stratum as train_stratum
    from sih_ml.serve.bundle import slope_stratum
    rng = np.random.default_rng(0)
    raw = rng.uniform(0, 1, 20000) ** 3
    slope = rng.uniform(0, 45, 20000)
    s = slope_stratum(slope, bundle.calibration.bins)

    class D:                                        # the training helper takes a Data
        panel = pd.DataFrame({"slope_mean_deg": slope})
    assert np.array_equal(s, train_stratum(D, bundle.calibration.bins))
    mdir = REPO_ROOT / "models" / bundle.version
    ref = Calibrator.load(mdir / "calibrator_pooled.pkl").transform(raw)
    for k in np.unique(s):
        ref[s == k] = Calibrator.load(mdir / f"calibrator_slope_{k}.pkl").transform(raw[s == k])
    assert np.array_equal(ref, bundle.calibration(raw, slope))


def test_whatif_path_matches_feed_path(bundle, store):
    """Supplying a cell's own feed history through the what-if path must give the
    same rainfall features as the operational path."""
    from sih_ml.serve.featurestore import rainfall_from_history
    d = pd.Timestamp(DATE)
    cut = d - pd.Timedelta(days=1)
    cell = store.cell_ids[0]
    hist = store.rain.loc[:cut, cell].to_numpy()[-int(bundle.schema["history_days"]):]
    a = rainfall_from_history(hist, d, bundle.schema["rainfall_cols"])
    b = store.rainfall_by_cell(d)[0]
    assert np.allclose(a, b, equal_nan=True, rtol=0, atol=1e-9)


# ------------------------------------------------------------------ bundle
def test_tampered_bundle_refuses_to_load(tmp_path):
    from sih_ml.serve.bundle import Bundle, BundleError
    dst = tmp_path / "b"
    shutil.copytree(BUNDLE.resolve(), dst)
    p = dst / "policy.json"
    pol = json.loads(p.read_text())
    pol["alert_probability_threshold"] = 0.5
    p.write_text(json.dumps(pol))
    with pytest.raises(BundleError):
        Bundle.load(dst)


def test_serving_runtime_has_no_pickle_or_sklearn():
    """Runtime modules may not import pickle or scikit-learn. Only the build step
    (bundle.build_bundle) reads the Stage 10 pickles, once."""
    runtime = ["api", "batch", "featurestore", "predictor", "validate", "monitor", "bundle"]
    for name in runtime:
        tree = ast.parse((REPO_ROOT / "src" / "sih_ml" / "serve" / f"{name}.py").read_text())
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                mods = [a.name for a in node.names] if isinstance(node, ast.Import) else [node.module or ""]
                bad = [m for m in mods if m.startswith(("pickle", "sklearn", "joblib"))
                       or m == "sih_ml.models.calibration"]
                if bad:
                    fn = next((f for f in ast.walk(tree) if isinstance(f, ast.FunctionDef)
                               and f.lineno <= node.lineno <= f.end_lineno), None)
                    assert name == "bundle" and fn is not None and fn.name == "build_bundle", \
                        (name, bad)


# -------------------------------------------------------------- validation
def test_date_beyond_feed_is_refused(store):
    from sih_ml.serve.validate import InputError, check_date_scorable
    ok = store.rain_end + pd.Timedelta(days=1)
    check_date_scorable(ok, store.rain_start, store.rain_end, 1, 61)
    with pytest.raises(InputError) as e:
        check_date_scorable(ok + pd.Timedelta(days=1), store.rain_start, store.rain_end, 1, 61)
    assert e.value.code == "rainfall_not_available"
    with pytest.raises(InputError):
        check_date_scorable(store.rain_start + pd.Timedelta(days=10), store.rain_start,
                            store.rain_end, 1, 61)


@pytest.mark.parametrize("vals,code", [([1.0] * 60, "bad_rainfall"), ([1.0] * 60 + [np.nan], "bad_rainfall"),
                                       ([1.0] * 60 + [-1.0], "bad_rainfall"),
                                       ([1.0] * 60 + [5000.0], "bad_rainfall"), ("abc", "bad_rainfall")])
def test_rain_history_validation(vals, code):
    from sih_ml.serve.validate import InputError, check_rain_history
    with pytest.raises(InputError) as e:
        check_rain_history(vals, 61)
    assert e.value.code == code


def test_steep_segments_never_alert_autonomously(bundle):
    from sih_ml.serve.predictor import Predictor
    p = Predictor(bundle)
    prob = np.array([0.9, 0.9, 0.01, 0.01])
    slope = np.array([25.0, 2.0, 25.0, 2.0])
    tier, steep = p.tiers(prob, slope)
    assert list(tier) == ["human_review", "alert", "none", "none"]


# ------------------------------------------------------------------- batch
@pytest.fixture(scope="module")
def scored(bundle, store, tmp_path_factory):
    from sih_ml.serve.batch import run_daily
    out = tmp_path_factory.mktemp("scores")
    m = run_daily(DATE, bundle, store, out)
    return out, m


def test_batch_scores_every_segment_once(scored, store):
    out, m = scored
    df = pd.read_parquet(out / f"date={DATE}" / "scores.parquet")
    assert len(df) == len(store.segment_ids) == m["n_segments"] and df.segment_id.is_unique
    assert set(df.tier) <= {"none", "alert", "human_review"}
    assert not (df.steep & (df.tier == "alert")).any()
    assert df.p_calibrated.between(0, 1).all() and np.isfinite(df.raw_score).all()
    assert m["data_quality"]["non_finite_scores"] == 0
    assert not any(p.name.startswith(".tmp") for p in out.iterdir())      # atomic


def test_batch_is_idempotent_and_refuses_stale_dates(scored, bundle, store):
    from sih_ml.serve.batch import run_daily
    from sih_ml.serve.validate import InputError
    out, _ = scored
    assert run_daily(DATE, bundle, store, out).get("skipped")
    with pytest.raises(InputError):
        run_daily(str((store.rain_end + pd.Timedelta(days=5)).date()), bundle, store, out)


# --------------------------------------------------------------------- api
def _call(app, method, path, query="", body=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else b"")
    env = {"REQUEST_METHOD": method, "PATH_INFO": path, "QUERY_STRING": query,
           "wsgi.input": io.BytesIO(data), "CONTENT_LENGTH": str(len(data))}
    got = {}

    def sr(status, headers):
        got["status"], got["headers"] = int(status.split()[0]), dict(headers)
    out = b"".join(app(env, sr))
    ctype = got["headers"]["Content-Type"]
    return got["status"], (json.loads(out) if "json" in ctype else out.decode())


@pytest.fixture(scope="module")
def app(scored):
    from sih_ml.serve.api import App
    out, _ = scored
    return App(BUNDLE, STORE, out, num_threads=1)


def test_api_health_and_readiness(app):
    assert _call(app, "GET", "/healthz")[0] == 200
    s, body = _call(app, "GET", "/readyz")
    # CHIRPS in this repo ends 2025-12-31: there is no live feed, so NOT ready is correct
    assert s == 503 and body["rain_feed_fresh"] is False


def test_api_lookup_and_errors(app, store):
    ids = list(store.segment_ids[:3])
    s, b = _call(app, "GET", "/v1/scores", f"date={DATE}&segment_id={','.join(ids)},NOPE")
    assert s == 200 and len(b["rows"]) == 3 and b["unknown_segment_ids"] == ["NOPE"]
    assert b["primary_output"] == "risk_percentile" and "case-control" in b["probability_note"]
    assert _call(app, "GET", "/v1/scores", "date=2025-08-16&segment_id=x")[0] == 404
    assert _call(app, "GET", "/v1/scores", f"date=notadate&segment_id={ids[0]}")[0] == 400
    assert _call(app, "GET", "/v1/nope")[0] == 404
    assert _call(app, "DELETE", "/v1/scores")[0] == 405
    s, b = _call(app, "GET", "/v1/alerts", f"date={DATE}&tier=human_review&limit=5")
    assert s == 200 and len(b["rows"]) <= 5


def test_api_score_matches_batch_and_validates(app, store, scored):
    out, _ = scored
    ids = list(store.segment_ids[1000:1050])
    s, b = _call(app, "POST", "/v1/score", body={"date": DATE, "segment_ids": ids})
    assert s == 200 and b["rainfall_source"] == "feed"
    day = pd.read_parquet(out / f"date={DATE}" / "scores.parquet").set_index("segment_id")
    got = pd.DataFrame(b["rows"]).set_index("segment_id")
    assert np.array_equal(got.raw_score.to_numpy(), day.loc[got.index, "raw_score"].to_numpy())
    assert _call(app, "POST", "/v1/score", raw=b"{not json")[0] == 400
    assert _call(app, "POST", "/v1/score", body={"date": DATE, "segment_ids": ids,
                                                 "rain_mm": [1] * 10})[0] == 400
    assert _call(app, "POST", "/v1/score", raw=b'{"date": "2025-08-15", "segment_ids": ["%s"], '
                 b'"rain_mm": [NaN]}' % ids[0].encode())[0] in (400, 422)
    assert _call(app, "POST", "/v1/score", body={"date": DATE,
                                                 "segment_ids": [f"x{i}" for i in range(6000)]})[0] == 413
    assert _call(app, "POST", "/v1/score", body={"date": "2026-09-01", "segment_ids": ids})[0] == 422


def test_whatif_more_rain_never_lowers_risk(app, store):
    """The monotone-rainfall guarantee, end to end through the public API."""
    ids = list(store.segment_ids[::20000])
    rng = np.random.default_rng(3)
    base = rng.gamma(0.6, 8.0, 61)
    prev = None
    for f in (1.0, 1.5, 2.0, 4.0):
        s, b = _call(app, "POST", "/v1/score", body={"date": DATE, "segment_ids": ids,
                                                     "rain_mm": (base * f).round(3).tolist()})
        assert s == 200
        cur = np.array([r["raw_score"] for r in b["rows"]])
        if prev is not None:
            assert (cur >= prev - 1e-12).all()
        prev = cur


def test_metrics_exposition(app):
    s, text = _call(app, "GET", "/metrics")
    assert s == 200 and "sih_http_requests_total" in text and "sih_model_info" in text


def test_drift_monitor_catches_feed_faults_without_crying_wolf(bundle, store):
    """Measured in Stage 11: 0/5 false alarms on clean data; zeros, a mm->inch unit
    error and a stale feed are caught at every tested date. Pinned on one date."""
    from sih_ml.serve.monitor import drift_report
    cut = pd.Timestamp("2025-08-14")
    win = (store.rain.index > cut - pd.Timedelta(days=40)) & (store.rain.index <= cut)

    def warn(transform):
        r = store.rain.copy()
        r.loc[win] = transform(r.loc[win])
        return any(v["warn"] for v in drift_report(r, cut, bundle.reference).values())
    assert not warn(lambda r: r)
    assert warn(lambda r: r * 0)
    assert warn(lambda r: r / 25.4)


def test_benchmark_only_bundle_refuses_to_serve(tmp_path, monkeypatch):
    """A truncated model with the full model's calibrators is miscalibrated; the
    loader must refuse it unless explicitly overridden for benchmarking."""
    from sih_ml.serve.bundle import Bundle, BundleError
    dst = tmp_path / "b"
    shutil.copytree(BUNDLE.resolve(), dst)
    m = json.loads((dst / "manifest.json").read_text())
    m["benchmark_only"] = True
    (dst / "manifest.json").write_text(json.dumps(m))
    monkeypatch.delenv("SIH_ALLOW_BENCHMARK_BUNDLE", raising=False)
    with pytest.raises(BundleError):
        Bundle.load(dst)
