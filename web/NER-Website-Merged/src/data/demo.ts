export type Severity = 'CRITICAL' | 'HIGH' | 'MODERATE' | 'LOW';
export type IncidentStatus = 'PENDING_VERIFICATION' | 'ACTIVE' | 'ESCALATED' | 'RESOLVED' | 'UNDER_REVIEW';
export type IncidentType = 'Flood' | 'Landslide' | 'Road Blockage' | 'Accident' | 'Infrastructure Damage' | 'Vehicle Breakdown';
export type RouteStatus = 'Open' | 'Restricted' | 'Blocked' | 'Closed';
export type OfficerStatus = 'Available' | 'On Task' | 'Emergency' | 'Offline';
export type TaskStatus = 'New' | 'In Progress' | 'Completed' | 'Escalated';

export interface IncidentEvidence {
  name: string;
  type: string;
  size: number;
  dataUrl: string;
}

export interface Incident {
  id: string;
  type: IncidentType;
  location: string;
  route: string;
  severity: Severity;
  reportedBy: string;
  reportedTime: string;
  verification: 'Pending' | 'Verified' | 'Rejected';
  assignedOfficer: string | null;
  status: IncidentStatus;
  description: string;
  gpsCoords: string;
  riskScore: number;
  affectedLogistics: number;
  estimatedDisruption: string;
  evidence?: IncidentEvidence[];
}

export interface Route {
  id: string;
  name: string;
  distance: string;
  accessibilityScore: number;
  riskScore: number;
  status: RouteStatus;
  weather: string;
  eta: string;
  delay: string;
  floodRisk: Severity;
  landslideRisk: Severity;
  lastUpdated: string;
  incidents: number;
}

export interface Vehicle {
  id: string;
  cargo: string;
  origin: string;
  destination: string;
  currentLocation: string;
  route: string;
  eta: string;
  delay: string;
  risk: Severity;
  status: 'On Time' | 'Delayed' | 'At Risk' | 'Stopped';
}

export interface FieldOfficer {
  id: string;
  name: string;
  location: string;
  currentTask: string | null;
  status: OfficerStatus;
  lastUpdate: string;
  avgResponseTime: string;
  assignedIncidents: number;
}

export interface Task {
  id: string;
  title: string;
  location: string;
  priority: Severity;
  assignedOfficer: string | null;
  created: string;
  deadline: string;
  status: TaskStatus;
  relatedIncident: string | null;
  description: string;
}

export interface Alert {
  id: string;
  severity: Severity;
  category: string;
  title: string;
  location: string;
  time: string;
  description: string;
  source: string;
  acknowledged: boolean;
}

