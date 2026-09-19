#!/usr/bin/env bash
# Publishes the `ner` PostGIS tables, analytics views and styles to GeoServer
# through its REST API. Safe to re-run (creates what's missing, updates styles).
#
#   GEOSERVER_URL=http://localhost:8080/geoserver GEOSERVER_AUTH=admin:geoserver ./publish.sh
set -euo pipefail

GS="${GEOSERVER_URL:-http://localhost:8080/geoserver}"
AUTH="${GEOSERVER_AUTH:-admin:geoserver}"
WS=ner
STORE=ner_postgis
# Host/credentials GeoServer uses to reach PostGIS (docker compose service).
PG_HOST="${PG_HOST:-postgis}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RESP="$(mktemp)"
trap 'rm -f "$RESP"' EXIT

# rest METHOD PATH [CONTENT_TYPE] [BODY|@FILE] → prints HTTP status
rest() {
  local args=(-s -o "$RESP" -w '%{http_code}' -u "$AUTH" -X "$1")
  if [[ $# -ge 4 ]]; then args+=(-H "Content-Type: $3" --data-binary "$4"); fi
  curl "${args[@]}" "$GS/rest$2"
}
exists() { [[ "$(rest GET "$1")" == 200 ]]; }
check() { # check STATUS WHAT
  if [[ "$1" != 2* ]]; then echo "  ✗ $2 (HTTP $1): $(head -c 300 "$RESP")" >&2; exit 1; fi
  echo "  ✓ $2"
}

echo "Waiting for GeoServer at $GS …"
for _ in $(seq 1 60); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" "$GS/rest/about/version.json")" == 200 ]] && break
  sleep 5
done

exists "/workspaces/$WS" ||
  check "$(rest POST /workspaces application/json "{\"workspace\":{\"name\":\"$WS\"}}")" "workspace $WS"

exists "/workspaces/$WS/datastores/$STORE" ||
  check "$(rest POST "/workspaces/$WS/datastores" application/json "{
    \"dataStore\": {\"name\": \"$STORE\", \"connectionParameters\": {\"entry\": [
      {\"@key\": \"dbtype\", \"\$\": \"postgis\"},
      {\"@key\": \"host\", \"\$\": \"$PG_HOST\"},
      {\"@key\": \"port\", \"\$\": \"5432\"},
      {\"@key\": \"database\", \"\$\": \"ner\"},
      {\"@key\": \"schema\", \"\$\": \"ner\"},
      {\"@key\": \"user\", \"\$\": \"ner\"},
      {\"@key\": \"passwd\", \"\$\": \"ner\"},
      {\"@key\": \"Expose primary keys\", \"\$\": \"true\"}
    ]}}}")" "datastore $STORE"

LAYERS=(highways incidents risk_zones safe_zones depots vehicles
        highway_risk_exposure convoy_exposure area_incident_summary)
for ft in "${LAYERS[@]}"; do
  path="/workspaces/$WS/datastores/$STORE/featuretypes"
  if ! exists "$path/$ft"; then
    check "$(rest POST "$path" application/json "{\"featureType\": {
      \"name\": \"$ft\", \"nativeName\": \"$ft\", \"title\": \"$ft\",
      \"srs\": \"EPSG:4326\", \"projectionPolicy\": \"FORCE_DECLARED\"}}")" "layer $WS:$ft"
  fi
  # Bounds change whenever the seed data does.
  check "$(rest PUT "$path/$ft?recalculate=nativebbox,latlonbbox" application/json \
    '{"featureType": {"enabled": true}}')" "bounds $WS:$ft"
done

for sld in "$HERE"/styles/*.sld; do
  name="$(basename "$sld" .sld)"
  if exists "/workspaces/$WS/styles/$name"; then
    check "$(rest PUT "/workspaces/$WS/styles/$name" application/vnd.ogc.sld+xml "@$sld")" "style $name (updated)"
  else
    check "$(rest POST "/workspaces/$WS/styles?name=$name" application/vnd.ogc.sld+xml "@$sld")" "style $name"
  fi
done

check "$(rest PUT "/layers/$WS:risk_zones" application/json \
  "{\"layer\": {\"defaultStyle\": {\"name\": \"$WS:ner_risk_zones\"}}}")" "risk_zones default style"
check "$(rest PUT "/layers/$WS:incidents" application/json \
  "{\"layer\": {\"styles\": {\"@class\": \"linked-hash-set\", \"style\": [{\"name\": \"$WS:ner_incident_heatmap\"}]}}}")" \
  "incidents heatmap style"

echo
echo "Done. Test:"
echo "  curl '$GS/$WS/ows?service=WFS&version=2.0.0&request=GetFeature&typeNames=$WS:highway_risk_exposure&outputFormat=application/json&propertyName=highway_id,flood_km,landslide_km'"
