# NER Logistics Platform — Front-End Requirements & Design System
### Flutter + Figma · SIH26002

---

## 1. Decisions log (from requirement gathering)

| Decision | Choice | Why |
|---|---|---|
| App shape | One codebase, two adaptive navigation trees switched by role/screen size | Avoids maintaining two apps; still lets each persona get a purpose-built layout |
| Platforms | Android + iOS + Web, Android-first | Highest risk item — architecture must allow dropping iOS/Web without rewrite |
| Map engine | `flutter_map` on OSM/self-hosted tiles | Only realistic offline-capable option; matches OSM/PMGSY data pipeline; free |
| State management | Riverpod | Testable, low boilerplate, good for async/streaming Supabase data |
| Navigation | Two distinct trees (Field Officer / Dashboard) sharing core widgets | Personas' jobs-to-be-done are genuinely different, not just resized |
| Languages (wired, not stubbed) | English, Hindi, Assamese, Bodo, Khasi | Assamese = lingua franca of the Brahmaputra valley corridor; Bodo & Khasi cover two more distinct NER language families (Sino-Tibetan, Austroasiatic) — signals real regional grounding to MDoNER judges, not a token toggle |
| Alerts | Push (critical) + in-app banner (informational) | Matches severity to intrusiveness; push needs Supabase + FCM wiring |
| Visual direction | Official govt-serious, tricolor-adjacent | Explicit brief constraint — see tokens below for how this is executed without clichés |

**Open risk to track:** role-adaptive + 3 platforms is the most likely thing to slip. Build Android + adaptive layout first; treat Web promotion and iOS packaging as stretch, not core path.

---

## 2. Information architecture — screen inventory

Organized by the six-feature spine agreed earlier. Each screen is tagged **[F]** Field Officer, **[D]** Dashboard/control-room, or **[S]** Shared.

### Onboarding & identity
1. **[S] Splash / language select** — first-run only; sets locale before anything else loads (multilingual is a first-class entry point, not a settings toggle buried later)
2. **[S] Login / role selection** — Supabase Auth; role (field officer / district officer / control-room) determines which nav tree loads
3. **[S] Offline-mode indicator overlay** — persistent, not a separate screen, but must be designed as a component that can appear on every screen

### Field Officer track
4. **[F] Home / My Area** — map centered on assigned district/corridor, risk-colored roads, nearest active alerts
5. **[F] Route Planner** — origin/destination entry, fast-vs-safe route choice (the risk-aware routing feature), ETA range not point estimate
6. **[F] Active Trip** — turn-by-turn-lite view, live reroute banner if a segment ahead turns high-risk mid-trip
7. **[F] Report Incident** — camera + geo-tag + category (blocked/damaged/flooded/other) + optional note; must fully function offline and queue
8. **[F] My Reports** — submitted reports with sync status (pending / synced / rejected)
9. **[F] Alerts Inbox** — chronological list backing up the push notifications

### Dashboard / control-room track
10. **[D] District Connectivity Overview** — the "must-see" screen: map + district-wise accessibility status list, matches PS capability (g) almost verbatim
11. **[D] Corridor Risk Detail** — drill into one road segment: current risk score, contributing factors (rainfall, susceptibility, terrain), historical events — this is where you *show the ML*, not just its output
12. **[D] Live Consignment / Fleet View** — simulated vehicle markers, status per consignment (priority tier, ETA, current risk exposure)
13. **[D] Field Reports Feed** — moderation-style list/map of incoming geo-tagged reports, approve/flag
14. **[D] Alerts & Broadcast** — view fired alerts; optionally compose a manual broadcast override
15. **[D] What-if / Scenario Panel** *(stretch — only if spine is solid early)* — manual rainfall input to preview how risk-coloring would shift; this is your "future work" slide if time runs out, not a core build item

### Shared utility
16. **[S] Settings** — language, notification preferences, offline data management (view/clear cached tiles)
17. **[S] Empty / error / no-connectivity states** — designed as first-class screens, not afterthoughts (see writing guidance §6)

