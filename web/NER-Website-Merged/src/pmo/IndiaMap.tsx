import { useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import 'leaflet.markercluster';
import 'leaflet.markercluster/dist/MarkerCluster.css';
import { nameKey, regionOfState } from '@/data/indiaLocations';
import { INCIDENT_TYPES, typeDef } from './incidentTypes';
import { districtFeatures, INDIA_TOPOJSON_URL, loadIndiaGeo, stateFeatures, type BoundaryFeature, type IndiaGeo } from './indiaGeo';
import { scopeLabel, type PmoFilters } from './filters';
import type { NationalIncident } from './types';
import './pmo.css';

const INDIA_BOUNDS = L.latLngBounds([6.5, 68], [37.3, 97.5]);
const OSM_TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

interface Props {
  /** Incidents to plot, already filtered. */
  incidents: NationalIncident[];
  filters: PmoFilters;
  onSelectState: (state: string) => void;
  onSelectDistrict: (state: string, district: string) => void;
  onResetView: () => void;
}

const hasCoords = (i: NationalIncident): i is NationalIncident & { lat: number; lng: number } =>
  Number.isFinite(i.lat) && Number.isFinite(i.lng);

function formatWhen(value: string | null): string {
  if (!value) return 'Not recorded';
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? value : d.toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });
}

const titleCase = (s: string) => s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

/** DOM nodes with textContent only: titles and descriptions come from user reports and must never be parsed as HTML. */
function popupContent(i: NationalIncident): HTMLElement {
  const type = typeDef(i.typeId);
  const el = (tag: string, cls: string, text: string) => {
    const node = document.createElement(tag);
    node.className = cls;
    node.textContent = text;
    return node;
  };
  const root = document.createElement('div');
  root.appendChild(el('div', 'ner-pop-title', i.title || type.label));
  const chip = el('span', 'ner-pop-chip', type.label);
  chip.style.setProperty('--c', type.color);
  const meta = el('div', 'ner-pop-meta', '');
  meta.appendChild(chip);
  root.appendChild(meta);
  if (i.description) root.appendChild(el('div', 'pmo-pop-desc', i.description));
  const rows: [string, string | null][] = [
    ['Status', titleCase(i.status)],
    ['Severity', i.severity ? titleCase(i.severity) : null],
    ['State', i.state],
    ['District', i.district],
    ['Region', i.region],
    ['Location', hasCoords(i) ? `${i.lat.toFixed(4)}, ${i.lng.toFixed(4)}` : null],
    ['Reported', formatWhen(i.reportedAt)],
    ['Source', [i.reporter, i.source === 'demo' ? 'Demo data' : titleCase(i.source)].filter(Boolean).join(' · ')],
    ['Ref', i.reference],
  ];
  for (const [label, value] of rows) {
    if (!value) continue;
    const row = el('div', 'ner-pop-row', '');
    row.appendChild(el('span', '', label));
    row.appendChild(el('span', '', value));
    root.appendChild(row);
  }
  return root;
}

const iconCache = new Map<string, L.DivIcon>();
function markerIcon(i: NationalIncident): L.DivIcon {
  const key = `${i.typeId}|${i.status}`;
  let icon = iconCache.get(key);
  if (!icon) {
    const state = i.status === 'resolved' ? ' is-resolved' : i.status === 'pending' || i.status === 'escalated' ? ' is-pending' : '';
    icon = L.divIcon({
      className: 'ner-marker',
      html: `<span class="ner-inc${state}" style="--c:${typeDef(i.typeId).color}"></span>`,
      iconSize: [0, 0],
    });
    iconCache.set(key, icon);
  }
  return icon;
}

function clusterIcon(cluster: L.MarkerCluster): L.DivIcon {
  const count = cluster.getChildCount();
  const size = count < 10 ? 'sm' : count < 100 ? 'md' : 'lg';
  return L.divIcon({ html: `<span>${count}</span>`, className: `pmo-cluster pmo-cluster-${size}`, iconSize: [40, 40] });
}

