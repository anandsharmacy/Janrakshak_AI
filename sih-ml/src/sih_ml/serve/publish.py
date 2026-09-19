"""Publish corridor scores into the shared Supabase/Postgres database.

    python -m sih_ml.serve.publish segments
    python -m sih_ml.serve.publish run --date 2025-08-05 --mode replay
    python -m sih_ml.serve.publish current --date 2025-08-05

The Flutter app and the website never call the model service. They read ML risk
from Supabase, where PostGIS maps their routes to segments and RLS decides who
sees what (supabase/migrations/..._ml_integration.sql). This module is the only
writer:

  * `segments` loads the 309,042 segment centroids and the coverage polygon (once
    per feature-store build);
  * `run` publishes one scored day: register it (ml_begin_run) -> COPY the rows
    into its staging partition -> validate against run.json, attach, make current
    (ml_finish_run). One transaction, so a failure leaves the previous day current.
    Re-publishing a (date, bundle) that is already there is a no-op;
  * `current` re-points clients at an already published day (replay switch, rollback).

`--mode replay` publishes a historical day that clients label as a replay; `live`
is refused for days older than two days, so old rainfall can't pass as today's.

Connection: SIH_PUBLISH_DSN, e.g. the local Supabase stack
    postgresql://postgres:postgres@127.0.0.1:54322/postgres
In production use a LOGIN user that is a member of role ml_publisher.

Exit codes: 0 ok | 2 bad input (no batch output, wrong mode) | 4 database refused.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

from sih_ml.serve.batch import _defaults
from sih_ml.utils.common import REPO_ROOT

log = logging.getLogger("sih.publish")
SCORE_COLUMNS = ("run_id", "segment_id", "raw_score", "p_calibrated", "risk_percentile",
                 "steep", "tier", "tier_rank")
TIERS = ("none", "alert", "human_review")
LIVE_MAX_AGE_DAYS = 2
# Only used when the feature store predates lon/lat in segments.parquet.
FALLBACK_CENTROIDS = REPO_ROOT / "data" / "interim" / "segment_centroids.parquet"


class PublishInputError(ValueError):
    """The files on disk can't be published as asked (exit code 2)."""


# --------------------------------------------------------------------------- #
# pure helpers (unit-tested without a database)
# --------------------------------------------------------------------------- #
def load_day(scores_dir: Path, date: str) -> tuple[dict, pd.DataFrame]:
    d = Path(scores_dir) / f"date={date}"
    if not (d / "run.json").exists() or not (d / "scores.parquet").exists():
        raise PublishInputError(f"no batch output for {date} in {scores_dir}; run the batch first")
    return json.loads((d / "run.json").read_text()), pd.read_parquet(d / "scores.parquet")


def check_mode(mode: str, date: str, today: str | None = None) -> None:
    if mode not in ("live", "replay"):
        raise PublishInputError("mode must be 'live' or 'replay'")
    now = pd.Timestamp(today) if today else pd.Timestamp.now(tz="Asia/Kolkata").tz_localize(None)
    age = (now.normalize() - pd.Timestamp(date)).days
    if mode == "live" and age > LIVE_MAX_AGE_DAYS:
        raise PublishInputError(f"{date} is {age} days old; publish it with --mode replay so "
                                "clients label it as historical")


def score_rows(df: pd.DataFrame, run_id: int):
    """Rows for COPY, validated so a model fault can't reach clients as a score."""
    need = set(SCORE_COLUMNS) - {"run_id"}
    missing = need - set(df.columns)
    if missing:
        raise PublishInputError(f"scores.parquet lacks columns {sorted(missing)}")
    num = df[["raw_score", "p_calibrated", "risk_percentile"]].to_numpy(float)
    if not np.isfinite(num).all():
        raise PublishInputError("scores.parquet contains non-finite scores")
    if (num[:, :2] < 0).any() or (num[:, :2] > 1).any() or (num[:, 2] < 0).any() or (num[:, 2] > 100).any():
        raise PublishInputError("scores.parquet contains out-of-range scores")
    bad = set(df.tier.unique()) - set(TIERS)
    if bad:
        raise PublishInputError(f"unknown tiers {sorted(bad)}")
    if df.segment_id.duplicated().any():
        raise PublishInputError("scores.parquet has duplicate segment_id rows")
    for r in df.itertuples(index=False):
        yield (run_id, r.segment_id, float(r.raw_score), float(r.p_calibrated),
               float(r.risk_percentile), bool(r.steep), r.tier, int(r.tier_rank))


