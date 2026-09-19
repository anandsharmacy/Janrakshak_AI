import { nameKey } from '@/data/indiaLocations';
import { isActive } from './incidents';
import type { NationalIncident } from './types';

export interface PmoFilters {
  region: string;
  state: string;
  district: string;
  /** Incident type ids; empty means every type. */
  types: string[];
  includeResolved: boolean;
}

export const EMPTY_FILTERS: PmoFilters = { region: '', state: '', district: '', types: [], includeResolved: false };

/** Geography and status only, so the per-type statistics stay comparable while a type is selected. */
function inScope(i: NationalIncident, f: PmoFilters): boolean {
  if (f.region && i.region !== f.region) return false;
  if (f.state && i.state !== f.state) return false;
  if (f.district && nameKey(i.district ?? '') !== nameKey(f.district)) return false;
  return f.includeResolved || isActive(i);
}

export const applyFilters = (list: NationalIncident[], f: PmoFilters) =>
  list.filter(i => inScope(i, f) && (f.types.length === 0 || f.types.includes(i.typeId)));

export function computeStats(list: NationalIncident[], f: PmoFilters) {
  const byType: Record<string, number> = {};
  for (const i of list) if (inScope(i, f)) byType[i.typeId] = (byType[i.typeId] ?? 0) + 1;
  const counted = f.types.length ? f.types : Object.keys(byType);
  return { byType, total: counted.reduce((sum, id) => sum + (byType[id] ?? 0), 0) };
}

export const scopeLabel = (f: PmoFilters) =>
  [f.region, f.state, f.district].filter(Boolean).join(' › ') || 'All India';
