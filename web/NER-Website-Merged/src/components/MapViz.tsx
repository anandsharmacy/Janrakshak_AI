import { useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { Severity } from '@/data/demo';
import { CORRIDORS, NER_CENTER, NER_ZOOM, locate, normalizeRouteId, type LatLng } from '@/data/geo';
import { fetchMlSegmentsInBbox, fetchMlStatus, stateLabel, TIER_LABEL, topShare, useMlQuery, type MlSegment } from '@/lib/ml';
import { riderRoute } from '@/data/demoRiders';
import { drivenWaypoints, type LiveRider } from '@/lib/riderTracking';

/* ────────────────────────────────────────────────────────────────
   Interactive Leaflet map shared by all three role dashboards.
   Plots incidents (GPS → named place → route midpoint), highway
   corridors coloured by reported status, convoys/tasks, optional
   risk zones, and an optional pickable pin for location capture.
──────────────────────────────────────────────────────────────── */

export type MapLayer = 'routes' | 'incidents' | 'logistics' | 'risk' | 'ml';

export interface MapIncident {
  id: string;
  type: string;
  severity: Severity;
  status: string;
  location: string;
  route: string;
  gpsCoords?: string;
  riskScore?: number;
  reportedTime?: string;
}

export interface MapRoute {
  id: string;
  status: string;
  name?: string;
}

export interface MapVehicle {
  id: string;
  currentLocation: string;
  risk: Severity;
  cargo?: string;
  destination?: string;
  route?: string;
  status?: string;
  eta?: string;
}

interface MapVizProps {
  incidents?: MapIncident[];
  routes?: MapRoute[];
  vehicles?: MapVehicle[];
  /** Live riders (demo dataset). Drawn on the logistics layer alongside convoys. */
  riders?: LiveRider[];
  /** Highlights this rider and zooms to its route; every other rider stays visible. */
  selectedRiderId?: string | null;
  onSelectRider?: (riderId: string | null) => void;
  height?: number;
  showLegend?: boolean;
  /** Layer visibility; routes, incidents and logistics are on by default, risk zones and ML risk off. */
  layers?: Partial<Record<MapLayer, boolean>>;
  /** Incident types that get a risk zone when the risk layer is on (all types when omitted). */
  riskTypes?: string[];
  /** Zooms to and highlights this highway corridor. */
  focusRouteId?: string | null;
  center?: LatLng;
  zoom?: number;
  /** A single location pin, e.g. the point being reported. */
  pin?: LatLng | null;
  pinColor?: string;
  /** Makes the map pickable: clicking the map or dragging the pin reports the new point. */
  onPick?: (point: LatLng) => void;
  rounded?: string;
}

const severityColor: Record<Severity, string> = {
  CRITICAL: '#BE2424', HIGH: '#E07840', MODERATE: '#C4861A', LOW: '#2D6B4F',
};
const routeColor: Record<string, string> = {
  Open: '#2D6B4F', Restricted: '#E07840', Blocked: '#C25A1A', Closed: '#BE2424',
};
const NEUTRAL_ROUTE = '#7E8C7C';
const DEFAULT_LAYERS: Record<MapLayer, boolean> = { routes: true, incidents: true, logistics: true, risk: false, ml: false };
const ML_COLOR = { alert: '#BE2424', human_review: '#C4861A', none: '#2D6B4F' } as const;
const RIDER_COLOR = { active: '#2F6F7E', inactive: '#8A9098', selected: '#17324D', blocked: '#BE2424', detour: '#C4861A' } as const;

const OSM_TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const OSM_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

function esc(value: unknown) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]!);
}

function popupRows(rows: [string, unknown][]) {
  return rows
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([label, value]) => `<div class="ner-pop-row"><span>${esc(label)}</span><span>${esc(value)}</span></div>`)
    .join('');
}

/** Nudges markers that share a position so each stays clickable. */
function spread<T>(items: { item: T; at: LatLng | null }[]) {
  const seen = new Map<string, number>();
  return items.map(({ item, at }) => {
    if (!at) return { item, at };
    const key = `${at[0].toFixed(4)},${at[1].toFixed(4)}`;
    const n = seen.get(key) ?? 0;
    seen.set(key, n + 1);
    if (!n) return { item, at };
    const angle = n * 2.4;
    const r = 0.006 * Math.sqrt(n);
    return { item, at: [at[0] + r * Math.sin(angle), at[1] + r * Math.cos(angle)] as LatLng };
  });
}

