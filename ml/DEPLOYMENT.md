# DEPLOYMENT — Stage 11: production inference for `final_v3`

How the Stage 10 champion is served, which optimizations were adopted and which were
rejected, and the measurements behind each decision. Every number here is measured
on the benchmark machine (Apple M2 Pro, 10 cores, 16 GB) unless marked otherwise.
Raw results are in `reports/stage11/`.

> **Recommended production configuration:** `final_v3`, **unmodified** (LightGBM 4.7.0
> native, all 1,199 trees, float64), served from a **precomputed daily corridor batch**
> with a thin read API, on **one small CPU VM (4 vCPU / 8 GB), no GPU.** The only
> optimizations adopted are in the *pipeline* (feature store, numpy input path, JSON
> calibrators): 4.8× faster end-to-end, 40× faster per request, 234 MB less memory,
> with **bit-identical** outputs. Every *model* optimization tested was rejected or not
> needed. §8 has the full comparison.

---

## 1. Deployment strategy

### What the product actually needs

| requirement | value | source |
|---|---|---|
| population | 309,042 road segments, scored **once per day** | corridor definition |
| input freshness | rainfall through the day before (horizon = 1 day) | Stage 2 contract |
| consumer | routing layer: per-edge risk for `W = dist·(1 + λ·P)` | product |
| batch window | < 300 s per corridor pass | deployment gate |
| what to ship | the **ranking**; probability with a caveat; steep → human review | Stage 9 |

This is a **daily batch problem with a read-heavy lookup API**, not a real-time
inference problem. The model runs once a day in about 1 s; everything the routing
layer asks is a lookup.

### Target: one CPU VM (cloud or on-prem server)

| option | verdict | why |
|---|---|---|
| **CPU server / cloud VM** | **chosen** | a whole corridor pass is 0.76 s on 8 threads or 4.5 s on 1. The gate has 60–400× headroom |
| local GPU / TensorRT | rejected | tree ensembles are memory-bound traversals, a GPU pays off only at millions of rows/s sustained, and there's no NVIDIA GPU to measure on anyway (§2) |
| edge / mobile | not needed | nothing runs on a device; the routing service calls the API. If an offline edge copy is ever needed, §2 has the measured options |
| serverless | not recommended | the value is a daily table plus a sub-2 ms lookup; cold starts would dominate |

### Architecture and data flow

```
 rainfall feed (CHIRPS-prelim / IMERG-Early / IMD, per 0.05° cell)
      │  daily CSV: date, cell_id, precip_mm
      ▼
 sih_ml.serve.feed ──► deploy/featurestore/          static_matrix.npy (309,042 × 45, mmap)
   validates: every     ├─ rainfall.parquet          segments.parquet (cell index, slope)
   cell, no gaps,       └─ manifest.json             built once from Stage 2 sources
   0 ≤ mm ≤ 1000
      │
      ▼  systemd timer, 06:30 IST, hourly retry          (deploy/ops/sih-daily.*)
 sih_ml.serve.batch --date D
   1 refuse if rainfall through D-1 is missing   (exit 3 — the Stage 10 D1 lesson)
   2 X = static block + 119 cell rainfall rows gathered + season   0.06–0.19 s
   3 raw = booster.predict(X)                                       0.76 s
   4 p = per-slope isotonic (JSON tables); percentile; tier         0.08 s
   5 atomic write deploy/scores/date=D/{scores.parquet,run.json}   0.15 s
   6 batch.prom (node-exporter textfile): success time, tiers, drift
      │
      ▼
 gunicorn (4 × gthread workers, preload)                  sih_ml.serve.api:create_app()
   GET  /v1/scores?date&segment_id=…   lookup in the day's table   ◄── routing layer
   GET  /v1/alerts?date&tier&limit     top-N of a tier             ◄── ops dashboard
   POST /v1/score                      on-demand / what-if rainfall (≤ 5,000 segments)
   GET  /healthz /readyz /v1/model /metrics
```

