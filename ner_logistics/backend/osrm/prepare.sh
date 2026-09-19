#!/usr/bin/env bash
# Builds a self-hosted OSRM car graph for North-East India (Geofabrik extract,
# ~110 MB download, a few minutes and ~4 GB RAM to process).
#   ./prepare.sh && docker compose up -d      → http://localhost:5000
set -euo pipefail

IMAGE="${OSRM_IMAGE:-ghcr.io/project-osrm/osrm-backend:v26.9.0-debian}"
REGION="${REGION:-north-eastern-zone}"
cd "$(dirname "$0")"
mkdir -p data

PBF="data/$REGION-latest.osm.pbf"
if [[ ! -f "$PBF" ]]; then
  curl -L --fail -o "$PBF" "https://download.geofabrik.de/asia/india/$REGION-latest.osm.pbf"
fi

run() { docker run --rm -t -v "$PWD/data:/data" "$IMAGE" "$@"; }
# car.lua ships in the image; swap for a truck profile to model heavy vehicles.
run osrm-extract -p /opt/car.lua "/data/$REGION-latest.osm.pbf"
run osrm-partition "/data/$REGION-latest.osrm"
run osrm-customize "/data/$REGION-latest.osrm"
echo "Graph ready: data/$REGION-latest.osrm"
