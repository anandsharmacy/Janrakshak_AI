#!/usr/bin/env bash
# Build the private release asset the "Publish ML replay day" workflow downloads.
#
#   ml/scripts/make_replay_assets.sh [DATE]     (default 2025-07-28)
#
# Contents (paths relative to ml/, so the workflow can `tar -xzf -C ml`):
#   deploy/bundles/final_v3/            model bundle (manifest, policy, model.txt, ...)
#   deploy/featurestore/{manifest.json,segments.parquet}
#   deploy/scores/date=DATE/{run.json,scores.parquet}
#   data/interim/segment_centroids.parquet   (the store's segments.parquet has no lon/lat)
# The 106 MB static_matrix.npy is NOT needed to publish. Output: ml/deploy/dist/ml-replay-assets.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."
DATE="${1:-2025-07-28}"
OUT=deploy/dist; mkdir -p "$OUT"

need=(deploy/bundles/final_v3/manifest.json deploy/bundles/final_v3/policy.json deploy/bundles/final_v3/model.txt
      deploy/featurestore/manifest.json deploy/featurestore/segments.parquet
      "deploy/scores/date=$DATE/run.json" "deploy/scores/date=$DATE/scores.parquet"
      data/interim/segment_centroids.parquet)
for f in "${need[@]}"; do [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 2; }; done

# the bundle is a directory `current -> final_v3`; ship the real directory plus the symlink
tar -czf "$OUT/ml-replay-assets.tar.gz" \
  deploy/bundles \
  deploy/featurestore/manifest.json deploy/featurestore/segments.parquet \
  "deploy/scores/date=$DATE" \
  data/interim/segment_centroids.parquet

( cd "$OUT" && shasum -a 256 ml-replay-assets.tar.gz | tee ml-replay-assets.tar.gz.sha256 )
ls -lh "$OUT/ml-replay-assets.tar.gz"