The bundle (`deploy/bundles/<version>/`) is immutable and hash-verified. The feature
store and scores are mutable data. The API process never writes anything.

---

## 2. Model optimization — evaluated one by one, against the original

"Original" is `final_v3` exactly as trained: LightGBM text model, 1,199 trees, float64,
pandas input, pickled scikit-learn calibrators. Accuracy is measured the Stage 10 way
(5 spatial folds × 3 seeds, paired, A/A-calibrated non-inferiority, guardrails;
`reports/stage11/accuracy_variants.csv`). Runtime is measured per runtime in a fresh
subprocess on the real 309,042-row corridor matrix (`reports/stage11/runtimes.json`).
**Parity** compares each runtime's corridor output with the original's.

| technique | accuracy (Δ AP vs original) | corridor parity | speed | verdict |
|---|---|---|---|---|
| **numpy input path** (feature store) | identical | **bit-identical** (Δ = 0) | 40× per row (1.25 → 0.031 ms); same bulk speed | **ADOPTED** |
| **JSON calibrators** (replace sklearn pickles) | identical | **bit-identical** | — | **ADOPTED**: removes sklearn and pickle from serving |
| **batch inference** (whole corridor, one call) | identical | identical | best throughput at batch = corridor | **ADOPTED**: it *is* the architecture |
| thread tuning | identical | identical | 4.50 s (1 thread) → 1.22 s (4) → 0.76 s (8) | **ADOPTED**: batch uses all cores; API workers use 1 thread each |
| pruning = tree truncation to 50% | −0.0024, non-inferior | not measured at 50% | ~2× | not adopted: see the 25% row |
| pruning = tree truncation to 25% (300 trees) | −0.0030, non-inferior | **Spearman 0.851, top-1% overlap 76%** | 4.0× | **REJECTED**: re-ranks the corridor (below) |
| pruning = truncation to 10% | −0.0124, **fails** (worst region −0.064, steep ROC −0.013) | — | ~10× | **REJECTED** |
| FP32 (thresholds + leaves + inputs) | −0.0000 | 2 rows > 1e-6 (via ONNX) | no CPU FP32 path in LightGBM | not needed |
| FP16 quantization | +0.0001 | not measured as a runtime | **no FP16 kernel exists for CPU tree inference** | **AVOID**: nothing to gain; float16 scores move up to 0.005 |
| INT8 quantization | not applicable | — | no INT8 tree runtime; the model is 0.71 MB | **AVOID** |
| knowledge distillation (300-tree student) | −0.0046, non-inferior | — | ≈ truncation | **REJECTED**: dominated by plain truncation at the same size, with more pipeline to maintain |
| **ONNX Runtime** 1.30 (opset 15) | = FP32 row | **2 / 309,042 rows > 1e-6** (max 0.0012), top-1% identical | 1.5× on 1 thread (2.92 s), equal on 8 (0.76 s); **peak RSS 1,124 MB vs 303 MB** | not adopted; **the right choice only if the serving language stops being Python** |
| **Treelite** 4.1.2 / tl2cgen 1.0 (compiled C) | — | **2,795 rows differ, up to 0.58**; top-1% overlap 98.8% | 8.5× on 1 thread (0.53 s), 7× on 8 (0.11 s) | **REJECTED**: silently wrong on segments with missing inputs |
| TensorRT / GPU (FIL, Hummingbird) | — | — | no NVIDIA GPU on the benchmark host | **NOT MEASURED; AVOID**: a 1 s daily CPU job has nothing to gain from a GPU |
| operator/kernel tuning | — | — | LightGBM's C++ traversal is already the kernel; the only knobs are threads and input dtype, both measured above | done via the adopted rows |

### The two findings that decided the model side

**1. Non-inferior on the evaluation set is not equivalent on the deployment
population.** Truncating to 300 trees passed the Stage 10 non-inferiority rule on AP
(−0.0030). On the full corridor, though, its ranking correlates with the original at
only **0.851**, and **24% of the top-1% segments change**. AP is measured on the
labelled case-control panel. It cannot see how a model re-orders the 300k unlabelled
segments that the product actually ranks. A compressed model must therefore pass
**both** tests: non-inferior accuracy on labelled data, and ranking parity on the
corridor. Truncation fails the second. Since the corridor pass already fits the
batch window about 60× over at 4 cores, there is no reason to take that risk.

