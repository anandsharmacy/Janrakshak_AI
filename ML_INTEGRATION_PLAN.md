# ML Integration Plan: connecting `sih-ml` to the Flutter app and the website

**Date:** 2026-09-12
**Scope:** SRS §6.7 (ML-001 … ML-011), WEB-007, acceptance criterion §12.2 #8
**Model:** `final_v3` (LightGBM, 1,199 trees, 309,042 road segments, daily horizon)

---

## 1. Recommendation in one paragraph

Don't let the apps call the model service. `sih-ml` is already built as a **daily batch plus a read API**:
the model scores the whole corridor once a day in about 1 s, and every later question is a lookup.
The integration should work the same way. After each daily batch, a new **publish step** copies that day's
scores into the shared **Supabase/PostGIS** database. There, **PostGIS maps route geometry to road segments**
and **RLS/RPCs enforce roles**. Flutter and the website read ML risk through Supabase RPCs, as they already do
for rider tracking. The `sih-ml` HTTP API stays private: it gets called by the publish job, and later by one
Edge Function for control-room what-if scenarios. This gives both clients the same versioned prediction
(§12.2 #8), audit records (ML-007), offline caching and Realtime refresh without shipping any credential.

---

## 2. What exists today

| Component | State relevant to ML | Evidence |
|---|---|---|
| `sih-ml` serving | Daily batch → `deploy/scores/date=D/{scores.parquet,run.json}`; WSGI API `GET /v1/scores`, `GET /v1/alerts`, `POST /v1/score`, `/v1/model`, `/readyz`, `/metrics`. Hash-verified bundle, drift monitor, Prometheus. | `sih-ml/src/sih_ml/serve/api.py`, `DEPLOYMENT.md` |
| API output per segment | `raw_score`, `p_calibrated`, `risk_percentile` (**primary output**), `steep`, `tier` ∈ {none, alert, human_review}, `tier_rank` | `scores.parquet`, `policy.json` |
| API security | **No auth, no CORS.** Clients can only query by opaque ids like `SEG291652` | `api.py` |
| Segment geometry | Serving store has **no coordinates** (`segment_id, cell_index, slope_mean_deg`). Centroids exist in `data/interim/segment_centroids.parquet`. Line geometry (`corridor_roads.gpkg`) sits in `../data2`, **which is not in the workspace** | `featurestore/segments.parquet`, `conf/config.yaml` |
| Flutter app | Riverpod → repository → Supabase RPC pattern (`RiderRepository`). OSRM trip plans, `SpatialAnalyticsService` with fallback. All "AI prediction" cards are **hard-coded strings** | `lib/features/rider/data/rider_repository.dart`, `lib/services/geo_providers.dart`, `control_room_shell.dart:902-1872` |
| Website (`web/NER-Website-Merged`) | Supabase is used **only for auth**; pages use `src/data/demo.ts`. `aiInsights.riskPredictions` is `[]`. `MapViz` has a `risk` layer driven by incidents | `src/lib/supabase.ts`, `src/pages/AIInsights.tsx`, `src/components/MapViz.tsx` |
| Supabase | Shared backend (Auth, Postgres+PostGIS, RLS helpers `is_active_user()`, `is_officer()`, `has_role()`, Realtime) | `ner_logistics/SUPABASE_INTEGRATION.md` |

---

## 3. Blockers found during analysis (resolve in Phase 0)

| # | Finding | Impact | Resolution |
|---|---|---|---|
| **B1** | The Supabase project `web/district,field,contro dashboards/App Development/` (migrations, `seed.sql`, `config.toml`) **is missing**. Only a macOS `._App Development` stub remains. `docker-compose.yml` mounts that missing path. | No place to add ML tables/RPCs; the rider-tracking migrations described in `SUPABASE_INTEGRATION.md` can't be replayed. | Restore it from its git remote or a backup, or recreate it as `supabase/` at the workspace root. **Nothing in Phase 2 can start until this is done.** |
| **B2** | **Coverage mismatch.** Model cells span lat 25.625–28.125°N, lon 87.125–89.875°E: the Siliguri corridor, North Bengal, Sikkim and far-west Assam. Both Flutter demo trips (Guwahati → Meghalaya, lon 91.7–92.4) touch **0 segments**. The seeded rider (Nongpoh, LG-108) and most web corridors are also out of coverage. | Without a fix, every demo route would show "outside model coverage". | Add an in-coverage demo route, **Siliguri → Gangtok (NH-10)**. Its box holds 11,297 segments; on 2025-08-05 it had 205 `alert` and 2,303 `human_review` segments. Show an explicit out-of-coverage state everywhere else (ML-008). Expanding coverage to the NE states needs new training data and retraining, which is out of scope here. |
| **B3** | **No live rainfall feed.** CHIRPS ends 2025-12-31, `/readyz` returns 503 by design, and scored days run 2025-06-01 … 2025-09-30 (123 days). | Nothing "today" to show. | **Replay mode:** publish a historical day and label it everywhere as *"Replay: rainfall of 5 Aug 2025"* (ML-011). Live mode needs the IMD/IMERG feed adapter and P4 recalibration (DEPLOYMENT.md §9). |
| **B4** | Only centroids, no line geometry. Median spacing between neighbouring centroids is **97 m** (p90 266 m). | Route → segment matching is approximate. | Match segments to routes by buffer (`ST_DWithin`, default 100 m, tuned in Phase 2). Switch to line geometry if `data2/…/corridor_roads.gpkg` is recovered. |
| **B5** | **Alert volume.** A median 2025 monsoon day had 3,502 `alert` + 20,940 `human_review` segments. | Alert fatigue if everything is pushed. | Never auto-create alerts. Show the top-N by `tier_rank`; N is a policy decision with MDoNER. Officers promote individual items (Phase 3/4). |
| **B6** | Compose drift: `web-dashboard` sets `VITE_SUPABASE_ANON_KEY`, but the web code reads `VITE_SUPABASE_PUBLISHABLE_KEY`. It also hardcodes LAN IP `10.183.142.78` and points at the missing folder instead of `NER-Website-Merged`. Web `CORRIDORS` are coarse town-to-town waypoints, not road geometry. | Web container can't authenticate; routes can't be matched to segments. | Fix in Phase 5. Store road-snapped (OSRM) geometry for canonical routes in Supabase `routes.geom` so **both clients score the identical line**. |

---

## 4. Target architecture

```text
                         ┌──────────── sih-ml VM / container (private network) ────────────┐
 rainfall feed ──► feed ─┤ featurestore ──► batch (06:30 IST) ──► scores/date=D/*.parquet   │
 (replay: none)          │                                  │                               │
                         │                                  ▼                               │
                         │                     publish (NEW)  ── psycopg COPY ──────────┐   │
                         │  gunicorn API (unchanged, private) ◄── Edge Fn (Phase 6)     │   │
                         └──────────────────────────────────────────────────────────────┼───┘
                                                                                        ▼
            ┌──────────────────────── Supabase (Postgres + PostGIS) ────────────────────────┐
            │ ml_model_versions  ml_batch_runs  ml_coverage  ml_segments(geom)              │
            │ ml_segment_scores (partitioned by date)  ml_route_risk_snapshots  alerts(+ml) │
            │ RPC: ml_status · get_route_ml_risk · get_ml_segments_in_bbox ·                │
            │      get_ml_top_alerts · record_route_risk_snapshot · promote_ml_alert        │
            │ RLS + Realtime(ml_batch_runs, alerts)                                         │
            └───────────────┬──────────────────────────────────────────┬────────────────────┘
                            │ supabase_flutter (publishable key + JWT)  │ supabase-js
                            ▼                                          ▼
        Flutter: lib/features/ml/  (rider route panel,     Web: src/lib/ml.ts  (AI Insights,
        trip map, officer route status, control room)     MapViz 'ml' layer, Routes, Command Center)
```

### Why this shape

| Option | Verdict | Reason |
|---|---|---|
| Clients call `sih-ml` directly | Rejected | No auth, no CORS, no role checks. Clients only know coordinates, never segment ids. Violates SRS §8.3 and §9.1 (no model credentials in APK/JS). |
| Edge Function proxy on every request | Rejected as primary path | Adds a hop to a value that changes once a day. No audit copy, no offline cache, and it still needs geometry → segment matching somewhere. |
| **Publish daily scores into Supabase; clients use RPCs** | **Chosen** | Matches the model's daily cadence (DEPLOYMENT.md §1). PostGIS already does the spatial matching. RLS, Realtime and the audit trail come for free. Flutter and web share one code path. |
| Edge Function → `POST /v1/score` | Phase 6 | Only for control-room what-if rainfall scenarios, which need the live model. |

### SRS amendment needed

SRS §8.3 shows clients sending `features` (rainfall, slope…). With this model **the server owns the features**
(the feature store). Clients send only **route geometry or route id plus a date**. Update ML-002 and §8.3 to that contract.

---

## 5. Data contract

### 5.1 Tables (new migration `…_ml_integration.sql`)

| Table | Rows | Written by | Purpose |
|---|---|---|---|
| `ml_model_versions` | 1 per bundle | publish | version, bundle hash, manifest, policy JSON, registry status, approved_by/at (ML-009) |
| `ml_batch_runs` | 1 per published day | publish | score_date, mode (`live`/`replay`), bundle hash, featurestore schema hash, tier counts, drift, data quality, `is_current`, published_at, `expires_at` (next batch) — the `run.json` |
| `ml_coverage` | 1 | publish `--segments` | multipolygon = union of the 119 rainfall cells that contain segments |
| `ml_segments` | 309,042 | publish `--segments` | segment_id PK, `geom geography(Point)` (GiST), slope, steep, cell_index; later `geom_line` |
| `ml_segment_scores` | 309,042 per day, **range-partitioned by `score_date`**, 30-day retention | publish | segment_id, score_date, risk_percentile, tier, tier_rank, p_calibrated, raw_score, run_id |
| `ml_route_risk_snapshots` | per trip start / advisory shown | clients via RPC | route id or geometry hash, run_id, summary JSON, user, shipment: the record of what a rider or officer was actually shown (ML-006/007) |
| `alerts` (+ columns) | as promoted | `promote_ml_alert` | `source` (`human`/`rule`/`feed`/`ml`), `ml_segment_id`, `ml_run_id`, `promoted_by` (WEB-007, ML-011) |
| `routes` (+ column) | canonical routes | seed script | `geom geography(LineString)`: OSRM-snapped geometry so both clients score the same line |

The full parquet per day stays in `sih-ml/deploy/scores/` as the long-term audit copy. `run_id` links the two.

### 5.2 RPCs (all `SECURITY DEFINER`, `stable`, role-checked)

| RPC | Callers | Returns |
|---|---|---|
| `ml_status()` | all active users | `{state: live\|replay\|stale\|unavailable, score_date, published_at, expires_at, model_version, bundle_hash, primary_output, probability_caveat}` |
| `get_route_ml_risk(p_route_id text default null, p_geojson jsonb default null, p_date date default null, p_buffer_m int default 100)` | all active users (riders: their assigned shipment's route or current trip geometry) | route summary plus ordered segments (below) |
| `get_ml_segments_in_bbox(p_bbox float8[4], p_min_tier text default 'human_review', p_limit int default 2000)` | officers | map points for the `ml` layer |
| `get_ml_top_alerts(p_date date default null, p_tier text default 'alert', p_limit int default 20, p_district text default null)` | officers | top-N by `tier_rank`, with nearest place/district |
| `record_route_risk_snapshot(p_client_id uuid, p_route_id text, p_geojson jsonb, p_run_id bigint, p_summary jsonb, p_shipment_id text)` | all active users | idempotent on `client_id` (fits the offline queue) |
| `promote_ml_alert(p_segment_id text, p_run_id bigint, p_note text)` | control_room, district_officer | creates an `alerts` row with `source='ml'` plus an audit entry |

`get_route_ml_risk` response (shared by both clients):

```json
{
  "status": "replay",
  "score_date": "2025-08-05",
  "model_version": "final_v3",
  "bundle_hash": "bf4ff57518c571e9",
  "run_id": 42,
  "expires_at": "2025-08-06T01:00:00Z",
  "coverage_fraction": 0.97,
  "summary": {
    "max_percentile": 99.8,
    "n_alert": 6,
    "n_human_review": 41,
    "worst_segment_id": "SEG123456",
    "worst_along_m": 48210
  },
  "segments": [
    {"segment_id": "SEG123456", "along_m": 48210, "lat": 27.12, "lon": 88.52,
     "risk_percentile": 99.8, "tier": "alert", "steep": false}
  ],
  "caveat": "Rank by risk_percentile. p_calibrated is not a true daily probability…"
}
```

The core of the query: simplify the line (`ST_Simplify` ~20 m), use `ST_DWithin` on geography with a GiST index, get
`along_m` from `ST_LineLocatePoint × ST_Length`, and compute `coverage_fraction` from the intersection length with `ml_coverage`.
It returns only segments whose tier is not `none`, plus the max-percentile segment, so payloads stay small.
Target: p95 < 150 ms for a 120 km route.

### 5.3 RLS

- `ml_*` tables: `select` for officers (`is_officer()`). Riders get **no direct table access**; they go through
  `get_route_ml_risk` / `ml_status` only (SRS §11.1: "relevant route").
- Writes only from the publish job's DB role (a dedicated `ml_publisher` Postgres role, not the service-role JWT) and the RPCs above.
- Realtime publication: `ml_batch_runs` (clients refresh when a new day lands) and `alerts` (already published).

### 5.4 UI semantics (identical in both clients)

| Model output | Shown as | Never |
|---|---|---|
| `risk_percentile` | "Riskier than 98% of corridor roads today" and a 5-step bar | shown as "probability" or "% confidence" |
| `tier = alert` | **High disruption risk: review before travel** (red, icon + text) | auto-reroute, auto-SOS |
| `tier = human_review` | **Needs officer review: steep terrain** (amber) | treated as an alert |
| `status = replay` | persistent chip "Replay · rainfall of 5 Aug 2025" | hidden |
| `status = stale / unavailable` | grey chip with the last good date; rule and incident alerts still show | treated as live |
| `coverage_fraction < 1` | "Model covers 34% of this route" | silence on the uncovered part |
| source | every ML item carries an **ML · final_v3** tag, separate from human, rule and feed items | mixed into incident lists unlabeled |

`p_calibrated` is **not shown** to users (per `policy.json` caveat). It is kept in the DB for analysts.

---

## 6. Implementation phases

Order: 0 → 1 → 2, then 3 and 4 in parallel, then 5. Phase 6 is optional or later. Sizes: S ≈ ≤ 2 days, M ≈ 3–5 days, L ≈ 1–2 weeks (one developer).

### Phase 0: Unblock (S)

- [ ] Restore the Supabase project (B1) and confirm `supabase db reset` replays the existing migrations and seed.
- [ ] Confirm the canonical website: **`web/NER-Website-Merged`** (recommended; it merges auth and dashboards).
- [ ] Decide the demo/replay day (recommended **2025-08-05**) and the alert capacity N (B5) with the product owner.
- [ ] Try to recover `data2/training_data/road_network/corridor_roads.gpkg` (B4). Not blocking.
- **Exit:** local Supabase runs; decisions recorded in this file.

### Phase 1: `sih-ml` publish path (M)

| Task | Files |
|---|---|
| Add `lon`, `lat` (from `segment_centroids.parquet`) to the deploy feature store so the serving artifact is self-contained | `src/sih_ml/serve/build.py`, `deploy/featurestore/segments.parquet` |
| New `publish` module: `--segments` (load `ml_segments` + `ml_coverage`), `--date D [--mode live\|replay] [--set-current]`: COPY into a staging table, `ATTACH PARTITION` + insert `ml_batch_runs` in one transaction; idempotent on (score_date, bundle_hash); drop partitions > retention | `src/sih_ml/serve/publish.py` (new), `deploy/requirements-publish.txt` (psycopg 3) |
| Upsert `ml_model_versions` from `models/registry.json` + bundle manifest | same |
| Hook into the daily job after the batch: `publish --date "$DAY"`; exit code 4 on publish failure | `deploy/ops/sih-daily.sh` |
| Metrics `sih_publish_last_success_timestamp`, alert "no publish for 36 h" | `serve/monitor.py`, `deploy/ops/alerts.yml` |
| Optional: bearer-token check on the API (`SIH_API_TOKEN`) for the Phase 6 Edge Function | `serve/api.py` |
| Tests: publish idempotence, row-count parity (309,042), tier counts = `run.json`, failed publish leaves the previous day current | `tests/test_publish.py` (new, against a throwaway Postgres) |

- **Exit:** `make publish DATE=2025-08-05 MODE=replay` fills local Supabase; re-running is a no-op.

### Phase 2: Supabase schema and RPCs (M)

| Task | Files |
|---|---|
| Migration: tables in §5.1, partitions, GiST indexes, `alerts`/`routes` columns | `supabase/migrations/2026xxxx_ml_integration.sql` |
| RPCs in §5.2 + RLS in §5.3 + Realtime on `ml_batch_runs` | same |
| Seed: canonical routes with OSRM-snapped `geom`, including **Siliguri → Gangtok (NH-10)** and one out-of-coverage route (Guwahati → Shillong) | `supabase/seed.sql`, a small script that calls OSRM once |
| Tune `p_buffer_m` on NH-10: compare centroid matches with a hand-checked sample and pick the smallest buffer that catches the road without parallel roads | notes in this file |
| pgTAP (or SQL) tests: rider can't `select` `ml_segment_scores`; officer can; rider RPC works; `promote_ml_alert` refused for riders; out-of-coverage route returns `coverage_fraction = 0` | `supabase/tests/ml_*.sql` |

- **Exit:** `select get_route_ml_risk('NH10-SLG-GTK')` returns segments ordered by `along_m`; the RLS tests pass.

### Phase 3: Website, `web/NER-Website-Merged` (M)

| Task | Files |
|---|---|
| Typed client + hooks: `mlStatus()`, `routeRisk()`, `segmentsInBbox()`, `topAlerts()`, `promote()`; Realtime subscription on `ml_batch_runs` | `src/lib/ml.ts`, `src/lib/useMl.ts` (new) |
| Components: `MlStatusChip`, `MlRiskPill`, `MlPercentileBar`, `MlSourceTag` | `src/components/ml/*` (new) |
| **AI Insights:** replace empty `aiInsights.riskPredictions` with `get_ml_top_alerts`; keep demo items only under a "Demo / rule-based" heading | `src/pages/AIInsights.tsx`, `src/data/demo.ts` |
| **MapViz:** add `'ml'` to `MapLayer`; on `moveend` fetch `get_ml_segments_in_bbox`, draw tier-coloured circle markers and a coverage outline; legend "ML model · final_v3" | `src/components/MapViz.tsx` |
| **Routes / FO Route Status:** per-route ML summary (status chip, worst segment, alert count, coverage %) | `src/pages/Routes.tsx`, `src/pages/fo/RouteStatus.tsx` |
| **Command Center:** top-N ML alerts with "Promote to alert" (control_room, district_officer only) | `src/pages/control/CommandCenter.tsx` |
| Empty, loading, error, stale and out-of-coverage states for every component | — |

- **Exit:** with replay 2025-08-05 published, AI Insights lists real NH-10 segments; the map shows the ML layer; a rider-role session can't see Command Center data.

### Phase 4: Flutter, `ner_logistics` (L)

| Task | Files |
|---|---|
| Domain: `MlStatus`, `MlState`, `MlTier`, `SegmentRisk`, `RouteMlRisk` (`fromJson`, equatable) | `lib/features/ml/domain/ml_models.dart` (new) |
| Repository: RPC calls with a 15 s timeout, same style as `RiderRepository` | `lib/features/ml/data/ml_repository.dart` (new) |
| Providers: `mlStatusProvider` (fetch + Realtime), `routeMlRiskProvider.family(RouteKey)`, `riderRouteMlRiskProvider` wired to `riderTripPlanProvider`; **offline cache** of the last result per route in `shared_preferences` with `fetchedAt` → stale state | `lib/features/ml/application/ml_providers.dart` (new) |
| Widgets: `MlStatusChip`, `MlRiskBadge`, `MlRouteRiskStrip` (segments along the route); change `AiCard` so it no longer takes `confidence`, and add `metricLabel` + `sourceTag` | `lib/features/ml/presentation/*`, `lib/shared/widgets/ai_card.dart` |
| **Rider:** route panel shows the ML summary and the next risky segment ahead (distance from `vehicleM`); an advisory banner when `tier=alert` ahead; record a snapshot on trip start | `lib/features/rider/rider_route_panel.dart`, `lib/shared/map/trip_route_map.dart` |
| **Safer alternative (advisory):** score OSRM alternatives (`--max-alternatives 3`) and offer "Lower-risk route available" with explicit accept; never switch silently (ML-006) | `lib/services/routing/trip_plan.dart`, `route_planner.dart` |
| **Officers:** field route status, and replacing the hard-coded `AiCard`s in the control room with `get_ml_top_alerts`, plus promote | `lib/features/field_officer/route_status/route_status_screen.dart`, `lib/features/control_room/control_room_shell.dart` |
| Demo scenario inside coverage: Siliguri (26.727, 88.395) → Gangtok (27.339, 88.607) | `lib/mock_data/mock_route_scenarios.dart` |
| Tests: JSON parsing (every state), stale/offline mapping, widget tests for the chip/badge states, a provider test with a fake repository | `test/features/ml/*` |

- **Exit:** on an Android device, the NH-10 trip shows the same `score_date`, `bundle_hash`, alert count and worst segment as the website; the Guwahati → Shillong trip shows "Outside model coverage".

### Phase 5: Integration, ops, acceptance (S–M)

- [ ] `docker-compose.yml`: point `web-dashboard` at `web/NER-Website-Merged`, rename the env var to `VITE_SUPABASE_PUBLISHABLE_KEY`, move the LAN IP into `.env`, keep `sih-ml` on an internal network (host port for dev only), add a one-shot `sih-publish` service.
- [ ] E2E acceptance script (§12.2 #8): publish the replay day, then query the same route through the Flutter repository test and the web client; assert equal `model_version`, `bundle_hash`, `run_id`, `n_alert`, `max_percentile`.
- [ ] Security check: `strings` on the release APK and a grep of `dist/` for service-role keys, `SIH_API_TOKEN`, DB URLs (§12.2 #7).
- [ ] Update SRS §6.7 / §8.3 / §15 status rows and `SUPABASE_INTEGRATION.md`.

### Phase 6: Later

- **What-if scenarios:** Supabase Edge Function `ml-whatif` (control_room only) → `POST /v1/score` with a 61-day rainfall scenario, bearer token held as a function secret.
- **Explanations (ML-003):** LightGBM `pred_contrib=True` for tiered rows only in the batch, top 3 factors stored per segment ("7-day rainfall", "slope").
- **Feedback loop (ML-010):** link verified `road_incidents` to nearby `ml_segments` → outcome table for false-alarm and miss rates, feeding P4 recalibration.
- **Live feed:** IMD/IMERG adapter writing `incoming/rain_D.csv`, recalibrated before `mode=live` is enabled.
- **GeoServer WMS layer** of ML risk, if map point volume outgrows client rendering.

---

## 7. SRS traceability

| Req | Delivered by |
|---|---|
| ML-001 | Phase 1 publish + Phase 2 RPCs (protected, Supabase-compatible) |
| ML-002 | `get_route_ml_risk` (route id / geometry + date); features stay server-side (SRS amendment) |
| ML-003 | percentile, tier, model_version, bundle_hash, published_at, expires_at; factors in Phase 6 |
| ML-004 | Phase 3 |
| ML-005 | Phase 4 |
| ML-006 | advisory UI, explicit accept for alternatives, `promote_ml_alert`, snapshots |
| ML-007 | `ml_batch_runs`, partitions, `ml_route_risk_snapshots`, parquet archive |
| ML-008 | `ml_status` states + `coverage_fraction` |
| ML-009 | `ml_model_versions` from registry + bundle manifest; approval columns |
| ML-010 | existing drift + batch.prom, new publish metrics; outcomes in Phase 6 |
| ML-011 | `source` column and ML tag; demo items relabelled |
| WEB-007 | `MlSourceTag`, separate sections |
| §12.2 #7, #8 | Phase 5 checks |

## 8. Risks

| Risk | Mitigation |
|---|---|
| Stakeholders read replay output as today's conditions | Persistent replay chip in both clients; `mode` stored per run; no push notifications in replay |
| Centroid matching attaches a parallel road | Buffer tuning in Phase 2; line geometry once `gpkg` is found; show segment location on the map for review |
| Most NER routes are outside coverage | Explicit coverage %, coverage outline on maps, rule/incident alerts remain primary there |
| 309k-row daily load slows the shared DB | COPY into a detached partition, attach in one transaction, 30-day retention; runs off-peak (06:30 IST) |
| Probability misread as certainty | Percentile-only UI; `p_calibrated` hidden from users |
| Alert fatigue | Top-N by `tier_rank`, human promotion only |

## 9. Open decisions

1. Where is the Supabase project (B1)? Restore it, or recreate it at the workspace root?
2. Is `NER-Website-Merged` the canonical website?
3. Which replay day for demos (2025-08-05 proposed)? A fixed day, or rotating?
4. Daily capacity N for ML alerts shown to officers.
5. Should riders see ML risk for their own route only (SRS §11.1), or also a regional overview?
