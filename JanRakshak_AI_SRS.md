# JanRakshak AI
## Software Requirements Specification (SRS)

**Document version:** 0.1 (draft for review)  
**Date:** 2026-09-19  
**Status:** Draft requirements baseline for the national expansion of the NER Logistics Platform  
**Project:** JanRakshak AI, covering all States and Union Territories of India; evolved from the NER Logistics Platform (MDoNER SIH26002)  
**Scope:** Flutter mobile application, web dashboards, authentication and account creation, shared Supabase backend, routing/GIS services, multi-region ML integration, multilingual notifications, and national multi-state administration

> **How this document relates to the NER SRS.** This SRS is derived from the *NER Logistics Platform SRS v1.0 (2026-09-12)*. JanRakshak AI generalises the platform from the North Eastern Region (NER) to every State and Union Territory of India. Requirement IDs from the NER SRS are kept wherever a requirement carries over, so the two documents can be traced against each other. The **Origin** column in each requirement table shows whether a requirement is **Inherited** (unchanged from the NER SRS), **Adapted** (an NER requirement generalised for national scale), or **New** (introduced by nationwide scope).
>
> **Status caution.** What exists today is the NER baseline: the Flutter prototype, Supabase-backed authentication and rider tracking, and the ML batch pipeline running in replay mode for a single corridor. Everything specific to nationwide operation (jurisdiction model, multi-region ML coverage, multilingual delivery, region onboarding, national dashboards) is a target requirement and is not yet implemented. Items marked **[TBC]** need a decision from the project owner or the sponsoring authority before this SRS is baselined; they are collected in §18.

---

## 1. Purpose

The JanRakshak AI platform shall support the planning, monitoring, reporting, and safe execution of logistics operations, and hazard-aware access to communities, across all States and Union Territories of India. The platform shall give riders, field officers, district officers, state officers, and control-room operators a shared operational view of shipments, vehicles, routes, hazards, incidents, alerts, and rider locations, organised by jurisdiction from district level up to the national level.

The system shall:

- Improve visibility of logistics activity across districts, States/UTs, and inter-state corridors.
- Help officers identify road, weather, flood, landslide, cyclone, infrastructure, and shipment risks that are specific to each region.
- Provide riders with assigned deliveries, active-trip tools, route alerts, issue reporting, delivery proof, and live location sharing.
- Continue essential field work during poor or unavailable connectivity, including hilly, coastal, forested, and border areas.
- Provide a shared source of truth through Supabase/Postgres/PostGIS, authentication, and Realtime events, with data access limited by jurisdiction.
- Provide an extension point through which validated, region-specific disruption-prediction models deliver risk scores and operational recommendations to the mobile and web clients, and state clearly where no validated model exists.
- Serve users, and deliver alerts, in their own language.
- Allow a new State or UT to be onboarded through configuration and data loading rather than code changes.

### 1.1 Relationship to the NER Logistics Platform

The NER Logistics Platform becomes the first region pack and the reference deployment of JanRakshak AI. All NER requirements remain valid for the NER region; JanRakshak AI generalises them as follows.

| Aspect | NER Logistics Platform (baseline) | JanRakshak AI (this SRS) |
|---|---|---|
| Geographic scope | North Eastern Region and connected corridors | All States and Union Territories and inter-state corridors; NER is the first region pack |
| Jurisdiction model | Districts within NER | Nation → Region → State/UT → District → Sub-district, with jurisdiction-scoped roles and RLS |
| Roles | `field_officer`, `district_officer`, `control_room`, `rider` | The same four roles plus `state_officer`, `state_admin`, and `national_admin`; the control-room role is scoped to a State, Region, or the nation |
| Hazards | Flood, landslide, road blockage, accident, infrastructure damage | Region-specific hazard catalogue that adds, for example, cyclone, urban waterlogging, snow/avalanche, fog, and earthquake damage |
| ML coverage | One validated area (Siliguri corridor, Sikkim, North Bengal), replay mode only | Per-region model coverage registry, regional validation gate, explicit `no_coverage` elsewhere |
| Language | English UI; multilingual support listed as a future enhancement | English and Hindi at national release; State languages added as each State/UT is onboarded |
| Alert delivery | In-app alerts; production notification channels listed as future | Push, email, and SMS fallback with targeting and escalation |
| Data feeds | Weather and road feeds; no live rainfall feed yet | Adapter framework with per-source provenance, freshness, and failure isolation |
| Hosting | Local and hosted Supabase environments | India-resident hosting, regional isolation, and disaster recovery |
| Onboarding | Fixed NER district set | Repeatable State/UT onboarding through region packs |

## 2. Product Scope

### 2.1 In scope

1. Flutter Android-first mobile application.
2. Role-based sign-in and account creation with jurisdiction-scoped roles.
3. Logistics Rider dashboard and rider workflows.
4. Field Officer, District Officer, State Officer, and Control Room workflows at State, Region, and national scope.
5. Shipment, fleet, route, incident, alert, district, State, and national monitoring, including inter-state shipments and corridors.
6. Interactive maps covering India with drill-down from national to district level.
7. OSRM routing and ETA services at national road-network scale.
8. GeoServer/PostGIS risk overlays and analytical views.
9. Supabase Auth, Postgres, PostGIS, RLS, RPCs, and Realtime, with jurisdiction-aware policies.
10. Offline queues and synchronization for rider location and field actions.
11. Background location tracking with user permission on supported platforms.
12. The ML training, evaluation, and model-artifact pipeline, extended to multiple regions and hazards.
13. ML inference integration used by the Flutter app and web dashboards, governed by a model coverage registry.
14. Multilingual user interface and multilingual notifications.
15. Notification dissemination (in-app, push, email, SMS fallback) with escalation.
16. State/UT and Region onboarding and administration.
17. External data-feed adapters (weather, hydrology, road status, official alerts).
18. National, State, and district analytics and reporting.

### 2.2 Out of scope for the initial national release

- Payment, billing, payroll, or financial settlement.
- Full warehouse inventory management.
- Automatic dispatch optimization across all vehicles.
- Guaranteed cellular coverage or satellite connectivity.
- ML predictions for any region without a validated model. Such regions use rule-based and reported alerts and display `no_coverage`.
- Autonomous route changes without the required operational approval.
- Replacement of government emergency, police, medical, or disaster-response systems, including national, State, and district disaster-management authorities.
- Public or citizen-facing applications **[TBC]**.
- An iOS application **[TBC]**.

## 3. System Context

The platform consists of the following cooperating products:

| Product | Users | Primary purpose | Current state |
|---|---|---|---|
| Flutter mobile app | Riders and officers in the field | Trips, reports, maps, location sharing, offline work | Implemented prototype (NER) with Supabase-backed auth and rider tracking; national features planned |
| District/field/state/control web dashboard | Field, District, and State Officers; Control Room Operators | Operations, incidents, shipments, fleet, alerts, and live riders at district, State, Region, and national scope | React/Vite UI with Supabase integration (NER); national views planned |
| Login and Account Creation web app | All supported account users | Sign-in and registration flow | React/Vite UI with Supabase integration (NER); jurisdiction selection and approval flow planned |
| Admin console | State and National Administrators | User provisioning, jurisdiction and region configuration, region onboarding | Planned |
| Supabase backend | All clients | Auth, relational data, security, RPCs, and Realtime | Local project configuration and migrations present (NER); jurisdiction-aware schema planned |
| OSRM service | Mobile and officer workflows | Routes, ETAs, turn guidance, and detours | Optional local service with public demo fallback (NER); national extract planned |
| GeoServer/PostGIS service | Officer analytics and maps | WMS overlays, risk zones, exposure views, spatial inspection | Optional local service with Docker Compose configuration (NER) |
| ML pipeline (`sih-ml`) and model registry | Data/ML operators; ML inference | Segment-level disruption prediction per validated region | Pipeline and batch/publish path present for one corridor (replay mode); multi-region registry planned |
| Feed adapter service | Platform and integration owners | Ingest weather, hydrology, road, and alert feeds with provenance | Planned |
| Notification service | All users | Push, email, and SMS delivery, escalation, and delivery tracking | Planned |

### 3.1 High-level architecture