**2. A conversion that is fast but not exact is a bug, not an optimization.**
Treelite is the fastest runtime measured, 8.5× faster on one thread. But it disagrees
with LightGBM on 2,795 corridor rows, by up to 0.58 in probability, almost all of them
rows with a missing numeric input (soil NODATA covers 4.4% of the corridor). The
behaviour was investigated and three explanations ruled out:

- **categorical missing values:** 0 of the differing rows have a missing category;
- **NaN treated as zero:** every affected feature already has NaN-aware splits;
- **frontend/runtime version skew:** re-measured with aligned versions, same 2,795
  rows.

The root cause is not isolated, and the conclusion doesn't need it. The runtime
silently changes scores on real inputs, so it is disqualified regardless of speed.

---

## 3. Accuracy vs efficiency — before and after

Original = the training-time path (reload sources, per-segment Stage 2 features, pandas,
pickled calibrators). Optimized = the production path. Same day (2025-08-15), same
machine, default threads; `reports/stage11/benchmark_pipeline.json`.

| | original pipeline | **optimized pipeline** | change |
|---|---|---|---|
| **outputs** (309,042 raw scores + probabilities) | reference | **max \|Δ\| = 0.0** | bit-identical |
| end-to-end, one day | 5.03 s | **1.05–1.22 s** | 4.1–4.8× |
| · load sources / cold start | 3.36 s | **0.036 s** (mmap) | 93× |
| · rainfall features | 0.74 s (per segment) | **0.06–0.19 s** (per cell, 119 cells) | 4–12× |
| · model predict | 0.79 s | 0.76 s | same model, same kernel |
| single-row latency (1 thread, p50) | 1.254 ms | **0.031 ms** | 40× |
| 100-row latency (p50) | 2.82 ms | **1.49 ms** | 1.9× |
| peak memory, corridor predict | 537 MB | **303 MB** | −234 MB |
| model artifact | 710 KB + 5 pickles | 710 KB + 16 KB JSON | no sklearn, no pickle |
| runtime dependencies | + scikit-learn, geopandas… | numpy, pandas, pyarrow, lightgbm, pyyaml, gunicorn | image env 271 MB |
| 30-day backfill | — | **1.08 s/day** | |

### Acceptable trade-offs (the rules applied above)

| dimension | acceptable | why this line |
|---|---|---|
| accuracy | non-inferior under the Stage 10 rule: Δ AP ≥ −min(A/A floor 0.0124, 0.01), < 4/5 folds worse, guardrails held | the same bar every model change in this project has met |
| **ranking parity on the corridor** | **Spearman ≥ 0.999 and top-1% overlap ≥ 99%** vs the original | the product ships a ranking; this is the population it ranks |
| probabilities | bit-identical, or max \|Δ\| ≤ 1e-6 | calibrated values feed routing weights |
| latency | batch < 300 s (gate); lookup p99 < 100 ms | daily cadence; interactive routing |
| memory | < 2 GB per API host | a small VM |

On these rules only exact or near-exact paths qualify: native LightGBM (any thread
count) and ONNX Runtime. Nothing faster would buy anything, because the constraint
that binds is the rainfall feed, not compute.

---

## 4. Inference pipeline — what was optimized and why it is safe

1. **Split the input by change rate.** 27 static columns are encoded once
   (categoricals are mapped to the model's own level indices, with unseen levels →
   NaN, exactly as LightGBM does for pandas input) into a 106 MB float64 matrix that is
   memory-mapped, so gunicorn workers share its pages.
2. **Compute rainfall per CHIRPS cell, not per segment.** 309,042 segments sit in 119
   cells. The 14 rainfall features are computed 119 times, **by the Stage 2 function
   itself** (`rainfall_features`), and gathered to rows with one fancy-index. The
   what-if path uses the same function on the caller's 61-day history.
