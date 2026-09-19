"""Phase 1 task 1.2: prove the ml_publisher role can publish, then roll everything back.

    SIH_PUBLISH_DSN=... PYTHONPATH=ml/src python ml/scripts/publish_dry_run.py --date 2025-07-28

Everything runs inside one outer transaction that is always rolled back (segments load, run
registration, the COPY into the run partition, ml_finish_run, and a pipeline-failure report), so the
database is unchanged afterwards. It exercises the exact code paths and grants the workflow needs.
Exit codes: 0 all steps passed | 4 a step was refused by the database | 2 bad input.
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from sih_ml.serve import publish as p
from sih_ml.serve.batch import _defaults


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--date", required=True)
    ap.add_argument("--centroids", type=Path, default=None)
    a = ap.parse_args(argv)

    dsn = os.environ.get("SIH_PUBLISH_DSN")
    if not dsn:
        print("set SIH_PUBLISH_DSN", file=sys.stderr)
        return 2
    import psycopg

    bundle, store, scores = _defaults()
    steps = []
    try:
        with psycopg.connect(dsn, connect_timeout=10) as conn:
            who = conn.execute("select current_user").fetchone()[0]
            with conn.transaction(force_rollback=True):
                t = time.monotonic()
                seg = p.publish_segments(conn, store, bundle, a.centroids)
                steps.append(("segments", seg, time.monotonic() - t))
                t = time.monotonic()
                run = p.publish_run(conn, scores, bundle, a.date, "replay", set_current=True)
                steps.append(("run", run, time.monotonic() - t))
                # what a client would now see, while still inside the rolled-back transaction
                cur = conn.execute("select count(*) from public.ml_batch_runs where is_current").fetchone()[0]
                n = conn.execute("select count(*) from public.ml_segments").fetchone()[0]
                steps.append(("visible", {"current_runs": cur, "ml_segments": n}, 0.0))
                ev = conn.execute("select public.ml_report_pipeline_failure('other', 'dry run', null)").fetchone()[0]
                steps.append(("failure_report", {"event_id": ev}, 0.0))
    except p.PublishInputError as e:
        print(f"bad input: {e}", file=sys.stderr)
        return 2
    except psycopg.Error as e:
        print(f"REFUSED after {[s[0] for s in steps]}: {str(e).splitlines()[0]}", file=sys.stderr)
        return 4
    print(f"connected as {who}; everything below was rolled back")
    for name, out, secs in steps:
        print(f"  ok {name:15s} {secs:6.1f}s  {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
