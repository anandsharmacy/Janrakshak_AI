# DATA_DECISIONS — Stage 2 (labeling → split)

Every judgment call in the data pipeline, with the reason. You will be asked to
defend these. Numbers below are what the current `conf/config.yaml` produces; see
`data/processed/manifests/*.json` for the exact run.

---

## 0. Framing

- **Task:** per-road-segment-per-day binary classification — *will this segment be
  disrupted (closed/restricted) by a rainfall-triggered landslide or flood?*
- **Headline metric is ranking, not AUC.** After filtering we have ~173 usable
  events / ~115 space-time clusters / 1 verified road closure. That is far below
  the ~200-dated-events line where classification accuracy is defensible, so the
  primary metric is **precision@k / average-precision on spatially-held-out data**
  ("did we rank the segment that actually failed near the top that day?").
- **Unit N is clusters, not rows.** 9,387 positive segment-days come from ~115
  independent space-time clusters. Report both; never quote row count as sample size.

## 1. Label sources & tiers

| Source | Role | Notes |
|---|---|---|
| `road_segment_disruption_labels.csv` | **gold** | the 1 verified (segment, date, closed) record — anchors the test set |
| `corridor_landslides.csv` (26) | silver/bronze | pre-snapped, place-level accuracy |
| `glc_chickens_neck_bbox.csv` — COOLR/GLC (200, 2007–2017) | silver/bronze | rain-triggered only; 1–50 km location accuracy |
| `corridor_disruption_events.csv` — reliefweb (58 in-bbox dated) | bronze | mixed hazards; place-level |
| `corridor_flood_extents.gpkg` — Dartmouth (97) | **off for v1** | whole max-inundation extent × multi-week span explodes the positive count and is low confidence; v2 uses per-day Sentinel-1 inundation |

**Tiering** (`assign_tier`): gold = verified, or road-explicit hazard with ≤1 km
accuracy. silver = ≤5 km accuracy. bronze = coarser. Tier sets the confidence prior
(1.0 / 0.75 / 0.40).

## 2. Filters applied to events

- **Temporal gate 2005-07-01.** CHIRPS starts 2005-01-01; we require lead time for
  antecedent + climatology features. Drops pre-2005 events (all Dartmouth-only).
- **Hazard filter:** keep `landslide / flood / *road* / mudslide / debris`; hard-drop
  `EQ / earthquake / TC / cyclone` (187 + 15 rows). Earthquake/cyclone disruptions
  have a different causal mechanism that our rainfall+terrain features cannot learn —
  including them injects unlearnable noise.
- **GLC trigger filter:** keep rainfall mechanisms only (`downpour / rain /
  continuous_rain / monsoon / flooding / tropical_cyclone / unknown`); drop
  `construction` etc.
- **Accuracy cap 25 km.** Coarser events snap to too much of the corridor to be useful.
- **Result:** 285 raw rows → 220 after filter → **178 after spatio-temporal dedup**
  (merge within 2 days & 5 km, keep the most precise, record `merged_event_ids`).

## 3. Positive construction (`snap_positives`)

- Each event snaps to every road segment whose **centroid** is within
  `max(location_accuracy, 500 m)`, capped at the 20 nearest.
- **Confidence = tier_prior · exp(−d / radius) · susceptibility_factor.**
  - distance decay reflects genuine location uncertainty.
  - `susceptibility_factor ∈ [0.5, 1.5]` (landslide events only): among the
    candidate segments, up-weight the ones on terrain that can actually fail
    (static slope/lithology/stream percentile). This resolves location ambiguity
    toward physically plausible segments instead of spreading it uniformly.
- **Persistence window = 2 days.** A road stays closed after the trigger; event
  date + {1, 2} days are also positive, at 0.8× confidence. Ablate `persistence_days`.
- **5 of 178 events produce 0 labels** — precise GLC points with no mapped road
  within 500 m. Left as-is: no road ⇒ no road-disruption label (also flags OSM gaps).
- **Segment-day collapse:** one row per (segment, date), keeping the best tier /
  highest confidence.
- **Output:** 9,387 positive segment-days, 2,011 distinct segments, mean confidence ≈ 0.39.

## 4. Negative construction (`build_negatives`) — case-control, NOT "everything else"

Under-reporting means an unreported segment-day is *not* a confirmed negative.
We build **strong negatives** only, in two strata (both > 2 km from *any* hazard):

1. **Easy (~55%)** — low-susceptibility-tercile segments, far from events (plains).
   Teaches the gross "plains are safe" signal.
2. **Hard / matched (~45%)** — the **2–25 km "donut" around positive events**,
   restricted to segments whose susceptibility matches the positives
   (`susceptibility_q ≥ P10 of positives`). Same hill terrain, same region, same
   difficulty — *not* the road that failed. Result: 75% of hard negatives are in
   the hills (lat > 26.9) vs 76% of positives — a genuine matched control group,
   so the model cannot separate classes on elevation / "is this the Darjeeling
   hills" and must use rainfall + local terrain. This is up-front hard-negative
   mining and it is the single most important robustness fix in Stage 2.
3. **Season-matched dates:** 60% monsoon (Jun–Sep), 40% uniform, 2005–2026 — so
   the model learns *rainfall × terrain*, not "June 2012 = disruption".