3. **Skip pandas at inference.** A float64 numpy matrix goes straight to LightGBM's C
   API. float32 was measured and *also* matched on these rows, but float64 is kept
   because matching is not guaranteed for every value.
4. **Calibrators as lookup tables.** The fitted isotonic knots → `np.interp`,
   bit-identical to the sklearn pickles (tested on 20,000 random inputs).
5. **Reuse the daily buffer; write atomically.** One preallocated 309k × 45 buffer per
   process. Output goes to a temp dir and is `rename`d, so readers never see half a day.
6. **Cache at the API.** Day tables are loaded lazily into an LRU of 3 days.
   Rainfall is reloaded in-worker when the feed file changes: with preload, a gunicorn
   HUP would re-fork workers from the master's stale copy.

**Safety net.** `tests/test_serve.py::test_feature_parity_with_panel` rebuilds every
feature of training rows on 40 sampled dates from the serving store and compares all
45 columns, NaN-aware. `test_predictions_bit_identical_to_training_path` requires
`array_equal` against the training predictor. An ad-hoc run on 150 dates / 2,033 rows
was also exact.

---

## 5. Production deployment

### API contract

| endpoint | purpose | notes |
|---|---|---|
| `GET /v1/scores?date=D&segment_id=a,b,…` | the routing layer's call | ≤ 5,000 ids; unknown ids listed, not fatal; `404 not_scored` if the day has no batch |
| `GET /v1/alerts?date=D&tier=alert\|human_review&limit=N` | ops dashboard | sorted by risk; `n_in_tier` returned |
| `POST /v1/score` `{date, segment_ids, rain_mm?}` | on-demand, or **what-if** with a 61-day rainfall scenario | `422 rainfall_not_available` if the feed doesn't cover `date−1` and no scenario is given |
| `GET /v1/model` | manifest (version, lineage, file hashes), policy, feature-store build | |
| `GET /healthz` | liveness | always 200 while the process runs |
| `GET /readyz` | readiness: bundle verified, feed lag ≤ `SIH_MAX_FEED_LAG_DAYS`, a scored day exists | **503 in this repo**: CHIRPS ends 2025-12-31, there is no live feed |
| `GET /metrics` | Prometheus text | request counts and latency histograms per route, feed lag, model info |

Every response carries `X-Model-Version` and `X-Request-ID`. Every body carries
`primary_output: "risk_percentile"` and the probability caveat (calibrated on a
case-control panel; does not transfer across regions without local recalibration).

**Output per segment:** `raw_score`, `p_calibrated`, `risk_percentile` (rank among all
corridor segments that day), `steep`, `tier` ∈ {`none`, `alert`, `human_review`},
`tier_rank`. Steep segments are **never** `alert`; above threshold they become
`human_review` (Stage 9 §D).

### Validation and error handling

| check | where | response |
|---|---|---|
| rainfall window through `date−1` present | batch, `/v1/score` | refuse: exit 3 / `422 rainfall_not_available` — **never** score a truncated window |
| 61-day history available | same | `422 rainfall_history_too_short` |
| scenario rainfall: exactly 61 values, finite, 0 ≤ mm ≤ 1000 | `/v1/score` | `400` / `422 bad_rainfall` (NaN is refused, not imputed) |
| segment ids: deduplicated, ≤ 5,000, unknown ones reported | lookups, `/v1/score` | `413`, or a partial result with `unknown_segment_ids` |
| unseen categorical level (new OSM `surface` etc.) | feature store | encoded as missing, exactly as training; counted in `run.json` (88 cells on the current corridor) |
| model output finite and in [0, 1] | batch, API | `500 non_finite_output` — a model fault must not look like a score |
| bundle files match manifest sha256; model features and categories match the schema | load | refuses to start |
| truncated or otherwise re-derived model with stale calibrators | load | refuses (`benchmark_only`) unless `SIH_ALLOW_BENCHMARK_BUNDLE=1` |
| feature store built for a different model schema | load | refuses to start |
| malformed JSON / wrong method / unknown route | API | `400` / `405` / `404`, JSON body, no traceback |