```text
Flutter mobile app  ─┐
Web dashboards     ──┼── Supabase Auth / PostgREST / RPC / Realtime   (India-resident hosting)
Admin console      ──┘              │
                                    ├── PostgreSQL + PostGIS
                                    │     ├── Jurisdiction hierarchy and role scopes
                                    │     ├── Rider location, shipment, incident, alert data
                                    │     ├── Region packs (boundaries, roads, config)
                                    │     └── ML predictions and model coverage registry
                                    ├── Notification service ── push / email / SMS gateways
                                    ├── Feed adapters ───────── weather / hydrology / road / official alert feeds
                                    └── ML batch scoring and inference (per validated region)

Flutter and web clients ─── OSRM routing service (national extract, partitioned by region where needed)
Web/mobile map clients ──── GeoServer/PostGIS spatial layers
ML pipeline ─────────────── model artifacts, regional validation, coverage registry
```

### 3.2 Jurisdiction hierarchy

```text
Nation
 └── Region              (configurable grouping, e.g. North Eastern Region)
      └── State / Union Territory
           └── District
                └── Sub-district / Block   (optional)
```

Every user role, rider, shipment, route, incident, and alert is attached to one or more nodes of this hierarchy. Access, alert targeting, configuration, and reporting are all resolved against it.

## 4. Stakeholders and User Classes

| User class | Responsibilities | Main interfaces |
|---|---|---|
| Logistics Rider | Execute assigned deliveries, share location, report issues, submit proof | Flutter mobile app |
| Field Officer | Inspect field conditions, submit and verify incidents, monitor routes and shipments | Flutter app and web dashboard |
| District Officer | Review district conditions, shipments, alerts, route access, and rider activity | Flutter app and web dashboard |
| State Officer | Oversee logistics, incidents, alerts, and riders across a State/UT; coordinate districts | Web dashboard and Flutter app |
| Control Room Operator | Monitoring, escalation, fleet visibility, alerts, and coordination for a State, Region, or the nation according to assigned scope | Web dashboard and Flutter app |
| State Administrator | Provision users and roles within a State/UT, maintain State configuration, review access | Admin console |
| National Administrator | Manage Regions and onboarding, national configuration, and cross-State policy | Admin console |
| State/Regional Authority Representative | Own data and decisions for a jurisdiction; approve thresholds, alert policy, and retention | Dashboard and reports |
| Operations Manager | Define policies, workflows, KPIs, and response procedures | Web dashboard and reports |
| Data Provider / Integration Owner | Maintain external feeds and data-sharing agreements | Feed adapter administration |
| ML/Data Engineer | Build, validate, deploy, monitor, and retrain regional disruption models | `sih-ml`, model service, operational dashboards |
| Platform Administrator | Configure Supabase, routing, GIS, monitoring, backups, and deployment | Backend and infrastructure tools |
| Auditor / Security Reviewer | Review audit trails, access, and compliance | Audit logs and reports |

## 5. Assumptions and Constraints

- The operating area is India: all States and Union Territories and their inter-state corridors. NER remains the first, reference region.
- The platform requires internet access for live Supabase, Realtime, routing, GIS, and remote map tiles, but must preserve critical actions offline where specified. Connectivity varies widely, from dense urban coverage to no coverage in remote areas.
- A physical Android device connecting to a local development stack must use the host machine's LAN IP, and the local API must be reachable from that network.
- Local Supabase, OSRM, and GeoServer services require their documented runtimes, including Docker where applicable.
- Only a Supabase publishable/anonymous client key may be shipped in mobile or browser clients. Service-role credentials shall remain server-side.
- GPS accuracy, battery level, network availability, and third-party map/routing availability are variable.
- ML predictions are decision support, not an automatic declaration that a road is unsafe, and exist only inside the coverage of a validated regional model.
- Government data sources, weather feeds, road feeds, and labels may have delays, gaps, or inconsistent quality, and their format, quality, and update cadence differ from State to State.
- Each State/UT authority owns operational decisions and data for its jurisdiction. Policies such as retention, proof requirements, and escalation may differ between States.
- Data and services are hosted on India-resident infrastructure. The hosting provider is **[TBC]**.
- Users work in many languages and scripts, and many riders use low-to-mid-range Android devices on limited bandwidth.
- States/UTs are enabled in phases. The platform shall not assume that every region is live at the same time or has the same data quality.
- Administrative boundaries and place names follow official Government of India sources.

## 6. Functional Requirements

### 6.1 Identity, authentication, and authorization

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| AUTH-001 | The system shall support email/password sign-in through Supabase Auth. | Must | Inherited |
| AUTH-002 | The system shall support the roles `rider`, `field_officer`, `district_officer`, `state_officer`, `control_room`, `state_admin`, and `national_admin`. Every role assignment shall carry a jurisdiction scope (§6.2). | Must | Adapted |
| AUTH-003 | The system shall load the authoritative role from the database after authentication; a UI-selected role shall not override the database role. | Must | Inherited |
| AUTH-004 | The system shall support account creation with full name, official email, State/UT and district (selected from the jurisdiction registry), password, and requested role. | Must | Adapted |
| AUTH-005 | Rider account creation shall accept a phone number and optional vehicle registration and shall send them as account metadata for rider profile creation. | Must | Inherited |
| AUTH-006 | The database trigger shall create the appropriate profile and active role record, including its jurisdiction, after approved account creation. Rider accounts shall receive a rider profile. Officer and administrator role requests shall remain pending until approved by an administrator with authority over the requested jurisdiction. | Must | Adapted |
| AUTH-007 | The system shall reject inactive users and users without an active operational role with a safe user-facing message. | Must | Inherited |
| AUTH-008 | The system shall persist sessions, refresh tokens, and PKCE state using the Supabase client facilities. | Must | Inherited |
| AUTH-009 | The system shall provide sign-out and clear local session state even when the remote sign-out request fails. | Must | Inherited |
| AUTH-010 | The system shall prevent riders from being routed into officer dashboards and shall route each authenticated role to its permitted experience, including the State and national views. | Must | Adapted |
| AUTH-011 | Passwords shall never be stored by the client application or written to application logs. | Must | Inherited |
| AUTH-012 | The system shall support multi-factor authentication for officer and administrator roles. The method is **[TBC]**. | Should | New |
| AUTH-013 | The system shall support phone-number OTP sign-in for riders as an alternative to email/password **[TBC]**. | Should | New |
| AUTH-014 | The system shall support federation with government identity providers (OIDC/SAML single sign-on) where the deploying authority requires it. The database role shall remain authoritative. | Could | New |
| AUTH-015 | Role changes, jurisdiction changes, and deactivations shall be audited, shall take effect within a bounded time, and shall revoke active sessions where required. | Must | New |
| AUTH-016 | The system shall throttle or lock out repeated failed sign-in attempts and account-creation abuse. | Must | New |

### 6.2 Jurisdiction and multi-state administration

This section is new for JanRakshak AI. It provides the model that lets one platform serve many States/UTs safely.

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| JUR-001 | The system shall model a jurisdiction hierarchy of Nation → Region (configurable grouping, e.g. NER) → State/UT → District → optional Sub-district/Block. | Must | New |
| JUR-002 | The system shall use official Local Government Directory (LGD) codes as canonical identifiers for States/UTs, districts, and sub-districts where available, and shall keep a mapping from legacy names and spellings. | Should | New |
| JUR-003 | Every role assignment, rider, shipment, route, incident, alert, and asset shall be associated with at least one jurisdiction, and RLS shall enforce jurisdiction scope in the database rather than in client code. | Must | New |
| JUR-004 | Inter-state shipments and routes shall be visible to officers of each State the route traverses, limited to the segments and data needed for that State's operations, and hand-off events at State boundaries shall be recorded. | Must | New |
| JUR-005 | Each State/UT shall be able to configure default languages, alert thresholds, retention within national limits, delivery-proof policy, escalation contacts, enabled hazards, and enabled feeds without a code change. | Must | New |
| JUR-006 | The system shall provide a region-onboarding workflow that loads boundaries, road network, and points of interest, configures hazards, feeds, and languages, provisions an administrator, and validates data quality before the region is enabled. | Must | New |
| JUR-007 | A region shall not be marked production-enabled until it passes the region-onboarding checklist in §13.3. | Must | New |
| JUR-008 | Displayed administrative boundaries shall conform to the official boundaries of India as notified by the Government of India (Survey of India), and boundary datasets shall be versioned. | Must | New |
| JUR-009 | A region shall be suspendable or disableable without affecting other regions. | Should | New |
| JUR-010 | State administrators shall manage users only within their own jurisdiction; national administrators shall manage users across all jurisdictions. Both shall be audited. | Must | New |

