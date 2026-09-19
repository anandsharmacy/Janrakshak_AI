#!/usr/bin/env bash
# Uploads the built PMTiles file (default out/india.pmtiles) to the project's public `basemap` bucket (the bucket already exists; only the service
# role can write to it). Usage:
#   Put the service_role key (Dashboard > Project Settings > API) in tools/basemap/.env.local as
#   SUPABASE_SERVICE_ROLE_KEY=...   (that file is git-ignored; never put the key in this script or commit it),
#   or export it in your shell.
#   tools/basemap/upload.sh [file]         # default: out/north-eastern-zone.pmtiles
# A 413 means the file is over the project's upload limit (50 MB on the free plan): build with a lower MAXZOOM
# (whole India: 9 = 34 MiB, 10 = 85 MiB, 12 = 530 MiB) and give the app the same value via --dart-define=PMTILES_MAX_ZOOM=.
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env.local ] && set -a && . ./.env.local && set +a
: "${SUPABASE_SERVICE_ROLE_KEY:?put SUPABASE_SERVICE_ROLE_KEY in tools/basemap/.env.local or export it}"
FILE=${1:-out/india.pmtiles}
NAME=$(basename "$FILE")
BASE=${SUPABASE_URL:-https://sjcqwxthimfuxmrodsbs.supabase.co}
PUBLIC="$BASE/storage/v1/object/public/basemap/$NAME"

echo "Uploading $FILE ($(du -h "$FILE" | cut -f1)) to bucket 'basemap' as $NAME ..."
resp=$(mktemp)
code=$(curl -sS --progress-bar -X POST "$BASE/storage/v1/object/basemap/$NAME" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "x-upsert: true" -H "Content-Type: application/octet-stream" --data-binary @"$FILE" -o "$resp" -w '%{http_code}')
if [ "$code" != 200 ]; then echo "Upload failed (HTTP $code): $(cat "$resp")" >&2; rm -f "$resp"; exit 1; fi
rm -f "$resp"

# The app reads the file with HTTP range requests, so the public URL must answer 206 Partial Content.
code=$(curl -s -o /dev/null -w '%{http_code}' -r 0-99 "$PUBLIC")
if [ "$code" = 206 ]; then echo "OK: $PUBLIC answers range requests (206)."; else echo "WARNING: expected 206, got $code for $PUBLIC" >&2; exit 1; fi
