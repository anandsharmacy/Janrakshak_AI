import type { Incident, Severity } from '@/data/demo';
import { formatCoords, parseCoords } from '@/data/geo';
import { getSessionSource } from '@/lib/auth';
import { supabase } from '@/lib/supabase';

export type IncidentEvidence = NonNullable<Incident['evidence']>[number];

export type StoredIncident = Incident & { evidence: IncidentEvidence[] };

const STORAGE_KEY = 'ner-incidents';
const INCIDENTS_CHANGED = 'ner-incidents-changed';

/** Incidents from the database (`road_incidents`) for the signed-in user; row-level security decides which. Memory only, so they never outlive the session in browser storage. */
let serverIncidents: StoredIncident[] = [];

function readLocalIncidents(): StoredIncident[] {
  if (typeof window === 'undefined') return [];

  try {
    const value = window.localStorage.getItem(STORAGE_KEY);
    if (!value) return [];
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function readIncidents(): StoredIncident[] {
  return [...readLocalIncidents(), ...serverIncidents];
}

function publish(incidents: StoredIncident[]) {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(incidents));
  window.dispatchEvent(new CustomEvent(INCIDENTS_CHANGED, { detail: incidents }));
}

function createIncidentId() {
  const timestamp = new Date().getTime().toString().slice(-6);
  const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
  return `INC-${new Date().getFullYear()}-${timestamp}${random}`;
}

export function getIncidents(): StoredIncident[] {
  return readIncidents();
}

export function addIncident(input: {
  type: Incident['type'];
  location: string;
  route: string;
  severity: Severity;
  reportedBy: string;
  description: string;
  gpsCoords: string;
  evidence: IncidentEvidence[];
}) {
  const incident: StoredIncident = {
    id: createIncidentId(),
    type: input.type,
    location: input.location.trim() || 'Location not provided',
    route: input.route.trim() || 'Route not provided',
    severity: input.severity,
    reportedBy: input.reportedBy,
    reportedTime: new Date().toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }),
    verification: 'Pending',
    assignedOfficer: null,
    status: 'PENDING_VERIFICATION',
    description: input.description.trim() || 'No description provided.',
    gpsCoords: input.gpsCoords || 'Not captured',
    riskScore: input.severity === 'CRITICAL' ? 90 : input.severity === 'HIGH' ? 70 : input.severity === 'MODERATE' ? 45 : 20,
    affectedLogistics: 0,
    estimatedDisruption: 'Pending assessment',
    evidence: input.evidence,
  };

  publish([...readLocalIncidents(), incident]);
  return incident;
}

export function updateIncident(id: string, updates: Partial<Pick<Incident, 'verification' | 'assignedOfficer' | 'status'>>) {
  if (serverIncidents.some(incident => incident.id === id)) {
    // Database incident: status and verification are persisted; the officer assignment is not (the UI only has a display id, the table needs a user id).
    const { assignedOfficer: _ignored, ...persisted } = updates;
    serverIncidents = serverIncidents.map(incident => incident.id === id ? { ...incident, ...persisted } : incident);
    window.dispatchEvent(new CustomEvent(INCIDENTS_CHANGED));
    void saveIncidentUpdate(id, persisted);
    return;
  }
  const incidents = readLocalIncidents().map(incident => incident.id === id ? { ...incident, ...updates } : incident);
  publish(incidents);
}

export function subscribeToIncidents(listener: (incidents: StoredIncident[]) => void) {
  if (typeof window === 'undefined') return () => {};

  const notify = () => listener(readIncidents());
  window.addEventListener(INCIDENTS_CHANGED, notify);
  window.addEventListener('storage', notify);
  if (++subscribers === 1) startServerSync();
  return () => {
    window.removeEventListener(INCIDENTS_CHANGED, notify);
    window.removeEventListener('storage', notify);
    if (--subscribers === 0) stopServerSync();
  };
}

// ---- Database-backed incidents (Supabase `road_incidents` table) ------------------------------

const isLive = () => !!supabase && getSessionSource() === 'supabase';

