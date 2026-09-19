# JanRakshak AI 🛡️📦

> **Nationwide Disaster-Resilient & Hazard-Aware Logistics Management Platform**  
> *Evolved from the NER Logistics Platform ()*

---

## 📌 Executive Summary

**JanRakshak AI** is a comprehensive, multi-tiered logistics monitoring, hazard prediction, and operational coordination platform covering all States and Union Territories of India. Designed to maintain operational continuity under extreme weather, natural disasters (floods, landslides, cyclones), and infrastructure outages, JanRakshak AI connects field riders, control rooms, and government disaster authorities through a unified, offline-resilient digital backbone.

---

## 🏗️ System Architecture & Subsystems

The platform consists of several loosely-coupled microservices and application frontends coordinated through Docker Compose and Supabase:

```
                               ┌────────────────────────────────────────┐
                               │           JanRakshak AI Clients         │
                               └──────────────────┬─────────────────────┘
                                                  │
                      ┌───────────────────────────┴───────────────────────────┐
                      │                                                       │
         ┌────────────▼────────────┐                             ┌────────────▼────────────┐
         │  Flutter Mobile App     │                             │  React Web Dashboards   │
         │  (Riders / Field)       │                             │  (Control Room/Officers)│
         └────────────┬────────────┘                             └────────────┬────────────┘
                      │                                                       │
                      └───────────────────────────┬───────────────────────────┘
                                                  │
                                    ┌─────────────▼─────────────┐
                                    │ Supabase (Postgres/PostGIS│
                                    │ RLS / Auth / Realtime)    │
                                    └─────────────▲─────────────┘
                                                  │
                      ┌───────────────────────────┼───────────────────────────┐
                      │                           │                           │
         ┌────────────┴────────────┐ ┌────────────┴────────────┐ ┌────────────┴────────────┐
         │     sih-ml Engine       │ │     OSRM Engine        │ │      GeoServer        │
         │  (Disruption Inference) │ │  (Routing & Navigation)│ │  (Spatial Layers/Maps) │
         └─────────────────────────┘ └────────────────────────┘ └────────────────────────┘
```

### 1. 📱 Mobile Application (`janrakshak_user`)
- **Tech Stack**: Flutter 3.x, Dart, Riverpod, Hive (Offline Cache), Supabase Flutter SDK, Geolocator, Flutter Map, Vector Map Tiles.
- **Key Features**:
  - Offline-first tracking with Hive queue sync when connection drops.
  - Active trip monitoring, route guidance, turn-by-turn navigation.
  - Incident & hazard reporting (road blockages, landslides, floods) with media attachments.
  - Multi-language UI support (English, Hindi, and regional languages).

### 2. 🖥️ Web Dashboards & Control Room (`web/NER-Website-Merged`)
- **Tech Stack**: React 19, TypeScript, Vite 8, Leaflet, Tailwind CSS.
- **Key Features**:
  - Jurisdiction-aware UI for Field Officers, District Officers, State Officers, and National Control Rooms.
  - Live interactive maps showing active riders, shipments, hazard overlays, and heatmaps.
  - Real-time incident dispatching and emergency response coordination.

### 3. 🧠 Machine Learning Engine
- **Tech Stack**: Python 3.10+, LightGBM, GeoPandas, XArray, Scikit-Learn, PyArrow, Docker.
- **Key Features**:
  - Segment-level risk scoring along transport corridors based on weather, rainfall, terrain, and past historical disruption data.
  - Model coverage registry supporting fallback to rule-based risk evaluation for regions without active ML models.
  - Automated database publisher (`sih-publish`) syncing daily predicted risk scores into Supabase Postgres tables.

### 4. 🗄️ Backend Services (`supabase`, `postgis`, `geoserver`, `osrm`)
- **Supabase**: Row Level Security (RLS) policies scoped by jurisdiction hierarchy (`National → Region → State → District → Sub-district`), realtime subscriptions, and authentication.
- **PostGIS & GeoServer**: Geospatial vector and raster layer rendering, risk zone buffer calculations, and spatial heatmaps.
- **OSRM (Open Source Routing Machine)**: Custom road network routing engine optimized for hazard detours and ETA estimates.

---

## 📂 Repository Layout

