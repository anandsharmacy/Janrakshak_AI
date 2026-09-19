# Supabase integration — shared backend for WEB and Flutter

This document records what was analysed, what was reused, what changed in the
database, and how the rider-tracking pipeline works end to end.

## 1. What the WEB project provides (reused as-is)

Backend source of truth: `web/district,field,contro dashboards/App Development/supabase`

| Area | Reused |
|---|---|
| Auth | Supabase email/password. Demo officer IDs map to seeded emails exactly like `src/lib/useAuth.ts`. |
| Sign-up | `auth.signUp` with metadata `{full_name, district, requested_role}`; the `handle_new_user` trigger creates `profiles` + `user_roles`. |
| Roles | `user_role_enum` + RLS helpers `has_role()`, `my_role()`, `my_district_name()`, `is_active_user()`. |
| Data | `profiles`, `user_roles`, `locations`, `routes`, `shipments`, `alerts`, `road_incidents`, … unchanged. |
| Realtime | Existing `supabase_realtime` publication (shipments, incidents, alerts, tasks, …). |
| Local stack | `supabase/config.toml` (API 54321, DB 54322, Studio 54323), local publishable key. |

The two other web folders (`Login and Account Creation Screen`, the
`district,field,contro dashboards` root) are UI-only; the dashboards root has
no Supabase dependency at all.

## 2. Database changes (two new migrations)

`supabase/migrations/20260912000001_rider_role_enum.sql`

- `alter type user_role_enum add value 'rider'` — isolated in its own file
  because Postgres forbids using a new enum value in the transaction that
  added it (the CLI runs one transaction per migration file).

`supabase/migrations/20260912000002_rider_tracking.sql`

| Object | Purpose |
|---|---|
| `rider_profiles` | vehicle registration/type, phone, `is_on_duty`, `active_shipment_id` |
| `rider_locations` | **one row per rider** = latest fix (lat/lng + PostGIS point, accuracy, speed, heading, `recorded_at` device time, `received_at` server time). Realtime-published, `replica identity full`. |
| `rider_location_history` | append-only trail; `client_id` unique → idempotent re-uploads; pruned after 7 days by `pg_cron` (`prune_rider_location_history`). |
| `shipments.rider_id` | which rider carries a shipment |
| `handle_new_user()` | now accepts `requested_role = 'rider'`, creates `rider_profiles` (uses `vehicle_registration` metadata) |
| `is_officer()` | helper: field/district/control room |
| RLS | riders: own rows only; officers: read all rider rows + rider `profiles`/`user_roles`; riders: read/update their assigned `shipments`, read `routes`, create own `road_incidents` |
| `sync_rider_locations(jsonb)` | rider upload (single or batch ≤500). Validates role, clamps clock skew, ignores older fixes (`where recorded_at <= excluded.recorded_at`), also updates `shipments.current_location` |
| `set_rider_duty(bool, text, text)` | on/off duty + vehicle |
| `get_my_rider_context()` | profile + vehicle + assigned shipments in one call |
| `get_active_riders(int)` | officer feed: joined identity + vehicle + shipment + last fix + `is_stale` |
| `get_rider_trail(uuid, timestamptz, int)` | recent breadcrumbs for one rider |

`seed.sql` gained the demo rider (P. Lyngdoh, NER-RD-1184, truck ML-05-A-2047)
assigned to shipment LG-108 with one recent fix near Nongpoh, so the officer
maps are not empty on first launch.

### Apply

```bash
cd "web/district,field,contro dashboards/App Development"
supabase db reset            # local: replays all migrations + seed
# hosted: supabase db push   # after review
```

> The migrations were written against the existing schema but could **not be
> executed on this machine** (no Docker runtime installed, so the local stack
> was down). Run `supabase db reset` once and check `supabase status` before
> testing the app.

### Web compatibility

- `src/lib/database.types.ts`: `"rider"` added to the enum, new tables/functions typed, `shipments.rider_id`.
- `src/lib/useAuth.ts`: a rider signing in on the web is signed out with the
  message *“Logistics Rider accounts use the NER Logistics mobile app.”*
  Previously any unknown role fell through to the Control Room dashboard.
