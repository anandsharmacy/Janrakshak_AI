"""HTTP API — a plain WSGI app (no framework), served by gunicorn in production.

    GET  /healthz                         liveness: the process is up
    GET  /readyz                          readiness: bundle verified, store matches it,
                                          rainfall feed fresh, today's batch present
    GET  /v1/model                        bundle manifest + output policy
    GET  /v1/scores?date=D&segment_id=a,b precomputed scores from the daily batch (fast path)
    GET  /v1/alerts?date=D&tier=T&limit=N top-ranked segments of a tier for a day
    POST /v1/score                        on-demand scoring, optionally under a caller-
                                          supplied rainfall scenario (forecast / what-if)
    GET  /metrics                         Prometheus text format

Design choice: the routing layer reads PRECOMPUTED scores. The model runs once per
day over the corridor (batch.py); a request is a dictionary lookup. Only /v1/score
touches the model at request time, and it is bounded (<= 5,000 segments).

Errors are JSON `{"error": code, "detail": ...}` with a status that says whose fault
it is: 400 malformed, 404 unknown/absent, 413 too large, 422 well-formed but not
scorable (e.g. rainfall not yet available), 500 a model/server fault, 503 not ready.
"""
from __future__ import annotations

import json
import logging
import os
import sys
import threading
import uuid
from collections import OrderedDict
from pathlib import Path
from urllib.parse import parse_qs

import numpy as np
import pandas as pd

from sih_ml.serve.batch import bundle_hash
from sih_ml.serve.bundle import Bundle
from sih_ml.serve.featurestore import FeatureStore, rainfall_from_history
from sih_ml.serve.monitor import Metrics, Timer
from sih_ml.serve.predictor import Predictor, percentile_against
from sih_ml.serve.validate import (InputError, check_date_scorable, check_rain_history,
                                   check_segment_ids, parse_date)

log = logging.getLogger("sih.api")
MAX_BODY_BYTES = 1 << 20
STATUS = {200: "200 OK", 400: "400 Bad Request", 404: "404 Not Found", 405: "405 Method Not Allowed",
          413: "413 Payload Too Large", 422: "422 Unprocessable Entity",
          500: "500 Internal Server Error", 503: "503 Service Unavailable"}