def segment_table(store_dir: Path, centroids: Path | None = None) -> pd.DataFrame:
    """segment_id, lon, lat, slope, cell_index — lon/lat from the store when present."""
    seg = pd.read_parquet(Path(store_dir) / "segments.parquet")
    if not {"lon", "lat"} <= set(seg.columns):
        src = Path(centroids or FALLBACK_CENTROIDS)
        if not src.exists():
            raise PublishInputError(f"feature store has no lon/lat and {src} is missing; "
                                    "rebuild the store with `make bundle`")
        seg = seg.merge(pd.read_parquet(src)[["segment_id", "lon", "lat"]], on="segment_id",
                        how="left", validate="one_to_one")
    if seg[["lon", "lat"]].isna().any().any():
        raise PublishInputError(f"{int(seg.lon.isna().sum())} segments have no coordinates")
    return seg


def segment_rows(seg: pd.DataFrame, steep_deg: float):
    for r in seg.itertuples(index=False):
        slope = None if pd.isna(r.slope_mean_deg) else float(r.slope_mean_deg)
        yield (r.segment_id, f"SRID=4326;POINT({r.lon:.7f} {r.lat:.7f})", slope,
               slope is not None and slope >= steep_deg, int(r.cell_index))


def coverage_polygons(cell_ids: list[str]) -> list[str]:
    """WKT boxes for the rainfall cells (ids are 'lat_lon' cell centres)."""
    pts = np.array([[float(v) for v in c.split("_")] for c in cell_ids])
    step = min(np.diff(np.unique(pts[:, 0])).min(), np.diff(np.unique(pts[:, 1])).min())
    h = step / 2
    return [f"POLYGON(({lon - h} {lat - h},{lon + h} {lat - h},{lon + h} {lat + h},"
            f"{lon - h} {lat + h},{lon - h} {lat - h}))" for lat, lon in pts]


def model_payload(bundle_dir: Path) -> dict:
    b = Path(bundle_dir).resolve()
    return {"uri": str(b),
            "manifest": json.loads((b / "manifest.json").read_text()),
            "policy": json.loads((b / "policy.json").read_text())}


# --------------------------------------------------------------------------- #
# database writers — each takes an open psycopg connection; the caller commits
# --------------------------------------------------------------------------- #
def publish_segments(conn, store_dir: Path, bundle_dir: Path, centroids: Path | None = None) -> dict:
    seg = segment_table(store_dir, centroids)
    steep = float(model_payload(bundle_dir)["policy"]["steep_slope_deg"])
    cells = json.loads((Path(store_dir) / "manifest.json").read_text())["cell_ids"]
    with conn.transaction(), conn.cursor() as cur:
        cur.execute("truncate public.ml_segments")
        with cur.copy("copy public.ml_segments (segment_id, geom, slope_deg, steep, cell_index) "
                      "from stdin") as cp:
            for row in segment_rows(seg, steep):
                cp.write_row(row)
        cur.execute(
            "insert into public.ml_coverage (id, geom, n_cells, updated_at) "
            "select 1, extensions.st_multi(extensions.st_union(array("
            "  select extensions.st_geomfromtext(w, 4326) from unnest(%s::text[]) w)))::extensions.geography, "
            "  %s, now() "
            "on conflict (id) do update set geom = excluded.geom, n_cells = excluded.n_cells, "
            "  updated_at = now()",
            (coverage_polygons(cells), len(cells)))
    return {"segments": int(len(seg)), "cells": len(cells), "steep_slope_deg": steep}


