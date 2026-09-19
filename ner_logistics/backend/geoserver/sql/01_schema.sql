-- NER Logistics — PostGIS schema served by GeoServer (workspace `ner`).
-- Loaded automatically by the postgis container on first start.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS ner;

CREATE TABLE IF NOT EXISTS ner.highways (
  highway_id text PRIMARY KEY,
  name       text,
  geom       geometry(LineString, 4326) NOT NULL
);

CREATE TABLE IF NOT EXISTS ner.incidents (
  id         text PRIMARY KEY,
  type       text NOT NULL,
  type_label text NOT NULL,
  severity   text NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low')),
  status     text NOT NULL,
  route      text,
  location   text,
  area       text,
  state      text,
  reported   text,
  -- Heatmap weight (styles/ner_incident_heatmap.sld).
  weight     int GENERATED ALWAYS AS (
               CASE severity WHEN 'critical' THEN 4 WHEN 'high' THEN 3
                             WHEN 'medium' THEN 2 ELSE 1 END) STORED,
  geom       geometry(Point, 4326) NOT NULL
);

CREATE TABLE IF NOT EXISTS ner.risk_zones (
  id             serial PRIMARY KEY,
  kind           text NOT NULL CHECK (kind IN ('flood', 'landslide')),
  name           text NOT NULL,
  susceptibility text,
  source         text,
  geom           geometry(Polygon, 4326) NOT NULL
);

CREATE TABLE IF NOT EXISTS ner.safe_zones (
  id       serial PRIMARY KEY,
  name     text NOT NULL,
  radius_m double precision,
  geom     geometry(Point, 4326) NOT NULL
);

CREATE TABLE IF NOT EXISTS ner.depots (
  id   serial PRIMARY KEY,
  name text NOT NULL,
  kind text,
  geom geometry(Point, 4326) NOT NULL
);

CREATE TABLE IF NOT EXISTS ner.vehicles (
  vehicle_id  text PRIMARY KEY,
  route       text,
  destination text,
  status      text,
  risk        text,
  geom        geometry(Point, 4326) NOT NULL
);

CREATE INDEX IF NOT EXISTS highways_geom_idx   ON ner.highways   USING gist (geom);
CREATE INDEX IF NOT EXISTS incidents_geom_idx  ON ner.incidents  USING gist (geom);
CREATE INDEX IF NOT EXISTS risk_zones_geom_idx ON ner.risk_zones USING gist (geom);
CREATE INDEX IF NOT EXISTS safe_zones_geom_idx ON ner.safe_zones USING gist (geom);
CREATE INDEX IF NOT EXISTS vehicles_geom_idx   ON ner.vehicles   USING gist (geom);