---

## 3. Navigation architecture

```
App Shell (Riverpod-provided: session, role, connectivity, locale)
│
├── Field Officer Shell — bottom nav (4 items, thumb-reachable)
│     Home │ Route │ Report │ Alerts        (My Reports nested under Report tab)
│
└── Dashboard Shell — side rail (≥900px) / drawer (<900px)
      Overview │ Corridor Detail │ Fleet │ Reports Feed │ Alerts │ Settings
```

- **Role determines shell, not screen size.** A control-room user on a phone still gets the Dashboard shell (drawer instead of rail); a field officer on a tablet still gets the bottom-nav shell. Screen size only changes *how* a shell lays out, never *which* shell.
- Shared widgets (risk badge, map layer, alert card, sync-status chip) live in a common package/folder so both trees render identical visual language — this is what keeps "two nav trees" from becoming "two apps that don't look related."
- Breakpoints: `<600` compact (phone), `600–900` medium (small tablet/fold), `>900` expanded (tablet landscape/web/desktop) — standard Material 3 breakpoints, reused rather than invented.

---

## 4. Design tokens

The brief pins "official govt-serious, tricolor-adjacent" — that axis is fixed. Everything else below is a deliberate choice for *this* subject (a formal, multilingual, outdoor field tool), not a default template.

### Color
| Token | Hex | Role |
|---|---|---|
| `navy-900` | `#0E2A47` | Primary — headers, primary buttons, active nav |
| `navy-700` | `#1B3F63` | Pressed/hover states, secondary panels |
| `paper-50` | `#F5F5F1` | Base background — cool paper white, not warm cream |
| `saffron-600` | `#D97A1F` | Medium-risk / caution accent, warning banners |
| `signal-red-700` | `#B3261E` | High-risk / blocked / critical alert only — never decorative |
| `deep-green-700` | `#1E6B45` | Clear/low-risk, success, synced status |
| `slate-500` | `#5B6472` | Body text on light surfaces, secondary labels |

**Deliberate choices:** background is a cool off-white, not the near-cream `#F4F1EA` that reads as generic AI output. Saffron and red are kept visually distinct (amber-orange vs true red) because risk severity must be distinguishable by field officers in direct sunlight and by colorblind users — never rely on hue alone; always pair color with an icon + text label on risk indicators. No gradients, no soft drop-shadows as decoration.

### Typography
- **UI chrome & headings:** **Public Sans** — the typeface built for the US Web Design System (government digital services); its lineage directly matches "official govt-serious" and reads as a considered choice, not a default pick.
- **Body & multilingual data:** **Noto Sans** (+ Noto Sans Devanagari/Bengali/other required subsets) — this is a practical necessity, not a style choice: it's one of the only free families with verified glyph coverage across English, Hindi, Assamese, and Bodo. Khasi uses Latin script, so it renders in the same family — one font stack covers all five languages.
- Type scale follows a standard modular scale (1.25 ratio); body text 16sp minimum for outdoor/field legibility, never below 14sp anywhere in the field-officer track.
- No all-caps labels, no tracked-out eyebrow text above headings — plain sentence case throughout, consistent with plain-language government service-design norms.

### Layout & surfaces
- Flat panels with 1px hairline borders (`slate-500` at 20% opacity), minimal/no shadow, small radius (4–6px) — evokes formal document/gazette structure rather than the rounded-card-with-soft-shadow SaaS kit. This is legitimate here because the subject genuinely is an official government record-keeping tool, not decoration for its own sake.
- Dashboard screens use rule-line-divided sections and left-aligned tabular data (like a gazette or official report), not a grid of identical cards.
- Left-aligned throughout; no centered marketing-style layouts anywhere in the product.

### Iconography & motion
- Outlined icon set, consistent stroke width, no filled/playful icons.
- Motion limited to: one reroute-confirmation animation (route line redraws when risk triggers a change) and standard Material state transitions. No hover-fade sequences, no scattered per-card animation — the reroute redraw is the one "memorable moment," everything else stays quiet.