### Logging and monitoring

- **Logs:** one JSON line per request (`rid`, method, path, status, ms), per batch run
  (`batch_scored` or `batch_refused` with code) and per rainfall reload.
- **run.json** per day: bundle version + hash, feature-store schema hash, per-stage
  timings, tier counts, data-quality counts, drift, score quantiles. Any score can be
  traced to exactly what produced it.
- **Rainfall drift**: a trailing 30-day window of all cells vs the same month's
  climatology, with the warning threshold set at the **99th percentile of the same
  statistic over the 2005–2025 record** for that month. The first design (one day's
  cells) fired on an ordinary monsoon day (PSI 1.85). Cells under one weather system
  aren't independent samples. Fault-injection results (`reports/stage11/drift_fault_injection.csv`),
  out of 5 test dates:

  | injected fault | caught |
  |---|---|
  | none (clean feed) | 0/5 false alarms |
  | all zeros | 5/5 |
  | mm↔inch unit error | 5/5 |
  | stale feed | 5/5 |
  | ×0.5 scaling | 4/5 |
  | ×2 scaling | 2/5 |

  It detects **broken feeds**, not subtle bias. Subtle bias needs the P4 recalibration
  loop.
- **Alert rules** (`deploy/ops/alerts.yml`): feed lag > 2 days (page), no batch for
  36 h (page), 5xx > 1% (page), lookup p95 > 100 ms (ticket), not ready 15 min (ticket).

### Scalability and concurrency

- **API:** stateless processes. Scale up with workers (≈ cores); scale out with
  replicas behind a load balancer, all mounting the same read-only feature store and
  scores (a shared volume or an object-store sync). Measured capacity: §6.
- **Batch:** one instance, idempotent (skips a day already scored by the same bundle),
  1 s/day. Backfills run at ~1 s/day, so a year takes about 6 minutes.
- **Growth headroom:** at 1 thread the model scores 68k rows/s (4.5 s for the corridor);
  a 100× larger corridor would still fit the window on 8 threads (~76 s).

---

## 6. Testing

### Latency and throughput by runtime, batch size and threads

`reports/stage11/runtimes.json`. p50 per call; corridor = 309,042 rows, median of 5.

| runtime | 1 row | 100 rows | 1,000 rows | corridor 1 thread | 4 threads | 8 threads | peak RSS | artifact |
|---|---|---|---|---|---|---|---|---|
| LightGBM, pandas (original) | 1.254 ms | 2.82 ms | 15.5 ms | 4.55 s | 1.25 s | 0.80 s | 537 MB | 710 KB |
| **LightGBM, numpy (production)** | **0.032 ms** | **1.49 ms** | **14.4 ms** | **4.50 s** | **1.22 s** | **0.76 s** | **303 MB** | **710 KB** |
| LightGBM, 300 trees *(rejected)* | 0.017 ms | 0.38 ms | 3.6 ms | 1.12 s | 0.30 s | 0.19 s | 304 MB | 183 KB |
| ONNX Runtime 1.30 | 0.023 ms | 0.97 ms | 9.4 ms | 2.92 s | 0.94 s | 0.76 s | 1,124 MB | 360 KB |
| Treelite / tl2cgen *(rejected)* | 0.017 ms | 0.20 ms | 1.8 ms | 0.53 s | 0.15 s | 0.11 s | 410 MB | 259 KB (native lib) |

### Hardware configurations

| configuration | measured |
|---|---|
| threads 1 / 4 / 8 (≈ vCPU counts) | table above |
| API workers 1 / 2 / 4 / 8 | §6 load tests |
| Python 3.12 (production env, no sklearn) vs 3.14 (dev env) | **bit-identical** scores, all 309,042 segments |
| x86-64 Linux, GPUs | **not measured** — no such host. Run the release checklist's parity step on the target before go-live |

### Load and stress (gunicorn, production config)

