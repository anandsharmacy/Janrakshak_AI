# Logistics Rider Dashboard — Implementation Plan

## Purpose

Add a dedicated **Logistics Rider** dashboard to the NER Logistics app. A Rider is the person operating a vehicle that carries essential supplies, medicines, agricultural produce, relief materials, or construction materials. The role supports truck drivers, transport partners, and last-mile delivery operators.

The dashboard must help a Rider answer three immediate questions:

1. What delivery or trip do I need to complete next?
2. Is it safe to continue on my current route?
3. What must I report or prove before the trip is considered complete?

## Current Project Context

The app is a Flutter, Android-first prototype with three existing roles:

- Field Officer: ground reporting, route inspection, and incident reporting.
- District Officer: district-level monitoring and review.
- Control Room Operator: region-wide command, fleet visibility, and alerts.

The app already has mock shipment, route, fleet, incident, and alert data. It has UI support for an active-trip/rerouting experience and Android permissions for location and camera. Maps, authentication, background GPS tracking, persistence, APIs, and real synchronization are not yet implemented as production services.

## Role Definition

### User-facing name

**Logistics Rider**

Use **Rider** as the short label in navigation and compact UI spaces.

### Internal role identifier

Add `rider` to `AppRole`.

### Core responsibilities

- View assigned deliveries and trip details.
- Accept or reject an assignment when permitted.
- Start, pause, resume, and complete an assigned trip.
- Share location while an active trip is in progress.
- Follow approved route guidance and receive disruption alerts.
- Request or accept an alternate route when a route becomes unsafe.
- Report road, vehicle, safety, and delivery issues.
- Submit proof of delivery.
- Continue critical work offline and synchronize when connectivity returns.

## Product Decisions Required

Confirm these decisions before implementing production integrations:

1. Can a Rider accept/reject assignments, or only receive dispatched work?
2. Can a Rider carry multiple consignments in a single trip or convoy?
3. Which proof of delivery is mandatory: recipient OTP, signature, photo, QR scan, geotag, or a combination?
4. Can a Rider independently choose an AI-proposed alternate route, or is control-room approval required?
5. Should live tracking run continuously during a trip or use periodic check-ins?
6. Which rider data is visible to dispatchers: location, speed, stoppage duration, SOS state, vehicle status, and delivery proof?
7. Which languages are required in the first release?
8. Which tasks are allowed offline: trip start/end, delivery proof, incident reporting, and location updates?

## Dashboard Scope

### Primary dashboard sections

1. **Active Delivery Card**
   - Delivery/trip ID and cargo priority.
   - Origin, destination, recipient, and delivery time window.
   - Current trip state: assigned, accepted, en route, paused, rerouting, arrived, completed, or failed.
   - ETA, distance remaining, and progress.
   - Prominent action: Start Trip or Resume Trip.

2. **Safety and Route Status**
   - Current route accessibility and risk level.
   - Critical road/weather alerts relevant to the active route.
   - Next-turn instruction and immediate speed/safety guidance.
   - Safe alternate-route recommendation and approval state.

3. **Today’s Deliveries**
   - Assigned, upcoming, delayed, and completed deliveries.
   - Cargo category and priority.
   - Delivery windows, route risk, and status.

4. **Quick Actions**
   - SOS / emergency assistance.
   - Report road or weather incident.
   - Report vehicle breakdown or unsafe condition.
   - Contact control room.
   - Send manual location check-in.
   - Add delivery proof.

5. **Offline and Sync Status**
   - Network state and last successful sync time.
   - Count of queued location pings, reports, delivery proofs, and trip updates.
   - Clear retry/sync action when connectivity is restored.

6. **Recent Activity**
   - Route changes, delivery events, alerts acknowledged, and reports submitted.

## Rider Navigation

Create a separate Rider shell and drawer. Recommended destinations:

- Dashboard
- My Deliveries
- Active Trip
- Route & Alerts
- Report Issue
- Delivery History
- Offline Queue
- Profile & Settings