### 6.3 Rider account and rider dashboard

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| RIDER-001 | A rider shall be able to view identity, phone, district, vehicle, duty state, and assigned shipment context. | Must | Inherited |
| RIDER-002 | A rider shall be able to view assigned deliveries including origin, destination, cargo, risk, time window, ETA, route, and status. | Must | Inherited |
| RIDER-003 | The system shall support assignment states including pending, accepted, rejected, expired, assigned, en route, paused, rerouting, arrived, completed, failed, and cancelled. | Must | Inherited |
| RIDER-004 | Where policy allows, a rider shall accept an assignment and the decision shall be recorded with an idempotent identifier. | Must | Inherited |
| RIDER-005 | A rider shall be able to start, pause, resume, and complete a trip according to required delivery and proof rules. | Must | Inherited |
| RIDER-006 | The active-trip view shall display route, current position when available, next instruction, ETA, progress, route risk, and operational alerts. | Must | Inherited |
| RIDER-007 | A rider shall be able to report road, weather, vehicle, safety, delivery, and emergency issues with severity, location, time, description, and optional media. Issue types shall include the hazards enabled for the rider's region. | Must | Adapted |
| RIDER-008 | A rider shall be able to submit configured delivery proof such as OTP, signature, photo, QR code, or geotag. The required proof types shall follow the State/UT policy. | Must | Adapted |
| RIDER-009 | The system shall provide SOS/emergency assistance from active-trip workflows and include the latest known rider, vehicle, shipment, and position context. | Must | Inherited |
| RIDER-010 | The rider dashboard shall display offline status, last synchronization time, queued actions, retry state, and sync errors. | Must | Inherited |
| RIDER-011 | The rider shall be able to download and refresh supported offline map regions (per State or corridor) before leaving network coverage, with the download size shown before the download starts. | Should | Adapted |
| RIDER-012 | Rider navigation shall remain focused on delivery execution and shall not expose unrelated district, State, or control-room analytics. | Must | Inherited |
| RIDER-013 | Rider flows shall be available in the rider's selected language (§6.9) and shall use clear icons for critical actions so they remain usable with limited literacy. | Must | New |
| RIDER-014 | For inter-state trips the app shall notify the rider when crossing a State boundary and show advisories that apply to the State being entered. | Should | New |
| RIDER-015 | When no data connection is available, the SOS flow shall offer an SMS fallback to configured control-room numbers containing the latest known position and shipment reference. | Should | New |
| RIDER-016 | The system shall support configurable vehicle categories (for example two-wheeler, light goods vehicle, truck) with a routing profile for each. | Should | New |

### 6.4 Location tracking and live rider monitoring

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| LOC-001 | A rider shall explicitly start and stop live location sharing; sign-out shall stop sharing. | Must | Inherited |
| LOC-002 | The app shall request and explain the location permissions required for foreground and background tracking. | Must | Inherited |
| LOC-003 | The location policy shall filter duplicate/stationary fixes, enforce movement/time thresholds, reject poor accuracy fixes, and emit periodic heartbeats. | Must | Inherited |
| LOC-004 | Location points shall contain a client ID, latitude, longitude, recorded device time, accuracy, speed, heading, and optional shipment ID. | Must | Inherited |
| LOC-005 | Location points shall be persisted locally before upload so temporary network loss does not silently discard accepted fixes. | Must | Inherited |
| LOC-006 | The client shall upload locations in batches, retry failures with bounded exponential backoff, and de-duplicate retries server-side. | Must | Inherited |
| LOC-007 | The system shall store the latest rider fix and an append-only location history. The default retention is seven days (as in the NER design); each State/UT may configure a different period within national policy limits. | Must | Adapted |
| LOC-008 | The officer live-rider view shall show riders, duty state, last seen age, movement, accuracy, shipment, route, risk, and staleness. | Must | Inherited |
| LOC-009 | Officer maps shall show live rider positions with heading when available and distinguish stale or high-risk riders visually. | Must | Inherited |
| LOC-010 | The officer live-rider feed shall use Supabase Realtime and fall back to periodic polling when Realtime is unavailable. | Must | Inherited |
| LOC-011 | The system shall ignore out-of-order location fixes and shall refresh joined shipment/rider data when an unknown or changed relationship is detected. | Must | Inherited |
| LOC-012 | Rider location access shall be protected by RLS: riders may access their own records, and authorized officers may read operational rider data only within their jurisdiction scope. | Must | Adapted |
| LOC-013 | Location ingestion and history storage shall be partitioned (by time and region) so ingestion, pruning, and queries remain performant as rider volume grows. | Must | New |
| LOC-014 | A State officer shall see riders of their State plus riders of other States who are on a shared inter-state route with that State (JUR-004), and no others. | Must | New |
| LOC-015 | The reporting interval shall adapt to connectivity and battery conditions within configured bounds, without losing safety-relevant events. | Should | New |

### 6.5 Shipments, fleet, and logistics operations

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| OPS-001 | Officers shall view active shipments with shipment ID, vehicle, cargo type, origin, destination, location, ETA, status, and risk. | Must | Inherited |
| OPS-002 | The system shall support shipment statuses including in transit, delayed, on schedule, and configured operational states. | Must | Inherited |
| OPS-003 | Officers shall view fleet vehicles, route assignments, destination, movement/status, ETA, and risk. | Must | Inherited |
| OPS-004 | A shipment may be associated with a rider and vehicle, and that association shall be visible to authorized users. | Must | Inherited |
| OPS-005 | Delays, blocked routes, reroutes, and critical shipment risks shall be visible in operational dashboards at district, State, Region, and national scope. | Must | Adapted |
| OPS-006 | The system shall retain an activity history for material assignment, route, incident, alert, proof, and status changes. | Should | Inherited |
| OPS-007 | The system shall support inter-state shipments whose origin, destination, and route span more than one State/UT, and shall show them to each State whose territory they cross (JUR-004). | Must | New |
| OPS-008 | Shipments shall carry a configurable cargo priority class (for example essential goods, medical supplies, relief material, general) **[TBC classes]**, and dashboards shall let officers filter and prioritise by class. | Should | New |
| OPS-009 | The system shall record hand-off events when a shipment crosses a State boundary or changes custody. | Should | New |
| OPS-010 | The system shall support named logistics corridors (for example a highway stretch) with an aggregated status, so officers can monitor a corridor rather than individual segments. | Should | New |

### 6.6 Incidents, alerts, and field reporting

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| INC-001 | Authorized users shall report incidents including flood, landslide, road blockage, accident, infrastructure damage, and other hazards, drawn from the region's hazard catalogue (INC-009). | Must | Adapted |
| INC-002 | Incident reports shall include type, location, route, severity, reporter, timestamp, verification state, status, and optional evidence. | Must | Inherited |
| INC-003 | Officers shall view and filter alerts by critical, high, moderate, and informational severity. | Must | Inherited |
| INC-004 | Alerts shall show description, distance/context, recommended action, time, and related incident when available. | Must | Inherited |
| INC-005 | Authorized users shall acknowledge alerts, and the acknowledgement state shall be visible to the appropriate operational audience. | Must | Inherited |
| INC-006 | The system shall support verification, assignment, escalation, and resolution states for incidents. | Should | Inherited |
| INC-007 | Offline reports shall be queued locally and synchronized when connectivity returns without duplicate creation. | Must | Inherited |
| INC-008 | Critical alerts shall be prioritized over informational content and shall remain usable on small mobile screens. | Must | Inherited |
| INC-009 | Hazard types shall come from a configurable catalogue with region-specific entries (for example cyclone, urban waterlogging, snow/avalanche, fog, earthquake damage), enabled per State/UT. | Must | New |
| INC-010 | External colour-coded or level-coded warnings shall be mapped to platform severity levels through a documented, versioned mapping. | Must | New |
| INC-011 | The system shall import and export alerts in Common Alerting Protocol (CAP) format where authorised systems require it. | Should | New |
| INC-012 | The system shall detect and offer merging of duplicate or near-duplicate incident reports from different reporters. | Should | New |
| INC-013 | Alerts shall be targetable by jurisdiction, route, geofence, role, and shipment so users only receive alerts relevant to them. | Must | New |
| INC-014 | The system shall support escalation from district to State to national level when severity, duration, or multi-State impact crosses configured thresholds. | Should | New |

