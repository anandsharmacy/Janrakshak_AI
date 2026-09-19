# NER Logistics Platform
## Software Requirements Specification (SRS)

**Document version:** 1.0  
**Date:** 2026-09-12  
**Status:** Baseline requirements and implementation reference  
**Project:** NER Logistics Platform, MDoNER SIH26002  
**Scope:** Flutter mobile application, web dashboards, authentication/account creation, shared Supabase backend, routing/GIS services, and planned ML integration

> This document is the combined requirements baseline for the software present in this workspace. It describes the current implemented capabilities and the target capabilities required for a complete production system. The ML model exists as a separate pipeline in `sih-ml`; its runtime connection to the Flutter app and web dashboards is planned and is not yet implemented.

---

## 1. Purpose

The NER Logistics Platform shall support the planning, monitoring, reporting, and safe execution of logistics operations across the North Eastern Region of India. The platform shall give field officers, district officers, control-room operators, and logistics riders a shared operational view of shipments, vehicles, routes, hazards, incidents, alerts, and rider locations.

The system shall:

- Improve visibility of logistics activity across districts and regional corridors.
- Help officers identify road, weather, flood, landslide, infrastructure, and shipment risks.
- Provide riders with assigned deliveries, active-trip tools, route alerts, issue reporting, delivery proof, and live location sharing.
- Continue essential field work during poor or unavailable connectivity.
- Provide a shared source of truth through Supabase/Postgres/PostGIS, authentication, and Realtime events.
- Provide an extension point for the disruption-prediction ML model to deliver risk scores and operational recommendations to both the mobile and web clients.

## 2. Product Scope

### 2.1 In scope

1. Flutter Android-first mobile application.
2. Role-based sign-in and account creation.
3. Logistics Rider dashboard and rider workflows.
4. Field Officer, District Officer, and Control Room workflows.
5. Shipment, fleet, route, incident, alert, district, and regional monitoring.
6. Interactive maps covering the North Eastern Region.
7. OSRM routing and ETA services.
8. GeoServer/PostGIS risk overlays and analytical views.
9. Supabase Auth, Postgres, PostGIS, RLS, RPCs, and Realtime.
10. Offline queues and synchronization for rider location and field actions.
11. Background location tracking with user permission on supported platforms.
12. The separate ML training, evaluation, and model-artifact pipeline.
13. A future ML inference integration used by the Flutter app and websites.

### 2.2 Out of scope for the current release

- Payment, billing, payroll, or financial settlement.
- Full warehouse inventory management.
- Automatic dispatch optimization across all vehicles.
- Guaranteed cellular coverage or satellite connectivity.
- Production ML inference integration. The model is currently not connected to the app or websites.
- Autonomous route changes without the required operational approval.
- Replacement of government emergency, police, medical, or disaster-response systems.

## 3. System Context

The platform consists of the following cooperating products:

| Product | Users | Primary purpose | Current state |
|---|---|---|---|
| Flutter mobile app in `ner_logistics` | Riders and officers in the field | Trips, reports, maps, location sharing, offline work | Implemented prototype with Supabase-backed auth and rider tracking |
| District/field/control web dashboard | Field Officers, District Officers, Control Room Operators | Regional operations, incidents, shipments, fleet, alerts, live riders | React/Vite UI with Supabase integration in the App Development project |
| Login and Account Creation web app | All supported account users | Sign-in and registration flow | React/Vite UI with Supabase integration |
| Supabase backend | All clients | Auth, relational data, security, RPCs, and Realtime | Local project configuration and migrations present; deployment depends on runtime/hosting |
| OSRM service | Mobile and officer workflows | Routes, ETAs, turn guidance, and detours | Optional local service; public demo fallback exists |
| GeoServer/PostGIS service | Officer analytics and maps | WMS overlays, risk zones, exposure views, and spatial inspection | Optional local service with Docker Compose configuration |
| `sih-ml` pipeline | Data/ML operators and future inference service | Road-segment disruption prediction | Training/evaluation pipeline present; client integration pending |

### 3.1 High-level architecture

```text
Flutter mobile app  ─┐
                     ├── Supabase Auth / PostgREST / RPC / Realtime
Web dashboards     ──┘              │
                                    ├── PostgreSQL + PostGIS
                                    ├── Rider location and shipment data
                                    ├── Auth profiles and role policies
                                    └── Future ML inference service

Flutter and web clients ─── OSRM routing service
Web/mobile map clients ──── GeoServer/PostGIS spatial layers
ML pipeline ─────────────── model artifacts and future inference API
```

