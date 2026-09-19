# NER Logistics — routing & GIS backend

The app talks to two services. Both are optional: without them it uses the
public OSRM demo server and on-device analytics estimates.

| Service | Used for | App code |
| --- | --- | --- |
| **OSRM** (routing engine) | Trip routes, ETAs, turn instructions, hazard detours, closure impact | `lib/services/routing/` |
| **GeoServer** + PostGIS (advanced analytics) | Risk-zone & heatmap WMS overlays, highway exposure / convoy exposure / incident summaries, hazards along a route, tap-to-inspect | `lib/services/gis/` |

## OSRM

```bash
cd backend/osrm
./prepare.sh            # downloads the Geofabrik north-eastern-zone extract and builds the graph
docker compose up -d    # http://localhost:5000
```

The extract covers the north-eastern states only. Routes that leave the region
(e.g. the Siliguri corridor, NH-10) need `REGION=eastern-zone` merged in or the
full India extract. The default `car.lua` profile is optimistic for loaded
trucks on hill roads, which is why the app shows a +20 % ETA window.

The public demo server (`router.project-osrm.org`) is fine for demos but
allows ~1 request/second and no heavy use. The app spaces requests
automatically when pointed at it.

## GeoServer

```bash
cd backend/geoserver
docker compose up -d    # PostGIS loads sql/01 → 02 → 03 on first start
./publish.sh            # workspace `ner`, PostGIS store, layers, styles
```

Layers in workspace `ner`:

- Tables: `highways`, `incidents`, `risk_zones`, `safe_zones`, `depots`, `vehicles`
- Analytics views (`sql/03_analytics_views.sql`):
  - `highway_risk_exposure` — km of each highway inside flood / landslide zones, incidents within 2 km
  - `convoy_exposure` — risk zone each vehicle is in, nearest safe zone and distance
  - `area_incident_summary` — incident counts by area and severity
- Styles: `ner_risk_zones` (default for `risk_zones`), `ner_incident_heatmap`
  (`vec:Heatmap` on `incidents`, needs the WPS extension the compose file installs)

`sql/02_seed.sql` is demo data generated from the app. Replace it with real
susceptibility polygons (e.g. GSI landslide zonation, ASDMA flood hazard) and
live incident/fleet feeds; the views and the app keep working as long as the
column names stay the same.

## Pointing the app at them

```bash
flutter run \
  --dart-define=OSRM_URL=http://10.0.2.2:5000 \
  --dart-define=GEOSERVER_URL=http://10.0.2.2:8080/geoserver
```

`10.0.2.2` is the host machine from the Android emulator; use your machine's
LAN IP on a physical device. Cleartext HTTP is allowed in **debug** Android
builds and for local-network hosts on iOS; use HTTPS for anything else.

## Regenerating baked data

The app ships a snapshot of OSRM road geometry (highways, trip routes and the
precomputed detour) so maps work offline. After changing waypoints, zones or
the trip scenarios:

```bash
dart run tool/generate_geodata.dart [OSRM_URL]
```

This rewrites `lib/shared/map/generated/geo_snapshot.g.dart` and
`backend/geoserver/sql/02_seed.sql`. Reload PostGIS with
`docker compose down -v && docker compose up -d && ./publish.sh`.
