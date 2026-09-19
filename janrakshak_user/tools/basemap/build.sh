#!/usr/bin/env bash
# Builds the offline basemap: OpenStreetMap extract (Geofabrik) -> Planetiler (OpenMapTiles schema) -> one PMTiles file.
# Usage: tools/basemap/build.sh            (North East India, ~110 MB extract; MAXZOOM=12 -> ~30 MB file)
#        EXTRACT=asia/india/eastern-zone-latest tools/basemap/build.sh   (any other Geofabrik extract)
# Needs Java 21+. First run also downloads ~1.3 GB of Natural Earth / water-polygon data (cached in data/sources).
set -euo pipefail
cd "$(dirname "$0")"
EXTRACT=${EXTRACT:-asia/india/north-eastern-zone-latest}
NAME=$(basename "${EXTRACT%-latest}")
HEAP=${HEAP:-6g}
# Only the layers assets/basemap/style.json draws; POIs, house numbers and parks just make the file (and every offline download) bigger.
MAXZOOM=${MAXZOOM:-12}
LAYERS=${LAYERS:-aeroway,boundary,building,landcover,landuse,place,transportation,transportation_name,water,water_name,waterway}
mkdir -p data/sources data/tmp out

[ -f data/planetiler.jar ] || curl -fL -o data/planetiler.jar \
  https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar

PBF="data/sources/$NAME.osm.pbf"
[ -f "$PBF" ] || curl -fL -C - -o "$PBF" "https://download.geofabrik.de/$EXTRACT.osm.pbf"

# The app overzooms beyond MAXZOOM (vectors stay sharp; only the finest road/building detail is lost). --force overwrites a previous build.
java -Xmx"$HEAP" -jar data/planetiler.jar \
  --download --osm-path="$PBF" --tmpdir=data/tmp \
  --output="out/$NAME.pmtiles" --maxzoom="$MAXZOOM" --only-layers="$LAYERS" --force

ls -lh "out/$NAME.pmtiles"
