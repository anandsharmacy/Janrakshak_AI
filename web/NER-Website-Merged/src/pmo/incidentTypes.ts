/**
 * Incident categories shown on the PMO dashboard. To add a category, add one entry here:
 * `raw` lists the database values (incident_type_enum / disaster_type_enum) it groups.
 * Anything unlisted falls into "other", so new database values never disappear from the map.
 */
export interface IncidentTypeDef {
  id: string;
  label: string;
  color: string;
  raw: string[];
}

export const INCIDENT_TYPES: IncidentTypeDef[] = [
  { id: 'road_blockage', label: 'Road Blockage', color: '#C25A1A', raw: ['road_block', 'road_blockage'] },
  { id: 'flood', label: 'Flood', color: '#2F6F7E', raw: ['flood', 'flash_flood'] },
  { id: 'landslide', label: 'Landslide', color: '#8A5A2B', raw: ['landslide'] },
  { id: 'accident', label: 'Accident', color: '#BE2424', raw: ['accident'] },
  { id: 'infrastructure', label: 'Infrastructure', color: '#5B4B8A', raw: ['bridge_damage', 'infrastructure_damage'] },
  { id: 'other', label: 'Other', color: '#5A6670', raw: [] },
];

export const typeIdOf = (raw: string): string =>
  INCIDENT_TYPES.find(t => t.raw.includes(raw.toLowerCase()))?.id ?? 'other';

export const typeDef = (id: string): IncidentTypeDef =>
  INCIDENT_TYPES.find(t => t.id === id) ?? INCIDENT_TYPES[INCIDENT_TYPES.length - 1];