### 6.7 Maps, routing, and GIS

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| GIS-001 | The system shall provide interactive maps covering India, with drill-down from national to State, district, and route level, showing routes, vehicles, incidents, points of interest, risk zones, and rider positions. | Must | Adapted |
| GIS-002 | The map shall support street and terrain presentation where configured. | Should | Inherited |
| GIS-003 | The routing service shall provide route geometry, ETA, turn instructions, and detour/closure impact where available. | Must | Inherited |
| GIS-004 | OSRM shall be configurable through build/runtime settings, and the national road network shall be served from a national extract, partitioned by region where needed for performance. A public-demo fallback shall be documented for non-production demos only. | Must | Adapted |
| GIS-005 | GeoServer/PostGIS shall provide WMS risk overlays and spatial analytics including highway exposure, convoy exposure, incident summaries, and hazards along a route. | Should | Inherited |
| GIS-006 | Users shall be able to inspect supported map locations and related spatial information through configured long-press/tap interactions. | Should | Inherited |
| GIS-007 | Offline map mode shall provide downloaded map coverage and local route overlays without requiring live tile requests. | Should | Inherited |
| GIS-008 | Routing and hazard information shall display freshness/source state where operationally important. | Should | Inherited |
| GIS-009 | Routing shall support vehicle-category profiles (RIDER-016) and, where data exists, vehicle-class constraints such as bridge load or height limits. | Should | New |
| GIS-010 | Each region's road network, boundaries, bridges, and points of interest shall be loaded and updated as versioned region packs, and the pack version in use shall be visible to administrators. | Must | New |
| GIS-011 | Production map tiles shall come from a self-hosted or licensed tile source and shall not depend on public community tile servers whose usage policies do not allow production-scale use. | Must | New |
| GIS-012 | Road closures and restrictions recorded in the system shall be applied to routing (avoid or penalise) for the affected region, and shall expire or be reviewed on a configured schedule. | Should | New |

### 6.8 ML integration (multi-region)

In the NER baseline the ML model is maintained in the separate `sih-ml` project. It predicts road-segment/day disruption risk, especially rainfall-triggered landslide and flood disruption, and supports risk-aware routing. JanRakshak AI keeps that architecture and extends it so that any number of validated regional models can be connected, each declaring where and for what it is valid.

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| ML-001 | The platform shall connect each validated ML model to the shared logistics system through a server-side inference service or protected Supabase-compatible API. | Must for ML release | Adapted |
| ML-002 | The ML inference service shall accept a road segment or route context and a date. Environmental/operational features shall be resolved server-side from the model's own feature store, not supplied by the client. | Must for ML release | Inherited |
| ML-003 | The service shall return a risk score, risk band, model/version identifier, inference timestamp, and explanation or contributing factors where available. | Must for ML release | Inherited |
| ML-004 | The web dashboards shall display ML risk results on relevant routes, incidents, alerts, and map segments. | Must for ML release | Inherited |
| ML-005 | The Flutter app shall display ML-derived route warnings and recommendations to riders and officers through the active-trip, route-alert, and shipment workflows. | Must for ML release | Inherited |
| ML-006 | ML recommendations shall be advisory and shall not silently change a rider's route or declare an emergency without an explicit operational rule and audit record. | Must for ML release | Inherited |
| ML-007 | ML results shall be stored or linked to the route/segment/time context needed for audit, replay, and operational review. | Must for ML release | Inherited |
| ML-008 | The system shall show when ML data is unavailable, stale, out of coverage, or below the configured confidence/quality threshold. | Must for ML release | Inherited |
| ML-009 | Model versions, feature schemas, training data snapshots, evaluation results, and deployment approvals shall be versioned. | Must for ML release | Inherited |
| ML-010 | The model shall be monitored for drift, calibration, regional transfer performance, false alarms, missed events, and data-quality failures. | Must for ML release | Inherited |
| ML-011 | Until ML integration is implemented for a region, existing rule-based, seeded, or manually configured alerts shall remain clearly distinguishable from live model predictions. | Must now | Adapted |
| ML-012 | The platform shall keep a model coverage registry in which each model version declares its geographic coverage, hazards, valid date range, and feature schema, and `ml_status()` shall expose coverage per region. | Must for ML release | New |
| ML-013 | A route that is partly or wholly outside model coverage shall report the covered fraction and `no_coverage` for the uncovered portion, and clients shall show which parts of the route are covered. | Must for ML release | New |
| ML-014 | A model shall not be enabled for a region until it passes a regional validation gate covering transfer performance, calibration, false alarms, and missed events, signed off by the ML lead and the region's authority. | Must for ML release | New |
| ML-015 | The platform shall support hazard-specific models (for example landslide, flood, cyclone-related disruption) with independent versioning, and risk shall be displayed per hazard. | Should | New |
| ML-016 | A region shall run in `live` mode only when its operational data adapters are in place and the model has been recalibrated for live inputs. Until then it shall run in `replay` or `unavailable` mode, labelled as such in every client. | Must for ML release | New |
| ML-017 | Batch scoring shall scale to all enabled regions, with a schedule, failure alerting, and stale-run detection per region. | Must for ML release | New |
| ML-018 | Alert volume shall be controlled per region through tuned thresholds and top-N limits per jurisdiction, so scoring does not flood officers with alerts. | Should | New |
| ML-019 | Verified incidents and route outcomes shall be captured as labelled feedback per region for retraining and evaluation. | Should | New |
| ML-020 | Recommended actions and explanations shall be available in the user's selected language. | Could | New |

**Inherited ML baseline (NER).** The `sih-ml` repository contains data preparation, training, evaluation, optimization, and model artifacts, plus a batch-and-publish serving path (`sih_ml.serve.batch`, `sih_ml.serve.publish`) that copies daily scores into Supabase. Flutter and web clients read ML risk through the RPCs in §8.3, and both were verified to return the identical versioned prediction (model version, bundle hash, run id, risk counts) for the same route on the same day. The model's rainfall-cell coverage is limited to roughly 87–90°E, 25.5–28.25°N (the Siliguri corridor, Sikkim, and North Bengal); routes outside that box report `no_coverage` and fall back to rule-based and reported alerts. No live rainfall feed exists yet (data ends 2025-12-31), so the connected system currently runs in `replay` mode only, clearly labelled in both clients; enabling `live` mode requires the operational rainfall adapter and recalibration described in `sih-ml/DEPLOYMENT.md` §9.

**Consequence for JanRakshak AI.** At baseline, every State/UT outside that coverage box reports `no_coverage`. National ML coverage is therefore delivered region by region through ML-012 to ML-016, and no region shall be described as ML-covered before it passes the regional validation gate.

### 6.9 Multilingual support and localisation

The NER SRS listed multilingual support as a future enhancement. For a national platform it is a core requirement.

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| I18N-001 | The user interface shall be available in English and Hindi at national release, and in additional scheduled languages as each State/UT is onboarded. | Must | New |
| I18N-002 | Each State/UT configuration shall declare its official and operational languages; users shall select a preferred language, defaulting to their State's primary language. | Must | New |
| I18N-003 | All text handling shall be Unicode (UTF-8) end to end, with fonts and layouts that render Indian scripts correctly and tolerate text expansion. | Must | New |
| I18N-004 | The interface shall support right-to-left rendering for languages such as Urdu. | Should | New |
| I18N-005 | Templates for critical alerts and recommended actions shall be human-reviewed in each enabled language. Machine translation may be used for non-critical content and shall be labelled as such. | Must | New |
| I18N-006 | Notifications shall be delivered in the recipient's language with an English fallback. | Must | New |
| I18N-007 | Place search shall work across scripts and alternate spellings and transliterations. | Should | New |
| I18N-008 | Dates and times shall be stored in UTC and displayed in IST by default, with locale-aware formatting. | Must | New |
| I18N-009 | Rider flows shall be icon-first for critical actions, with optional voice prompts for low-literacy users. | Should | New |
| I18N-010 | Translation resources shall be versioned, and a missing translation shall fall back to English without breaking the screen. | Must | New |

Candidate national language-translation services (for example Bhashini) shall be evaluated for non-critical content **[TBC]**.

### 6.10 Notifications and alert dissemination

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| NOT-001 | The system shall deliver alerts in-app and by push notification, and by email; SMS shall be available as a fallback for critical alerts. | Must (in-app, push); Should (email, SMS) | New |
| NOT-002 | Unacknowledged critical alerts shall escalate to the next role or jurisdiction after a configurable timeout. | Must | New |
| NOT-003 | Notifications shall be targetable by jurisdiction, route, geofence, role, and shipment (INC-013). | Must | New |
| NOT-004 | Delivery status (sent, delivered, acknowledged, failed) shall be tracked and auditable. | Should | New |
| NOT-005 | Where SMS is enabled, sender and template registration required by applicable telecom regulation (for example TRAI DLT) shall be completed in each language before go-live. | Must if SMS enabled | New |
| NOT-006 | Deduplication and rate limits shall prevent alert fatigue, and critical alerts shall be exempt from suppression. | Must | New |
| NOT-007 | Notification providers shall be pluggable per State or deployment. | Should | New |
| NOT-008 | The system shall be able to receive and forward CAP alerts with authorised external alerting systems (INC-011). | Could | New |