```
.
├── JanRakshak_AI_SRS.md           # Master Software Requirements Specification (SRS)
├── ML_INTEGRATION_PLAN.md          # Machine Learning integration & publication strategy
├── docker-compose.yml              # Master Docker Compose orchestration setup
├── .env.example                    # Template for environment configuration
├── janrakshak_user/                # Flutter Mobile Application (Android/Web)
├── web/                            # React Web Dashboards
│   └── NER-Website-Merged/         # Officer & Control Room React application
├── sih-ml/                         # Python ML training, inference, and publisher engine
├── supabase/                       # Supabase database migrations and schemas
├── ner_logistics/                  # Reference NER baseline implementation & assets
└── northeast_india_districts.csv   # District geospatial metadata baseline
```

---

## 🚀 Quick Start Guide

### Prerequisites

Ensure you have the following installed:
- [Docker](https://www.docker.com/) & Docker Compose
- [Node.js](https://nodejs.org/) (v18+) & `npm`
- [Flutter SDK](https://flutter.dev/) (v3.13+)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`supabase`)
- [Python](https://www.python.org/) (3.10+)

---

### Step 1: Environment Setup

Clone the repository and copy the environment template:

```bash
cp .env.example .env
```

Edit `.env` to set your local IP address or localhost URLs:

```env
NER_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NER_SUPABASE_PUBLISHABLE_KEY=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH
SIH_PUBLISH_DSN=postgresql://postgres:postgres@host.docker.internal:54322/postgres
```

---

### Step 2: Launch Backend & GIS Services (Docker Compose)

Start the core services (ML Inference API, GeoServer, PostGIS, OSRM, Web Dashboard):

```bash
docker compose up -d
```

Check running container status:

```bash
docker compose ps
```

*Port Mappings*:
- **Web Dashboard**: `http://localhost:3000`
- **ML API**: `http://localhost:8080`
- **GeoServer**: `http://localhost:8081`
- **OSRM Routing Engine**: `http://localhost:5001`
- **PostGIS**: `localhost:5432`

---

### Step 3: Start Supabase Local Stack

Navigate to the Supabase setup directory and start the local Supabase environment:

```bash
supabase start
```

This starts local Supabase Auth, REST API (`http://127.0.0.1:54321`), PostgreSQL (`127.0.0.1:54322`), and Studio (`http://127.0.0.1:54323`).

---

### Step 4: Run the Web Dashboard (Development Mode)

```bash
cd web/NER-Website-Merged
npm install
npm run dev
```

The web dashboard will be available at `http://localhost:5173`.

---

### Step 5: Run the Flutter Mobile Application

```bash
cd janrakshak_user
flutter pub get
flutter run
```

To build an Android APK:

```bash
flutter build apk --release
```

---

### Step 6: Publish ML Risk Predictions to Database

To execute a batch scoring run and publish risk scores to Supabase:

```bash
# Scored day publish (Replay mode)
docker compose --profile tools run --rm sih-publish run --date 2025-08-05 --mode replay
```

---

## 🔐 Jurisdiction & Security Matrix

JanRakshak AI enforces strict Row-Level Security (RLS) in PostgreSQL based on user jurisdictions:

| Role | Scope / Access Level |
|---|---|
| `national_admin` | Nationwide visibility; full system administration and onboarding |
| `state_admin` / `state_officer` | State-level visibility across all contained districts and corridors |
| `district_officer` | District-wide operational view for assigned district |
| `field_officer` / `control_room` | Local district / sub-district active trip and incident monitoring |
| `rider` | Own assigned trips, route alerts, personal tracking, and field issue reports |

---

## 📖 Key Documentation

For detailed technical guidelines, refer to:
- 📄 [Software Requirements Specification (JanRakshak_AI_SRS.md)](file:///Users/anand/Desktop/JanRakshak%20AI/JanRakshak_AI_SRS.md)
- 📊 [ML Integration Plan (ML_INTEGRATION_PLAN.md)](file:///Users/anand/Desktop/JanRakshak%20AI/ML_INTEGRATION_PLAN.md)
- 🐳 [Docker Infrastructure Configuration (docker-compose.yml)](file:///Users/anand/Desktop/JanRakshak%20AI/docker-compose.yml)

---

## 🤝 Contributing & License

Private Project repository built for **JanRakshak AI Initiative**. All rights reserved.