---

## 5. Component library plan (build these once, reuse everywhere)

| Component | Notes |
|---|---|
| `RiskBadge` | Color + icon + text label (never color alone); three states: clear/caution/blocked |
| `RouteOptionCard` | Fast vs Safe choice, shows ETA range + risk exposure summary |
| `AlertBanner` | In-app, dismissible, severity-colored, used for informational alerts |
| `SyncStatusChip` | Pending (queued) / Synced / Failed — appears on any user-submitted content |
| `OfflineOverlay` | Persistent top strip when connectivity drops; never blocks interaction |
| `MapLegend` | Explains risk color scale; must be present any time the map shows risk coloring |
| `IncidentReportForm` | Camera capture, geo-tag auto-fill, category picker, offline-safe draft save |
| `ConnectivityStatusRow` | District-wise status list item, used in Overview and drill-downs |
| `LanguageSwitcher` | Accessible from Settings and first-run; changes locale app-wide via Riverpod |
| `EmptyState` / `ErrorState` | Written in interface voice: explain what happened, what to do next — never blank screens |

---

## 6. Offline & sync UX pattern

- Every user-generated action (incident report, form submit) writes to local storage **first**, shows a `SyncStatusChip: Pending` immediately, and syncs opportunistically when connectivity returns.
- The `OfflineOverlay` communicates state, never blocks: "You're offline. Reports will send when you're back online." — informative, not apologetic, matches the interface-voice guidance (state what happened, what happens next).
- Map tiles for the officer's assigned corridor pre-cache on login when online; `Settings` exposes "Manage offline maps" so officers can see/clear cached area — this is a visible feature to demo, not just invisible plumbing.

## 7. Alert/notification UX flow

- **Critical** (segment just crossed high-risk threshold on an active route) → push notification via FCM through Supabase → tapping opens `Active Trip` with reroute already suggested.
- **Informational** (general district advisory, non-blocking) → in-app `AlertBanner` + entry in `Alerts Inbox`, no push interruption.
- All alerts, regardless of channel, land in the same `Alerts Inbox`/`Alerts & Broadcast` list so there's one source of truth to demo.

---

## 8. Flutter package shortlist

| Concern | Package |
|---|---|
| Map rendering | `flutter_map` + `flutter_map_tile_caching` (offline tiles) |
| State management | `flutter_riverpod` |
| Routing/navigation | `go_router` (supports the two-shell/adaptive pattern cleanly) |
| Backend | `supabase_flutter` |
| Local persistence/offline queue | `drift` (SQLite) |
| Localization | `flutter_localizations` + `intl`, ARB files per language |
| Push notifications | `firebase_messaging` (via Supabase-triggered FCM) |
| Camera/geo-tag | `image_picker` + `geolocator` |
| Adaptive layout | Material 3 breakpoints, no extra package needed |

---

## 9. Figma file structure

```
📁 NER Logistics Platform
 ├── 🎨 Foundations       (color, type, spacing, icon library — tokens from §4)
 ├── 🧩 Components         (matches §5 — build once, variants for state/size)
 ├── 📱 Field Officer Flow (screens 4–9, compact breakpoint)
 ├── 🖥️ Dashboard Flow     (screens 10–15, expanded breakpoint)
 ├── 🔁 Shared Flows       (onboarding, settings, empty/error states)
 └── 🗺️ Prototype          (clickable: login → route → reroute-on-risk → alert, the core demo path)
```
Build Foundations and Components first — every screen frame should be assembled from them, not drawn freehand, so Figma-to-Flutter handoff stays 1:1.

---

## Next steps
1. Build Foundations + Components in Figma from §4/§5.
2. Wireframe the six spine screens (4, 5, 6, 10, 11, 13) end-to-end before touching stretch screens.
3. Stand up the `go_router` two-shell skeleton in Flutter with mock data, wire Supabase auth/role next.