Measured under `gunicorn` (4 `gthread` workers, preload_app enabled) on the Apple M2 Pro host (10 cores). Zero errors across all test scenarios (>100k total HTTP requests).

| scenario | endpoint | concurrency | requests/sec | p50 latency | p95 latency | p99 latency | error rate |
|---|---|---|---|---|---|---|---|
| **lookup_1** | GET `/v1/scores` (1 segment) | 1 | 806 | 1.2 ms | 1.4 ms | 1.6 ms | 0.0% |
| **lookup_1** | GET `/v1/scores` (1 segment) | 8 | 2,497 | 2.8 ms | 4.6 ms | 5.3 ms | 0.0% |
| **lookup_1** | GET `/v1/scores` (1 segment) | 32 | 2,548 | 12.2 ms | 17.5 ms | 23.8 ms | 0.0% |
| **lookup_1** | GET `/v1/scores` (1 segment) | 128 | 2,725 | 41.1 ms | 55.2 ms | 57.1 ms | 0.0% |
| **lookup_1** | GET `/v1/scores` (1 segment) | 256 *(stress)* | 2,554 | 93.8 ms | 128.5 ms | 197.8 ms | 0.0% |
| **lookup_100** | GET `/v1/scores` (100 segments) | 1 | 574 | 1.6 ms | 1.9 ms | 2.3 ms | 0.0% |
| **lookup_100** | GET `/v1/scores` (100 segments) | 8 | 1,862 | 3.3 ms | 7.6 ms | 9.2 ms | 0.0% |
| **lookup_100** | GET `/v1/scores` (100 segments) | 32 | 1,897 | 13.3 ms | 25.7 ms | 41.5 ms | 0.0% |
| **alerts** | GET `/v1/alerts` (top 100) | 8 | 1,878 | 3.3 ms | 7.8 ms | 9.5 ms | 0.0% |
| **whatif_100** | POST `/v1/score` (100 segments, custom rain) | 1 | 60 | 15.8 ms | 18.0 ms | 29.1 ms | 0.0% |
| **whatif_100** | POST `/v1/score` (100 segments, custom rain) | 8 | 119 | 64.9 ms | 67.6 ms | 71.5 ms | 0.0% |
| **score_100** | POST `/v1/score` (100 segments, feed rain) | 1 | 19 | 48.2 ms | 59.8 ms | 91.1 ms | 0.0% |
| **score_100** | POST `/v1/score` (100 segments, feed rain) | 8 | 72 | 94.4 ms | 174.8 ms | 275.6 ms | 0.0% |

**Key Observations:**
- **Read throughput:** Read lookups (`/v1/scores` and `/v1/alerts`) saturate at **~2,500 – 2,700 requests/sec** under 4 workers with sub-5 ms median latency up to concurrency 8.
- **On-demand scoring:** On-demand requests (`POST /v1/score`) execute model inference in real time for requested segments and achieve ~70-120 req/s.
- **Stress resistance:** Under 256 concurrent connections (well beyond worker count), zero requests dropped or timed out; latency scaled predictably to ~94 ms p50.

### Accuracy validation against the original

- **Serving path vs training path:** feature parity on sampled training rows (all 45
  columns), `array_equal` predictions, `array_equal` calibration — in `test_serve.py`.
- **Production batch vs original pipeline**, full corridor: max |Δ| = 0.0 on raw and
  calibrated scores.
- **Across environments:** Python 3.12 deploy venv vs Python 3.14 dev venv:
  bit-identical.
- **Every rejected optimization**, with the accuracy and parity numbers in §2.

### Real-world edge cases (all in `tests/test_serve.py`)

Stale feed refused (the D1 case); history too short; scenario rainfall with NaN,
negative, 5,000 mm or the wrong length; unknown and duplicated segment ids; 6,000-id
request (413); malformed JSON; unknown route and wrong method; tampered bundle; a
benchmark-only bundle; unseen categorical levels (counted, graceful); steep terrain
never auto-alerts; **more rain never lowers risk**, end-to-end through the what-if
API at 1×, 1.5×, 2× and 4× rainfall; drift detector against injected faults; batch
idempotence and atomic writes; every segment scored exactly once.

