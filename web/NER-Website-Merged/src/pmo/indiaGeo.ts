import { feature } from 'topojson-client';
import type { GeometryCollection, Topology } from 'topojson-specification';
import type { Feature, FeatureCollection, MultiPolygon, Polygon } from 'geojson';
import { nameKey, statesOf } from '@/data/indiaLocations';

/**
 * State and district boundaries (Census-of-India based TopoJSON, ~0.9 MB) loaded at runtime.
 * Default is a commit-pinned jsDelivr copy; set VITE_INDIA_TOPOJSON_URL to self-host the same file.
 * Its state names match india_districts.csv exactly; district names are 2011-era, so a few newer
 * districts have no polygon (the map then falls back to the incident extent or the state).
 */
const DEFAULT_URL = 'https://cdn.jsdelivr.net/gh/udit-001/india-maps-data@2884453/topojson/india.json';
export const INDIA_TOPOJSON_URL: string = import.meta.env.VITE_INDIA_TOPOJSON_URL || DEFAULT_URL;

export interface GeoProps { st_nm: string; district?: string }
type Boundaries = FeatureCollection<Polygon | MultiPolygon, GeoProps>;
export type BoundaryFeature = Feature<Polygon | MultiPolygon, GeoProps>;
export interface IndiaGeo { districts: Boundaries; states: Boundaries }

let cached: Promise<IndiaGeo> | null = null;

export function loadIndiaGeo(): Promise<IndiaGeo> {
  cached ??= fetch(INDIA_TOPOJSON_URL)
    .then(res => {
      if (!res.ok) throw new Error(`Boundary data request failed (${res.status})`);
      return res.json() as Promise<Topology>;
    })
    .then(topo => ({
      districts: feature(topo, topo.objects.districts as GeometryCollection<GeoProps>) as Boundaries,
      states: feature(topo, topo.objects.states as GeometryCollection<GeoProps>) as Boundaries,
    }));
  cached.catch(() => { cached = null; }); // allow a retry after a failure
  return cached;
}

export function stateFeatures(geo: IndiaGeo, region: string, state: string): BoundaryFeature[] {
  if (state) return geo.states.features.filter(f => nameKey(f.properties.st_nm) === nameKey(state));
  const inRegion = new Set(statesOf(region).map(nameKey));
  return geo.states.features.filter(f => inRegion.has(nameKey(f.properties.st_nm)));
}

export const districtFeatures = (geo: IndiaGeo, state: string, district: string): BoundaryFeature[] =>
  geo.districts.features.filter(
    f => nameKey(f.properties.st_nm) === nameKey(state) && nameKey(f.properties.district ?? '') === nameKey(district),
  );