export const incidents: Incident[] = [];
/*
  {
    id: 'INC-2026-041', type: 'Flood', location: 'Barpeta, Assam', route: 'NH-27',
    severity: 'CRITICAL', reportedBy: 'FO-102', reportedTime: '10:32 AM', verification: 'Pending',
    assignedOfficer: null, status: 'PENDING_VERIFICATION',
    description: 'Severe waterlogging on NH-27 near Barpeta bridge. Water level rising rapidly.',
    gpsCoords: '26.3219° N, 91.0013° E', riskScore: 87, affectedLogistics: 6, estimatedDisruption: '4–6 hours',
  },
  {
    id: 'INC-2026-042', type: 'Landslide', location: 'Kohima–Imphal Highway, Nagaland', route: 'NH-2',
    severity: 'HIGH', reportedBy: 'FO-118', reportedTime: '09:48 AM', verification: 'Verified',
    assignedOfficer: 'FO-121', status: 'ACTIVE',
    description: 'Partial road blockage due to landslide near Mao Gate. Debris clearance required.',
    gpsCoords: '25.6751° N, 94.1077° E', riskScore: 72, affectedLogistics: 3, estimatedDisruption: '2–3 hours',
  },
  {
    id: 'INC-2026-043', type: 'Road Blockage', location: 'Aizawl District, Mizoram', route: 'NH-306',
    severity: 'HIGH', reportedBy: 'FO-134', reportedTime: '08:15 AM', verification: 'Verified',
    assignedOfficer: 'FO-109', status: 'ESCALATED',
    description: 'Tree fall blocking both lanes. Emergency vehicle access compromised.',
    gpsCoords: '23.7271° N, 92.7173° E', riskScore: 68, affectedLogistics: 4, estimatedDisruption: '1–2 hours',
  },
  {
    id: 'INC-2026-044', type: 'Flood', location: 'Silchar, Assam', route: 'NH-6',
    severity: 'MODERATE', reportedBy: 'FO-107', reportedTime: '07:50 AM', verification: 'Verified',
    assignedOfficer: 'FO-115', status: 'ACTIVE',
    description: 'Low-lying road sections submerged. Heavy vehicles being diverted.',
    gpsCoords: '24.8333° N, 92.7789° E', riskScore: 55, affectedLogistics: 2, estimatedDisruption: '3–4 hours',
  },
  {
    id: 'INC-2026-045', type: 'Infrastructure Damage', location: 'Tawang, Arunachal Pradesh', route: 'NH-13',
    severity: 'CRITICAL', reportedBy: 'FO-128', reportedTime: '06:30 AM', verification: 'Pending',
    assignedOfficer: null, status: 'PENDING_VERIFICATION',
    description: 'Bridge damage reported near Tawang. Structural integrity assessment required.',
    gpsCoords: '27.5859° N, 91.8594° E', riskScore: 91, affectedLogistics: 8, estimatedDisruption: '8–12 hours',
  },
  {
    id: 'INC-2026-038', type: 'Vehicle Breakdown', location: 'Gangtok, Sikkim', route: 'NH-10',
    severity: 'LOW', reportedBy: 'FO-101', reportedTime: 'Yesterday 4:15 PM', verification: 'Verified',
    assignedOfficer: 'FO-103', status: 'RESOLVED',
    description: 'Medical supply vehicle breakdown resolved. Cargo transferred.',
    gpsCoords: '27.3389° N, 88.6065° E', riskScore: 12, affectedLogistics: 1, estimatedDisruption: 'Resolved',
  },
  {
    id: 'INC-2026-039', type: 'Accident', location: 'Shillong, Meghalaya', route: 'NH-40',
    severity: 'MODERATE', reportedBy: 'FO-112', reportedTime: 'Yesterday 2:30 PM', verification: 'Verified',
    assignedOfficer: 'FO-116', status: 'RESOLVED',
    description: 'Minor collision. Traffic cleared within 45 minutes.',
    gpsCoords: '25.5788° N, 91.8933° E', riskScore: 28, affectedLogistics: 1, estimatedDisruption: 'Resolved',
  },
]; */