---

## 7. Implementation

### Layout

```
src/sih_ml/serve/
  bundle.py        self-verifying model bundle (build + load), JSON isotonic calibration
  featurestore.py  static block + per-cell rainfall + season → model matrix
  predictor.py     raw → calibrated → tier (Stage 9 policy); percentiles
  validate.py      input rules and error codes
  batch.py         daily corridor job (idempotent, atomic, run.json, batch.prom)
  api.py           WSGI app + create_app() for gunicorn + stdlib dev server
  feed.py          rainfall feed ingestion into the store
  monitor.py       Prometheus metrics, calibrated rainfall drift
  build.py         registry champion → bundle + feature store
  benchmark.py     accuracy of compression variants, pipeline cost
deploy/
  requirements.txt  minimal serving deps (pinned lightgbm)
  gunicorn.conf.py  workers / keep-alive / preload
  Dockerfile        python:3.12-slim image (NOT built here — no Docker on the host)
  ops/              sih-daily.sh, systemd service + timer, sih-api.service, alerts.yml
  bundles/<ver>/    generated: model.txt, calibration.json, schema.json, policy.json,
                    reference.json, manifest.json   (+ `current` symlink)
  featurestore/     generated: static_matrix.npy, segments.parquet, rainfall.parquet
  scores/           generated: date=YYYY-MM-DD/{scores.parquet, run.json}, batch.prom
scripts/
  bench_runtimes.py export | run   LightGBM / ONNX / Treelite on the corridor
  load_test.py, load_suite.py      closed-loop load + stress under gunicorn
tests/test_serve.py                serving contract
```

### Build, convert, benchmark

```bash
make bundle                          # champion → deploy/bundles/final_v3 + feature store (~6 s)
make deploy-venv                     # .venv-deploy from deploy/requirements.txt
make bench                           # accuracy of truncation / FP32 / FP16 / distillation + pipeline cost
# runtime comparison (needs onnxruntime onnxmltools treelite==4.1.2 tl2cgen in a separate env)
python scripts/bench_runtimes.py export --date 2025-08-15 --out /tmp/corridor.npy
python scripts/bench_runtimes.py run --matrix /tmp/corridor.npy --bundle deploy/bundles/current \
       --out reports/stage11/runtimes.json
```

The ONNX conversion used, for the record (not in the serving path):
`onnxmltools.convert_lightgbm(booster, initial_types=[("input", FloatTensorType([None, 45]))], zipmap=False, target_opset=15)`.

### Run locally

```bash
make bundle && make deploy-venv
make score DATE=2025-08-15           # writes deploy/scores/date=2025-08-15/
SIH_MAX_FEED_LAG_DAYS=100000 make serve-dev      # the repo has no live feed
curl 'localhost:8080/v1/scores?date=2025-08-15&segment_id=SEG291652'
curl -XPOST localhost:8080/v1/score -d '{"date":"2025-08-15","segment_ids":["SEG291652"],"rain_mm":[0,…61 values…]}'
```

### Production (systemd on a VM)

```bash
# once
sudo useradd --system sih && sudo mkdir -p /opt/sih-ml && sudo chown sih /opt/sih-ml
rsync -a src conf deploy/requirements.txt deploy/gunicorn.conf.py deploy/ops /opt/sih-ml/
rsync -a deploy/bundles deploy/featurestore /opt/sih-ml/deploy/
cd /opt/sih-ml && uv venv -p 3.12 .venv && uv pip install -p .venv/bin/python -r requirements.txt
sudo cp deploy/ops/sih-*.service deploy/ops/sih-daily.timer /etc/systemd/system/
sudo systemctl enable --now sih-api.service sih-daily.timer
```

**Release checklist** for any new bundle:

1. `make stage10`: the champion comes from the loop, never from hand edits.
2. `make bundle` → `pytest tests/test_serve.py` (parity, calibration, contract).
3. On the **target host**: `make score` for 3 known dates and diff them against the dev
   host's outputs (bit-identical expected).