const CATEGORY_TO_DB: Record<string, string> = {
  'Road Blockage': 'road_block', Flood: 'flood', Landslide: 'landslide', Accident: 'accident',
  'Infrastructure Damage': 'infrastructure_damage', 'Vehicle Breakdown': 'vehicle_breakdown',
};
const CATEGORY_FROM_DB: Record<string, string> = {
  road_block: 'Road Blockage', flood: 'Flood', landslide: 'Landslide', bridge_damage: 'Infrastructure Damage',
  vehicle_breakdown: 'Vehicle Breakdown', accident: 'Accident', infrastructure_damage: 'Infrastructure Damage', other: 'Other',
};
const SEVERITY_FROM_DB: Record<string, Severity> = { critical: 'CRITICAL', high: 'HIGH', moderate: 'MODERATE', medium: 'MODERATE', low: 'LOW', info: 'LOW' };
const RISK_SCORE: Record<Severity, number> = { CRITICAL: 90, HIGH: 70, MODERATE: 45, LOW: 20 };
const STATUS_FROM_DB: Record<string, Incident['status']> = { pending: 'PENDING_VERIFICATION', active: 'ACTIVE', escalated: 'ESCALATED', resolved: 'RESOLVED' };
const STATUS_TO_DB: Record<string, string> = { PENDING_VERIFICATION: 'pending', UNDER_REVIEW: 'pending', ACTIVE: 'active', ESCALATED: 'escalated', RESOLVED: 'resolved' };
// Types the private `incident-media` bucket accepts.
const EVIDENCE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'video/mp4', 'video/quicktime', 'video/3gpp'];

interface IncidentRow {
  id: string; incident_ref: string | null; reported_by: string | null; category: string; title: string | null;
  description: string | null; severity: string; status: string; verified: boolean; assigned_to: string | null;
  district: string | null; state: string | null; location_text: string | null; route_text: string | null;
  latitude: number | null; longitude: number | null; sync_source: string; created_at: string;
}

let inFlight: Promise<void> | null = null;
let rerun = false;

/** Reloads the incidents the signed-in user may see and notifies every incident view. Overlapping calls are coalesced into one follow-up. */
export function syncIncidentsFromServer(): Promise<void> {
  if (inFlight) {
    rerun = true;
    return inFlight;
  }
  inFlight = loadServerIncidents().finally(() => {
    inFlight = null;
    if (rerun) {
      rerun = false;
      void syncIncidentsFromServer();
    }
  });
  return inFlight;
}

async function loadServerIncidents(): Promise<void> {
  if (!supabase || !isLive()) {
    if (serverIncidents.length) {
      serverIncidents = [];
      window.dispatchEvent(new CustomEvent(INCIDENTS_CHANGED));
    }
    return;
  }
  const [{ data: session }, { data, error }] = await Promise.all([
    supabase.auth.getSession(),
    supabase.from('road_incidents')
      .select('id, incident_ref, reported_by, category, title, description, severity, status, verified, assigned_to, district, state, location_text, route_text, latitude, longitude, sync_source, created_at')
      .order('created_at', { ascending: true }),
  ]);
  if (error || !data) return;

  const rows = data as IncidentRow[];
  const me = session.session?.user.id;
  const ids = [...new Set(rows.flatMap(row => [row.reported_by, row.assigned_to]).filter((id): id is string => !!id))];
  const { data: profiles } = ids.length ? await supabase.from('profiles').select('id, officer_id, full_name').in('id', ids) : { data: [] };
  const names = new Map((profiles ?? []).map(p => [p.id as string, (p.officer_id || p.full_name || '') as string]));

  serverIncidents = rows.map(row => {
    const severity = SEVERITY_FROM_DB[row.severity] ?? 'MODERATE';
    const status = STATUS_FROM_DB[row.status] ?? 'PENDING_VERIFICATION';
    const place = [row.district, row.state].filter(Boolean).join(', ');
    return {
      id: row.incident_ref ?? row.id,
      type: (CATEGORY_FROM_DB[row.category] ?? 'Other') as Incident['type'],
      location: row.location_text || place || row.title || 'Location not provided',
      route: row.route_text || 'Route not provided',
      severity,
      // "Field Officer" is how the field pages recognise the signed-in officer's own reports.
      reportedBy: row.reported_by === me ? 'Field Officer' : (row.reported_by && names.get(row.reported_by)) || (row.sync_source === 'citizen_app' ? 'Citizen' : 'Field Officer'),
      reportedTime: new Date(row.created_at).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }),
      verification: row.verified ? 'Verified' : 'Pending',
      assignedOfficer: row.assigned_to ? names.get(row.assigned_to) || row.assigned_to.slice(0, 8) : null,
      status,
      description: row.description || 'No description provided.',
      gpsCoords: row.latitude != null && row.longitude != null ? formatCoords([row.latitude, row.longitude]) : 'Not captured',
      riskScore: RISK_SCORE[severity],
      affectedLogistics: 0,
      estimatedDisruption: status === 'RESOLVED' ? 'Resolved' : 'Pending assessment',
      evidence: [],
    };
  });
  window.dispatchEvent(new CustomEvent(INCIDENTS_CHANGED));
}