export default function MapViz({
  incidents = [], routes = [], vehicles = [], riders = [], selectedRiderId = null, onSelectRider,
  height = 480, showLegend = true, layers, riskTypes, focusRouteId,
  center = NER_CENTER, zoom = NER_ZOOM, pin = null, pinColor = '#BE2424', onPick,
  rounded = '0 0 12px 12px',
}: MapVizProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [map, setMap] = useState<L.Map | null>(null);
  const [loading, setLoading] = useState(true);
  const [tileError, setTileError] = useState(false);
  const [legendOpen, setLegendOpen] = useState(height >= 400);
  const onPickRef = useRef(onPick);
  const onSelectRiderRef = useRef(onSelectRider);
  const fitRef = useRef<() => void>(() => {});
  const [mlSegments, setMlSegments] = useState<MlSegment[]>([]);
  const [mlCapped, setMlCapped] = useState(false);

  useEffect(() => { onPickRef.current = onPick; }, [onPick]);
  useEffect(() => { onSelectRiderRef.current = onSelectRider; }, [onSelectRider]);

  const visible = { ...DEFAULT_LAYERS, ...layers };
  const mlStatus = useMlQuery(fetchMlStatus);
  const mlBbox = mlStatus.data?.coverage_bbox ?? null;
  const mlBboxKey = mlBbox?.join(',') ?? '';
  const focusId = focusRouteId ? normalizeRouteId(focusRouteId) : null;
  const pickable = Boolean(onPick);
  const riskKey = riskTypes?.join('|');
  const riskFilter = useMemo(() => (riskKey === undefined ? null : new Set(riskKey.split('|'))), [riskKey]);

  const placedIncidents = useMemo(() => spread(incidents.map(item => ({ item, at: locate(item) }))), [incidents]);
  const placedVehicles = useMemo(
    () => spread(vehicles.map(item => ({ item, at: locate({ location: item.currentLocation, route: item.route }) }))),
    [vehicles],
  );
  const routeStatus = useMemo(() => new Map(routes.map(route => [normalizeRouteId(route.id), route])), [routes]);

  // Rider route geometry is static, so the auto-fit does not chase moving markers.
  const riderIdsKey = riders.map(r => r.id).join('|');
  const riderRoutePoints = useMemo(() => {
    const points: LatLng[] = [];
    riderIdsKey.split('|').filter(Boolean).forEach(id => {
      const route = riderRoute(id);
      if (!route) return;
      route.path.forEach(p => points.push(p.at));
      route.blocked?.detour.forEach(p => points.push(p.at));
    });
    return points;
  }, [riderIdsKey]);
  const selectedRiderBounds = useMemo(() => {
    const route = selectedRiderId ? riderRoute(selectedRiderId) : null;
    if (!route) return null;
    const points = [...route.path.map(p => p.at), ...(route.blocked?.detour.map(p => p.at) ?? [])];
    return L.latLngBounds(points);
  }, [selectedRiderId]);

  const dataBounds = useMemo(() => {
    const points: LatLng[] = [];
    placedIncidents.forEach(({ at }) => at && points.push(at));
    placedVehicles.forEach(({ at }) => at && points.push(at));
    routeStatus.forEach((_, id) => CORRIDORS[id] && points.push(...CORRIDORS[id].path));
    points.push(...riderRoutePoints);
    return points.length ? L.latLngBounds(points) : null;
  }, [placedIncidents, placedVehicles, routeStatus, riderRoutePoints]);
  const fitKey = dataBounds?.toBBoxString() ?? '';
  const selectedFitKey = selectedRiderBounds?.toBBoxString() ?? '';

  // Create the map once per mount.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const instance = L.map(el, {
      center: pin ?? center,
      zoom: pin ? 14 : zoom,
      zoomControl: false,
      scrollWheelZoom: false,
    });
    L.control.zoom({ position: 'topright' }).addTo(instance);

    const tiles = L.tileLayer(OSM_TILES, { maxZoom: 19, attribution: OSM_ATTRIBUTION }).addTo(instance);

    const ResetControl = L.Control.extend({
      onAdd() {
        const bar = L.DomUtil.create('div', 'leaflet-bar');
        const link = L.DomUtil.create('a', '', bar);
        link.href = '#';
        link.title = 'Reset view';
        link.setAttribute('role', 'button');
        link.setAttribute('aria-label', 'Reset view');
        link.innerHTML = '⊕';
        L.DomEvent.disableClickPropagation(bar);
        L.DomEvent.on(link, 'click', event => {
          L.DomEvent.preventDefault(event);
          fitRef.current();
        });
        return bar;
      },
    });
    new ResetControl({ position: 'topright' }).addTo(instance);

    // Only capture the scroll wheel once the user has engaged with the map.
    instance.on('focus', () => instance.scrollWheelZoom.enable());
    instance.on('blur', () => instance.scrollWheelZoom.disable());
    instance.on('click', event => onPickRef.current?.([event.latlng.lat, event.latlng.lng]));

    tiles.on('load', () => { setLoading(false); setTileError(false); });
    tiles.on('tileerror', () => setTileError(true));
    const loadTimer = window.setTimeout(() => setLoading(false), 4000);

    // Keeps tiles aligned when the container resizes (drawers, sidebar, window).
    const observer = new ResizeObserver(() => instance.invalidateSize());
    observer.observe(el);

    setMap(instance);
    return () => {
      window.clearTimeout(loadTimer);
      observer.disconnect();
      instance.remove();
      setMap(null);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    fitRef.current = () => {
      if (!map) return;
      const corridor = focusId ? CORRIDORS[focusId] : null;
      if (corridor) map.fitBounds(corridor.path, { padding: [24, 24] });
      else if (selectedRiderBounds) map.fitBounds(selectedRiderBounds.pad(0.35), { padding: [24, 24], maxZoom: 14 });
      else if (pin) map.setView(pin, 14);
      else if (dataBounds) map.fitBounds(dataBounds, { padding: [36, 36], maxZoom: 11 });
      else map.setView(center, zoom);
    };
  });

  useEffect(() => {
    if (map && (fitKey || focusId || selectedFitKey)) fitRef.current();
  }, [map, fitKey, focusId, selectedFitKey]);

  // Highway corridors
  useEffect(() => {
    if (!map || !visible.routes) return;
    const group = L.layerGroup();
    Object.entries(CORRIDORS).forEach(([id, corridor]) => {
      const route = routeStatus.get(id);
      const color = route ? routeColor[route.status] ?? NEUTRAL_ROUTE : NEUTRAL_ROUTE;
      const blocked = route?.status === 'Blocked' || route?.status === 'Closed';
      const focused = focusId === id;
      if (blocked || focused) {
        L.polyline(corridor.path, { color, weight: 12, opacity: 0.16, interactive: false }).addTo(group);
      }
      L.polyline(corridor.path, {
        color,
        weight: focused ? 5 : route ? 3.5 : 2.5,
        opacity: route || focused ? 0.92 : 0.6,
        dashArray: blocked ? '8 6' : undefined,
        lineCap: 'round',
      })
        .bindTooltip(`<b>${esc(id)}</b> · ${esc(route?.name && route.name !== id ? route.name : corridor.name)}<br>${esc(route?.status ?? 'No status reported')}`, { sticky: true })
        .addTo(group);
    });
    group.addTo(map);
    return () => { group.remove(); };
  }, [map, visible.routes, routeStatus, focusId]);

  // Risk zones around unresolved incidents
  useEffect(() => {
    if (!map || !visible.risk) return;
    const group = L.layerGroup();
    placedIncidents.forEach(({ item, at }) => {
      if (!at || item.status === 'RESOLVED') return;
      if (riskFilter && !riskFilter.has(item.type)) return;
      const color = severityColor[item.severity] ?? '#E07840';
      L.circle(at, {
        radius: 4000 + (item.riskScore ?? 50) * 180,
        color, weight: 1, opacity: 0.6, fillColor: color, fillOpacity: 0.14, interactive: false,
      }).addTo(group);
    });
    group.addTo(map);
    return () => { group.remove(); };
  }, [map, visible.risk, placedIncidents, riskFilter]);

  // Incidents
  useEffect(() => {
    if (!map || !visible.incidents) return;
    const group = L.layerGroup();
    placedIncidents.forEach(({ item, at }) => {
      if (!at) return;
      const color = severityColor[item.severity] ?? '#E07840';
      const pending = item.status === 'PENDING_VERIFICATION';
      const icon = L.divIcon({
        className: 'ner-marker',
        html: `<span class="ner-inc${pending ? ' is-pending' : ''}" style="--c:${color}"></span>`,
        iconSize: [0, 0], iconAnchor: [0, 0], popupAnchor: [0, -8],
      });
      L.marker(at, { icon, riseOnHover: true, alt: `${item.type} incident` })
        .bindTooltip(esc(item.type), { direction: 'right', offset: [9, 0] })
        .bindPopup(
          `<div class="ner-pop-title">${esc(item.type)}</div>`
          + `<div class="ner-pop-meta">${esc(item.id)} · <span class="ner-pop-chip" style="--c:${color}">${esc(item.severity)}</span></div>`
          + popupRows([
            ['Location', item.location],
            ['Route', item.route],
            ['Status', item.status.replace(/_/g, ' ')],
            ['Reported', item.reportedTime],
            ['GPS', item.gpsCoords && /\d/.test(item.gpsCoords) ? item.gpsCoords : 'Approximate (from location)'],
          ]),
        )
        .addTo(group);
    });
    group.addTo(map);
    return () => { group.remove(); };
  }, [map, visible.incidents, placedIncidents]);

  // Convoys / logistics tasks
  useEffect(() => {
    if (!map || !visible.logistics) return;
    const group = L.layerGroup();
    placedVehicles.forEach(({ item, at }) => {
      if (!at) return;
      const color = severityColor[item.risk] ?? '#2D6B4F';
      const icon = L.divIcon({
        className: 'ner-marker',
        html: `<span class="ner-veh" style="--c:${color}">${esc(item.id)}</span>`,
        iconSize: [0, 0], iconAnchor: [0, 0], popupAnchor: [0, -10],
      });
      L.marker(at, { icon, riseOnHover: true, alt: `Convoy ${item.id}` })
        .bindPopup(
          `<div class="ner-pop-title">${esc(item.id)}</div>`
          + `<div class="ner-pop-meta">${esc(item.cargo)}</div>`
          + popupRows([
            ['Location', item.currentLocation],
            ['Heading', item.destination],
            ['Route', item.route],
            ['ETA', item.eta],
            ['Status', item.status],
          ]),
        )
        .addTo(group);
    });
    group.addTo(map);
    return () => { group.remove(); };
  }, [map, visible.logistics, placedVehicles]);

  // Rider routes: the selected rider's road, plus every blocked stretch and its detour (always shown)
  useEffect(() => {
    if (!map || !visible.logistics || !riders.length) return;
    const group = L.layerGroup();
    riders.forEach(rider => {
      const route = riderRoute(rider.id);
      if (!route || route.path.length < 2) return;
      const selected = rider.id === selectedRiderId;
      const { blocked } = route;

      if (selected) {
        const driven = drivenWaypoints(route).map(p => p.at);
        L.polyline(driven, { color: RIDER_COLOR.selected, weight: 10, opacity: 0.14, interactive: false }).addTo(group);
        L.polyline(driven, { color: RIDER_COLOR.selected, weight: 3.5, opacity: 0.9, lineCap: 'round' })
          .bindTooltip(`<b>${esc(rider.id)}</b> · ${esc(rider.name)}<br>${esc(blocked ? 'Diverted route' : 'Planned route')}`, { sticky: true })
          .addTo(group);
      }

      if (blocked) {
        const blockedPath = route.path.slice(blocked.from, blocked.to + 1).map(p => p.at);
        const detourPath = [route.path[blocked.from].at, ...blocked.detour.map(p => p.at), route.path[blocked.to].at];
        L.polyline(blockedPath, { color: RIDER_COLOR.blocked, weight: selected ? 12 : 9, opacity: 0.16, interactive: false }).addTo(group);
        L.polyline(blockedPath, { color: RIDER_COLOR.blocked, weight: selected ? 4.5 : 3.5, opacity: 0.95, dashArray: '8 6', lineCap: 'round' })
          .bindTooltip(`<b>Road blocked</b><br>${esc(blocked.reason)}`, { sticky: true })
          .addTo(group);
        L.polyline(detourPath, { color: RIDER_COLOR.detour, weight: selected ? 4.5 : 3, opacity: selected ? 0.95 : 0.75, lineCap: 'round' })
          .bindTooltip(`<b>Diversion</b> · ${esc(rider.id)}<br>${esc(blocked.detour[0]?.label ?? '')}`, { sticky: true })
          .addTo(group);
        L.circleMarker(route.path[blocked.from].at, { radius: 5, color: '#FFFFFF', weight: 1.5, fillColor: RIDER_COLOR.blocked, fillOpacity: 1, interactive: false }).addTo(group);
      }
    });
    group.addTo(map);
    return () => { group.remove(); };
  }, [map, visible.logistics, riderIdsKey, selectedRiderId]);

  // Rider markers (live positions; all riders stay visible, the selected one is emphasised)
  useEffect(() => {
    if (!map || !visible.logistics || !riders.length) return;
    const group = L.layerGroup();
    riders.forEach(rider => {
      const selected = rider.id === selectedRiderId;
      const active = rider.status === 'Active';
      const color = selected ? RIDER_COLOR.selected : active ? RIDER_COLOR.active : RIDER_COLOR.inactive;
      const icon = L.divIcon({
        className: 'ner-marker',
        html: `<span class="ner-veh${selected ? ' is-selected' : ''}${active ? '' : ' is-idle'}" style="--c:${color}">${esc(rider.id)}</span>`,
        iconSize: [0, 0], iconAnchor: [0, 0], popupAnchor: [0, -10],
      });
      const marker = L.marker(rider.position, { icon, riseOnHover: true, zIndexOffset: selected ? 1000 : 0, alt: `Rider ${rider.id}` })
        .bindTooltip(esc(rider.name), { direction: 'top', offset: [0, -10] })
        .bindPopup(
          `<div class="ner-pop-title">${esc(rider.id)} · ${esc(rider.name)}</div>`
          + `<div class="ner-pop-meta">${esc(rider.district)}, ${esc(rider.state)} · <span class="ner-pop-chip" style="--c:${active ? RIDER_COLOR.active : RIDER_COLOR.inactive}">${esc(rider.status)}</span></div>`
          + popupRows([
            ['Location', rider.currentLocation],
            ['Vehicle', rider.vehicleType],
            ['Phone', rider.phone],
            ['Rating', rider.rating.toFixed(1)],
            ['Route', rider.diverted ? 'On diversion (road blocked)' : rider.moving ? 'On planned route' : 'Stationary'],
          ]),
        );
      marker.on('click', () => onSelectRiderRef.current?.(rider.id));
      marker.addTo(group);
    });
    group.addTo(map);
    return () => { group.remove(); };
  }, [map, visible.logistics, riders, selectedRiderId]);

  // ML road-disruption risk: coverage outline + scored segments in view (officers only; RLS-enforced)
  useEffect(() => {
    if (!map || !visible.ml || !mlBboxKey) return;
    const [w, s, e, n] = mlBboxKey.split(',').map(Number);
    const outline = L.rectangle([[s, w], [n, e]], {
      color: '#17324D', weight: 1.5, dashArray: '6 5', fill: false, interactive: false,
    }).addTo(map);
    return () => { outline.remove(); };
  }, [map, visible.ml, mlBboxKey]);

  useEffect(() => {
    if (!map || !visible.ml || mlStatus.signedOut) {
      setMlSegments([]);
      return;
    }
    let seq = 0;
    let timer: number | undefined;
    const load = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        const id = ++seq;
        const b = map.getBounds();
        fetchMlSegmentsInBbox({ west: b.getWest(), south: b.getSouth(), east: b.getEast(), north: b.getNorth() })
          .then(rows => { if (id === seq) { setMlSegments(rows); setMlCapped(rows.length >= 1000); } })
          .catch(() => { if (id === seq) setMlSegments([]); });
      }, 250);
    };
    load();
    map.on('moveend', load);
    return () => { window.clearTimeout(timer); map.off('moveend', load); };
  }, [map, visible.ml, mlStatus.signedOut, mlStatus.data?.run_id]);

  useEffect(() => {
    if (!map || !visible.ml || !mlSegments.length) return;
    const renderer = L.canvas({ padding: 0.3 });
    const group = L.layerGroup();
    const when = stateLabel(mlStatus.data);
    // draw review segments first so high-risk ones sit on top
    [...mlSegments].sort((a, b) => (a.tier === 'alert' ? 1 : 0) - (b.tier === 'alert' ? 1 : 0)).forEach(seg => {
      const color = ML_COLOR[seg.tier];
      L.circleMarker([seg.lat, seg.lon], {
        renderer, radius: seg.tier === 'alert' ? 5 : 3.5, color: '#FFFFFF', weight: 1,
        fillColor: color, fillOpacity: 0.9,
      })
        .bindPopup(
          `<div class="ner-pop-title">${esc(TIER_LABEL[seg.tier])}</div>`
          + `<div class="ner-pop-meta">${esc(seg.segment_id)} · <span class="ner-pop-chip" style="--c:${color}">${esc(topShare(seg.risk_percentile))} of roads</span></div>`
          + popupRows([
            ['Terrain', seg.steep ? 'Steep — officer review, never auto-alerted' : 'Not steep'],
            ['Source', when],
            ['Position', `${seg.lat.toFixed(5)}, ${seg.lon.toFixed(5)}`],
            ['Use', 'Advisory — verify before rerouting'],
          ]),
        )
        .addTo(group);
    });
    group.addTo(map);
    return () => { group.remove(); };
  }, [map, visible.ml, mlSegments, mlStatus.data]);

  // Location pin
  const pinLat = pin?.[0];
  const pinLng = pin?.[1];
  useEffect(() => {
    if (!map || pinLat === undefined || pinLng === undefined) return;
    const point: LatLng = [pinLat, pinLng];
    const marker = L.marker(point, {
      icon: L.divIcon({ className: 'ner-marker', html: `<span class="ner-pin" style="--c:${pinColor}"></span>`, iconSize: [0, 0], iconAnchor: [0, 0] }),
      draggable: pickable,
      alt: 'Selected location',
    });
    marker.on('dragend', () => {
      const { lat, lng } = marker.getLatLng();
      onPickRef.current?.([lat, lng]);
    });
    marker.addTo(map);
    map.setView(point, Math.max(map.getZoom(), 14));
    return () => { marker.remove(); };
  }, [map, pinLat, pinLng, pinColor, pickable]);

  const unplacedIncidents = visible.incidents ? placedIncidents.filter(p => !p.at).length : 0;
  const mlChip = !visible.ml ? null
    : mlStatus.signedOut ? 'ML road risk needs a live sign-in'
    : mlStatus.data ? `${stateLabel(mlStatus.data)}${mlCapped ? ' · showing the 1,000 riskiest in view' : ''}`
    : null;
  const missingCorridor = Boolean(focusId && !CORRIDORS[focusId]);

  const legend = [
    ...(visible.routes ? [
      { color: routeColor.Open, label: 'Open route', kind: 'line' },
      { color: routeColor.Restricted, label: 'Restricted', kind: 'line' },
      { color: routeColor.Closed, label: 'Closed / blocked', kind: 'dash' },
      { color: NEUTRAL_ROUTE, label: 'No status reported', kind: 'line' },
    ] : []),
    ...(visible.incidents ? [
      { color: severityColor.CRITICAL, label: 'Critical incident', kind: 'dot' },
      { color: severityColor.HIGH, label: 'High', kind: 'dot' },
      { color: severityColor.MODERATE, label: 'Moderate', kind: 'dot' },
      { color: severityColor.LOW, label: 'Low', kind: 'dot' },
    ] : []),
    ...(visible.logistics && vehicles.length ? [{ color: '#17324D', label: 'Convoy / task', kind: 'box' }] : []),
    ...(visible.logistics && riders.length ? [
      { color: RIDER_COLOR.active, label: 'Active rider', kind: 'box' },
      { color: RIDER_COLOR.inactive, label: 'Inactive rider', kind: 'box' },
      { color: RIDER_COLOR.blocked, label: 'Blocked road', kind: 'dash' },
      { color: RIDER_COLOR.detour, label: 'Diversion', kind: 'line' },
    ] : []),
    ...(visible.risk ? [{ color: '#E07840', label: 'Risk zone (incidents)', kind: 'zone' }] : []),
    ...(visible.ml ? [
      { color: ML_COLOR.alert, label: 'ML: high disruption risk', kind: 'dot' },
      { color: ML_COLOR.human_review, label: 'ML: needs officer review', kind: 'dot' },
      { color: '#17324D', label: 'ML model coverage', kind: 'dash' },
    ] : []),
  ];

  return (
    <div className="relative isolate overflow-hidden" style={{ height, borderRadius: rounded }}>
      <div ref={containerRef} className={`ner-map h-full w-full${pickable ? ' is-picking' : ''}`} />

      {loading && (
        <div className="absolute inset-0 z-[1100] flex flex-col items-center justify-center gap-3 pointer-events-none"
          style={{ background: 'rgba(238,242,245,0.72)', backdropFilter: 'blur(3px)' }}>
          <div className="ui-gps"><span className="ui-gps-pin">◉</span></div>
          <div className="text-xs font-medium tracking-wide" style={{ color: '#17324D' }}>Loading map…</div>
        </div>
      )}

      {(tileError || unplacedIncidents > 0 || missingCorridor || mlChip) && (
        <div className="absolute top-3 left-3 z-[1000] flex flex-col items-start gap-1 pointer-events-none">
          {tileError && <Chip>Map tiles unavailable — check your connection</Chip>}
          {missingCorridor && <Chip>No mapped geometry for {focusId}</Chip>}
          {unplacedIncidents > 0 && <Chip>{unplacedIncidents} incident{unplacedIncidents > 1 ? 's' : ''} without location data</Chip>}
          {mlChip && <Chip>{mlChip}</Chip>}
        </div>
      )}

      {showLegend && legend.length > 0 && (
        <div className="absolute bottom-6 left-3 z-[1000] rounded-md shadow-sm text-xs"
          style={{ background: 'rgba(250,247,240,0.92)', border: '1px solid rgba(200,186,164,0.6)', minWidth: 148, backdropFilter: 'blur(4px)' }}>
          <button type="button" onClick={() => setLegendOpen(open => !open)} aria-expanded={legendOpen}
            className="w-full flex items-center justify-between gap-3 px-2.5 py-1.5 font-semibold uppercase tracking-wider"
            style={{ color: '#8A9098', fontSize: 10 }}>
            Legend <span aria-hidden>{legendOpen ? '▾' : '▸'}</span>
          </button>
          {legendOpen && (
            <div className="space-y-1.5 px-2.5 pb-2.5">
              {legend.map(item => (
                <div key={item.label} className="flex items-center gap-2">
                  {item.kind === 'dot' && <span className="w-3 h-3 rounded-full border-2 border-white shadow-sm flex-shrink-0" style={{ background: item.color }} />}
                  {item.kind === 'line' && <span className="w-5 h-0.5 rounded flex-shrink-0" style={{ background: item.color }} />}
                  {item.kind === 'dash' && <span className="w-5 flex-shrink-0" style={{ borderTop: `2px dashed ${item.color}` }} />}
                  {item.kind === 'box' && <span className="w-5 h-3 rounded-sm flex-shrink-0" style={{ border: `1.5px solid ${item.color}`, background: 'rgba(250,247,240,0.95)' }} />}
                  {item.kind === 'zone' && <span className="w-3 h-3 rounded-full flex-shrink-0" style={{ background: 'rgba(224,120,64,0.2)', border: `1px solid ${item.color}` }} />}
                  <span style={{ color: '#5A6670' }}>{item.label}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-xs px-2 py-0.5 rounded-full shadow-sm"
      style={{ background: 'rgba(250,247,240,0.94)', border: '1px solid rgba(200,186,164,0.6)', color: '#5A6670' }}>
      {children}
    </span>
  );
}