class App:
    def __init__(self, bundle_dir, store_dir, scores_dir, num_threads: int = 1,
                 max_feed_lag_days: int = 3, cache_days: int = 3):
        self.bundle = Bundle.load(bundle_dir)                  # verifies every sha256
        self.store = FeatureStore.load(store_dir, self.bundle.schema)
        self.store_dir = Path(store_dir)
        self._rain_mtime = (self.store_dir / "rainfall.parquet").stat().st_mtime
        self.predictor = Predictor(self.bundle, num_threads)
        self.scores_dir = Path(scores_dir)
        self.bundle_hash = bundle_hash(self.bundle)
        self.max_feed_lag_days = max_feed_lag_days
        self.metrics = Metrics()
        self.metrics.set("sih_model_info", 1, version=self.bundle.version, bundle=self.bundle_hash)
        self._cache: OrderedDict[str, pd.DataFrame] = OrderedDict()
        self._cache_days = cache_days
        self._lock = threading.Lock()
        self.routes = {("GET", "/healthz"): self.healthz, ("GET", "/readyz"): self.readyz,
                       ("GET", "/v1/model"): self.model, ("GET", "/v1/scores"): self.scores,
                       ("GET", "/v1/alerts"): self.alerts, ("POST", "/v1/score"): self.score,
                       ("GET", "/metrics"): self.prom}

    # ------------------------------------------------------------------ wsgi
    def __call__(self, environ, start_response):
        timer, rid = Timer(), environ.get("HTTP_X_REQUEST_ID") or uuid.uuid4().hex[:12]
        method, path = environ.get("REQUEST_METHOD", "GET"), environ.get("PATH_INFO", "/")
        handler = self.routes.get((method, path))
        try:
            if handler is None:
                known = {p for _, p in self.routes}
                raise InputError("not_found" if path not in known else "method_not_allowed",
                                 f"{method} {path}", 404 if path not in known else 405)
            status, body, ctype = handler(environ)
        except InputError as e:
            status, body, ctype = e.status, {"error": e.code, "detail": e.detail}, "json"
        except Exception as e:                      # noqa: BLE001 — must never leak a traceback
            log.exception("unhandled error rid=%s", rid)
            status, body, ctype = 500, {"error": "internal", "detail": type(e).__name__}, "json"
        payload = (body if ctype == "text" else json.dumps(body, default=_js)).encode()
        dt = timer()
        route = path if handler else "unmatched"
        self.metrics.inc("sih_http_requests_total", route=route, status=status)
        self.metrics.observe("sih_http_request_seconds", dt, route=route)
        if path not in ("/healthz", "/metrics"):
            log.info(json.dumps({"rid": rid, "method": method, "path": path, "status": status,
                                 "ms": round(1000 * dt, 2)}))
        start_response(STATUS.get(status, f"{status} Error"),
                       [("Content-Type", "text/plain; version=0.0.4" if ctype == "text"
                         else "application/json"),
                        ("Content-Length", str(len(payload))), ("X-Request-ID", rid),
                        ("X-Model-Version", self.bundle.version)])
        return [payload]

    # --------------------------------------------------------------- helpers
    @staticmethod
    def _q(environ) -> dict:
        return parse_qs(environ.get("QUERY_STRING", ""), keep_blank_values=False)

    @staticmethod
    def _body(environ) -> dict:
        try:
            n = int(environ.get("CONTENT_LENGTH") or 0)
        except ValueError:
            n = 0
        if n > MAX_BODY_BYTES:
            raise InputError("body_too_large", f"max {MAX_BODY_BYTES} bytes", 413)
        try:
            return json.loads(environ["wsgi.input"].read(n) or b"{}")
        except json.JSONDecodeError as e:
            raise InputError("bad_json", str(e), 400)

    def _day(self, date: pd.Timestamp) -> pd.DataFrame | None:
        key = str(date.date())
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
                return self._cache[key]
        d = self.scores_dir / f"date={key}"
        if not (d / "run.json").exists():
            return None
        run = json.loads((d / "run.json").read_text())
        df = pd.read_parquet(d / "scores.parquet").set_index("segment_id")
        df.attrs["run"] = run
        with self._lock:
            self._cache[key] = df
            while len(self._cache) > self._cache_days:
                self._cache.popitem(last=False)
        return df

    def _refresh_rain(self, min_interval_s: float = 60.0) -> None:
        """Pick up days appended by `sih_ml.serve.feed` without a restart. (With
        gunicorn preload, a HUP re-forks from the master's stale copy, so the reload
        has to happen in the worker.) Checked at most once a minute."""
        import time as _t
        now = _t.monotonic()
        if now - getattr(self, "_rain_checked", 0.0) < min_interval_s:
            return
        self._rain_checked = now
        p = Path(self.store_dir) / "rainfall.parquet"
        mt = p.stat().st_mtime
        if mt != self._rain_mtime:
            r = pd.read_parquet(p)
            r.index = pd.DatetimeIndex(r.index)
            self.store.rain = r
            self._rain_mtime = mt
            log.info(json.dumps({"event": "rainfall_reloaded",
                                 "rain_end": str(self.store.rain_end.date())}))

    def _latest_day(self) -> str | None:
        days = sorted(p.name.split("=", 1)[1] for p in self.scores_dir.glob("date=*")
                      if (p / "run.json").exists())
        return days[-1] if days else None

    def _meta(self, df=None) -> dict:
        m = {"model_version": self.bundle.version,
             "primary_output": "risk_percentile",
             "probability_note": self.bundle.policy["probability_caveat"]}
        if df is not None:
            m["batch_bundle_version"] = df.attrs["run"]["bundle_version"]
        return m

    # ---------------------------------------------------------------- routes
    def healthz(self, environ):
        return 200, {"status": "ok"}, "json"

    def readyz(self, environ):
        self._refresh_rain()
        today = pd.Timestamp.now().normalize()
        lag = int((today - self.store.rain_end).days)
        latest = self._latest_day()
        checks = {"bundle_verified": True, "model_version": self.bundle.version,
                  "rain_feed_end": str(self.store.rain_end.date()), "rain_feed_lag_days": lag,
                  "rain_feed_fresh": lag <= self.max_feed_lag_days,
                  "latest_scored_date": latest}
        self.metrics.set("sih_rain_feed_lag_days", lag)
        ok = bool(latest) and checks["rain_feed_fresh"]
        return (200 if ok else 503), {"ready": ok, **checks}, "json"

    def model(self, environ):
        return 200, {"manifest": self.bundle.manifest, "policy": self.bundle.policy,
                     "bundle_hash": self.bundle_hash,
                     "featurestore": {k: self.store.manifest[k]
                                      for k in ("n_segments", "rain_last", "built_utc")}}, "json"

    def scores(self, environ):
        q = self._q(environ)
        date = parse_date((q.get("date") or [None])[0])
        ids = check_segment_ids(",".join(q.get("segment_id", [])) or None)
        df = self._day(date)
        if df is None:
            raise InputError("not_scored", f"no batch output for {date.date()}; run the daily "
                             "job, or POST /v1/score for on-demand scoring", 404)
        idx = df.index.get_indexer(ids)
        missing = [s for s, i in zip(ids, idx) if i < 0]
        rows = df.iloc[idx[idx >= 0]].reset_index()
        return 200, {"date": str(date.date()), **self._meta(df),
                     "unknown_segment_ids": missing,
                     "rows": rows.to_dict("records")}, "json"

    def alerts(self, environ):
        q = self._q(environ)
        date = parse_date((q.get("date") or [None])[0])
        tier = (q.get("tier") or ["alert"])[0]
        if tier not in ("alert", "human_review"):
            raise InputError("bad_tier", "tier must be 'alert' or 'human_review'", 400)
        try:
            limit = min(int((q.get("limit") or ["100"])[0]), 5000)
        except ValueError:
            raise InputError("bad_limit", "limit must be an integer", 400)
        df = self._day(date)
        if df is None:
            raise InputError("not_scored", f"no batch output for {date.date()}", 404)
        top = df[df.tier == tier].nlargest(limit, "raw_score").reset_index()
        return 200, {"date": str(date.date()), "tier": tier, **self._meta(df),
                     "n_in_tier": int((df.tier == tier).sum()),
                     "rows": top.to_dict("records")}, "json"

    def score(self, environ):
        body = self._body(environ)
        self._refresh_rain()
        date = parse_date(body.get("date"))
        ids = check_segment_ids(body.get("segment_ids"))
        pos, missing = self.store.positions(ids)
        if not len(pos):
            raise InputError("unknown_segments", "none of the segment_ids exist", 404)
        sch = self.bundle.schema
        if body.get("rain_mm") is not None:                    # caller's scenario
            hist = check_rain_history(body["rain_mm"], int(sch["history_days"]))
            X = np.array(self.store.static_matrix[pos])
            X[:, self.store.rain_idx] = rainfall_from_history(hist, date, sch["rainfall_cols"])
            from sih_ml.serve.featurestore import season_values
            sv = season_values(date)
            for j, c in zip(self.store.season_idx, sch["season_cols"]):
                X[:, j] = sv[c]
            source = "caller_scenario"
        else:                                                  # the operational feed
            check_date_scorable(date, self.store.rain_start, self.store.rain_end,
                                int(sch["horizon_days"]), int(sch["history_days"]))
            X = self.store.matrix(date, rows=pos)
            source = "feed"
        out = self.predictor.score(X, self.store.slope[pos])
        day = self._day(date)
        pct = (percentile_against(out["raw_score"], np.sort(day.raw_score.to_numpy()))
               if day is not None else np.full(len(pos), np.nan))
        rows = [{"segment_id": s, "raw_score": float(r), "p_calibrated": float(p),
                 "risk_percentile": None if np.isnan(c) else float(c),
                 "steep": bool(st), "tier": str(t)}
                for s, r, p, c, st, t in zip(self.store.segment_ids[pos], out["raw_score"],
                                             out["p_calibrated"], pct, out["steep"], out["tier"])]
        self.metrics.inc("sih_scored_rows_total", len(rows), source=source)
        return 200, {"date": str(date.date()), "rainfall_source": source, **self._meta(),
                     "percentile_reference": "corridor batch for this date" if day is not None
                     else "unavailable (no batch for this date)",
                     "unknown_segment_ids": missing, "rows": rows}, "json"

    def prom(self, environ):
        return 200, self.metrics.render(), "text"


