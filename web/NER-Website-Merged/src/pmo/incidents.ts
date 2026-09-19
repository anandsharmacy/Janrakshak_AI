import { resolveState } from '@/data/indiaLocations';
import { typeIdOf } from './incidentTypes';
import type { NationalIncident } from './types';

type IncidentInput = Omit<NationalIncident, 'typeId' | 'region' | 'state'> & { state: string | null };

/** Normalises the state to the CSV spelling and derives typeId and region, so every source filters the same way. */
export function makeIncident(input: IncidentInput): NationalIncident {
  const resolved = resolveState(input.state);
  return {
    ...input,
    typeId: typeIdOf(input.rawType),
    state: resolved?.state ?? input.state,
    region: resolved?.region ?? null,
  };
}

export const isActive = (incident: NationalIncident) => incident.status !== 'resolved';