export const routes: Route[] = [];
/*
  { id: 'NH-27', name: 'East-West Corridor (Assam)', distance: '110 km', accessibilityScore: 82, riskScore: 87, status: 'Blocked', weather: 'Heavy Rain', eta: '6h 20m', delay: '+3h 40m', floodRisk: 'CRITICAL', landslideRisk: 'MODERATE', lastUpdated: '10:45 AM', incidents: 2 },
  { id: 'NH-2', name: 'Kohima–Imphal Corridor', distance: '145 km', accessibilityScore: 48, riskScore: 72, status: 'Restricted', weather: 'Moderate Rain', eta: '4h 50m', delay: '+1h 15m', floodRisk: 'MODERATE', landslideRisk: 'HIGH', lastUpdated: '10:30 AM', incidents: 1 },
  { id: 'NH-306', name: 'Aizawl–Lunglei Highway', distance: '95 km', accessibilityScore: 55, riskScore: 68, status: 'Restricted', weather: 'Cloudy', eta: '3h 10m', delay: '+45m', floodRisk: 'LOW', landslideRisk: 'HIGH', lastUpdated: '09:50 AM', incidents: 1 },
  { id: 'NH-6', name: 'Silchar–Jiribam Corridor', distance: '205 km', accessibilityScore: 61, riskScore: 55, status: 'Restricted', weather: 'Light Rain', eta: '5h 40m', delay: '+1h 10m', floodRisk: 'HIGH', landslideRisk: 'MODERATE', lastUpdated: '10:15 AM', incidents: 1 },
  { id: 'NH-13', name: 'Tawang Highway', distance: '340 km', accessibilityScore: 78, riskScore: 91, status: 'Closed', weather: 'Fog + Rain', eta: 'Unavailable', delay: 'Indefinite', floodRisk: 'MODERATE', landslideRisk: 'CRITICAL', lastUpdated: '08:00 AM', incidents: 1 },
  { id: 'NH-40', name: 'Guwahati–Shillong Highway', distance: '100 km', accessibilityScore: 22, riskScore: 28, status: 'Open', weather: 'Partly Cloudy', eta: '2h 45m', delay: 'None', floodRisk: 'LOW', landslideRisk: 'LOW', lastUpdated: '10:50 AM', incidents: 0 },
  { id: 'NH-10', name: 'Siliguri–Gangtok Highway', distance: '115 km', accessibilityScore: 18, riskScore: 22, status: 'Open', weather: 'Clear', eta: '3h 20m', delay: '+15m', floodRisk: 'LOW', landslideRisk: 'LOW', lastUpdated: '10:55 AM', incidents: 0 },
]; */

export const vehicles: Vehicle[] = [];
/*
  { id: 'LG-102', cargo: 'Medical Supplies', origin: 'Guwahati', destination: 'Kohima', currentLocation: 'Near Dimapur', route: 'NH-2', eta: '4:40 PM', delay: '+1h 15m', risk: 'HIGH', status: 'Delayed' },
  { id: 'LG-115', cargo: 'Food Grains', origin: 'Silchar', destination: 'Aizawl', currentLocation: 'Cachar District', route: 'NH-306', eta: '6:20 PM', delay: '+45m', risk: 'MODERATE', status: 'Delayed' },
  { id: 'LG-089', cargo: 'Relief Materials', origin: 'Tezpur', destination: 'Itanagar', currentLocation: 'Sonitpur', route: 'NH-13', eta: 'Suspended', delay: 'Indefinite', risk: 'CRITICAL', status: 'Stopped' },
  { id: 'LG-134', cargo: 'Construction Materials', origin: 'Guwahati', destination: 'Shillong', currentLocation: 'En route', route: 'NH-40', eta: '2:15 PM', delay: 'None', risk: 'LOW', status: 'On Time' },
  { id: 'LG-098', cargo: 'Fuel Supplies', origin: 'Siliguri', destination: 'Gangtok', currentLocation: 'Rangpo', route: 'NH-10', eta: '3:50 PM', delay: '+20m', risk: 'LOW', status: 'On Time' },
  { id: 'LG-121', cargo: 'Telecom Equipment', origin: 'Imphal', destination: 'Kohima', currentLocation: 'Senapati', route: 'NH-2', eta: '5:30 PM', delay: '+1h 30m', risk: 'HIGH', status: 'At Risk' },
]; */