## 4. Stakeholders and User Classes

| User class | Responsibilities | Main interfaces |
|---|---|---|
| Logistics Rider | Execute assigned deliveries, share location, report issues, submit proof | Flutter mobile app |
| Field Officer | Inspect field conditions, submit and verify incidents, monitor routes and shipments | Flutter app and web dashboard |
| District Officer | Review district conditions, shipments, alerts, route access, and rider activity | Flutter app and web dashboard |
| Control Room Operator | Region-wide monitoring, escalation, fleet visibility, alerts, and coordination | Web dashboard and Flutter app |
| District/Regional Administrator | Provision users, manage roles, review access, maintain operational data | Web account/admin surfaces |
| Operations Manager | Define policies, workflows, KPIs, and response procedures | Web dashboard and reports |
| ML/Data Engineer | Build, validate, deploy, monitor, and retrain the disruption model | `sih-ml`, model service, operational dashboards |
| Platform Administrator | Configure Supabase, routing, GIS, monitoring, backups, and deployment | Backend and infrastructure tools |

## 5. Assumptions and Constraints

- The operating region is the North Eastern Region of India and its connected corridors.
- The platform requires internet access for live Supabase, Realtime, routing, GIS, and remote map tiles, but must preserve critical actions offline where specified.
- A physical Android device connecting to a local stack must use the host machine's LAN IP and the local API must be reachable from that network.
- Local Supabase, OSRM, and GeoServer services require their documented runtimes, including Docker where applicable.
- Only a Supabase publishable/anonymous client key may be shipped in mobile or browser clients. Service-role credentials shall remain server-side.
- GPS accuracy, battery level, network availability, and third-party map/routing availability are variable.
- The ML model's predictions are decision support, not an automatic declaration that a road is unsafe.
- Government data sources, weather feeds, road feeds, and labels may have delays, gaps, or inconsistent quality.

## 6. Functional Requirements

### 6.1 Identity, authentication, and authorization

| ID | Requirement | Priority |
|---|---|---|
| AUTH-001 | The system shall support email/password sign-in through Supabase Auth. | Must |
| AUTH-002 | The system shall support the roles `field_officer`, `district_officer`, `control_room`, and `rider`. | Must |
| AUTH-003 | The system shall load the authoritative role from the database after authentication; a UI-selected role shall not override the database role. | Must |
| AUTH-004 | The system shall support account creation with full name, official email, district/region, password, and selected role. | Must |
| AUTH-005 | Rider account creation shall accept a phone number and optional vehicle registration and shall send them as account metadata for rider profile creation. | Must |
| AUTH-006 | The database trigger shall create the appropriate profile and active role record after approved account creation. Rider accounts shall receive a rider profile. | Must |
| AUTH-007 | The system shall reject inactive users and users without an active operational role with a safe user-facing message. | Must |
| AUTH-008 | The system shall persist sessions, refresh tokens, and PKCE state using the Supabase client facilities. | Must |
| AUTH-009 | The system shall provide sign-out and clear local session state even when the remote sign-out request fails. | Must |
| AUTH-010 | The system shall prevent riders from being routed into officer dashboards and shall route each authenticated role to its permitted experience. | Must |
| AUTH-011 | Passwords shall never be stored by the client application or written to application logs. | Must |

### 6.2 Rider account and rider dashboard

