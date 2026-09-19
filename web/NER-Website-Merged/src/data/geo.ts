/* Geographic reference data for the North Eastern Region.
   Place coordinates are city centres; corridor paths are simplified
   waypoint polylines that follow each highway's general alignment. */

export type LatLng = [number, number];

export const NER_CENTER: LatLng = [26.2, 92.9];
export const NER_ZOOM = 6;

export const PLACES: Record<string, LatLng> = {
  guwahati: [26.1445, 91.7362],
  kamrup: [26.1445, 91.7362],
  dimapur: [25.9063, 93.7276],
  kohima: [25.6751, 94.1086],
  imphal: [24.817, 93.9368],
  shillong: [25.5788, 91.8933],
  aizawl: [23.7271, 92.7176],
  agartala: [23.8315, 91.2868],
  itanagar: [27.0844, 93.6053],
  gangtok: [27.3389, 88.6065],
  silchar: [24.8333, 92.7789],
  cachar: [24.8333, 92.7789],
  tezpur: [26.6528, 92.7926],
  sonitpur: [26.6528, 92.7926],
  jorhat: [26.7509, 94.2037],
  dibrugarh: [27.4728, 94.912],
  nagaon: [26.348, 92.6838],
  barpeta: [26.3226, 91.006],
  bongaigaon: [26.4831, 90.5627],
  tawang: [27.5859, 91.8594],
  bomdila: [27.2645, 92.4159],
  siliguri: [26.7271, 88.3953],
  rangpo: [27.176, 88.53],
  lunglei: [22.8671, 92.7655],
  kolasib: [24.2244, 92.6763],
  jiribam: [24.8055, 93.1128],
  senapati: [25.2677, 94.02],
  'mao gate': [25.5167, 94.1333],
  haflong: [25.1686, 93.0167],
  lumding: [25.7502, 93.1712],
  chumoukedima: [25.7962, 93.7806],
  mokokchung: [26.3265, 94.5248],
  wokha: [26.1003, 94.2626],
};

export const CORRIDORS: Record<string, { name: string; path: LatLng[] }> = {
  'NH-27': {
    name: 'East-West Corridor (Assam)',
    path: [[26.47, 89.97], PLACES.bongaigaon, [26.5, 90.97], PLACES.guwahati, PLACES.nagaon, PLACES.lumding, PLACES.haflong, PLACES.silchar],
  },
  'NH-2': {
    name: 'Kohima–Imphal Corridor',
    path: [PLACES.mokokchung, PLACES.wokha, PLACES.kohima, PLACES['mao gate'], PLACES.senapati, PLACES.imphal],
  },
  'NH-29': {
    name: 'Dimapur–Kohima Highway',
    path: [PLACES.dimapur, PLACES.chumoukedima, [25.74, 93.93], PLACES.kohima],
  },
  'NH-306': {
    name: 'Silchar–Aizawl–Lunglei Highway',
    path: [PLACES.silchar, [24.5, 92.75], PLACES.kolasib, PLACES.aizawl, [23.3, 92.75], PLACES.lunglei],
  },
  'NH-6': {
    name: 'Silchar–Jiribam Corridor',
    path: [PLACES.silchar, [24.82, 92.95], PLACES.jiribam],
  },
  'NH-37': {
    name: 'Jiribam–Imphal Highway',
    path: [PLACES.jiribam, [24.87, 93.4], [24.82, 93.7], PLACES.imphal],
  },
  'NH-13': {
    name: 'Tawang Highway',
    path: [PLACES.tezpur, [27.01, 92.65], PLACES.bomdila, [27.5, 92.1], PLACES.tawang],
  },
  'NH-40': {
    name: 'Guwahati–Shillong Highway',
    path: [PLACES.guwahati, [25.9, 91.88], PLACES.shillong],
  },
  'NH-10': {
    name: 'Siliguri–Gangtok Highway',
    path: [PLACES.siliguri, [26.89, 88.47], PLACES.rangpo, PLACES.gangtok],
  },
};

/** "nh 29", "NH29", "nh-29 " → "NH-29" */
export function normalizeRouteId(value: string): string {
  const match = value.trim().match(/^nh[\s-]*(\d+[a-z]?)$/i);
  return match ? `NH-${match[1].toUpperCase()}` : value.trim().toUpperCase();
}

export function corridorFor(routeId: string) {
  return CORRIDORS[normalizeRouteId(routeId)] ?? null;
}

/** Parses "26.3219° N, 91.0013° E" or "26.3219, 91.0013". */
export function parseCoords(value: string | null | undefined): LatLng | null {
  if (!value) return null;
  const match = value.match(/(-?\d+(?:\.\d+)?)\s*°?\s*([NS])?\s*(?:,|\s)\s*(-?\d+(?:\.\d+)?)\s*°?\s*([EW])?/i);
  if (!match) return null;
  let lat = parseFloat(match[1]);
  let lng = parseFloat(match[3]);
  if (match[2]?.toUpperCase() === 'S') lat = -Math.abs(lat);
  if (match[4]?.toUpperCase() === 'W') lng = -Math.abs(lng);
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return [lat, lng];
}

export function formatCoords([lat, lng]: LatLng): string {
  return `${Math.abs(lat).toFixed(6)}° ${lat >= 0 ? 'N' : 'S'}, ${Math.abs(lng).toFixed(6)}° ${lng >= 0 ? 'E' : 'W'}`;
}

/** Finds the first known place mentioned in free text, e.g. "Barpeta, Assam". */
export function placeFor(text: string | null | undefined): LatLng | null {
  if (!text) return null;
  const lower = text.toLowerCase();
  const key = Object.keys(PLACES).find(name => lower.includes(name));
  return key ? PLACES[key] : null;
}

function corridorMidpoint(routeId: string): LatLng | null {
  const corridor = corridorFor(routeId);
  return corridor ? corridor.path[Math.floor(corridor.path.length / 2)] : null;
}

/** Best available position: captured GPS, then a named place, then the route's midpoint. */
export function locate(item: { gpsCoords?: string; location?: string; route?: string }): LatLng | null {
  return parseCoords(item.gpsCoords) ?? placeFor(item.location) ?? (item.route ? corridorMidpoint(item.route) : null);
}