Keep the navigation focused on immediate delivery work. District and control-room analytics should not appear in the Rider experience.

## Data Model Changes

Extend `lib/mock_data/models.dart` with the following domain concepts.

### Enums

- `AppRole.rider`
- `RiderTripStatus`: assigned, accepted, enRoute, paused, rerouting, arrived, completed, failed, cancelled.
- `AssignmentDecision`: pending, accepted, rejected, expired.
- `DeliveryProofType`: otp, signature, photo, qrCode, geoTag.
- `VehicleIssueType`: breakdown, tyre, fuel, mechanical, accident, other.
- `LocationPingStatus`: queued, synced, failed.

### Entities

- `RiderProfile`: identity, contact details, language, assigned vehicle, emergency contact.
- `Vehicle`: registration number, type, capacity, fuel/charge level, maintenance status, documents.
- `DeliveryAssignment`: delivery details, rider/vehicle assignment, cargo, priority, origin, destination, time window, status, route, ETA, and control-room instructions.
- `TripStop`: pickup, intermediate, and delivery stop status with coordinates and timestamps.
- `ProofOfDelivery`: evidence type, recipient details, timestamp, coordinates, media path, and sync status.
- `RiderLocationPing`: coordinates, timestamp, accuracy, speed, heading, battery, and sync status.
- `RiderIssueReport`: road, weather, vehicle, safety, or delivery issue with media, coordinates, severity, and sync status.

Extend the existing `Shipment` model with rider ID, vehicle ID, assigned delivery state, delivery window, cargo priority, route progress, and proof-of-delivery state.

## State and Persistence Architecture

### Phase 1: prototype state

1. Add rider-specific mock data files:
   - `mock_riders.dart`
   - `mock_vehicles.dart`
   - `mock_deliveries.dart`
   - `mock_rider_activity.dart`
2. Extend `MockAppState` with active rider, rider assignments, active trip, queued proofs, queued location pings, and queued issue reports.
3. Add repository methods for assignment decisions, trip status updates, reroute selection, proof submission, issue reporting, and sync simulation.
4. Ensure dashboard values derive from the shared repository rather than local widget state.

### Phase 2: offline-first persistence

1. Implement Drift tables for trips, assignments, location pings, delivery proofs, and issue reports.
2. Write user actions locally before attempting network sync.
3. Maintain idempotent event IDs so retries do not duplicate trip completion or proof submission.
4. Display queued, synced, and failed status consistently.
5. Add conflict handling for assignments changed by the control room while the device was offline.

### Phase 3: production services

1. Replace mock authentication with secure role-based sign-in.
2. Connect a routing/GIS provider for maps, route geometry, and alternate routes.
3. Integrate weather, road-condition, and disruption feeds.
4. Add an API/websocket channel for assignment updates, critical alerts, and dispatcher acknowledgements.
5. Add secure cloud media upload for photos and signatures.
6. Implement background location tracking only after platform policy, consent, battery, and data-usage design are approved.

## Screens and User Flows

### 1. Assignment flow

1. Rider receives an assignment notification.
2. Rider opens assignment details and reviews cargo, route, delivery time, and risks.
3. Rider accepts or rejects the task, including a rejection reason when required.
4. Control room receives the decision and dispatches a replacement Rider if necessary.

### 2. Trip execution flow

1. Rider taps Start Trip after pickup confirmation.
2. Active Trip screen displays route, current position, next instruction, ETA, and alerts.
3. Location is recorded according to the approved tracking policy.
4. Rider can pause, report an issue, call for help, or request/choose a reroute.
5. Route changes update ETA and notify the control room.

### 3. Disruption and rerouting flow

1. System detects or receives a weather, landslide, road-block, or congestion risk.
2. Rider receives an actionable alert with distance, severity, and safe behavior.
3. The app offers route options with ETA, distance, risk, and approval requirement.
4. The selected/approved route becomes active and is recorded in the activity timeline.

