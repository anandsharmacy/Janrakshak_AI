#!/usr/bin/env bash
# Daily pipeline: ingest yesterday's rainfall, score today, fail loudly.
#   exit 0 ok | 3 rainfall not available (retry later) | 4 publish to Supabase failed
#   | other = page someone
set -euo pipefail
cd "${SIH_HOME:-/opt/sih-ml}"
export PYTHONPATH=src
PY="${SIH_PY:-.venv/bin/python}"
DAY="${1:-$(date +%F)}"

# 1) rainfall feed -> feature store (the operational feed adapter writes this CSV)
if [[ -f "incoming/rain_${DAY}.csv" ]]; then
  "$PY" -m sih_ml.serve.feed --csv "incoming/rain_${DAY}.csv"
fi
# 2) score the corridor (refuses if the rainfall window is incomplete -> exit 3)
"$PY" -m sih_ml.serve.batch --date "$DAY"
# 3) publish the day to Supabase so the Flutter app and website see it
#    (skipped when SIH_PUBLISH_DSN is unset, e.g. a scoring-only host)
if [[ -n "${SIH_PUBLISH_DSN:-}" ]]; then
  "${SIH_PUBLISH_PY:-.venv-publish/bin/python}" -m sih_ml.serve.publish run --date "$DAY" --mode live
fi