| ID | Requirement | Priority |
|---|---|---|
| RIDER-001 | A rider shall be able to view identity, phone, district, vehicle, duty state, and assigned shipment context. | Must |
| RIDER-002 | A rider shall be able to view assigned deliveries including origin, destination, cargo, risk, time window, ETA, route, and status. | Must |
| RIDER-003 | The system shall support assignment states including pending, accepted, rejected, expired, assigned, en route, paused, rerouting, arrived, completed, failed, and cancelled. | Must |
| RIDER-004 | Where policy allows, a rider shall accept an assignment and the decision shall be recorded with an idempotent identifier. | Must |
| RIDER-005 | A rider shall be able to start, pause, resume, and complete a trip according to required delivery and proof rules. | Must |
| RIDER-006 | The active-trip view shall display route, current position when available, next instruction, ETA, progress, route risk, and operational alerts. | Must |
| RIDER-007 | A rider shall be able to report road, weather, vehicle, safety, delivery, and emergency issues with severity, location, time, description, and optional media. | Must |
| RIDER-008 | A rider shall be able to submit configured delivery proof such as OTP, signature, photo, QR code, or geotag. | Must |
| RIDER-009 | The system shall provide SOS/emergency assistance from active-trip workflows and include the latest known rider, vehicle, shipment, and position context. | Must |
| RIDER-010 | The rider dashboard shall display offline status, last synchronization time, queued actions, retry state, and sync errors. | Must |
| RIDER-011 | The rider shall be able to download and refresh supported offline map regions before leaving network coverage. | Should |
| RIDER-012 | Rider navigation shall remain focused on delivery execution and shall not expose unrelated district/control-room analytics. | Must |

### 6.3 Location tracking and live rider monitoring

| ID | Requirement | Priority |
|---|---|---|
| LOC-001 | A rider shall explicitly start and stop live location sharing; sign-out shall stop sharing. | Must |
| LOC-002 | The app shall request and explain the location permissions required for foreground and background tracking. | Must |
| LOC-003 | The location policy shall filter duplicate/stationary fixes, enforce movement/time thresholds, reject poor accuracy fixes, and emit periodic heartbeats. | Must |
| LOC-004 | Location points shall contain a client ID, latitude, longitude, recorded device time, accuracy, speed, heading, and optional shipment ID. | Must |
| LOC-005 | Location points shall be persisted locally before upload so temporary network loss does not silently discard accepted fixes. | Must |
| LOC-006 | The client shall upload locations in batches, retry failures with bounded exponential backoff, and de-duplicate retries server-side. | Must |
| LOC-007 | The system shall store the latest rider fix and an append-only location history with a defined retention policy. | Must |
| LOC-008 | The officer live-rider view shall show riders, duty state, last seen age, movement, accuracy, shipment, route, risk, and staleness. | Must |
| LOC-009 | Officer maps shall show live rider positions with heading when available and distinguish stale or high-risk riders visually. | Must |
| LOC-010 | The officer live-rider feed shall use Supabase Realtime and fall back to periodic polling when Realtime is unavailable. | Must |
| LOC-011 | The system shall ignore out-of-order location fixes and shall refresh joined shipment/rider data when an unknown or changed relationship is detected. | Must |
| LOC-012 | Rider location access shall be protected by RLS: riders may access their own records, while authorized officers may read operational rider data. | Must |

### 6.4 Shipments, fleet, and logistics operations

| ID | Requirement | Priority |
|---|---|---|
| OPS-001 | Officers shall view active shipments with shipment ID, vehicle, cargo type, origin, destination, location, ETA, status, and risk. | Must |
| OPS-002 | The system shall support shipment statuses including in transit, delayed, on schedule, and configured operational states. | Must |
| OPS-003 | Officers shall view fleet vehicles, route assignments, destination, movement/status, ETA, and risk. | Must |
| OPS-004 | A shipment may be associated with a rider and vehicle, and that association shall be visible to authorized users. | Must |
| OPS-005 | Delays, blocked routes, reroutes, and critical shipment risks shall be visible in operational dashboards. | Must |
| OPS-006 | The system shall retain an activity history for material assignment, route, incident, alert, proof, and status changes. | Should |

### 6.5 Incidents, alerts, and field reporting

| ID | Requirement | Priority |
|---|---|---|
| INC-001 | Authorized users shall report incidents including flood, landslide, road blockage, accident, infrastructure damage, and other hazards. | Must |
| INC-002 | Incident reports shall include type, location, route, severity, reporter, timestamp, verification state, status, and optional evidence. | Must |
| INC-003 | Officers shall view and filter alerts by critical, high, moderate, and informational severity. | Must |
| INC-004 | Alerts shall show description, distance/context, recommended action, time, and related incident when available. | Must |
| INC-005 | Authorized users shall acknowledge alerts, and the acknowledgement state shall be visible to the appropriate operational audience. | Must |
| INC-006 | The system shall support verification, assignment, escalation, and resolution states for incidents. | Should |
| INC-007 | Offline reports shall be queued locally and synchronized when connectivity returns without duplicate creation. | Must |
| INC-008 | Critical alerts shall be prioritized over informational content and shall remain usable on small mobile screens. | Must |