async function saveIncidentUpdate(id: string, updates: Partial<Pick<Incident, 'verification' | 'status'>>) {
  if (!supabase) return;
  const patch: Record<string, unknown> = {};
  if (updates.status && STATUS_TO_DB[updates.status]) patch.status = STATUS_TO_DB[updates.status];
  if (updates.verification) {
    const verified = updates.verification === 'Verified';
    patch.verified = verified;
    patch.verified_at = verified ? new Date().toISOString() : null;
    patch.verified_by = verified ? (await supabase.auth.getSession()).data.session?.user.id ?? null : null;
  }
  if (!Object.keys(patch).length) return;
  const { error } = await supabase.from('road_incidents').update(patch).eq('incident_ref', id);
  if (error) void syncIncidentsFromServer(); // the database refused it: show what is really stored
}

/**
 * Saves a field report. With a live session it goes to the database (evidence to the private `incident-media`
 * bucket first), so district and control dashboards on other devices see it; the offline demo keeps it in this browser.
 */
export async function submitIncident(input: Parameters<typeof addIncident>[0]): Promise<{ id: string }> {
  if (!supabase || !isLive()) {
    try {
      return addIncident(input);
    } catch {
      throw new Error('Incident could not be saved. Please remove large files and try again.');
    }
  }
  const uid = (await supabase.auth.getSession()).data.session?.user.id;
  if (!uid) throw new Error('Your session has expired. Please sign in again.');

  const id = crypto.randomUUID();
  const prefix = `${uid}/${id}/`;
  let uploaded = 0;
  for (const [index, file] of input.evidence.entries()) {
    if (!EVIDENCE_TYPES.includes(file.type)) continue;
    const blob = await (await fetch(file.dataUrl)).blob();
    const { error } = await supabase.storage.from('incident-media')
      .upload(`${prefix}${index}-${file.name.replace(/[^\w.-]+/g, '_')}`, blob, { contentType: file.type });
    if (error) throw new Error('Could not upload the evidence. Please try again.');
    uploaded++;
  }

  const pin = parseCoords(input.gpsCoords);
  const { data, error } = await supabase.from('road_incidents').insert({
    id,
    reported_by: uid,
    category: CATEGORY_TO_DB[input.type] ?? 'other',
    title: `${input.type} - ${input.location.trim() || 'Location not provided'}`,
    description: input.description.trim() || null,
    severity: input.severity.toLowerCase(),
    location_text: input.location.trim() || null,
    route_text: input.route.trim() || null,
    ...(pin ? { geometry: `SRID=4326;POINT(${pin[1]} ${pin[0]})` } : {}),
    ...(uploaded ? { media_path: prefix } : {}),
  }).select('incident_ref').single();
  if (error) {
    throw new Error(error.code === '42501' ? 'You are not permitted to report incidents.' : 'Could not submit the incident. Please try again.');
  }
  await syncIncidentsFromServer();
  return { id: data.incident_ref ?? id };
}

// Live updates: the first incident view to mount loads the list and listens for changes; the last to unmount stops.
let subscribers = 0;
let channelSeq = 0;
let channel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null;

function startServerSync() {
  if (!supabase || !isLive()) return;
  void syncIncidentsFromServer();
  channel = supabase.channel(`road-incidents-web-${++channelSeq}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'road_incidents' }, () => void syncIncidentsFromServer())
    .subscribe();
}

function stopServerSync() {
  if (channel) {
    void supabase?.removeChannel(channel);
    channel = null;
  }
  serverIncidents = [];
}