export const fieldOfficers: FieldOfficer[] = [];
/*
  { id: 'FO-101', name: 'Rajesh Barman', location: 'Guwahati HQ', currentTask: null, status: 'Available', lastUpdate: '5 min ago', avgResponseTime: '28 min', assignedIncidents: 0 },
  { id: 'FO-102', name: 'Priya Nath', location: 'Barpeta', currentTask: 'INC-2026-041 Assessment', status: 'On Task', lastUpdate: '12 min ago', avgResponseTime: '32 min', assignedIncidents: 1 },
  { id: 'FO-103', name: 'Sunil Deka', location: 'Gangtok', currentTask: 'LG-089 Reroute Support', status: 'On Task', lastUpdate: '8 min ago', avgResponseTime: '25 min', assignedIncidents: 0 },
  { id: 'FO-107', name: 'Anita Gogoi', location: 'Silchar', currentTask: null, status: 'Available', lastUpdate: '3 min ago', avgResponseTime: '35 min', assignedIncidents: 0 },
  { id: 'FO-109', name: 'Mohan Tripura', location: 'Aizawl', currentTask: 'INC-2026-043 Response', status: 'On Task', lastUpdate: '20 min ago', avgResponseTime: '40 min', assignedIncidents: 1 },
  { id: 'FO-112', name: 'Leila Khonglah', location: 'Shillong', currentTask: null, status: 'Available', lastUpdate: '1 min ago', avgResponseTime: '22 min', assignedIncidents: 0 },
  { id: 'FO-115', name: 'David Ralte', location: 'Silchar', currentTask: 'INC-2026-044 Response', status: 'On Task', lastUpdate: '15 min ago', avgResponseTime: '30 min', assignedIncidents: 1 },
  { id: 'FO-118', name: 'Zothan Puia', location: 'Kohima', currentTask: null, status: 'Available', lastUpdate: '7 min ago', avgResponseTime: '38 min', assignedIncidents: 0 },
  { id: 'FO-121', name: 'Ramesh Sharma', location: 'NH-2 Zone', currentTask: 'INC-2026-042 Response', status: 'On Task', lastUpdate: '10 min ago', avgResponseTime: '29 min', assignedIncidents: 1 },
  { id: 'FO-128', name: 'Tashi Wangchuk', location: 'Tawang', currentTask: 'Emergency Response', status: 'Emergency', lastUpdate: '25 min ago', avgResponseTime: '45 min', assignedIncidents: 1 },
  { id: 'FO-134', name: 'Lalzuali Sailo', location: 'Aizawl', currentTask: null, status: 'Offline', lastUpdate: '2h ago', avgResponseTime: '33 min', assignedIncidents: 0 },
]; */

export const tasks: Task[] = [];
/*
  { id: 'TSK-0891', title: 'Assess flood damage on NH-27 bridge', location: 'Barpeta, Assam', priority: 'CRITICAL', assignedOfficer: null, created: '10:35 AM', deadline: '12:00 PM', status: 'New', relatedIncident: 'INC-2026-041', description: 'Conduct immediate structural assessment of the NH-27 bridge at Barpeta and report water level measurements.' },
  { id: 'TSK-0890', title: 'Coordinate debris clearance — NH-2', location: 'Mao Gate, Nagaland', priority: 'HIGH', assignedOfficer: 'FO-121', created: '09:55 AM', deadline: '02:00 PM', status: 'In Progress', relatedIncident: 'INC-2026-042', description: 'Supervise NHAI clearance team. Ensure single-lane traffic is enabled within 2 hours.' },
  { id: 'TSK-0889', title: 'Reroute LG-089 medical convoy', location: 'Sonitpur, Assam', priority: 'CRITICAL', assignedOfficer: 'FO-103', created: '09:10 AM', deadline: '11:30 AM', status: 'In Progress', relatedIncident: null, description: 'Coordinate alternative route for medical supplies convoy blocked on NH-13.' },
  { id: 'TSK-0888', title: 'Monitor water level — Silchar area', location: 'Silchar, Assam', priority: 'HIGH', assignedOfficer: 'FO-115', created: '08:20 AM', deadline: '05:00 PM', status: 'In Progress', relatedIncident: 'INC-2026-044', description: 'Hourly water level reporting from 3 monitoring points in Silchar District.' },
  { id: 'TSK-0885', title: 'Submit daily situation report', location: 'Guwahati HQ', priority: 'MODERATE', assignedOfficer: 'FO-101', created: '07:00 AM', deadline: '08:00 AM', status: 'Completed', relatedIncident: null, description: 'Daily SITREP for district operations submitted to Control Officer.' },
]; */