### 4. Delivery completion flow

1. Rider marks arrival at the delivery location.
2. The app validates the delivery location when GPS is available.
3. Rider collects the selected delivery proof.
4. Rider submits the completion event; it is queued locally if offline.
5. Recipient and control room receive confirmation after sync.

### 5. Emergency flow

1. Rider triggers SOS from any active-trip screen.
2. App immediately queues the SOS with latest known location, delivery, vehicle, and rider context.
3. Control room receives high-priority notification and can acknowledge it.
4. Rider sees acknowledgement, escalation contact, and next instructions.

## Codebase Integration Points

| Area | Existing location | Required change |
| --- | --- | --- |
| Roles and routing | `lib/app.dart` | Add `rider` role, rider route constants, redirect, and Rider shell route. |
| Models | `lib/mock_data/models.dart` | Add Rider, vehicle, assignment, tracking, proof, and issue-report models. |
| Shared state | `lib/mock_data/mock_repository.dart` | Add Rider state and lifecycle methods; later replace with repositories backed by Drift/API services. |
| Authentication | `lib/features/auth/login_screen.dart` | Add Logistics Rider to sign-in and account creation choices. |
| Profile | `lib/features/profile/profile_sheet.dart` | Add Rider profile selection and Rider-specific settings. |
| Existing active trip UI | `lib/features/field_officer/trip/route_screen.dart` | Extract reusable route/trip widgets or adapt the interaction pattern for Rider execution. |
| Existing shipment data | `lib/mock_data/mock_shipments.dart` | Associate shipments with rider, vehicle, trip status, and delivery proof. |

## Delivery Sequence

### Milestone 1: Role and data foundation

- Add the Rider role, login entry, routing, mock profile, and mock vehicle.
- Add rider-domain models and mock delivery data.
- Add repository state and unit tests for the trip lifecycle.

### Milestone 2: Rider shell and dashboard

- Create Rider shell, header, drawer, profile integration, and offline indicator.
- Build dashboard sections and empty/loading/offline states.
- Wire dashboard actions to repository state.

### Milestone 3: Deliveries and active trip

- Build delivery list/detail, accept/reject, and start/resume actions.
- Implement active trip state, progress, pause, reroute, and critical alerts.
- Reuse shared cards, badges, headers, and alert components to preserve the existing design system.

### Milestone 4: Reporting and proof of delivery

- Build issue-report workflow for road, vehicle, and safety issues.
- Build proof-of-delivery capture flow for the approved proof types.
- Add local queue visibility and retry behavior.

### Milestone 5: Production readiness

- Add Drift persistence, sync service, API contracts, background tracking, maps, alerts, and secure media upload.
- Add localization strings, accessibility labels, privacy consent, audit events, and device/network resilience checks.

## Acceptance Criteria

- A Logistics Rider can sign in and is routed to a Rider-only dashboard.
- The dashboard clearly identifies the active delivery, its risk, ETA, and next action.
- A Rider can view assignments, start/pause/resume a trip, report issues, receive route alerts, and complete a delivery.
- Critical alert and SOS actions remain visible during an active trip.
- Delivery completion requires the approved proof method and records time/location where available.
- Rider actions made offline are clearly queued and synchronize without duplicate records.
- District and control-room views can identify a rider’s assigned delivery, last update, current trip state, and exceptions.
- All status colors are accompanied by text and icon labels.
- Widget and unit tests cover the assignment, active-trip, reroute, delivery-proof, offline-queue, and recovery paths.

## Non-Functional Requirements

- Android-first, portrait-first usability with large touch targets for use in transit stops.
- Low-bandwidth operation and offline-first writes.
- Minimal data usage and an explicit policy for GPS frequency/background tracking.
- Secure handling of rider identity, location history, recipient information, and proof media.
- Localized and accessible labels, including non-color risk indicators.
- Full auditability for assignment changes, route overrides, SOS actions, and delivery completion.