4. Point `deploy/bundles/current` at the new version. The API picks it up on restart;
   the next batch writes with the new bundle hash.
5. Rollback: re-point `current` and restart. Old day tables stay readable because each
   records its bundle.

---

## 8. Final deployment decision

| | original (training path) | **recommended** | ONNX Runtime | truncated 300 trees | Treelite |
|---|---|---|---|---|---|
| accuracy | reference | **identical** (bit) | ≈ identical (2 rows > 1e-6) | non-inferior on AP, **re-ranks the corridor (ρ 0.85)** | **wrong on 2,795 rows** |
| corridor pass, 1 / 8 threads | 4.55 / 0.80 s | **4.50 / 0.76 s** | 2.92 / 0.76 s | 1.12 / 0.19 s | 0.53 / 0.11 s |
| end-to-end daily job | 5.03 s | **1.05–1.22 s** | ~ same | ~0.6 s | ~0.4 s |
| per-request (100 rows) | 2.82 ms | **1.49 ms** | 0.97 ms | 0.38 ms | 0.20 ms |
| peak memory | 537 MB | **303 MB** | 1,124 MB | 304 MB | 410 MB |
| artifact | 710 KB + pickles | **710 KB + JSON** | 360 KB | 183 KB | 259 KB native |
| extra toolchain | sklearn at serve | **none** | converter + ORT | refit calibrators | compiler + treelite |
| hardware | 1 small VM | **1 small VM, no GPU** | same | same | same |
| reliability | pickles, no validation | **hash-verified, refuses bad input** | float32 semantics layer | — | disqualified |

**Deploy:** `final_v3`, unmodified, on LightGBM 4.7.0 via the numpy/feature-store path,
calibrators as JSON. Run the daily batch on all cores and the API as gunicorn with 4
gthread workers × 1 thread, on **one 4-vCPU / 8 GB CPU VM** (x86-64 or ARM64). Add a
second identical VM behind a load balancer only if availability requires it, since
capacity doesn't (§6).

**Why not faster:** the batch window has 60–400× headroom and lookups are sub-2 ms,
so compute is not the binding constraint. **The binding constraints are the rainfall
feed** (freshness, source shift) **and the alert policy** (capacity per day). The
deployment engineering is aimed at those, not at FLOPs.

**Revisit the model-side options when:**

| trigger | option |
|---|---|
| serving must run outside Python (JVM/Go routing service) | ONNX Runtime, after the parity check |
| the corridor grows > 100× | truncation, only with refitted calibrators *and* a passing corridor ranking-parity test |
| an offline edge device is needed | ONNX Runtime, same conditions |
| never, without root-causing the missing-value mismatch | Treelite |

---

## 9. Known limitations — stated, not hidden

1. **No live rainfall feed exists yet.** The store holds CHIRPS final through
   2025-12-31, so `/readyz` is correctly 503 and the service refuses dates after
   2026-01-01. The operational source (CHIRPS-prelim / IMERG-Early / IMD) is a
   distribution shift the model has not seen. The drift monitor catches broken feeds,
   and recalibration on operational history (roadmap P4) is required before
   probabilities are trusted.
2. **Alert volume needs a policy decision.** At the dev-derived threshold, the median
   2025 monsoon day produced **3,502 `alert` and 20,940 `human_review` segments**
   (122 days backfilled). The threshold was fitted on a case-control panel, not the
   corridor. Set a per-day capacity with MDoNER and use `tier_rank ≤ N`.
3. **Not verified here:** the Docker image (no Docker on the host), x86-64 performance
   and parity, and GPU runtimes. The release checklist's step 3 covers the target host.
4. **Model-level limitations carry over unchanged** (REMEDIATION.md,
   CONTINUOUS_IMPROVEMENT.md): steep-terrain transfer, regional calibration, and a
   locked split that has been read twice. Deployment makes the model reliable to
   run; it does not make it more accurate.