### 6.11 Integrations and data feeds

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| INT-001 | The system shall provide a feed-adapter framework in which each external feed declares its source, licence, schedule, freshness target, field mapping, fallback, and health status. | Must | New |
| INT-002 | Adapters shall be built for the weather, hydrology, hazard, road-status, and official-alert feeds that each region needs. Candidate sources (availability, licence, and API access **[TBC]**) include the India Meteorological Department (weather warnings, rainfall), the Central Water Commission (river and flood status), ISRO's Bhuvan and MOSDAC (terrain and satellite products), the Geological Survey of India (landslide susceptibility), NDMA and State disaster-management authorities (official alerts), road agencies such as NHAI, MoRTH, and State PWDs (road and bridge status), and satellite rainfall products. | Should | New |
| INT-003 | Every ingested item shall carry its source, fetch time, and validity time, and these shall be shown to users where operationally important (GIS-008). | Must | New |
| INT-004 | A feed outage in one region or source shall not affect other regions or sources, and the degraded state shall be visible to users and administrators. | Must | New |
| INT-005 | The platform shall expose versioned REST APIs (with OpenAPI documentation), scoped API credentials, and rate limits for authorised State and national systems. | Should | New |
| INT-006 | Data exchange shall use standard formats such as GeoJSON, CAP, CSV, and JSON. | Should | New |
| INT-007 | Authoritative datasets (boundaries, road networks, shapefiles) shall be imported through validated, repeatable pipelines that check geometry, coordinate range, and schema. | Must | New |
| INT-008 | The system shall be able to export or hand off incident data to State emergency-response systems (for example the emergency response support system reached via 112) without replacing them. | Could | New |

### 6.12 Web application requirements

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| WEB-001 | The web system shall provide a login/account creation experience consistent with the shared role and Supabase account model. | Must | Inherited |
| WEB-002 | The dashboard shall provide district, field, State, control-room, and national views appropriate to the authenticated role and jurisdiction. | Must | Adapted |
| WEB-003 | The dashboard shall provide map-based views of routes, incidents, fleet, shipments, risk zones, and live riders. | Must | Inherited |
| WEB-004 | The dashboard shall provide shipment, incident, alert, and regional monitoring workflows. | Must | Inherited |
| WEB-005 | The web application shall consume the same operational data and role policies as the Flutter app. | Must | Inherited |
| WEB-006 | Web clients shall never use the Supabase service-role key. | Must | Inherited |
| WEB-007 | The dashboard shall identify ML predictions separately from human reports, static rules, and external feeds once ML integration is connected. | Must for ML release | Inherited |
| WEB-008 | The dashboard shall provide a national overview with State-level status, inter-state corridors, and drill-down to district and route level. | Must | New |
| WEB-009 | The dashboard shall let authorised users compare States/UTs on agreed indicators (RPT-001). | Should | New |
| WEB-010 | Web interfaces shall meet WCAG 2.1 AA and the Guidelines for Indian Government Websites (GIGW) where the deploying authority requires it. | Should | New |
| WEB-011 | Map views shall remain responsive at national scale through clustering, tiling, and level-of-detail rendering. | Must | New |
| WEB-012 | The web application shall provide language selection consistent with §6.9. | Must | New |
| WEB-013 | The admin console shall provide user, role, jurisdiction, region-pack, hazard, feed, and language configuration, all audited. | Must | New |

### 6.13 Reporting and analytics

| ID | Requirement | Priority | Origin |
|---|---|---|---|
| RPT-001 | The system shall provide a KPI catalogue at district, State, Region, and national level, including district connectivity index, blocked-road hours, on-time delivery rate, alert acknowledgement time, incident resolution time, and ML alert precision against verified incidents. | Should | New |
| RPT-002 | Authorised users shall be able to export reports (CSV/PDF), scoped to their jurisdiction, with each export audited. | Should | New |
| RPT-003 | The system shall support scheduled periodic reports. | Could | New |
| RPT-004 | National and cross-State views shall use aggregated data and shall not expose rider-level personal data to roles without that authority. | Must | New |

## 7. Data Requirements

### 7.1 Core entities

The shared data model shall support at least the NER entities and the national additions below. Names are indicative.

**Inherited from NER:**

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
- ML predictions, model versions, and prediction explanations

**New for JanRakshak AI:**

- `jurisdictions` (hierarchy with LGD codes and boundary versions) and `user_jurisdiction_scopes`
- `regions` and `region_config` (languages, thresholds, retention, proof policy, enabled hazards and feeds)
- `region_packs` (versioned boundaries, road networks, points of interest, terrain)
- `hazard_types` (region-enabled hazard catalogue)
- `corridors` and `handoff_events`
- `data_sources` and `feed_runs` (provenance and health of external feeds)
- `ml_models` and `ml_coverage_regions` (model coverage registry)
- `translations` (versioned language resources and reviewed alert templates)
- `notifications` and `notification_deliveries`
- `api_clients` (scoped credentials for external systems)

### 7.2 Data quality

- Required fields shall be validated at the client and server boundaries.
- Dates and timestamps shall be stored in an unambiguous timezone format, preferably UTC.
- GPS coordinates shall be validated for valid latitude/longitude ranges and, where applicable, against the bounds of the region concerned as well as the bounds of India.
- Client-generated IDs shall make retries idempotent.
- Stale, superseded, and unavailable data shall be distinguishable from current data.
- Seed/demo data shall be clearly separated from production operational data.
- ML training labels, feature schemas, splits, metrics, and model artifacts shall be reproducible and versioned.
- Jurisdiction and boundary datasets shall be versioned, and changes to administrative units (for example a new or renamed district) shall be handled through mapping, not by overwriting history.
- Each region's data-quality status (completeness, freshness, validation results) shall be recorded at onboarding and monitored afterwards.

### 7.3 Retention

- Rider location history shall follow the configured operational retention policy; the inherited design specifies pruning after seven days, and States/UTs may configure a different period within national limits.
- Incident, shipment, delivery proof, alert acknowledgement, and audit history retention shall be defined by the operating authority before production launch **[TBC]**.
- Media retention, access, and deletion rules shall be documented before photo/signature proof is enabled in production.
- Audit and security logs shall be retained for the period required by applicable Indian directions (see §11.3).

### 7.4 Data residency and ownership

- All personal and operational data, including backups, shall be stored and processed in India unless the owning authority explicitly approves otherwise.
- Third-party map, routing, notification, and analytics providers shall receive only the data needed for their function and shall not receive personal data unnecessarily.
- Each State/UT authority owns the operational data of its jurisdiction. Rules for sharing data between States and with national users shall be agreed and configured, not assumed **[TBC]**.
- The platform shall not collect or store Aadhaar numbers unless a legal basis exists and the deploying authority approves.

## 8. External Interface Requirements

### 8.1 Supabase

- Supabase Auth shall provide email/password authentication and session management.
- PostgREST shall expose only approved schemas, tables, and functions.
- Security-definer RPCs shall validate the authenticated user, role, and jurisdiction scope.
- Realtime shall publish approved rider, shipment, alert, and incident changes, filtered by jurisdiction.
- RLS shall be enabled for protected tables and tested per role and per jurisdiction.
- The backend shall be deployable on India-resident infrastructure, whether managed or self-hosted **[TBC]**.

### 8.2 Routing and GIS

- OSRM shall be consumed through configurable HTTP endpoints.
- GeoServer shall expose configured WMS layers and PostGIS-backed analytics.
- Local HTTP endpoints may be used only for explicitly configured development/LAN environments; production traffic shall use HTTPS.
- Public demo routing and tile endpoints shall not be used in production (GIS-004, GIS-011).

### 8.3 ML inference service

**Inherited architecture (NER baseline).** The `sih-ml` model scores its corridor once per day as a batch job (`sih_ml.serve.batch`); it is not called per request. A publisher (`sih_ml.serve.publish`) copies each published day into the shared Supabase/Postgres database, where PostGIS matches route geometry to scored segments. Flutter and web clients never call the `sih-ml` HTTP API directly; they call Supabase RPCs, which are `SECURITY DEFINER` and enforce RLS per role. JanRakshak AI retains this architecture.

