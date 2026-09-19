# 🧠 JanRakshak AI — Machine Learning System Architecture & Technical Masterclass

This document provides a comprehensive technical overview of the Machine Learning subsystem in **JanRakshak AI** (located in [`/ml`](file:///Users/anand/Desktop/JanRakshak%20AI/ml)). It details the mathematical formulation, feature engineering, 11-stage pipeline architecture, model training strategy, leakage firewalls, calibration, and production deployment.

---

## 📌 1. High-Level Problem Formulation

For every road segment \(i\) on day \(t\), the ML system predicts whether a rainfall-triggered disruption (landslide, flood, severe road damage) occurs:

\[
y_{i,t} \in \{0, 1\}, \qquad p = P(y_{i,t} = 1 \mid \mathbf{x}_{i,t})
\]

- **Input Vector (\(\mathbf{x}_{i,t}\))**: 49 features combining satellite precipitation (CHIRPS), terrain topography (DEM elevation, slope, aspect, TRI), soil characteristics, hydrology flow accumulation, and cyclic time markers.
- **Output Score (\(p\))**: A calibrated probability score \([0, 1]\) mapped into operational risk tiers:
  - 🟢 **LOW** (\(p < 0.25\))
  - 🟡 **MODERATE** (\(0.25 \le p < 0.50\))
  - 🟠 **HIGH** (\(0.50 \le p < 0.75\))
  - 🔴 **CRITICAL** (\(p \ge 0.75\))

---

## 🏗️ 2. The 11-Stage Pipeline Architecture

```
                                 DATA PIPELINE & PIPELINE LEAKAGE FIREWALL
┌────────────────────────┐      ┌─────────────────────────┐      ┌─────────────────────────┐
│ Raw Climate & Geodata  │ ───► │  Labels & Panel Parquet │ ───► │ 5-Fold Spatial Block CV │
│ (CHIRPS, DEM, COOLR)   │      │  (labels_v1, panel_v1)  │      │ (5 km buffer leakage)   │
└────────────────────────┘      └─────────────────────────┘      └─────────────────────────┘
                                                                              │
                                 TRAINING, TUNING & REMEDIATION               ▼
┌────────────────────────┐      ┌─────────────────────────┐      ┌─────────────────────────┐
│ Final Model (v3)       │ ◄─── │ Monotonic Remediation   │ ◄─── │ LightGBM GBDT + Optuna  │
│ (Bit-identical reproduce)     │ (Rainfall monotonic +1) │      │ (Weighted Binary Logloss)│
└───────────┬────────────┘      └─────────────────────────┘      └─────────────────────────┘
            │
            │                    PRODUCTION SERVING & SUPABASE PUBLICATION
            ▼
┌────────────────────────┐      ┌─────────────────────────┐      ┌─────────────────────────┐
│ FeatureStore & Predict │ ───► │   `sih-publish` Service │ ───► │  Supabase Postgres DB   │
│ (~1s / 300k segments)  │      │   (Daily Batch Scoring) │      │  (RPCs to Web/Flutter)  │
└────────────────────────┘      └─────────────────────────┘      └─────────────────────────┘
```

---

## 📊 3. Label Construction & Sample Weighting

### 🏷️ 4-Tier Positive Labels
Disruption reports come from global & national databases (COOLR, ReliefWeb, local logs) snapped to candidate road segment geometries:
- **Tier 1 (Gold)**: Field-verified road closures & inspected hazard locations.
- **Tier 2 (Silver)**: High-confidence landslide/flood event clusters.
- **Tier 3 (Bronze)**: Satellite-inferred or news-derived hazard reports.
- **Tier 0 (Negative)**: Case-control negative sampling (low slope, >2 km from hazards, season-matched dates, 10:1 negative-to-positive ratio).

### 📐 Confidence Weight Formula
Each positive sample receives a confidence score \(c_i \in [0, 1]\):

\[
c_i = \min\left(1.0, c_{\text{tier}} \cdot d_{\text{decay}} \cdot s_{\text{factor}}\right)
\]

Where:
- **Distance Decay**: \(d_{\text{decay}} = \exp\left(-\frac{d}{r}\right)\), where \(d\) is distance to hazard centroid and \(r = \max(\text{location accuracy}, 500\text{ m})\).
- **Landslide Susceptibility Factor**: \(s_{\text{factor}} = 0.5 + q_{\text{susceptibility}}\).
- **Training Sample Weight**: \(w_i = \text{clip}(c_i, 0.05, 1.0)\), passed directly into LightGBM weighted objectives.

---

## ⚙️ 4. Feature Engineering (49 Features)

Features are constructed with a strict **Leakage Firewall**: all rainfall features are lagged by at least 1 day (\(t_{\text{cutoff}} = t_{\text{event}} - 1\text{ day}\)).

### 1. Cumulative Rainfall Windows
For windows \(W \in \{1, 3, 7, 15, 30\}\) days:

\[
R_W(t) = \sum_{k=0}^{W-1} P(t-k)
\]

Also computes maximum 1-day rainfall over 3 days: \(R_{\max, 3}(t) = \max\{P(t), P(t-1), P(t-2)\}\).

### 2. Antecedent Precipitation Index (API-30)
Measures soil moisture saturation through exponential decay:

\[
\text{API}_{30}(t) = \sum_{k=0}^{29} P(t-k) \cdot (0.92)^k
\]

Includes a **dry-spell counter** (number of consecutive days with \(< 1\text{ mm}\) rainfall, capped at 60 days).

### 3. Intensity-Duration (ID) Threshold Exceedance
Calculates empirical regional landslide trigger thresholds:

\[
I_{\text{obs}} = \frac{R_D}{24D}, \qquad I_{\text{thr}} = 5.8294 (24D)^{-0.4141}
\]
\[
\text{IDRatio}_D = \frac{I_{\text{obs}}}{I_{\text{thr}}}, \qquad \text{IDExceed}_D = \mathbb{1}[\text{IDRatio}_D > 1.0] \quad \text{for } D \in \{1, 3, 7\}
\]

### 4. Cyclic & Terrain Encoding
- **Aspect Angle (Slope Orientation)**: \(\sin(\theta)\) and \(\cos(\theta)\) to eliminate 0°/360° discontinuities.
- **Day of Year**: \(\sin\left(\frac{2\pi \cdot \text{DOY}}{365.25}\right)\) and \(\cos\left(\frac{2\pi \cdot \text{DOY}}{365.25}\right)\).
- **Terrain & Hydrology**: DEM elevation, slope, TRI (Terrain Ruggedness Index), soil clay/sand content, drainage class, and upstream flow accumulation.

---

## 🌲 5. Model Training & Mathematics

### 1. LightGBM GBDT Objective
The core predictor is a **LightGBM Gradient Boosted Decision Tree (GBDT)** ensemble:

\[
F_M(x) = F_0(x) + \sum_{m=1}^{M} \eta f_m(x)
\]

Optimized using **Weighted Binary Log-Loss**:

\[
\mathcal{L} = -\sum_{i} w_i \left[ y_i \log(p_i) + (1 - y_i) \log(1 - p_i) \right], \qquad p_i = \frac{1}{1 + e^{-F(x_i)}}
\]

To handle severe class imbalance (~8.5% positive rate), \(\text{scale\_pos\_weight}\) is dynamically computed per fold:

\[
\text{scale\_pos\_weight} = \frac{N_{\text{negatives}}}{\max(1, N_{\text{positives}})} \times m_{\text{mult}}
\]

### 2. Monotonic Constraints
To enforce physical reality, monotonic increasing constraints (+1) are assigned to all rainfall volume features:

\[
x_{\text{rain}} \le x'_{\text{rain}} \implies F(x) \le F(x')
\]

*Why?* Higher rainfall must **never** reduce the predicted disruption risk.

### 3. Spatial-Block Cross-Validation (5-Fold)
Standard random k-fold causes severe spatial data leakage because adjacent road segments share the same storm. The pipeline uses **Spatial-Block CV**:
- Geographically partitions the region into spatial blocks.
- Imposes a **5 km buffer strip** around held-out validation blocks where training samples are discarded.
- Uses **event-grouped early stopping** so sibling segment-days from the same disaster event never appear in both training and early-stopping sets.

### 4. Probability Calibration
Raw GBDT margins are converted into true, well-calibrated probabilities using **Isotonic Regression** and **Sigmoid Platt Scaling** fit inside the CV loop.

---

## 🚀 6. Production Batch Inference & Supabase Integration

### 📦 1. Fast CPU FeatureStore (`src/sih_ml/serve/`)
- A zero-overhead SQLite/Parquet feature store (`deploy/featurestore`) allows scoring **309,042 road segments in ~1.0 second** on a standard CPU VM.
- Pure NumPy vectorized inference path with pre-compiled GBDT decision trees.

### 🔄 2. Automated Publisher (`sih-publish`)
The `sih-publish` service runs daily batch jobs or on-demand historical replays:

```bash
# Scored day publish to Supabase Postgres
docker compose --profile tools run --rm sih-publish run --date 2025-08-05 --mode replay
```

It writes risk scores directly into the `ml_segment_predictions` and `ml_corridor_runs` tables in Supabase Postgres.

### 🌐 3. Web & Mobile Integration
Frontends query these predictions using high-performance Supabase RPC functions:
- `get_routes_ml_risk(route_id)`: Checks an active rider's route geometry against ML risk segments.
- `get_ml_segments_in_bbox(...)`: Loads interactive risk heatmaps on the React Leaflet Web Dashboard and Flutter Mobile map.

---

## 📁 Key File Map in `/ml`

| Path | Purpose |
|---|---|
| [`ml/FORMULAS_AND_ALGORITHMS.md`](file:///Users/anand/Desktop/JanRakshak%20AI/ml/FORMULAS_AND_ALGORITHMS.md) | Mathematical formulation of all 49 features, loss functions & calibration |
| [`ml/FINAL_MODEL.md`](file:///Users/anand/Desktop/JanRakshak%20AI/ml/FINAL_MODEL.md) | Audit trail, validation metrics & deployment readiness verdict |
| [`ml/DEPLOYMENT.md`](file:///Users/anand/Desktop/JanRakshak%20AI/ml/DEPLOYMENT.md) | Production feature store design, batch latency benchmarks & API server |
| [`ml/src/sih_ml/features/build_panel.py`](file:///Users/anand/Desktop/JanRakshak%20AI/ml/src/sih_ml/features/build_panel.py) | Feature extractor for CHIRPS rainfall, terrain, & hydrology |
| [`ml/src/sih_ml/models/lgbm_baseline.py`](file:///Users/anand/Desktop/JanRakshak%20AI/ml/src/sih_ml/models/lgbm_baseline.py) | LightGBM model configuration, scale pos weights & monotonic constraints |
| [`ml/src/sih_ml/serve/batch.py`](file:///Users/anand/Desktop/JanRakshak%20AI/ml/src/sih_ml/serve/batch.py) | High-speed daily corridor batch predictor |
