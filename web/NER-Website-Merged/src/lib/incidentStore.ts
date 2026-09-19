import type { Incident, Severity } from '@/data/demo';

export type IncidentEvidence = NonNullable<Incident['evidence']>[number];

export type StoredIncident = Incident & { evidence: IncidentEvidence[] };

const STORAGE_KEY = 'ner-incidents';
const INCIDENTS_CHANGED = 'ner-incidents-changed';

function readIncidents(): StoredIncident[] {
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

  publish([...readIncidents(), incident]);
  return incident;
}

export function updateIncident(id: string, updates: Partial<Pick<Incident, 'verification' | 'assignedOfficer' | 'status'>>) {
  const incidents = readIncidents().map(incident => incident.id === id ? { ...incident, ...updates } : incident);
  publish(incidents);
}

export function subscribeToIncidents(listener: (incidents: StoredIncident[]) => void) {
  if (typeof window === 'undefined') return () => {};

  const notify = () => listener(readIncidents());
  window.addEventListener(INCIDENTS_CHANGED, notify);
  window.addEventListener('storage', notify);
  return () => {
    window.removeEventListener(INCIDENTS_CHANGED, notify);
    window.removeEventListener('storage', notify);
  };
}