### 6.6 Maps, routing, and GIS

| ID | Requirement | Priority |
|---|---|---|
| GIS-001 | The system shall provide interactive maps covering the North Eastern Region with routes, vehicles, incidents, points of interest, risk zones, and rider positions. | Must |
| GIS-002 | The map shall support street and terrain presentation where configured. | Should |
| GIS-003 | The routing service shall provide route geometry, ETA, turn instructions, and detour/closure impact where available. | Must |
| GIS-004 | OSRM shall be configurable through build/runtime settings, with a documented public-demo fallback for non-production demos. | Must |
| GIS-005 | GeoServer/PostGIS shall provide WMS risk overlays and spatial analytics including highway exposure, convoy exposure, incident summaries, and hazards along a route. | Should |
| GIS-006 | Users shall be able to inspect supported map locations and related spatial information through configured long-press/tap interactions. | Should |
| GIS-007 | Offline map mode shall provide downloaded map coverage and local route overlays without requiring live tile requests. | Should |
| GIS-008 | Routing and hazard information shall display freshness/source state where operationally important. | Should |

### 6.7 Planned ML integration

The ML model is maintained in the separate `sih-ml` project. It predicts road-segment/day disruption risk, especially rainfall-triggered landslide and flood disruption, and is intended to support risk-aware routing.

| ID | Requirement | Priority |
|---|---|---|
| ML-001 | The platform shall connect the validated ML model to the shared logistics system through a server-side inference service or protected Supabase-compatible API. | Must for ML release |
| ML-002 | The ML inference service shall accept a road segment or route context and a date. Environmental/operational features shall be resolved server-side from the model's own feature store, not supplied by the client. | Must for ML release |
| ML-003 | The service shall return a risk score, risk band, model/version identifier, inference timestamp, and explanation or contributing factors where available. | Must for ML release |
| ML-004 | The web dashboards shall display ML risk results on relevant routes, incidents, alerts, and map segments. | Must for ML release |
| ML-005 | The Flutter app shall display ML-derived route warnings and recommendations to riders and officers through the active-trip, route-alert, and shipment workflows. | Must for ML release |
| ML-006 | ML recommendations shall be advisory and shall not silently change a rider's route or declare an emergency without an explicit operational rule and audit record. | Must for ML release |
| ML-007 | ML results shall be stored or linked to the route/segment/time context needed for audit, replay, and operational review. | Must for ML release |
| ML-008 | The system shall show when ML data is unavailable, stale, out of coverage, or below the configured confidence/quality threshold. | Must for ML release |
| ML-009 | Model versions, feature schemas, training data snapshots, evaluation results, and deployment approvals shall be versioned. | Must for ML release |
| ML-010 | The model shall be monitored for drift, calibration, regional transfer performance, false alarms, missed events, and data-quality failures. | Must for ML release |
| ML-011 | Until ML integration is implemented, existing rule-based, seeded, or manually configured alerts shall remain clearly distinguishable from live model predictions. | Must now |

