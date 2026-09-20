# ML Go-Live Implementation Plan (Phases 0 to 5)

**Date:** 2026-09-20
**Goal:** the `sih-ml` road-disruption model is visible, online, in `janrakshak_user` (citizen app) and `web/NER-Website-Merged` (officer + PMO dashboards). Nothing is scored on a phone or in a browser: a cloud job publishes results to Supabase, and both apps only read them through RPCs.
**Supersedes for this scope:** the phasing in `ML_INTEGRATION_PLAN.md` (its data contract and UI rules still apply).
**Status:** Phases 0 and 1 are complete (2026-09-20). Phases 2 to 5 are pending.

---

## 1. Decisions (fixed)

| # | Decision | Consequence |
|---|---|---|
| D1 | **Replay-first.** Publish already-scored 2025 monsoon days, labelled "Replay · rainfall of <date>". No live rainfall feed in this plan. | No rainfall ingestion, no 2026 backfill, no feed backtest. Live stays a later, separate phase. |
| D2 | **GitHub Actions** is the online runner (manual-dispatch workflow). | No server to maintain. Only small assets are needed (section 3). |
| D3 | **Supabase Free plan** (500 MB DB, 50 MB file limit, IPv6-only direct DB, may pause when idle). | Keep at most 2 runs; publisher connects through the pooler; weekly liveness check. |
| D4 | **North East scope.** The model itself covers only the Siliguri / North Bengal / Sikkim corridor (25.6 to 28.1 N, 87.1 to 89.9 E, 119 cells). | Everything else shows "outside model coverage". Retraining for the wider NE is a separate project. |
| D5 | **10 ML alerts per day** for officers. | `ml_settings.alert_capacity_region = 10`, `alert_capacity_district = 10`. No push notifications while in replay. |
| D6 | **Pipeline failure alerts go to a new PMO "Alerts" section.** | New table + PMO RPCs + PMO UI (section 5, Phase 1 and 3). GitHub failure email stays as the fallback channel. |
| D7 | **Live-mode approval belongs to the PMO, enforced in the database.** | `ml_begin_run` refuses `mode = live` until a PMO user has approved the exact bundle hash. |
| D8 | **The GitHub repo is public and the replay assets stay unencrypted** (owner's decision, 2026-09-20). | Anyone can download the model bundle, road-segment centroids and the scored day from the release, and Actions logs are public. Logs print only counts; the DSN is a masked secret. Revisit if any of the source data turns out to be licence-restricted. |

## 2. Starting state (verified 2026-09-20, before Phase 0; see the Phase 0 and Phase 1 results for what changed)

| Area | State |
|---|---|
| Cloud DB (`sjcqwxthimfuxmrodsbs`, 22 MB) | ML schema exists: `ml_models`, `ml_batch_runs`, `ml_segments`, `ml_segment_scores` (per-run partitions in `ml_private`), `ml_coverage`, `ml_settings`, `ml_route_risk_snapshots`. **All empty.** RPCs exist: `ml_status`, `get_route_ml_risk(p_route_id, p_geojson, p_run_id, p_buffer_m)`, `get_routes_ml_summary`, `get_my_routes_ml_risk`, `get_ml_top_alerts`, `get_ml_segments_in_bbox`, `promote_ml_alert`, `ml_begin_run`, `ml_finish_run`, `ml_set_current`, `ml_prune_runs`. |
| Publisher role | `ml_publisher` exists but has **no login**. |
| `ml_settings` today | region cap 25, district cap 10, `retention_runs` 30, `stale_after_hours` 36. Updatable by any control-room user. |
| `routes` table | 0 rows (route summaries need seeded routes). |
| `alerts` policies | Control room has ALL on every row; `target_role IS NULL` rows are readable by every active user (citizens included). So **PMO-only rows must not live in `alerts`.** |
| Web | `src/lib/ml.ts` and `src/components/MlRisk.tsx` already call the ML RPCs; used by MapViz, Shell, AI Insights, Routes, Command Center. PMO dashboard has only Map and Approvals sections. |
| Citizen app | No ML code. `RiskLayer` in `lib/features/trip_planner/risk_layer.dart` is the designed swap point. ML RPCs are officer-gated, so citizens cannot call them. `trip_planner_screen.dart` and `dark_map.dart` have uncommitted edits. |
| Model | Bundle `final_v3`, hash `bf4ff57518c571e9`. Its manifest says **"DEV champion, not evaluated on the locked split"**. Older docs mark `final_v1` as known-leaked and superseded. |
| Artifacts | Deployable bundle, feature store and 122 scored days (2025-06-01 to 2025-09-30, 1 GB) exist in **two byte-identical places outside the repo's tracked files**: the stale `project /sih-ml/deploy/` and `~/Desktop/SIH/data/sih-ml/deploy/` (verified by SHA-256 in Phase 0). Source models and raw data are in `~/Desktop/SIH/data` (`sih-ml/models/final_v3`, `data2`). Phase 0 also placed the bundle, feature store and the replay day in `ml/deploy/` (git-ignored). |
| CI | Only `pylint.yml`. |

## 3. Target architecture

```
GitHub Actions (manual dispatch: "Publish ML replay day")
  download small assets -> publish segments (once) -> publish run --mode replay
  on failure -> ml_report_pipeline_failure() -> PMO Alerts
        | psycopg via Supabase pooler (IPv4), role ml_publisher
        v
Supabase: ml_* tables, RPCs (officer + citizen-safe), ml_pipeline_events, ml_settings (caps, live approval)
   |-- web (Vercel): officer ML views + PMO Alerts + PMO ML status/approval
   '-- janrakshak_user (APK): read-only RPCs, Hive cache, RiskLayer implementation
```

**What the replay job needs** (nothing else; the 106 MB `static_matrix.npy` is not required):

| Asset | Size | Source |
|---|---|---|
| Bundle (`manifest.json`, `policy.json`, model files) | about 0.75 MB | release asset |
| Feature store `segments.parquet` + `manifest.json` (for `publish segments`) | about 3.6 MB | release asset |
| `segment_centroids.parquet` (the store's `segments.parquet` has **no lon/lat**, so `publish segments` reads this fallback file from `data/interim/`) | about 7 MB | release asset |
| Chosen day's `scores.parquet` + `run.json` | about 8.6 MB per day | release asset |

One tarball (`ml-replay-assets.tar.gz`, about 21 MB for one day) attached to a GitHub Release, unpacked so the centroids land at `ml/data/interim/`. The workflow downloads it with `GITHUB_TOKEN`.

---

## 4. Phase 0: Preserve and decide (S, about 1 day)

**Goal:** nothing can be lost, and the model is described honestly.

| Task | Detail |
|---|---|
| 0.1 Back up artifacts | Copy `project /sih-ml/deploy/{bundles,featurestore,scores}` to `ml/deploy/` (git-ignored) **and** an off-machine copy. Confirm `~/Desktop/SIH/data/sih-ml` also has `models/final_v3`, `registry.json`, `data2`. |
| 0.2 Model lineage gate | Compare bundle `final_v3` (`source_config_sha256_16 37ff290bc79618c0`) with `registry.json`; confirm it descends from the remediated `final_v2`, not the leaked `final_v1`. Record the result in this file. |
| 0.3 Honest labelling | Manifest status is "DEV champion, not evaluated on the locked split". Agree the UI wording: "Experimental model, rank only, verify with officers" (no accuracy claims, no probabilities). |
| 0.4 Pick the replay day | Read `run.json` tier counts for candidate days (default 2025-08-05). Choose one day, fixed for the demo. |
| 0.5 Working tree | Commit or stash the uncommitted edits in `janrakshak_user/lib/features/trip_planner/trip_planner_screen.dart` and `lib/widgets/dark_map.dart` so Phase 4 starts clean. |
| 0.6 Do NOT delete `project ` | Only after 0.1 is verified (file counts and checksums match). |

**Exit:** artifacts verified in two places; lineage note and replay day recorded here.

### Phase 0 result (completed 2026-09-20)

| Task | Result |
|---|---|
| 0.1 Artifacts | **Done, with one correction.** `~/Desktop/SIH/data/sih-ml/deploy` already held a byte-identical copy of the bundle, feature store and scores, so the `project ` copy was not the only one. SHA-256 of every file in `bundles/`, `featurestore/` and the replay day match across the repo copy, the SIH copy and the `project ` copy; bundle files also match `manifest.json`. Copied into `ml/deploy/` (git-ignored): `bundles/`, `featurestore/`, `scores/date=2025-07-28/`, plus `ml/data/interim/segment_centroids.parquet`. The other 121 scored days were deliberately not duplicated (1 GB, already in the SIH copy). **Still open, needs you:** an off-machine copy (external disk or cloud) of `~/Desktop/SIH/data/sih-ml/{deploy,models}`; the Mac is 96% full (18 GB free). |
| 0.2 Lineage | **Passes the leak gate; not validated on new regions.** `registry.json`: `final_v1` (config `5c8ab2326f9c5b5c`) is "known-leaked, superseded"; `final_v2` (`5aed65f3f8729060`) is the remediated model; **`final_v3` (`37ff290bc79618c0`, the deployed bundle) has parent `final_v2`** and adds only the D1 rainfall-coverage correctness fix (accuracy effect -0.0014, not demonstrated). Dev mean AP about 0.40 (per seed 0.39 to 0.42). The locked split was opened for `final_v2` (Stage 9, with a bias disclosure) and is **not opened for `final_v3`**. `policy.json` states that calibration did not transfer to a new region (worst terrain stratum 2.65x) and to rank by `risk_percentile`. |
| 0.3 Wording | Agreed set below. |
| 0.4 Replay day | **2025-07-28.** Data checked across all 122 scored days: no drift warnings, no NaN rainfall, no non-finite scores. Alert counts range 1,016 to 5,329 with a median of 3,502. 2025-07-28 has 3,496 alert and 22,196 human-review segments (a median day, unlike the quieter 2025-08-05 default at 1,713). Within 6 km of a straight Siliguri to Gangtok line it has 222 alert and 959 human-review segments, so the NH-10 demo has content. This is a proxy; Phase 2 task 2.7 measures it on the real route. |
| 0.5 Working tree | Done: commit `1fa1a64`. |
| 0.6 Do not delete `project ` | Still in place. Artifacts are now safe elsewhere, but deletion stays a Phase 5.9 decision. |
| No-database check | With the repo copy, the publisher's own validators accept the inputs: 309,042 valid score rows, 309,042 segments with coordinates, replay mode accepted, `live` refused for this date. |

**Agreed UI wording (both apps):**

- Status chip: "Replay · rainfall of 28 Jul 2025 · Experimental model".
- Risk line: "Riskier than N% of corridor roads in this replay" (never a probability or "% confidence").
- `alert` tier: "High disruption risk: review before travel". `human_review` tier: "Steep terrain: needs officer review". Below threshold: "No elevated model risk" (never "safe").
- Coverage: "Model covers X% of this route" and "Outside model coverage".
- Help text: "Experimental ranking from a model not yet validated on unseen regions. It shows relative risk, not the chance of a closure. Always follow official advisories."

**Corrections carried into later phases:** the workflow needs the centroids file as well (section 3); `ml_settings` still holds 25/10/30 until Phase 2.1.

## 5. Phase 1: Online publish path (M, about 3 to 4 days)

**Goal:** a manual GitHub Actions run puts one replay day into cloud Supabase, and failures reach the PMO.

| Task | Detail |
|---|---|
| 1.1 Publisher login | `alter role ml_publisher login password '<generated>'`. Store the **pooler session-mode** DSN as GitHub secret `SIH_PUBLISH_DSN` (user `ml_publisher.<project_ref>`, port 5432). The direct DB host is IPv6-only and GitHub runners are IPv4. |
| 1.2 Grants dry-run | In a transaction that is rolled back, run `ml_begin_run`, `COPY` into the run partition, and `ml_finish_run` as `ml_publisher`. Fix any missing grants in the Phase 2 migration. |
| 1.3 Assets release | Create the release and tarball from Phase 0 artifacts (section 3). The repo is public, so the release is public and the tarball is unencrypted (owner's decision D8). |
| 1.4 Workflow | `.github/workflows/ml-publish-replay.yml`: `workflow_dispatch` with inputs `date` (default the chosen day) and `load_segments` (bool). Steps: checkout, setup Python, `pip install -r ml/deploy/requirements-publish.txt`, download assets, set `SIH_BUNDLE`/`SIH_STORE`/`SIH_SCORES`, run `python -m sih_ml.serve.publish segments` (when requested) then `run --date $DATE --mode replay`. Concurrency group so two runs never overlap. |
| 1.5 Failure reporting | `if: failure()` step runs `ml/scripts/report_failure.py`, which calls `ml_report_pipeline_failure(stage, message, run_url)`. Messages are length-capped and never include the DSN or paths. Exit codes map to stages: 2 = bad input, 4 = database refused. |
| 1.6 First load | Run with `load_segments = true` once (309,042 segments + coverage), then publish the replay day. Publishing the same (date, bundle) again is a no-op by design. |
| 1.7 Size measurement | After the first load, record `pg_total_relation_size` for `ml_segments` and one run partition. Confirm the total stays well under 500 MB with `retention_runs = 2`. If not, publish only rows at or above a percentile floor (needs a matching RPC change, decided then). |

**Exit:** `select ml_status()` returns state `replay`, the chosen date, model `final_v3`; a deliberately broken run produces one PMO-visible event (verified in Phase 3) and a GitHub failure email.

### Phase 1 result (completed 2026-09-20)

| Task | Status |
|---|---|
| Pulled forward from Phase 2 (2.2, 2.3) | **Done and applied to cloud.** Migration `ml_pipeline_events` (file: `supabase/migrations/20260920000001_ml_pipeline_events.sql`): table `ml_pipeline_events` (RLS on, no policies or grants), `ml_report_pipeline_failure` (executable by `ml_publisher` only), `pmo_list_pipeline_events` and `pmo_ack_pipeline_event` (PMO only). Grants verified against `pg_proc`: `anon` and `authenticated` cannot run the reporter, `authenticated` can only run the two PMO functions (which check the role inside). |
| Existing grants of `ml_publisher` | Verified: can truncate/insert `ml_segments`, insert `ml_coverage`, use `ml_private`, execute `ml_begin_run`, `ml_finish_run`, `ml_set_current`; cannot read `ml_pipeline_events`. |
| 1.3 Assets | **Done.** `ml/scripts/make_replay_assets.sh` builds `ml/deploy/dist/ml-replay-assets.tar.gz` (13 MB, SHA-256 `946fab32f0e5720a7dc22dfdb3152279a3a9eab8e8d60f233b6214cc3a45a52b`). Extracted into a clean folder, the publisher's validators accept it (309,042 score rows, 309,042 located segments). |
| 1.4 Workflow | **Done, works.** `.github/workflows/ml-publish-replay.yml` (manual dispatch; inputs `date`, `load_segments`, `asset_tag`; concurrency lock; replay mode hard-coded). Run #2 (commit `ec0bd75`) succeeded. Two first attempts failed: the secret held a trailing newline, so Postgres looked for a database named `postgres\n`; the publisher now strips whitespace from the DSN. Note: GitHub's "Re-run" reuses the old commit and old inputs; start a fresh **Run workflow** after any fix. |
| 1.5 Failure reporting | **Written; the database function is verified, the workflow path is not.** `ml/scripts/report_failure.py` is called by the workflow's last step. In the two failed runs it could not record an event because of the same newline fault. Rehearse it with a deliberate failure in Phase 5.3. |
| 1.1 Publisher login | **Done (2026-09-20).** `ml_publisher` has login and a connection limit of 3, with a password set by the owner. The session-pooler DSN is saved in the git-ignored `ml/publish.env.local`. The password appeared in the working transcript: rotate it to a random value before real use (it must then also go into the GitHub secret). |
| 1.2 Grants dry-run | **Done, passes.** `ml/scripts/publish_dry_run.py` ran as `ml_publisher` through the pooler, everything inside a transaction that is always rolled back: segments load (309,042 rows, 119 coverage cells, 7 s), run publish (309,042 score rows, tiers 283,350 / 22,196 / 3,496, 3 s), visibility check, failure report. Afterwards every ML table was verified empty. It found two missing grants, now applied and recorded in `supabase/migrations/20260920000002_ml_publisher_grants.sql`: `BYPASSRLS` on the role (COPY is refused on tables with row-level security; the role only has privileges on `ml_*` tables) and `USAGE` on schema `extensions` (PostGIS functions in the coverage load). |
| 1.6 First load | **Done.** Cloud now holds 309,042 segments, coverage of 119 cells, and one run: 2025-07-28, `replay`, `final_v3`, hash `bf4ff57518c571e9`, tiers 283,350 none / 22,196 human_review / 3,496 alert, marked current. No pipeline events. |
| 1.7 Size measurement | **Done.** Database 130 MB in total (26% of the 500 MB Free limit): `ml_segments` 57 MB, one run partition 50 MB, baseline about 22 MB. With `retention_runs = 2` (current plus one rollback run) expect about 180 MB. Fits the Free plan without publishing fewer rows. |
| Read-path check | `ml_status()` as a control-room user returns state `replay`, date 2025-07-28, model `final_v3`, coverage bbox 87 to 90 E, 25.5 to 28.25 N. `get_route_ml_risk` on a rough Siliguri to Gangtok line: 132 segments matched, 7 alert, 29 human review, worst segment `SEG247696` at km 42 (99.99th percentile, steep), coverage 100%. Note: the route response has no top-level `status` key; check what `web/.../lib/ml.ts` expects in Phase 3. `alert_capacity` still reads 25 until Phase 2.1. |

**Phase 1 exit criteria met:** `ml_status()` returns `replay` with the chosen date. The PMO-visible failure event is verified in Phase 3 and rehearsed in Phase 5.


## 6. Phase 2: Supabase migration (M, about 4 days)

One reviewed migration set, **committed to `supabase/migrations/`** (the repo tracks only 5 of 38 applied migrations). Apply with the Supabase MCP, then commit the files.

| Task | Detail |
|---|---|
| 2.1 Settings | `alert_capacity_region = 10`, `alert_capacity_district = 10`, `retention_runs = 2` (current plus one rollback run). Restrict `ml_settings` updates to the PMO instead of any control-room user. |
| 2.2 Pipeline events | New table `ml_pipeline_events` (`id`, `created_at`, `stage`, `severity`, `message` capped at 500 chars, `run_url`, `acknowledged_by/at`, unique on `(stage, day)` to de-duplicate). RLS on with **no policies or grants**, same pattern as `control_room_requests`. |
| 2.3 Pipeline RPCs | `ml_report_pipeline_failure(p_stage, p_message, p_run_url)` executable **only** by `ml_publisher`; `pmo_list_pipeline_events()` and `pmo_ack_pipeline_event(p_id)` executable only by `authenticated` and role-checked for `pmo`. |
| 2.4 Live approval | Add `live_approved_bundle_hash`, `live_approved_by`, `live_approved_at` to `ml_settings`. RPCs `pmo_approve_ml_live(p_bundle_hash, p_note)` and `pmo_revoke_ml_live()` (PMO only, write `audit_logs`). Change `ml_begin_run`: for `p_mode = 'live'`, raise unless the run's `bundle_hash` equals `live_approved_bundle_hash`. Replay is never blocked. |
| 2.5 Citizen-safe RPCs | `get_citizen_route_ml_risk(p_geojson jsonb)`: summary plus coordinates along the route, no internal segment ids beyond what the map needs. `get_citizen_ml_segments(p_west, p_south, p_east, p_north, p_limit)`: only `alert` and `human_review` tiers, hard cap on rows. Both role-checked for active `citizen` (and `rider`), built on the same matching code as `get_route_ml_risk`. `ml_status()` already works for any active user, so citizens need no new status RPC. |
| 2.6 Seed routes | Insert canonical `routes` with `geom`: Siliguri to Gangtok (NH-10) and one out-of-coverage route (Guwahati to Shillong), geometry snapped once from OSRM. |
| 2.7 Buffer tuning | Compare route-to-segment matches at 50, 100 and 150 m on NH-10 against a hand-checked sample; set `ml_settings.route_buffer_m` to the smallest buffer that captures the road without parallel roads (centroid spacing is about 97 m). |
| 2.8 Pruning | Schedule `select public.ml_prune_runs()` daily with pg_cron (only the rider prune job exists today). |
| 2.9 RLS tests | SQL tests: citizen cannot select `ml_segment_scores`, `ml_pipeline_events` or `ml_settings` writes; officers cannot call PMO RPCs; only `ml_publisher` can call `ml_report_pipeline_failure`; `live` publish is refused before approval and accepted only for the approved hash; out-of-coverage route returns `coverage_fraction = 0`. |
| 2.10 Advisors | Run the Supabase security advisor; fix any new warnings (new functions with `anon` execute, missing `search_path`). |

**Exit:** all SQL tests pass; `get_route_ml_risk` on NH-10 returns segments ordered along the route; advisor clean for the new objects.

## 7. Phase 3: Web `web/NER-Website-Merged` (M, about 4 days; can run in parallel with Phase 4)

| Task | Detail |
|---|---|
| 3.1 Verify existing ML client | Exercise `lib/ml.ts` and `MlRisk.tsx` against the published run: status chip, top alerts (max 10), map layer, route summaries. Fix mismatches with the deployed RPC signatures (`get_route_ml_risk` takes `p_route_id uuid`). |
| 3.2 States | Every ML view renders replay, stale, unavailable, signed-out and out-of-coverage. Persistent chip: "Replay · rainfall of <date> · model final_v3 (experimental)". |
| 3.3 Routes and Command Center | Use the seeded routes; per-route summary (worst segment, alert count, coverage %). "Promote to alert" only for control room and district officers; promoted rows are tagged ML. |
| 3.4 Coverage outline | Draw the `ml_coverage` extent on the maps, with the legend "ML model · final_v3". |
| 3.5 PMO Alerts section | New nav item "Alerts" with a pending badge (same pattern as Approvals) in `src/pmo/PmoDashboard.tsx`; new `PipelineAlerts.tsx` listing events with acknowledge; API functions in `pmoApi.ts`; poll every 60 s. |
| 3.6 PMO ML card | New `MlStatusCard.tsx`: state, replay date, model version and hash, coverage, last publish, and the "Approve live" control. The button stays disabled while any checklist item is unmet: (1) live rainfall source backtest passed, (2) 14 days of shadow runs without alerts, (3) drift clean, (4) coverage limitation acknowledged. Approval calls `pmo_approve_ml_live`. |
| 3.7 Demo data | Keep demo content only under a labelled "Demo / rule-based" heading; ML items are never mixed into human or rule lists unlabelled. |
| 3.8 Build and deploy | `npm run build`; no new Vercel variables. Redeploy to the existing Vercel project. |

**Exit:** with the replay day published, AI Insights lists real NH-10 segments (at most 10 alerts); a citizen or rider session cannot reach any of it; a forced failed workflow run appears in PMO Alerts and can be acknowledged.

## 8. Phase 4: Citizen app `janrakshak_user` (M to L, about 1.5 weeks)

| Task | Detail |
|---|---|
| 4.1 Models | `lib/features/ml/ml_models.dart`: `MlStatus`, `MlState` (live, replay, stale, unavailable, signed_out), `MlTier`, `RouteMlRisk`, `MlSegment`. `fromJson` tolerant of missing fields. |
| 4.2 Repository | `ml_repository.dart`: calls `ml_status`, `get_citizen_route_ml_risk`, `get_citizen_ml_segments` through `Supabase.instance.client.rpc`, 15 s timeout, same style as `feed.dart`. |
| 4.3 Providers and cache | `ml_providers.dart` (Riverpod 3): status provider (refetch on sign-in, connectivity return, every 10 minutes), route-risk provider per route, map-layer provider. Cache the last good result and its `fetchedAt` in Hive (`Store.settings`); when the fetch fails show the cached data as **stale** with its date. |
| 4.4 RiskLayer | `ml_risk_layer.dart` implements `RiskLayer` (`intersectsRoute`, `segmentsToAvoid`, `getDivertedRoute`); the trip planner uses it in place of `FeedRiskLayer` for the model-driven part, keeping feed hazards as they are. A diversion is only ever **offered**, never applied silently. |
| 4.5 UI | Route risk chip and worst-segment line in the trip planner; a home-screen status chip; an optional map layer of alert and review segments with the coverage outline; an "outside model coverage" state; a "model covers X% of this route" line. |
| 4.6 Wording rules | Rank by percentile ("riskier than N% of corridor roads today"); never show a probability; always show the Replay chip with the rainfall date; label items "ML · final_v3 (experimental)"; at most 10 ML items; no push notifications in replay. |
| 4.7 Tests | JSON parsing for every state; stale and offline mapping; `MlRiskLayer` against a fake repository using the existing NH-10-style route fixtures; widget tests for the chips. |
| 4.8 Build | `flutter build apk --release`; install on a device and the emulator. Users need one app update; afterwards the published day changes server-side with no release. |

**Exit:** an NH-10 trip shows the same date, model version, alert count and worst segment as the website; a Guwahati to Shillong trip shows "outside coverage"; airplane mode shows cached data as stale.

## 9. Phase 5: Acceptance and operations (S, about 2 days)

| Task | Detail |
|---|---|
| 5.1 Parity test | One script queries the same NH-10 route as an officer (web client) and through the citizen RPC; assert equal `run_id`, `bundle_hash`, `n_alert`, `max_percentile`. |
| 5.2 Security sweep | Grep the release APK and web `dist/` for `service_role`, DSNs, tokens and the `ml_publisher` password. Rotate the service-role key that was pasted into a previous session (basemap tool) before go-live. |
| 5.3 Failure rehearsal | Break a run on purpose (bad date); confirm the PMO Alerts entry, acknowledge it, and confirm GitHub's email. Confirm no secrets appear in the event text. |
| 5.4 Approval rehearsal | Attempt a `live` publish before approval (must fail), approve a hash as PMO, attempt with a different hash (must fail); revoke. |
| 5.5 Rollback drill | Publish a second replay day, then `publish current --date <first day>`; confirm both apps follow. |
| 5.6 Liveness | A weekly reminder to open the site (Free plans can pause when idle) and a check that `ml_status()` responds. |
| 5.7 Credentials | Rotate the PMO account password and email (weak password and suspect address, per earlier notes) because it is now the only failure-alert recipient. |
| 5.8 Documentation | Update `README.md` (roles, ML scope, quick start), `ML_INTEGRATION_PLAN.md` status, the SRS ML rows; add a short runbook (how to publish a replay day, roll back, read PMO alerts). |
| 5.9 Clean-up | Only now, and only if Phase 0 verification holds, archive or remove the stale `project ` folder and its dangling gitlink. |

**Definition of done:** replay day visible in both apps and the PMO card; capped at 10 alerts; failure path reaches PMO; live mode blocked until PMO approval; SQL and Flutter tests pass and the web build succeeds; security sweep clean.

---

## 10. Sequencing and effort

0 → 1 → 2, then 3 and 4 in parallel, then 5. One developer: about 3 to 4 weeks (Phase 0 about 1 day, Phase 1 about 3 to 4 days, Phase 2 about 4 days, Phase 3 about 4 days, Phase 4 about 1.5 weeks, Phase 5 about 2 days).

## 11. Risks

| Risk | Mitigation |
|---|---|
| Replay read as current conditions | Persistent Replay chip and rainfall date in both apps; `mode` stored per run; no push while replaying. |
| Model is "DEV champion, not evaluated on the locked split" | "Experimental" label; rank-only wording; lineage gate in Phase 0; PMO approval required before any live use. |
| Most NE users see "outside coverage" | Coverage % and outline everywhere; retraining tracked separately. |
| Free plan limits (500 MB DB, idle pausing) | Two runs kept; size measured in 1.7; weekly liveness check; upgrade if the numbers do not fit. |
| PMO alerts are passive (nobody is pushed a message) | GitHub failure email as second channel; optional email or SMTP later. |
| Failure cannot be recorded if the DB is unreachable | GitHub failure email is the only signal in that case (documented). |
| Route matching attaches a parallel road (centroids only) | Buffer tuning in 2.7; show the worst segment on the map for review. |
| Alert fatigue | Fixed cap of 10, human promotion only. |

## 12. Later (not in scope)

Live rainfall feed (CHIRPS-preliminary or IMERG-Early with a backtest), daily scheduled scoring, explanations of top risk factors, feedback from verified incidents, GeoServer risk layer, retraining for the rest of the North East, and an email or SMS channel for PMO alerts.