| RPC | Callers | Purpose |
|---|---|---|
| `ml_status()` | any active user | current run state (`live`/`replay`/`stale`/`unavailable`), model version, coverage bbox |
| `get_route_ml_risk(p_route_id \| p_geojson, p_date, p_buffer_m)` | riders (own assigned/planned routes), officers (any route in scope) | risk along one route or line |
| `get_routes_ml_summary()` | officers | ML summary for every stored route in scope |
| `get_my_routes_ml_risk()` | riders | ML summary for every route on the rider's open shipments |
| `get_ml_segments_in_bbox(...)` | officers | map layer of scored segments in view |
| `get_ml_top_alerts(p_tier, p_limit, p_district)` | officers | today's top-N highest-risk segments for their scope |
| `record_route_risk_snapshot(...)` | any active user | audit record of what was shown and the user's choice (ML-006/ML-007) |
| `promote_ml_alert(p_segment_id, p_run_id, p_note)` | control_room, district_officer | turns one ML segment into an operational `alerts` row (never automatic) |

**Planned extensions for JanRakshak AI:**

- `ml_status()` shall return per-region state and coverage from the model coverage registry (ML-012), and a new coverage query shall list which regions and hazards each model version covers.
- RPCs that take a district shall also accept a State or jurisdiction scope, and shall filter results by the caller's jurisdiction (JUR-003).
- `promote_ml_alert` shall also be callable by `state_officer` within that officer's State.
- Responses shall continue to carry the covered fraction, model version, run identifier, and mode so clients can label results correctly (ML-008, ML-013, ML-016).

Clients send a route id or a GeoJSON line and a date, never rainfall, terrain, or other model features, which live entirely in each model's own feature store.

### 8.4 External data feeds

External weather, hydrology, hazard, road, and alert feeds shall be reached only through the feed-adapter framework (INT-001). Each feed shall have a documented interface, credentials handled as server-side secrets, and a defined fallback.

### 8.5 Notification gateways

Push, email, and SMS gateways shall be reached through the notification service (§6.10) with credentials held server-side. SMS senders and templates shall be registered as required by the applicable regulation.

### 8.6 Identity providers

Where required, external identity providers shall be integrated by standard protocols (OIDC/SAML). The Supabase-held role and jurisdiction remain authoritative for authorization.

## 9. Non-Functional Requirements

### 9.1 Security

- All access shall be authenticated and authorized by role and jurisdiction.
- RLS policies shall prevent riders from reading or modifying other riders' protected records, and shall prevent officers from reading data outside their jurisdiction scope, except for shared inter-state route data (JUR-004).
- Officers shall have read access only to the operational scope assigned to their role.
- Service-role keys, database passwords, signing keys, and model-service credentials shall never be bundled into the Flutter APK or browser JavaScript.
- Sensitive data shall use HTTPS/TLS in production, and data at rest shall be encrypted.
- Location, phone, delivery proof, and profile data shall be handled according to applicable privacy law and organizational policy (§11.2).
- Administrative and ML decisions shall be auditable.
- Before national go-live, the system shall undergo a security audit and penetration test by a suitably accredited auditor, as the deploying authority requires **[TBC]**.

### 9.2 Availability and resilience

- The app shall remain usable for configured offline workflows.
- Queued actions shall survive app restarts.
- Synchronization shall retry with bounded backoff and report failures.
- Realtime consumers shall have polling or refresh fallback.
- A service outage shall present a useful degraded state rather than silently showing live data as current.
- A failure in one region's data, feed, or model shall not degrade other regions (INT-004, JUR-009).
- Availability targets for production control-room functions shall be defined before go-live. A proposed starting point is 99.5% monthly, excluding planned maintenance **[TBC]**.

### 9.3 Performance and scalability

- Auth and ordinary API requests should provide a visible result within 2 seconds under normal network conditions; requests shall time out rather than hang indefinitely.
- The mobile app shall avoid uploading duplicate or unnecessary GPS fixes.
- Officer map screens shall remain usable with the configured active rider and incident volumes, including at national scale (WEB-011).
- Batch location synchronization shall support up to the server-defined batch limit; the current RPC contract supports batches up to 500 and the mobile client sends smaller batches.
- ML inference latency and availability objectives shall be defined before production activation.
- The system shall be sized from a capacity plan produced before national rollout. The plan shall fix the parameters below **[TBC]**.

| Capacity parameter | Target |
|---|---|
| States/UTs enabled per phase | [TBC] |
| Registered users by role | [TBC] |
| Concurrent riders sharing location | [TBC] |
| Location fixes per second (sustained and peak) | [TBC] |
| Concurrent officer dashboard sessions | [TBC] |
| Active incidents and alerts per region | [TBC] |
| Scored segments per daily ML run | [TBC] |

For illustration only, 20,000 concurrent riders reporting once every 30 seconds produce roughly 667 fixes per second sustained. This is an example of the arithmetic the capacity plan must do, not a proposed target.

### 9.4 Usability and accessibility

- Critical rider actions shall be reachable from the active-trip context.
- Critical alerts shall use text, color, and iconography together rather than color alone.
- Forms shall provide clear validation, retry, and permission explanations.
- Layouts shall support common Android phone sizes and web desktop/tablet widths.
- Text shall remain readable in offline, loading, empty, error, and stale-data states.
- Operational terms and role labels shall be consistent across mobile and web and across languages.
- The mobile app shall run acceptably on low-to-mid-range Android devices and on limited bandwidth, with the minimum supported Android version and target app size defined **[TBC]**.

### 9.5 Maintainability

- Flutter state shall remain separated into UI, Riverpod controller/provider, repository, and service layers.
- Web clients shall use shared Supabase types and role semantics where practical.
- Backend schema changes shall be delivered through migrations and tested with reset/push workflows.
- ML feature specifications, training configuration, evaluation reports, and model cards shall be version-controlled.
- Configuration for Supabase, OSRM, GeoServer, feeds, and ML endpoints shall be environment-specific and injected at build/deploy time.
- Region-specific behaviour shall be driven by configuration and region packs, not by code branches per State.

### 9.6 Observability

The production system should provide:

- Auth failure and authorization metrics.
- API/RPC latency and error metrics.
- Realtime connection, reconnect, and polling-fallback metrics.
- Queue depth, retry count, and synchronization failure metrics.
- GPS permission, accuracy, and battery-impact metrics that respect privacy policy.
- Incident, alert, route, and delivery workflow audit events.
- ML inference latency, coverage, missing-feature, drift, calibration, and outcome metrics per region.
- Feed freshness and failure metrics per source and region.
- Notification delivery and escalation metrics per channel and language.

### 9.7 Hosting, backup, and disaster recovery

- Production shall run on India-resident infrastructure (§7.4).
- Databases shall be backed up on a defined schedule, with restore tested periodically.
- Recovery point and recovery time objectives shall be defined before go-live. Proposed starting values are RPO of 15 minutes and RTO of 4 hours for control-room functions **[TBC]**.
- A disaster-recovery drill shall be completed before national go-live (§12.2).

## 10. Offline and Synchronization Requirements

1. The client shall write accepted offline actions to durable local storage before attempting remote synchronization.
2. Every synchronizable action shall have an idempotency/client ID.
3. The client shall show queued, syncing, synced, and failed states.
4. The server shall reject malformed, unauthorized, duplicate, or out-of-order events safely.
5. Conflicts shall be resolved according to entity policy; server-authoritative assignment and role changes shall not be silently overwritten by an offline client.
6. When connectivity returns, the client shall retry automatically and provide a manual retry action.
7. The system shall retain enough metadata to explain why an action failed.
8. The client shall support extended offline periods, including several days in remote areas, with bounded local storage and a documented priority order when space is limited (SOS first, then incident reports, then location history).
9. Critical events (SOS, critical incident) shall have an SMS fallback path when no data connection exists (RIDER-015).
10. Downloaded offline map packs shall be versioned per State or corridor, and the app shall show pack age and size.
11. When many devices in a region reconnect at once, clients shall use randomised backoff so the backend is not hit by a synchronization surge.
12. The client shall tolerate device clock skew by recording both device time and receipt time, and the server shall reconcile them.

## 11. Security and Privacy Model

### 11.1 Role permissions

Each capability is limited to the user's assigned jurisdiction scope. "Scope" means the State, Region, or nation assigned to the role.