**Current ML status:** The `sih-ml` repository contains data preparation, training, evaluation, optimization, and model artifacts, plus a batch-and-publish serving path (`sih_ml.serve.batch`, `sih_ml.serve.publish`) that copies daily scores into Supabase. Flutter and web clients read ML risk through the RPCs in §8.3, both verified in this integration to return the identical versioned prediction (model version, bundle hash, run id, risk counts) for the same route on the same day (SRS §12.2 #8). The model's rainfall-cell coverage is limited to roughly 87–90°E, 25.5–28.25°N (the Siliguri corridor, Sikkim, and North Bengal); routes outside that box report `no_coverage` and fall back to rule-based and reported alerts. No live rainfall feed exists yet (data ends 2025-12-31), so the connected system currently runs in `replay` mode only, clearly labelled as such in both clients; enabling `live` mode requires the operational rainfall adapter and recalibration described in `sih-ml/DEPLOYMENT.md` §9.

### 6.8 Web application requirements

| ID | Requirement | Priority |
|---|---|---|
| WEB-001 | The web system shall provide a login/account creation experience consistent with the shared role and Supabase account model. | Must |
| WEB-002 | The officer dashboard shall provide district, field, and control-room views appropriate to the authenticated role. | Must |
| WEB-003 | The dashboard shall provide map-based views of routes, incidents, fleet, shipments, risk zones, and live riders. | Must |
| WEB-004 | The dashboard shall provide shipment, incident, alert, and regional monitoring workflows. | Must |
| WEB-005 | The web application shall consume the same operational data and role policies as the Flutter app. | Must |
| WEB-006 | Web clients shall never use the Supabase service-role key. | Must |
| WEB-007 | The dashboard shall identify ML predictions separately from human reports, static rules, and external feeds once ML integration is connected. | Must for ML release |

## 7. Data Requirements

### 7.1 Core entities

The shared data model shall support at least:

- `profiles`
- `user_roles`
- `locations`
- `rider_profiles`
- `rider_locations`
- `rider_location_history`
- `shipments`
- `routes`
- `alerts`
- `road_incidents`
- Vehicles and fleet records
- Delivery assignments and proofs
- Activity/audit records
- ML predictions, model versions, and prediction explanations when ML is integrated

### 7.2 Data quality

- Required fields shall be validated at the client and server boundaries.
- Dates and timestamps shall be stored in an unambiguous timezone format, preferably UTC.
- GPS coordinates shall be validated for valid latitude/longitude ranges and expected regional bounds where applicable.
- Client-generated IDs shall make retries idempotent.
- Stale, superseded, and unavailable data shall be distinguishable from current data.
- Seed/demo data shall be clearly separated from production operational data.
- ML training labels, feature schemas, splits, metrics, and model artifacts shall be reproducible and versioned.

### 7.3 Retention

- Rider location history shall follow the configured operational retention policy; the current design specifies pruning after seven days.
- Incident, shipment, delivery proof, alert acknowledgement, and audit history retention shall be defined by the operating authority before production launch.
- Media retention, access, and deletion rules shall be documented before photo/signature proof is enabled in production.

## 8. External Interface Requirements

### 8.1 Supabase

- Supabase Auth shall provide email/password authentication and session management.
- PostgREST shall expose only approved schemas, tables, and functions.
- Security-definer RPCs shall validate the authenticated user and role.
- Realtime shall publish approved rider, shipment, alert, and incident changes.
- RLS shall be enabled for protected tables and tested per role.

### 8.2 Routing and GIS

- OSRM shall be consumed through configurable HTTP endpoints.
- GeoServer shall expose configured WMS layers and PostGIS-backed analytics.
- Local HTTP endpoints may be used only for explicitly configured development/LAN environments; production traffic shall use HTTPS.

### 8.3 ML inference service

**Implemented architecture (supersedes the original client-facing HTTP sketch below).**
The `sih-ml` model scores the entire corridor once per day as a batch job (`sih_ml.serve.batch`); it is not called per-request. A publisher (`sih_ml.serve.publish`) copies each published day into the shared Supabase/Postgres database, where PostGIS matches route geometry to scored segments. Flutter and web clients never call the `sih-ml` HTTP API directly; they call Supabase RPCs, which are `SECURITY DEFINER` and enforce RLS per role:

| RPC | Callers | Purpose |
|---|---|---|
| `ml_status()` | any active user | current run state (`live`/`replay`/`stale`/`unavailable`), model version, coverage bbox |
| `get_route_ml_risk(p_route_id \| p_geojson, p_date, p_buffer_m)` | riders (own assigned/planned routes), officers (any route) | risk along one route or line |
| `get_routes_ml_summary()` | officers | ML summary for every stored route |
| `get_my_routes_ml_risk()` | riders | ML summary for every route on the rider's open shipments |
| `get_ml_segments_in_bbox(...)` | officers | map layer of scored segments in view |
| `get_ml_top_alerts(p_tier, p_limit, p_district)` | officers | today's top-N highest-risk segments for their scope |
| `record_route_risk_snapshot(...)` | any active user | audit record of what was shown and the user's choice (ML-006/ML-007) |
| `promote_ml_alert(p_segment_id, p_run_id, p_note)` | control_room, district_officer | turns one ML segment into an operational `alerts` row (never automatic) |

Clients send a route id or a GeoJSON line and a date — never rainfall or terrain features, which live entirely in the model's own feature store. Example `get_route_ml_risk` response:

```json
{
  "state": "replay",
  "score_date": "2025-08-05",
  "model_version": "final_v3",
  "bundle_hash": "bf4ff57518c571e9",
  "run_id": 1,
  "route_length_m": 517636,
  "coverage_fraction": 0.5559,
  "summary": { "n_matched": 640, "n_alert": 44, "n_human_review": 131,
    "max_percentile": 99.9961, "band": "high", "worst": { "segment_id": "SEG247524",
    "along_m": 79488, "risk_percentile": 99.9961, "tier": "human_review", "steep": true } },
  "segments": [ ... ]
}
```

Schema, tables, RLS and the publisher contract are defined in `supabase/migrations/20260912000003_ml_integration.sql` and `sih-ml/src/sih_ml/serve/publish.py`. The full design, including the six deployment blockers found and resolved (missing Supabase project, out-of-coverage demo routes, no live rainfall feed, centroid-only geometry, alert volume, and a website/compose config mismatch), is recorded in `ML_INTEGRATION_PLAN.md` at the workspace root.

## 9. Non-Functional Requirements

### 9.1 Security

- All access shall be authenticated and authorized by role.
- RLS policies shall prevent riders from reading or modifying other riders' protected records.
- Officers shall have read access only to the operational scope assigned to their role.
- Service-role keys, database passwords, signing keys, and model-service credentials shall never be bundled into the Flutter APK or browser JavaScript.
- Sensitive data shall use HTTPS/TLS in production.
- Location, phone, delivery proof, and profile data shall be handled according to applicable privacy and organizational policy.
- Administrative and ML decisions shall be auditable.

### 9.2 Availability and resilience

- The app shall remain usable for configured offline workflows.
- Queued actions shall survive app restarts.
- Synchronization shall retry with bounded backoff and report failures.
- Realtime consumers shall have polling or refresh fallback.
- A service outage shall present a useful degraded state rather than silently showing live data as current.

### 9.3 Performance

- Auth and ordinary API requests should provide a visible result within 2 seconds under normal network conditions; requests shall time out rather than hang indefinitely.
- The mobile app shall avoid uploading duplicate or unnecessary GPS fixes.
- Officer map screens shall remain usable with the configured active rider and incident volumes.
- Batch location synchronization shall support up to the server-defined batch limit; the current RPC contract supports batches up to 500 and the mobile client sends smaller batches.
- ML inference latency and availability objectives shall be defined before production activation.

### 9.4 Usability and accessibility

- Critical rider actions shall be reachable from the active-trip context.
- Critical alerts shall use text, color, and iconography together rather than color alone.
- Forms shall provide clear validation, retry, and permission explanations.
- Layouts shall support common Android phone sizes and web desktop/tablet widths.
- Text shall remain readable in offline, loading, empty, error, and stale-data states.
- Operational terms and role labels shall be consistent across mobile and web.

### 9.5 Maintainability

- Flutter state shall remain separated into UI, Riverpod controller/provider, repository, and service layers.
- Web clients shall use shared Supabase types and role semantics where practical.
- Backend schema changes shall be delivered through migrations and tested with reset/push workflows.
- ML feature specifications, training configuration, evaluation reports, and model cards shall be version-controlled.
- Configuration for Supabase, OSRM, GeoServer, and ML endpoints shall be environment-specific and injected at build/deploy time.

### 9.6 Observability

The production system should provide:

- Auth failure and authorization metrics.
- API/RPC latency and error metrics.
- Realtime connection, reconnect, and polling-fallback metrics.
- Queue depth, retry count, and synchronization failure metrics.
- GPS permission, accuracy, and battery-impact metrics that respect privacy policy.
- Incident, alert, route, and delivery workflow audit events.
- ML inference latency, coverage, missing-feature, drift, calibration, and outcome metrics.

## 10. Offline and Synchronization Requirements

1. The client shall write accepted offline actions to durable local storage before attempting remote synchronization.
2. Every synchronizable action shall have an idempotency/client ID.
3. The client shall show queued, syncing, synced, and failed states.
4. The server shall reject malformed, unauthorized, duplicate, or out-of-order events safely.
5. Conflicts shall be resolved according to entity policy; server-authoritative assignment and role changes shall not be silently overwritten by an offline client.
6. When connectivity returns, the client shall retry automatically and provide a manual retry action.
7. The system shall retain enough metadata to explain why an action failed.

## 11. Security and Privacy Model

### 11.1 Role permissions

| Capability | Rider | Field Officer | District Officer | Control Room |
|---|---:|---:|---:|---:|
| View own profile/role | Yes | Yes | Yes | Yes |
| Update own rider duty/location state | Yes | No | No | No |
| View all rider live locations | No | Yes | Yes | Yes |
| View assigned shipment | Yes | Operational scope | District scope | Regional scope |
| Create own incident/report | Yes, configured types | Yes | Yes | Yes |
| Review/verify incidents | No | Yes | Yes | Yes |
| Manage regional alerts | No | Limited | District scope | Yes |
| View ML risk predictions | Relevant route | Yes | Yes | Yes |
| Change ML model/version | No | No | No | Authorized admin/service only |

The exact policy must be implemented and tested in Supabase RLS and RPC functions rather than enforced only in client UI.

### 11.2 Privacy

- Location sharing shall require user awareness and permission.
- The system shall collect only data necessary for the configured operational purpose.
- Phone, location, profile, and delivery-proof access shall be limited to authorized roles.
- Data export, retention, deletion, and incident access policies shall be defined by the deploying organization.

## 12. Testing and Acceptance Criteria

### 12.1 Required test levels

- Unit tests for domain models, role mapping, auth error mapping, location policy, queue behavior, and ML response parsing.
- Widget/component tests for login, account creation, rider dashboard, alert states, live-rider states, empty states, and error states.
- Repository/API tests for Supabase queries, RPC parameters, idempotency, RLS, and Realtime updates.
- Integration tests for sign-in, rider signup, start/stop sharing, queue flush, incident submission, proof submission, and officer live feed.
- GIS tests for route rendering, risk overlays, coordinate handling, and offline map mode.
- ML tests for schema validation, feature availability, response versioning, threshold behavior, fallback behavior, and model monitoring.
- Security tests for role isolation, leaked credentials, unauthorized RPC calls, and protected media/data access.
- End-to-end tests on representative Android devices and web browsers.

### 12.2 Minimum release acceptance

A release shall not be accepted until:

1. All supported roles can authenticate and are routed to the correct experience.
2. A rider can create an account, view assigned work, start/stop location sharing, and see queue/sync state.
3. An officer can view rider locations and staleness with Realtime or polling fallback.
4. Offline location and report actions survive restart and synchronize without duplicates.
5. RLS and role permissions pass positive and negative tests.
6. Routing and map failures produce understandable fallback states.
7. Android release builds contain no service-role or private ML credentials.
8. If ML is enabled for a release, the same versioned prediction is visible and traceable in both the Flutter app and web dashboards; otherwise the release must label ML integration as unavailable/not connected.

## 13. Deployment and Operations

### 13.1 Development

- Run the Supabase local stack from the web App Development project.
- Apply migrations and seed data using `supabase db reset`.
- Run Flutter with local emulator, LAN, or hosted Supabase `--dart-define` values.
- Run web clients with Vite development servers.
- Run OSRM and GeoServer through their documented Docker Compose projects when needed.
- Run ML pipeline tests and training commands from `sih-ml`.

### 13.2 Staging and production

- Use separate Supabase projects/environments for development, staging, and production.
- Apply migrations through reviewed deployment processes.
- Use HTTPS endpoints and managed secrets.
- Deploy the web applications with environment-specific Supabase configuration.
- Build signed Android artifacts with release signing keys held outside source control.
- Deploy the ML inference service separately from training jobs and require model/version approval before exposure to users.
- Monitor application, data, GIS, routing, and ML services independently.

## 14. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Poor network coverage | Missing live updates and delayed reports | Durable queues, retries, offline maps, clear stale state |
| GPS inaccuracy or battery drain | Incorrect rider position or device impact | Accuracy thresholds, throttling, heartbeat policy, foreground-service consent |
| Incorrect route/GIS data | Unsafe or inefficient operational decisions | Source/freshness indicators, manual verification, fallback routes, bounded region data |
| Unauthorized location/profile access | Privacy and safety incident | RLS, security-definer RPC checks, least privilege, audit testing |
| ML false positive | Unnecessary reroute or alert fatigue | Advisory wording, calibrated thresholds, human approval, feedback monitoring |
| ML false negative or drift | Missed disruption | Multiple data sources, fallback rule alerts, monitoring, retraining and review |
| Model not yet integrated | Requirements not operationally fulfilled | Track ML integration as a separate release milestone; do not label static alerts as live ML output |
| Duplicate offline submissions | Incorrect counts or repeated actions | Client IDs, server uniqueness, idempotent RPCs |
| Third-party service outage | Reduced mapping/routing capability | Baked route data, offline mode, public/local fallback, degraded-state UI |

## 15. Implementation Status Summary

| Area | Status |
|---|---|
| Flutter Android-first app | Implemented prototype and release APK buildable |
| Role model including rider | Implemented |
| Rider account creation fields | Implemented in Flutter UI and auth metadata flow |
| Supabase auth/profile/role flow | Implemented in client and migration design; requires running/deployed Supabase stack |
| Rider location sync and officer live feed | Implemented in Flutter/Supabase integration code; requires running backend for live verification |
| Mock rider deliveries/proofs/issues | Present for prototype workflows |
| Web dashboard UI | Present in React/Vite project |
| Web login/account UI | Present in React/Vite project |
| OSRM routing | Configurable/optional with fallback |
| GeoServer/PostGIS analytics | Configurable/optional local backend |
| ML training/evaluation pipeline | Present in `sih-ml` |
| ML batch scoring + Supabase publisher | Implemented (`sih_ml.serve.batch`, `sih_ml.serve.publish`); replay mode only, no live rainfall feed yet |
| ML connection to Flutter app | Implemented — `lib/features/ml/`, RPCs in `supabase/migrations/20260912000003_ml_integration.sql` |
| ML connection to web dashboards | Implemented — `src/lib/ml.ts`, `src/components/MlRisk.tsx` (NER-Website-Merged) |
| Production deployment and operations | To be completed per deployment environment |

## 16. Future Enhancements

- Connect the approved ML model to a protected inference API.
- Add model-driven alert creation with human review and audit history.
- Add model feedback capture from verified incidents and route outcomes.
- Add multilingual UI and operational terminology support.
- Add richer dispatch, warehouse, convoy, and inter-district planning.
- Add configurable delivery-proof policies by cargo type and authority.
- Add production notification channels and escalation policies.
- Add formal analytics dashboards for service levels, route reliability, and model performance.

## 17. Traceability to Existing Workspace

| SRS area | Primary workspace reference |
|---|---|
| Flutter app and roles | `ner_logistics/README.md`, `ner_logistics/lib/` |
| Rider workflow | `ner_logistics/RIDER_DASHBOARD_IMPLEMENTATION_PLAN.md`, `ner_logistics/lib/features/rider/` |
| Supabase schema and synchronization | `ner_logistics/SUPABASE_INTEGRATION.md`, `ner_logistics/lib/features/rider/data/`, `web/district,field,contro dashboards/App Development/supabase/` |
| Auth and rider signup | `ner_logistics/lib/features/auth/` |
| Officer live-rider view | `ner_logistics/lib/features/tracking/` |
| Routing and GIS | `ner_logistics/backend/README.md`, `ner_logistics/lib/services/`, `ner_logistics/lib/shared/map/` |
| ML data/training/evaluation | `sih-ml/README.md` and referenced reports/configuration |
| ML integration architecture and design | `ML_INTEGRATION_PLAN.md`, `sih-ml/src/sih_ml/serve/publish.py`, `sih-ml/tests/test_publish.py` |
| ML database schema, RLS, RPCs | `web/district,field,contro dashboards/App Development/supabase/migrations/20260912000003_ml_integration.sql`, `20260912000004_data_api_grants.sql` |
| ML in Flutter app | `ner_logistics/lib/features/ml/`, `ner_logistics/test/features/ml_test.dart` |
| ML in web dashboards | `web/NER-Website-Merged/src/lib/ml.ts`, `src/components/MlRisk.tsx` |
| Web dashboards | `web/district,field,contro dashboards/` |
| Login/account web project | `web/Login and Account Creation Screen/` |

---

## Approval

| Role | Name | Signature | Date |
|---|---|---|---|
| Business/Product Owner |  |  |  |
| Technical Lead |  |  |  |
| Operations Representative |  |  |  |
| Security/Data Protection Representative |  |  |  |
| ML/Data Science Lead |  |  |  |