def _js(x):
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, (np.floating,)):
        return None if not np.isfinite(x) else float(x)
    if isinstance(x, (np.bool_,)):
        return bool(x)
    return str(x)


def create_app() -> App:
    """Factory for gunicorn: `gunicorn 'sih_ml.serve.api:create_app()'`."""
    logging.basicConfig(level=os.environ.get("SIH_LOG_LEVEL", "INFO"), format="%(message)s",
                        stream=sys.stderr)
    from sih_ml.serve.batch import _defaults
    b, s, o = _defaults()
    return App(b, s, o, num_threads=int(os.environ.get("SIH_THREADS", "1")),
               max_feed_lag_days=int(os.environ.get("SIH_MAX_FEED_LAG_DAYS", "3")))


def main() -> None:
    """Local development server (stdlib, threaded). Production uses gunicorn."""
    import argparse
    from socketserver import ThreadingMixIn
    from wsgiref.simple_server import WSGIRequestHandler, WSGIServer, make_server

    class _Threaded(ThreadingMixIn, WSGIServer):
        daemon_threads = True

    class _Quiet(WSGIRequestHandler):
        def log_message(self, *a):
            pass

    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8080)
    a = ap.parse_args()
    app = create_app()
    with make_server(a.host, a.port, app, server_class=_Threaded, handler_class=_Quiet) as srv:
        log.info(json.dumps({"event": "listening", "host": a.host, "port": a.port,
                             "model": app.bundle.version}))
        srv.serve_forever()


if __name__ == "__main__":
    main()