export default function IndiaMap({ incidents, filters, onSelectState, onSelectDistrict, onResetView }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const clusterRef = useRef<L.MarkerClusterGroup | null>(null);
  const tilesRef = useRef<L.TileLayer | null>(null);
  const districtLayerRef = useRef<L.GeoJSON | null>(null);
  const stateLayerRef = useRef<L.GeoJSON | null>(null);
  const [geo, setGeo] = useState<IndiaGeo | null>(null);
  const [geoError, setGeoError] = useState<string | null>(null);
  const [geoAttempt, setGeoAttempt] = useState(0);
  const [streets, setStreets] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  // Handlers and filters are read through refs so layers are built once, not on every render.
  const live = useRef({ filters, incidents, onSelectState, onSelectDistrict });
  live.current = { filters, incidents, onSelectState, onSelectDistrict };

  // Map instance.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const map = L.map(el, {
      preferCanvas: true,
      zoomControl: false,
      attributionControl: false,
      minZoom: 4,
      maxZoom: 15,
      zoomSnap: 0.25,
      maxBounds: L.latLngBounds([0, 60], [42, 105]),
      maxBoundsViscosity: 0.7,
    });
    L.control.zoom({ position: 'bottomright' }).addTo(map);
    L.control.attribution({ prefix: false }).addAttribution('Boundaries: Census of India (via udit-001/india-maps-data)').addTo(map);
    map.fitBounds(INDIA_BOUNDS);
    const cluster = L.markerClusterGroup({ showCoverageOnHover: false, maxClusterRadius: 48, iconCreateFunction: clusterIcon });
    map.addLayer(cluster);
    mapRef.current = map;
    clusterRef.current = cluster;

    const observer = new ResizeObserver(() => map.invalidateSize({ pan: false }));
    observer.observe(el);
    return () => {
      observer.disconnect();
      map.remove();
      mapRef.current = clusterRef.current = tilesRef.current = districtLayerRef.current = stateLayerRef.current = null;
    };
  }, []);

  // Boundary data.
  useEffect(() => {
    let cancelled = false;
    setGeoError(null);
    loadIndiaGeo()
      .then(g => { if (!cancelled) setGeo(g); })
      .catch(e => { if (!cancelled) setGeoError(e instanceof Error ? e.message : 'Boundary data could not be loaded.'); });
    return () => { cancelled = true; };
  }, [geoAttempt]);

  // Boundary layers: districts are the clickable surface, state borders are drawn above them.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !geo) return;
    const districts = L.geoJSON(geo.districts, {
      style: feature => districtStyle(feature as BoundaryFeature, live.current.filters),
      onEachFeature: (feature, layer) => {
        const p = (feature as BoundaryFeature).properties;
        layer.bindTooltip(`${p.district ?? ''}, ${p.st_nm}`, { sticky: true });
        layer.on('click', () => {
          const { filters: f, onSelectState: pickState, onSelectDistrict: pickDistrict } = live.current;
          if (f.state !== p.st_nm) pickState(p.st_nm);
          else if (p.district && nameKey(f.district) !== nameKey(p.district)) pickDistrict(p.st_nm, p.district);
        });
      },
    }).addTo(map);
    const states = L.geoJSON(geo.states, {
      interactive: false,
      style: feature => stateStyle(feature as BoundaryFeature, live.current.filters),
    }).addTo(map);
    // India's outer border: a white casing under a red line so it stays visible over any basemap.
    const casing = L.geoJSON(geo.outline, { interactive: false, style: { color: '#FFFFFF', weight: 5.5, opacity: 0.85, fill: false } }).addTo(map);
    const outline = L.geoJSON(geo.outline, { interactive: false, style: { color: BORDER_RED, weight: 2.6, opacity: 1, fill: false } }).addTo(map);
    districtLayerRef.current = districts;
    stateLayerRef.current = states;
    return () => {
      districts.remove();
      states.remove();
      casing.remove();
      outline.remove();
      districtLayerRef.current = stateLayerRef.current = null;
    };
  }, [geo]);

  // Highlight and zoom whenever the geographic filter changes.
  const { region, state, district } = filters;
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    districtLayerRef.current?.setStyle(feature => districtStyle(feature as BoundaryFeature, live.current.filters));
    stateLayerRef.current?.setStyle(feature => stateStyle(feature as BoundaryFeature, live.current.filters));

    const fit = (bounds: L.LatLngBounds, maxZoom: number) =>
      map.fitBounds(bounds, { padding: [28, 28], maxZoom, animate: true });
    const boundsOf = (features: BoundaryFeature[]) =>
      L.geoJSON({ type: 'FeatureCollection', features } as GeoJSON.FeatureCollection).getBounds();
    const pointsBounds = (list: NationalIncident[]) => {
      const pts = list.filter(hasCoords).map(i => L.latLng(i.lat, i.lng));
      return pts.length ? L.latLngBounds(pts) : null;
    };

    setNote(null);
    if (!region && !state && !district) {
      fit(INDIA_BOUNDS, 6);
      return;
    }

    if (district) {
      const shapes = geo ? districtFeatures(geo, state, district) : [];
      if (shapes.length) {
        fit(boundsOf(shapes), 11);
        return;
      }
      const own = pointsBounds(live.current.incidents.filter(i => nameKey(i.district ?? '') === nameKey(district)));
      if (own) {
        setNote(`No boundary for ${district} in the map data; zoomed to its incidents.`);
        fit(own, 11);
        return;
      }
      setNote(`No boundary for ${district} in the map data; showing ${state}.`);
    }
    const shapes = geo ? stateFeatures(geo, region, state) : [];
    if (shapes.length) {
      fit(boundsOf(shapes), 9);
      return;
    }
    const any = pointsBounds(live.current.incidents);
    if (any) fit(any, 9);
  }, [geo, region, state, district]);

  // Incident markers, clustered.
  useEffect(() => {
    const cluster = clusterRef.current;
    if (!cluster) return;
    cluster.clearLayers();
    cluster.addLayers(
      incidents.filter(hasCoords).map(i =>
        L.marker([i.lat, i.lng], { icon: markerIcon(i), title: i.title, alt: `${typeDef(i.typeId).label} incident`, riseOnHover: true })
          .bindPopup(() => popupContent(i), { maxWidth: 320 }),
      ),
    );
  }, [incidents]);

  // Optional street basemap. Off by default so the drawn boundaries stay the only borders on screen.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (streets && !tilesRef.current) {
      tilesRef.current = L.tileLayer(OSM_TILES, { maxZoom: 19, attribution: '© OpenStreetMap contributors' }).addTo(map);
      tilesRef.current.bringToBack();
    } else if (!streets && tilesRef.current) {
      tilesRef.current.remove();
      tilesRef.current = null;
    }
  }, [streets]);

  const plotted = useMemo(() => incidents.filter(hasCoords), [incidents]);
  const unplaced = incidents.length - plotted.length;
  const legend = useMemo(
    () => INCIDENT_TYPES.map(t => ({ ...t, count: plotted.filter(i => i.typeId === t.id).length })),
    [plotted],
  );

  const resetView = () => {
    onResetView();
    mapRef.current?.fitBounds(INDIA_BOUNDS, { animate: true });
  };

  return (
    <div className="relative h-full w-full">
      <div ref={containerRef} className="ner-map pmo-map h-full w-full" role="region" aria-label="India situation map" />

      <div className="pmo-map-overlay pmo-map-tl">
        <div className="pmo-chip" aria-live="polite">
          <span className="pmo-chip-label">View</span> {scopeLabel(filters)}
          <span className="pmo-chip-sep">·</span>
          {plotted.length} on map{unplaced > 0 ? `, ${unplaced} without coordinates` : ''}
        </div>
        {note && <div className="pmo-chip pmo-chip-warn">{note}</div>}
        {!geo && !geoError && <div className="pmo-chip">Loading boundaries…</div>}
        {geoError && (
          <div className="pmo-chip pmo-chip-warn">
            Boundaries unavailable ({geoError}).{' '}
            <button type="button" className="pmo-link" onClick={() => setGeoAttempt(n => n + 1)}>Retry</button>
            <span className="sr-only"> from {INDIA_TOPOJSON_URL}</span>
          </div>
        )}
      </div>

      <div className="pmo-map-overlay pmo-map-tr">
        <label className="pmo-chip pmo-toggle">
          <input type="checkbox" checked={streets} onChange={e => setStreets(e.target.checked)} /> Street map
        </label>
        <button type="button" className="pmo-btn" onClick={resetView}>Reset view</button>
      </div>

      <div className="pmo-map-overlay pmo-map-bl">
        <ul className="pmo-legend" aria-label="Map legend">
          {legend.map(t => (
            <li key={t.id}>
              <span className="pmo-dot" style={{ background: t.color }} aria-hidden="true" />
              {t.label} <span className="pmo-legend-count">{t.count}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

const BORDER_RED = '#D32F2F';
const BORDER_RED_DARK = '#8E1B1F';

// The fill is transparent so the map underneath stays visible. It must stay `fill: true` (opacity 0,
// not fill: false), because Leaflet only lets a shape receive clicks when it has a fill.
function districtStyle(f: BoundaryFeature, filters: PmoFilters): L.PathOptions {
  const { st_nm, district } = f.properties;
  const inState = !!filters.state && st_nm === filters.state;
  const inRegion = !filters.state && !!filters.region && regionOfState(st_nm) === filters.region;
  const selected = inState && !!filters.district && nameKey(district ?? '') === nameKey(filters.district);
  return {
    color: selected ? BORDER_RED_DARK : '#5F7182',
    weight: selected ? 2 : 0.45,
    opacity: selected ? 1 : 0.7,
    fill: true,
    fillColor: selected ? '#F0B429' : '#2F6F7E',
    fillOpacity: selected ? 0.4 : inState || inRegion ? 0.14 : 0,
  };
}

function stateStyle(f: BoundaryFeature, filters: PmoFilters): L.PathOptions {
  const chosen = !!filters.state && f.properties.st_nm === filters.state;
  return { color: chosen ? BORDER_RED_DARK : BORDER_RED, weight: chosen ? 2.8 : 1.3, opacity: 1, fill: false };
}