def publish_run(conn, scores_dir: Path, bundle_dir: Path, date: str, mode: str,
                set_current: bool = True) -> dict:
    check_mode(mode, date)
    run, df = load_day(scores_dir, date)
    with conn.transaction(), conn.cursor() as cur:
        cur.execute("select public.ml_begin_run(%s::jsonb, %s, %s::jsonb)",
                    (json.dumps(run), mode, json.dumps(model_payload(bundle_dir))))
        run_id = cur.fetchone()[0]
        if run_id is None:                                   # already published
            cur.execute("select id from public.ml_batch_runs where score_date = %s and bundle_hash = %s",
                        (date, run["bundle_hash"]))
            run_id = cur.fetchone()[0]
            if set_current:
                cur.execute("select public.ml_set_current(%s)", (run_id,))
            return {"run_id": run_id, "date": date, "already_published": True, "current": set_current}
        with cur.copy(f"copy ml_private.scores_r{int(run_id)} ({', '.join(SCORE_COLUMNS)}) from stdin") as cp:
            for row in score_rows(df, run_id):
                cp.write_row(row)
        cur.execute("select public.ml_finish_run(%s, %s)", (run_id, set_current))
        return {"date": date, "mode": mode, **cur.fetchone()[0]}


def set_current(conn, date: str, bundle_hash: str | None = None) -> dict:
    with conn.transaction(), conn.cursor() as cur:
        cur.execute("select id from public.ml_batch_runs where score_date = %s "
                    "and (%s::text is null or bundle_hash = %s) and scores_pruned_at is null "
                    "order by published_at desc limit 1", (date, bundle_hash, bundle_hash))
        row = cur.fetchone()
        if row is None:
            raise PublishInputError(f"{date} is not published")
        cur.execute("select public.ml_set_current(%s)", (row[0],))
    return {"run_id": row[0], "date": date, "current": True}


def _write_prom(scores_dir: Path, ok: bool) -> None:
    p = Path(scores_dir)
    tmp = p / ".publish.prom.tmp"
    lines = ["# HELP sih_publish_last_run_ok 1 if the last publish succeeded",
             "# TYPE sih_publish_last_run_ok gauge", f"sih_publish_last_run_ok {int(ok)}"]
    if ok:
        lines += ["# HELP sih_publish_last_success_timestamp_seconds last successful publish",
                  "# TYPE sih_publish_last_success_timestamp_seconds gauge",
                  f"sih_publish_last_success_timestamp_seconds {time.time():.0f}"]
    try:
        tmp.write_text("\n".join(lines) + "\n")
        os.replace(tmp, p / "publish.prom")
    except OSError:                                          # read-only scores mount
        log.warning("could not write publish.prom")


def main(argv=None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stderr)
    b_dir, s_dir, o_dir = _defaults()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_seg = sub.add_parser("segments", help="load segment centroids + coverage")
    p_seg.add_argument("--centroids", type=Path, default=None)
    p_run = sub.add_parser("run", help="publish one scored day")
    p_run.add_argument("--date", required=True)
    p_run.add_argument("--mode", choices=("live", "replay"), default="live")
    p_run.add_argument("--no-set-current", action="store_true")
    p_cur = sub.add_parser("current", help="make a published day current")
    p_cur.add_argument("--date", required=True)
    a = ap.parse_args(argv)

    dsn = os.environ.get("SIH_PUBLISH_DSN")
    if not dsn:
        log.error(json.dumps({"event": "publish_refused", "code": "no_dsn",
                              "detail": "set SIH_PUBLISH_DSN"}))
        return 2
    import psycopg                                           # publish-only dependency

    t0 = time.monotonic()
    try:
        with psycopg.connect(dsn, connect_timeout=10) as conn:
            if a.cmd == "segments":
                out = publish_segments(conn, s_dir, b_dir, a.centroids)
            elif a.cmd == "run":
                out = publish_run(conn, o_dir, b_dir, a.date, a.mode, not a.no_set_current)
            else:
                out = set_current(conn, a.date)
    except PublishInputError as e:
        log.error(json.dumps({"event": "publish_refused", "code": "bad_input", "detail": str(e)}))
        return 2
    except psycopg.Error as e:
        log.error(json.dumps({"event": "publish_failed", "code": "database",
                              "detail": str(e).splitlines()[0]}))
        if a.cmd == "run":
            _write_prom(o_dir, ok=False)
        return 4
    if a.cmd == "run":
        _write_prom(o_dir, ok=True)
    log.info(json.dumps({"event": f"published_{a.cmd}", **out,
                         "ms": round(1000 * (time.monotonic() - t0))}, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