| Capability | Rider | Field Officer | District Officer | State Officer | Control Room | State / National Admin |
|---|---:|---:|---:|---:|---:|---:|
| View own profile/role | Yes | Yes | Yes | Yes | Yes | Yes |
| Update own rider duty/location state | Yes | No | No | No | No | No |
| View rider live locations | Own only | Operational scope | District scope | State scope | Scope | Aggregated/audited only |
| View assigned shipment | Yes | Operational scope | District scope | State scope | Scope | No (aggregates only) |
| Create own incident/report | Yes, configured types | Yes | Yes | Yes | Yes | No |
| Review/verify incidents | No | Yes | Yes | Yes | Yes | No |
| Manage alerts | No | Limited | District scope | State scope | Scope | No |
| View ML risk predictions | Relevant route | Yes | Yes | Yes | Yes | Status/coverage only |
| Promote ML segment to alert | No | No | District scope | State scope | Scope | No |
| Manage users, roles, and jurisdictions | No | No | No | No | No | Yes, within own jurisdiction (national: all) |
| Configure region/State settings | No | No | No | No | No | Yes, within own jurisdiction |
| Change ML model/version | No | No | No | No | No | No (authorised ML release role/service only) |
| See other States' data | No | No | No | Shared inter-state route data only | Per configured scope | No |

The exact policy must be implemented and tested in Supabase RLS and RPC functions rather than enforced only in client UI.

### 11.2 Privacy

- Location sharing shall require user awareness and permission, with the notice available in the user's language.
- The system shall collect only data necessary for the configured operational purpose.
- Phone, location, profile, and delivery-proof access shall be limited to authorized roles and jurisdictions.
- Data export, retention, deletion, and incident access policies shall be defined by the deploying organization.
- The platform shall be designed to meet the principles of the Digital Personal Data Protection Act, 2023 (notice, consent or other lawful basis, purpose limitation, data minimisation, accuracy, storage limitation, security safeguards, breach notification, and handling of data-principal requests). Whether and how exemptions for State instrumentalities apply shall be confirmed by legal counsel **[TBC]**.
- Aggregated national and cross-State reporting shall not expose personal data (RPT-004).

### 11.3 Security compliance

- The deployment shall comply with applicable CERT-In directions, including cyber-incident reporting timelines and retention of system logs within India. The specific periods (the 2022 directions set a six-hour reporting window and a rolling 180-day log retention) shall be verified against the current text before go-live.
- Secure development practices shall include dependency scanning, secret management, code review, and vulnerability remediation tracking.
- Security-sensitive changes to RLS, RPCs, and roles shall be reviewed and covered by negative tests.

## 12. Testing and Acceptance Criteria

### 12.1 Required test levels

- Unit tests for domain models, role mapping, auth error mapping, location policy, queue behavior, and ML response parsing.
- Widget/component tests for login, account creation, rider dashboard, alert states, live-rider states, empty states, and error states.
- Repository/API tests for Supabase queries, RPC parameters, idempotency, RLS, and Realtime updates.
- Integration tests for sign-in, rider signup, start/stop sharing, queue flush, incident submission, proof submission, and officer live feed.
- GIS tests for route rendering, risk overlays, coordinate handling, boundary correctness, and offline map mode.
- ML tests for schema validation, feature availability, response versioning, threshold behavior, fallback behavior, coverage handling, and model monitoring.
- Security tests for role isolation, jurisdiction isolation, leaked credentials, unauthorized RPC calls, and protected media/data access.
- End-to-end tests on representative Android devices and web browsers, including low-end devices.
- Multi-state tests using at least two regions with different languages, hazards, and data quality, plus an inter-state shipment crossing a boundary.
- Localisation tests for each enabled language, including script rendering, right-to-left layout, fallback, and reviewed alert templates.
- Load tests against the capacity plan (§9.3) and resilience tests for feed, region, and service failures.
- Notification tests for delivery, escalation, deduplication, and SMS fallback.

### 12.2 Minimum release acceptance

A release shall not be accepted until:

1. All supported roles can authenticate and are routed to the correct experience.
2. A rider can create an account, view assigned work, start/stop location sharing, and see queue/sync state.
3. An officer can view rider locations and staleness with Realtime or polling fallback.
4. Offline location and report actions survive restart and synchronize without duplicates.
5. RLS and role permissions pass positive and negative tests, including jurisdiction isolation between States.
6. Routing and map failures produce understandable fallback states.
7. Android release builds contain no service-role or private ML credentials.
8. If ML is enabled for a release, the same versioned prediction is visible and traceable in both the Flutter app and web dashboards for each enabled region, uncovered regions show `no_coverage`, and each ML-enabled region has passed the regional validation gate (ML-014). Otherwise the release must label ML integration as unavailable/not connected.
9. Each region enabled in the release has passed the region-onboarding checklist (§13.3).
10. Each enabled language has reviewed critical-alert templates, and the UI passes localisation tests.
11. Displayed boundaries match the official boundary dataset in use (JUR-008).
12. A load test at the agreed capacity targets and a disaster-recovery drill have been completed.
13. The required security audit has been completed and its critical findings resolved **[TBC]**.

## 13. Deployment and Operations

### 13.1 Development

- Run the Supabase local stack from the web App Development project.
- Apply migrations and seed data using `supabase db reset`.
- Run Flutter with local emulator, LAN, or hosted Supabase `--dart-define` values.
- Run web clients with Vite development servers.
- Run OSRM and GeoServer through their documented Docker Compose projects when needed.
- Run ML pipeline tests and training commands from `sih-ml`.
- Seed at least two regions (NER and one further region) so multi-state behaviour can be developed and tested locally.

### 13.2 Staging and production

- Use separate Supabase projects/environments for development, staging, and production.
- Apply migrations through reviewed deployment processes.
- Use HTTPS endpoints and managed secrets.
- Host production on India-resident infrastructure with regional isolation and tested backups (§9.7).
- Deploy the web applications with environment-specific Supabase configuration.
- Build signed Android artifacts with release signing keys held outside source control.
- Deploy each ML inference or batch-scoring service separately from training jobs and require model/version approval before exposure to users.
- Monitor application, data, GIS, routing, feed, notification, and ML services independently, per region where relevant.

### 13.3 Region-onboarding checklist

A State/UT or Region is production-enabled only when all of the following are complete (JUR-006, JUR-007):

- [ ] Jurisdiction nodes created with LGD codes and validated against the official boundary dataset.
- [ ] Region pack loaded: boundaries, road network, bridges, points of interest, terrain, with version recorded.
- [ ] Routing extract built and route quality spot-checked on representative corridors.
- [ ] Hazard catalogue selected and severity mappings configured.
- [ ] Feeds configured with provenance, freshness targets, and fallbacks.
- [ ] Languages configured and critical-alert templates reviewed.
- [ ] State administrator provisioned and approval chain agreed.
- [ ] Retention, proof, escalation, and notification policies configured and signed off by the State authority.
- [ ] RLS and jurisdiction isolation tests passed for the new region, including inter-state cases with neighbours.
- [ ] ML status recorded for the region (`covered`, `replay`, or `no_coverage`), and any ML enablement approved through the validation gate.
- [ ] Data-quality report accepted by the State authority.
- [ ] Field officers and riders trained, and support contacts published.

### 13.4 Proposed phased rollout

This phasing is a proposal **[TBC]**.

| Phase | Content |
|---|---|
| Phase 0 | NER baseline: existing Flutter app, dashboards, Supabase backend, and ML replay mode for the covered corridor |
| Phase 1 | Jurisdiction model, admin console, multilingual UI (English and Hindi), and pilot in a small set of States chosen to cover different hazard regimes |
| Phase 2 | Region-by-region expansion, feed adapters, SMS fallback, national dashboard, and ML validation for additional regions where data allows |
| Phase 3 | Nationwide availability, full reporting and analytics, and stable APIs for State and national systems |

