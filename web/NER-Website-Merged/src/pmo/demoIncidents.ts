import type { Incident } from '@/data/demo';
import { districtsOf, nameKey, resolveState } from '@/data/indiaLocations';
import { makeIncident } from './incidents';
import type { NationalIncident } from './types';

const RAW_TYPE: Record<Incident['type'], string> = {
  Flood: 'flood',
  Landslide: 'landslide',
  'Road Blockage': 'road_block',
  Accident: 'accident',
  'Infrastructure Damage': 'infrastructure_damage',
  'Vehicle Breakdown': 'vehicle_breakdown',
};

const STATUS: Record<Incident['status'], string> = {
  PENDING_VERIFICATION: 'pending',
  UNDER_REVIEW: 'pending',
  ACTIVE: 'active',
  ESCALATED: 'escalated',
  RESOLVED: 'resolved',
};

const SEVERITY: Record<Incident['severity'], string> = { CRITICAL: 'critical', HIGH: 'high', MODERATE: 'medium', LOW: 'low' };

/** "26.32° N, 91.00° E" -> [lat, lng]. */
function parseCoords(text: string): [number, number] | null {
  const m = /(-?[\d.]+)\s*°?\s*N\s*,\s*(-?[\d.]+)\s*°?\s*E/i.exec(text);
  return m ? [Number(m[1]), Number(m[2])] : null;
}

/** Adapts the site's existing demo incidents ("Barpeta, Assam" style locations) to the national model. */
export function demoNationalIncidents(list: Incident[]): NationalIncident[] {
  return list.map(d => {
    const parts = d.location.split(',').map(p => p.trim());
    const state = resolveState(parts[parts.length - 1]);
    const first = nameKey(parts[0]);
    const district = state
      ? districtsOf(state.region, state.state).find(x => nameKey(x) === first) ?? null
      : null;
    const coords = parseCoords(d.gpsCoords);
    return makeIncident({
      id: d.id, reference: d.id, source: 'demo', rawType: RAW_TYPE[d.type] ?? 'other',
      title: `${d.type} · ${d.location}`, description: d.description,
      severity: SEVERITY[d.severity], status: STATUS[d.status],
      state: state?.state ?? null, district, lat: coords?.[0] ?? null, lng: coords?.[1] ?? null,
      reportedAt: d.reportedTime, reporter: d.reportedBy,
    });
  });
}