- **Ratio 10:1** (not the true ~10⁴:1). Extreme imbalance wastes model capacity on
  trivial negatives and destabilises calibration. Recover the true base rate in
  Stage 3 with a **prior-correction** step on predicted probabilities, then calibrate
  (isotonic) on a held-out fold.
- Negatives never collide with a positive segment-day (checked).
- **Pool:** 100,119 segments → 93,865 negative rows.
- **PU-learning variant** (treat unlabeled as unlabeled) is a planned Stage 3
  robustness check; if PU and case-control agree on the segment ranking the result
  is defensible.

## 5. Two independent weight levers (do not conflate)

- `label_confidence` / `sample_weight` — encodes **label noise** (down-weights
  uncertain snapped positives). Set here in Stage 2.
- `scale_pos_weight` / `class_weight` — encodes **class imbalance**. Set in Stage 3,
  on top of the sample weights.

## 6. Preprocessing (`build_panel`, `preprocess/transformers.py`)

- **Leakage firewall:** every rainfall feature uses a cutoff of `date − 1 day`
  (`FORECAST_HORIZON_DAYS = 1`) — the model predicts a disruption purely from
  rainfall known the day before. Event-history counts are lagged ≥ 30 days.
  All scaling / imputation / encoding is fit **inside the CV loop**, never in
  `build_panel`.
- **SoilGrids nodata:** an all-zero soil vector (13,501 segments) is nodata, not
  data → set to NaN + `soil_is_missing` flag. SoilGrids integer conventions undone
  for EDA sanity (÷10 for %, ÷100 for bulk density).
- **Rainfall features:** antecedent sums 1/3/7/15/30 d, decayed API (30 d, 0.92),
  days-since-rain, max-1d-in-3d, and **intensity–duration threshold ratios**
  `I_obs / (5.8294 · D^−0.4141)` for 1/3/7 d (NE-Himalaya TRMM coefficients) +
  binary exceedance flags. These bake the published empirical thresholds in as
  features, not hard rules.
- **Aspect / day-of-year:** sin/cos encoded (circular).
- **CHIRPS grid:** ~0.25° here; nearest-cell distance p95 ≈ 16 km. Fine for
  antecedent indices, weak for short-duration intensity in steep valleys — noted.
- **Column roles** are declared in `conf/feature_spec.yaml`; IDs
  (`nearest_river_id`, `hydrobasin_id`) are excluded from the model.

## 7. Augmentation

Deliberately minimal — ~115 positive clusters cannot support synthetic expansion
without inflating CV. In the pipeline: location-radius spreading (already in
snapping) and season-matched negative jitter. SMOTE-NC / feature-noise / mixup are
**ablation-only** behind flags, off by default. No augmentation is ever applied
before the split.

## 8. Splits (`make_splits`) — never random k-fold

Spatial autocorrelation inflates AUC badly (published: 0.948 → 0.890 under spatial
CV); with ~115 clusters it would be worse.

- **Primary — spatial block CV.** 0.25° (~25 km) grid → 96 blocks, 31 with
  positives. GroupKFold-style over blocks (a block is never split), balanced by
  positive count. Training rows within **5 km** of a validation block are marked
  `buffer` and dropped from that fold's training set.
- **Group integrity:** an event snaps to many segments that can straddle a
  boundary, so every positive row of an event is pinned to that event's **modal
  block** and **earliest date**. An event is therefore never split across
  train/val/test (enforced by `tests/test_no_leakage.py`).
- **Secondary — out-of-time.** train ≤ 2015 / val 2016–2018 / test 2019+.
  ⚠️ COOLR/GLC stops in 2017, so the temporal test also carries a **label-source
  shift** (reliefweb-dominated), not just a time shift. It is the hardest,
  most deployment-realistic estimate; expect lower numbers and report them honestly.
- **Tertiary — Leave-One-Event-Cluster-Out.** `event_cluster_id` from DBSCAN on
  (lon, lat, time-bucket); 115 clusters. Answers "would we have flagged this real
  event?" — the most persuasive demo metric.
- **Locked final test** (`final_test`): year ≥ 2019 **OR** in a randomly chosen
  pair of held-out positive blocks **OR** gold-tier. ~40k rows / ~1.5k positives.
  Touch once, at the very end. No HPO or threshold decision may see it.
- **Nested CV for Stage 3:** outer = spatial blocks (reporting); inner = spatial
  GroupKFold on training blocks (HPO + threshold).

## 9. Known weaknesses (say these before a judge finds them)

1. **1 verified label.** Everything else is weak/silver. Mitigation: tiered
   confidence weights + ranking metrics + honest spatial/temporal CV.
2. **Positive labels are under-reported** (NER inventory incompleteness) → true
   recall is underestimated.
3. **Label-source shift over time** (GLC → reliefweb) confounds the temporal split.
4. **CHIRPS is ~25 km & daily** — smooths valley extremes, no sub-daily intensity.
5. **Centroid-based spatial joins** (segment↔hazard, segment↔flood) — segments are
   short (median ~150 m) so error is small, but it is an approximation.
6. **Terrain confound** (positives in the hills, plains are the obvious negative).
   Mitigated by the matched hard-negative donut (§4.2) + spatial block CV, but
   still verify in Stage 3: check permutation importance of `elevation_mean` /
   latitude proxies, and that spatial-CV precision@k ≫ a terrain-only baseline.
