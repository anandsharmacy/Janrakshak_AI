"""Report a failed ML publish to the PMO dashboard (public.ml_pipeline_events).

    SIH_PUBLISH_DSN=... python ml/scripts/report_failure.py --stage publish \
        --run-url https://github.com/<org>/<repo>/actions/runs/123

Runs as the ml_publisher role, which can execute only ml_report_pipeline_failure. The message is a
fixed sentence plus the stage: never pass logs, paths or connection strings into it. If the database
itself is unreachable this fails too, and the GitHub failure email is the only signal.
Exit codes: 0 reported | 1 could not report.
"""
from __future__ import annotations

import argparse
import os
import sys

STAGES = ("assets", "segments", "publish", "other")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--stage", choices=STAGES, default="other")
    ap.add_argument("--run-url", default=None)
    a = ap.parse_args(argv)

    dsn = (os.environ.get("SIH_PUBLISH_DSN") or "").strip()  # a pasted secret often carries a trailing newline
    if not dsn:
        print("report_failure: SIH_PUBLISH_DSN is not set", file=sys.stderr)
        return 1
    import psycopg  # publish-only dependency

    message = f"ML replay publish failed at stage '{a.stage}'. See the workflow run for details."
    try:
        with psycopg.connect(dsn, connect_timeout=10) as conn:
            event_id = conn.execute(
                "select public.ml_report_pipeline_failure(%s, %s, %s)", (a.stage, message, a.run_url)
            ).fetchone()[0]
    except psycopg.Error as e:
        print(f"report_failure: database refused: {str(e).splitlines()[0]}", file=sys.stderr)
        return 1
    print(f"report_failure: recorded event {event_id} for stage {a.stage}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