- No web screen, query or policy used by the three officer roles was changed.

## 3. Flutter architecture

```text
Screen → Riverpod provider/notifier → repository → Supabase client
```

| Layer | File |
|---|---|
| Config | `lib/core/config/supabase_config.dart` — `--dart-define` with local defaults (10.0.2.2 on Android) |
| Client | `lib/core/supabase/supabase_providers.dart` |
| Auth | `features/auth/data/auth_repository.dart`, `application/auth_controller.dart` (AsyncNotifier). Router redirects from `authRoleProvider`; DB role is authoritative, the login tile is only a hint. |
| Rider | `features/rider/application/rider_tracking_controller.dart` (+ `location_policy.dart`, `location_queue.dart`), `data/rider_repository.dart` |
| Officers | `features/tracking/application/live_riders_controller.dart`, `data/live_rider_repository.dart`, `presentation/live_riders_screen.dart` |
| Map | `MapVehicle` gained `live / heading / stale / selected / onTap`; `NerMap` draws live riders as rotated arrows |

Session persistence, token refresh and PKCE are handled by `supabase_flutter`;
`Supabase.initialize` runs before `runApp`.

## 4. Rider location pipeline

```text
geolocator stream (10 m filter, foreground service on Android)
   └─ LocationPolicy: accept if moved ≥25 m AND ≥10 s since last upload,
                      heartbeat every 60 s, drop fixes worse than 100 m
        └─ LocationQueue (SharedPreferences, ≤1000 points, survives restarts)
             └─ flush: batches ≤200 → rpc sync_rider_locations, exponential back-off ≤2 min,
                        immediate flush on reconnect (connectivity_plus)
                  └─ rider_locations upsert (Realtime) + rider_location_history insert
```

- *Start trip*, *Resume* or **Start sharing** → `start()`; *Pause* / *Arrived*
  → low-power profile (100 m / 30 s / 3 min heartbeat); **Stop sharing** or
  sign-out → `stop()` + `set_rider_duty(false)`.
- Shipment id from `get_my_rider_context` is attached to each fix, so the
  officer feed shows what the rider is carrying.
- Battery: the platform fused provider does the filtering; the app only wakes
  for accepted fixes and the 60 s heartbeat. Battery level is not read (no
  extra plugin); the column exists for later.

## 5. Officer feed

- Initial state: `get_active_riders(30)`.
- Realtime: one channel on `rider_locations` + `rider_profiles`; rows are merged
  by `user_id`; out-of-order fixes are ignored; a fix with an unknown
  shipment/rider triggers a debounced re-fetch.
- Resilience: polling every 30 s while the channel is not `subscribed`,
  safety refresh every 2 min when live, automatic re-subscribe after channel
  errors, refresh on reconnect. A 20 s tick re-renders staleness labels
  without network traffic.
- Scope: the requirement asks that all three officer roles see **all** riders,
  so `get_active_riders` is region-wide. To scope district officers, add
  `and (l.district = public.my_district_name() or public.has_role('control_room'))`
  to its `where` clause.

## 6. Security checklist

- Only the publishable key is in the app; RLS enabled on all three new tables.
- All RPCs are `security definer` and check `auth.uid()` + role; `execute`
  revoked from `anon`; the pruning job is not callable through the API.
- Riders cannot read other riders; officers cannot write rider rows.
- Location history retention: 7 days (pg_cron `prune-rider-location-history`).

## 7. Platform configuration

- Android: `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `WAKE_LOCK`; cleartext
  HTTP only in debug builds (existing `src/debug/AndroidManifest.xml`).
- iOS: `NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription`, `UIBackgroundModes: location`;
  `NSAllowsLocalNetworking` already allowed the local stack.

## 8. Known limitations / next steps

- Rider deliveries, proofs and issue reports still use the in-app mock state;
  only identity, vehicle, shipment assignment and location are live.
- Officer profile editing in the sheet is still simulated (web has it live).
- `battery_percent` is always null until a battery plugin is added.
- Migrations need to be applied and smoke-tested on a running stack (see §2).