## 14. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Poor network coverage | Missing live updates and delayed reports | Durable queues, retries, offline maps, SMS fallback for critical events, clear stale state |
| GPS inaccuracy or battery drain | Incorrect rider position or device impact | Accuracy thresholds, throttling, heartbeat policy, adaptive reporting, foreground-service consent |
| Incorrect route/GIS data | Unsafe or inefficient operational decisions | Source/freshness indicators, manual verification, fallback routes, versioned region packs |
| Unauthorized location/profile access | Privacy and safety incident | RLS, jurisdiction scoping, security-definer RPC checks, least privilege, audit testing |
| ML false positive | Unnecessary reroute or alert fatigue | Advisory wording, calibrated thresholds, per-region alert caps, human approval, feedback monitoring |
| ML false negative or drift | Missed disruption | Multiple data sources, fallback rule alerts, monitoring, retraining and review |
| ML claimed beyond validated coverage | Users trust predictions where none exist | Coverage registry, `no_coverage` labelling, regional validation gate (ML-012 to ML-016) |
| Model not yet integrated for a region | Requirements not operationally fulfilled | Track ML integration per region as a separate release milestone; never label static alerts as live ML output |
| Duplicate offline submissions | Incorrect counts or repeated actions | Client IDs, server uniqueness, idempotent RPCs |
| Third-party service outage | Reduced mapping/routing capability | Baked route data, offline mode, self-hosted tiles and routing, degraded-state UI |
| Uneven data quality across States | Inconsistent behaviour and unfair comparison | Region data-quality reports, onboarding checklist, provenance and freshness display |
| Divergent State policies | Conflicting rules and hard-to-maintain code | Configuration-driven policy per State, no per-State code branches |
| Mistranslated critical alerts | Wrong action taken by a rider or officer | Human-reviewed templates for critical alerts, English fallback, machine translation labelled |
| Alert fatigue at national scale | Real alerts ignored | Targeting by jurisdiction and geofence, deduplication, rate limits, escalation only on thresholds |
| Incorrect boundary depiction | Legal and reputational harm | Official boundary dataset, versioning, boundary tests (JUR-008) |
| Scale beyond design capacity | Slow or failing service during a disaster | Capacity plan, partitioned storage, load tests, regional isolation |
| Cross-State data-sharing disputes | Delays or blocked adoption | Agreed sharing rules (§7.4), least-data inter-state views, audit |
| Privacy non-compliance at scale | Legal exposure and loss of trust | Data minimisation, consent notices, retention limits, legal review, audits |
| Single point of failure at national level | Nationwide outage | Regional isolation, backups, disaster-recovery drill, degraded-mode clients |

## 15. Implementation Status Summary

The baseline column repeats the NER SRS status. The right-hand column states what JanRakshak AI still has to deliver.

| Area | Baseline status (from NER) | JanRakshak AI work |
|---|---|---|
| Flutter Android-first app | Implemented prototype; release APK buildable | Jurisdiction-aware flows, language support, SMS fallback, inter-state features |
| Role model including rider | Implemented (4 roles) | Add `state_officer`, `state_admin`, `national_admin` and jurisdiction scope |
| Rider account creation fields | Implemented in Flutter UI and auth metadata flow | State/district selection from registry, approval flow |
| Supabase auth/profile/role flow | Implemented in client and migration design; requires running/deployed stack | Jurisdiction-aware RLS, MFA, India-resident deployment |
| Rider location sync and officer live feed | Implemented in Flutter/Supabase code; requires running backend for live verification | Partitioning, jurisdiction filtering, adaptive reporting |
| Mock rider deliveries/proofs/issues | Present for prototype workflows | Replace with real assignment and proof policy per State |
| Web dashboard UI | Present in React/Vite project | State, Region, and national views; admin console |
| Web login/account UI | Present in React/Vite project | Jurisdiction selection, approval flow, language selection |
| OSRM routing | Configurable/optional with fallback | National extract, vehicle profiles, production hosting |
| GeoServer/PostGIS analytics | Configurable/optional local backend | National layers, region packs |
| ML training/evaluation pipeline | Present in `sih-ml` | Extend to further regions and hazards |
| ML batch scoring + Supabase publisher | Implemented; replay mode only, no live rainfall feed yet | Multi-region scoring, coverage registry, live-mode adapters |
| ML connection to Flutter app | Implemented (`lib/features/ml/`, ML RPC migration) | Coverage-aware display, multilingual recommendations |
| ML connection to web dashboards | Implemented (`src/lib/ml.ts`, `src/components/MlRisk.tsx`) | Coverage-aware display, State/national views |
| Multilingual UI and notifications | Not implemented | Build (§6.9, §6.10) |
| Notification service and escalation | Not implemented | Build (§6.10) |
| Feed adapter framework | Not implemented | Build (§6.11) |
| Region onboarding and admin console | Not implemented | Build (§6.2, §6.12) |
| Production deployment and operations | To be completed per environment | India-resident hosting, DR, security audit, capacity plan |

## 16. Future Enhancements

- Extend the approved ML models to further regions and hazards through the regional validation gate.
- Add model-driven alert creation with human review and audit history.
- Add model feedback capture from verified incidents and route outcomes across all regions.
- Add richer dispatch, warehouse, convoy, and inter-district and inter-state planning.
- Add configurable delivery-proof policies by cargo type and authority.
- Add voice-based interaction and further accessibility support for riders.
- Add formal analytics dashboards for service levels, route reliability, and model performance across States.
- Add an iOS client and public or citizen-facing reporting channels if the sponsoring authority requires them **[TBC]**.
- Add deeper integration with State and national disaster-management and emergency-response systems.

## 17. Traceability to Existing Workspace

JanRakshak AI starts from the NER workspace. The references below are the inherited baseline; JanRakshak-specific artifacts (jurisdiction migrations, admin console, feed adapters, notification service, region packs) are **to be created** and should be added here as they appear.

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
| Jurisdiction model, admin console, region packs, feed adapters, notification service | To be created |

Requirement families and their NER origin:

| JanRakshak family | NER SRS section |
|---|---|
| AUTH, RIDER, LOC, OPS, INC, GIS, ML, WEB | §6.1, §6.2, §6.3, §6.4, §6.5, §6.6, §6.7, §6.8 (IDs preserved) |
| JUR, I18N, NOT, INT, RPT | New in this SRS; extend NER §16 (future enhancements) and §9 |

## 18. Open Decisions

These items need an answer from the project owner or the sponsoring authority before this SRS can be baselined.

| # | Decision | Related requirements |
|---|---|---|
| 1 | Final product name and spelling (JanRakshak AI, JanRaksha AI, or JanRakshak) | Title, all sections |
| 2 | Sponsoring/owning authority for the national deployment, and whether the SIH/MDoNER lineage remains in the project description | §1, Approval |
| 3 | Scope beyond logistics (for example citizen-facing reporting or wider civil-protection functions) | §2 |
| 4 | Platform scope: Android only or iOS as well, and the minimum Android version | §2.2, §9.4 |
| 5 | Hosting provider and India-residency approach, and whether Supabase is managed or self-hosted | §7.4, §8.1, §9.7 |
| 6 | Confirmed role set and approval chain (`state_officer`, `state_admin`, `national_admin`) | AUTH-002, AUTH-006, JUR-010 |
| 7 | Languages for the first release beyond English and Hindi | I18N-001 |
| 8 | Pilot States and hazard priorities | §13.4, INC-009 |
| 9 | Data-sharing rules between States and with national users | JUR-004, §7.4 |
| 10 | Retention periods per data class | LOC-007, §7.3 |
| 11 | SMS and push providers, budget, and template registration | §6.10 |
| 12 | Authoritative data sources, access, and licences per region | INT-002 |
| 13 | Capacity targets (users, riders, throughput) | §9.3 |
| 14 | Availability, RPO, and RTO targets | §9.2, §9.7 |
| 15 | Security audit authority and DPDP applicability | §9.1, §11.2, §11.3 |
| 16 | Which regions and hazards get ML models next, and who owns labels and validation | ML-012 to ML-019 |
| 17 | MFA method and whether rider OTP sign-in is required | AUTH-012, AUTH-013 |
| 18 | Cargo priority classes | OPS-008 |

## 19. Glossary

| Term | Meaning |
|---|---|
| CAP | Common Alerting Protocol, a standard format for public alerts |
| CERT-In | Indian Computer Emergency Response Team |
| DPDP Act | Digital Personal Data Protection Act, 2023 |
| GIGW | Guidelines for Indian Government Websites |
| IMD | India Meteorological Department |
| LGD | Local Government Directory, the official coding of States, districts, and sub-districts |
| NDMA / SDMA / DDMA | National, State, and District Disaster Management Authorities |
| NER | North Eastern Region of India |
| Region | A configurable grouping of States/UTs (for example NER) |
| Region pack | A versioned bundle of boundaries, road network, points of interest, terrain, and configuration for a region |
| RLS | Row-Level Security in Postgres/Supabase |
| RPC | Remote procedure call exposed by Supabase/Postgres functions |
| `no_coverage` | ML state meaning that no validated model covers the route or segment |
| `replay` / `live` | ML modes: scoring from historical data, or from operational live inputs |
| State/UT | State or Union Territory |

---

## Approval

| Role | Name | Signature | Date |
|---|---|---|---|
| Business/Product Owner |  |  |  |
| Technical Lead |  |  |  |
| Operations Representative |  |  |  |
| State/Regional Authority Representative |  |  |  |
| Security/Data Protection Representative |  |  |  |
| Legal/Compliance Representative |  |  |  |
| ML/Data Science Lead |  |  |  |