export const alerts: Alert[] = [];
/*
  { id: 'ALT-001', severity: 'CRITICAL', category: 'Flood', title: 'Flash flood warning — NH-27 Barpeta', location: 'Barpeta, Assam', time: '10:40 AM', description: 'IMD has issued flash flood warning for next 6 hours. NH-27 at high risk of complete closure.', source: 'IMD / AI System', acknowledged: false },
  { id: 'ALT-002', severity: 'CRITICAL', category: 'Infrastructure', title: 'Bridge damage — Tawang', location: 'Tawang, Arunachal Pradesh', time: '10:22 AM', description: 'Unverified report of structural damage to Tawang bridge. Pending field verification.', source: 'Field Officer FO-128', acknowledged: false },
  { id: 'ALT-003', severity: 'HIGH', category: 'Logistics Delay', title: '3 convoys at risk — NH-2 Zone', location: 'Nagaland', time: '10:15 AM', description: 'AI prediction: LG-102, LG-121 likely to miss ETA by >90 minutes due to NH-2 restrictions.', source: 'AI Prediction System', acknowledged: false },
  { id: 'ALT-004', severity: 'HIGH', category: 'Escalation', title: 'INC-2026-043 exceeds SLA threshold', location: 'Aizawl, Mizoram', time: '09:50 AM', description: 'Incident unresolved beyond 4-hour SLA. Escalation to Control Officer initiated.', source: 'System Automation', acknowledged: true },
  { id: 'ALT-005', severity: 'MODERATE', category: 'AI Warning', title: 'Increased landslide probability — NH-306', location: 'Mizoram', time: '09:30 AM', description: 'AI model predicts 64% landslide probability on NH-306 in next 12 hours based on rainfall patterns.', source: 'AI Risk Model', acknowledged: true },
  { id: 'ALT-006', severity: 'MODERATE', category: 'Route Closure', title: 'NH-13 closed indefinitely', location: 'Tawang, Arunachal Pradesh', time: '08:05 AM', description: 'NH-13 has been officially closed pending structural inspection of bridge and road assessment.', source: 'NHAI', acknowledged: true },
]; */

export const aiInsights = {
  riskPredictions: [],
  /*
    { route: 'NH-27', probability: 94, window: 'Next 3 hours', confidence: 89, factors: ['Active flooding', 'IMD flash flood warning', 'High water level', 'Historical risk zone'] },
    { route: 'NH-13', probability: 78, window: 'Next 6 hours', confidence: 72, factors: ['Bridge structural damage', 'Heavy rainfall forecast', 'Remote location', 'Limited access'] },
    { route: 'NH-306', probability: 64, window: 'Next 12 hours', confidence: 68, factors: ['Saturated soil', 'Steep gradient', 'Previous landslide history', 'Rainfall forecast'] },
  ], */
  logisticsPredictions: [],
  /*
    { route: 'NH-2', convoys: 2, probability: 82, estimatedDelay: '+1h 30m', cause: 'Landslide debris clearance' },
    { route: 'NH-27', convoys: 3, probability: 97, estimatedDelay: 'Indefinite', cause: 'Active flooding, road closure' },
    { route: 'NH-306', convoys: 1, probability: 58, estimatedDelay: '+45m', cause: 'Road blockage clearance' },
  ], */
  routeRecommendations: [],
  /*
    { from: 'NH-27', to: 'NH-37 via Jorhat', reason: 'Avoid active flood zone', savings: 'Risk reduction: 94% → 18%', additionalDistance: '+35 km' },
    { from: 'NH-13', to: 'Air transport via Tezpur', reason: 'Road closed indefinitely', savings: 'Ensures delivery of critical supplies', additionalDistance: 'N/A' },
  ], */
  resourceRecommendations: [],
  /*
    'Deploy 2 additional field teams to Barpeta — NH-27 situation deteriorating rapidly.',
    'Pre-position NDRF team at Kohima for potential NH-2 emergency response.',
    '1 logistics coordinator needed at Dimapur to manage convoy rerouting.',
  ], */
};
