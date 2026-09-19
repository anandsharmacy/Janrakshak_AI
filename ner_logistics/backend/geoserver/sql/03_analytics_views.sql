-- Spatial analytics computed in PostGIS and published by GeoServer as WFS
-- layers. Distances use `geography` (metres on the ellipsoid).
-- Field names match GeoServerSpatialAnalytics in
-- lib/services/gis/spatial_analytics.dart.

-- Kilometres of each highway inside flood / landslide zones, and incidents
-- within 2 km of the road.
CREATE OR REPLACE VIEW ner.highway_risk_exposure AS
WITH flood AS (
  SELECT ST_Union(geom) AS geom FROM ner.risk_zones WHERE kind = 'flood'
), slide AS (
  SELECT ST_Union(geom) AS geom FROM ner.risk_zones WHERE kind = 'landslide'
)
SELECT
  h.highway_id,
  ST_Length(h.geom::geography) / 1000 AS total_km,
  COALESCE(ST_Length(ST_Intersection(h.geom, flood.geom)::geography), 0) / 1000 AS flood_km,
  COALESCE(ST_Length(ST_Intersection(h.geom, slide.geom)::geography), 0) / 1000 AS landslide_km,
  (SELECT count(*) FROM ner.incidents i
     WHERE ST_DWithin(i.geom::geography, h.geom::geography, 2000))::int AS incidents_2km,
  h.geom
FROM ner.highways h CROSS JOIN flood CROSS JOIN slide;

-- Each vehicle: the risk zone it is inside (flood first, as in the app) and
-- the nearest safe zone.
CREATE OR REPLACE VIEW ner.convoy_exposure AS
SELECT
  v.vehicle_id,
  v.route,
  v.destination,
  v.risk,
  z.kind AS zone_kind,
  z.name AS zone_name,
  s.name AS nearest_safe_zone,
  ST_Distance(v.geom::geography, s.geom::geography) / 1000 AS safe_zone_km,
  v.geom
FROM ner.vehicles v
LEFT JOIN LATERAL (
  SELECT r.kind, r.name FROM ner.risk_zones r
  WHERE ST_Intersects(r.geom, v.geom)
  ORDER BY CASE r.kind WHEN 'flood' THEN 0 ELSE 1 END, r.id
  LIMIT 1
) z ON true
LEFT JOIN LATERAL (
  SELECT sz.name, sz.geom FROM ner.safe_zones sz
  ORDER BY sz.geom::geography <-> v.geom::geography
  LIMIT 1
) s ON true;

-- Incident counts per area (nearest town) and severity.
CREATE OR REPLACE VIEW ner.area_incident_summary AS
SELECT
  area,
  state,
  (count(*) FILTER (WHERE severity = 'critical'))::int AS critical,
  (count(*) FILTER (WHERE severity = 'high'))::int     AS high,
  (count(*) FILTER (WHERE severity = 'medium'))::int   AS medium,
  (count(*) FILTER (WHERE severity = 'low'))::int      AS low,
  (count(*) FILTER (WHERE status <> 'Resolved'))::int  AS open_count,
  ST_Centroid(ST_Collect(geom))::geometry(Point, 4326) AS geom
FROM ner.incidents
GROUP BY area, state;
