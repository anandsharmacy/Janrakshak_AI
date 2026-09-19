import { useState, useEffect, useMemo } from 'react';
import MapViz from '@/components/MapViz';
import { SeverityBadge, StatusBadge, AccessibilityBadge } from '@/components/StatusBadge';
import type { Severity } from '@/data/demo';
import { PLACES } from '@/data/geo';
import { profileService } from '@/lib/profileService';
import { getIncidents, subscribeToIncidents } from '@/lib/incidentStore';
import { getTasks, subscribeToTasks, updateTask } from '@/lib/taskStore';

/* ────────────────────────────────────────────────────────────────
   Field Officer Dashboard
   Reuses the exact District Officer design system:
   – peach→sage gradient shows through semi-transparent cream cards
   – warm earthy borders rgba(180,162,136,0.55)
   – navy / teal / gold accents, shared badge + score components
   Only the information architecture is field-operations oriented.
──────────────────────────────────────────────────────────────── */

const SURFACE = 'rgba(250,247,240,0.82)';
const BORDER = 'rgba(180,162,136,0.55)';
const SURFACE_2 = 'rgba(238,228,210,0.88)';

interface FOTask {
  id: string;
  title: string;
  location: string;
  priority: Severity;
  due: string;
  status: string;
}

function toDashboardTask(task: ReturnType<typeof getTasks>[number]): FOTask {
  return {
    id: task.id,
    title: task.title,
    location: task.location,
    priority: task.priority,
    due: task.deadline,
    status: task.status === 'New' ? 'Assigned' : task.status,
  };
}

interface NearbyIncident {
  type: string;
  icon: string;
  distance: string;
  location: string;
  severity: Severity;
  time: string;
  status: string;
}

const quickActions = [
  { label: 'Report Flood', icon: '≈', color: '#2F6F7E' },
  { label: 'Report Road Blockage', icon: '⊗', color: '#C25A1A' },
  { label: 'Report Landslide', icon: '⛰', color: '#8A6A3A' },
  { label: 'Report Accident', icon: '⊙', color: '#BE2424' },
  { label: 'Report Infrastructure Damage', icon: '⌂', color: '#17324D' },
];

function Card({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`rounded-xl border shadow-sm ${className}`} style={{ background: SURFACE, borderColor: BORDER }}>
      {children}
    </div>
  );
}

export default function FieldOfficerDashboard({ setPage }: { setPage?: (p: string) => void }) {
  const [priorityTasks, setPriorityTasks] = useState<FOTask[]>(() => getTasks().filter(task => task.assignedOfficer === 'FO-1024').map(toDashboardTask));
  const [incidents, setIncidents] = useState(() => getIncidents());

  useEffect(() => subscribeToIncidents(stored => setIncidents(stored)), []);

  const areaIncidentRecords = useMemo(() => incidents.filter(incident =>
    ['PENDING_VERIFICATION', 'ACTIVE', 'ESCALATED', 'UNDER_REVIEW'].includes(incident.status) &&
    (incident.assignedOfficer === 'FO-1024' ||
      incident.reportedBy === 'FO-1024' ||
      incident.location.toLowerCase().includes('dimapur') ||
      incident.route.toLowerCase().includes('nh-'))
  ), [incidents]);

  const areaIncidents = useMemo(() => {
    return areaIncidentRecords.slice(0, 4).map(incident => ({
      type: incident.type,
      icon: incident.type === 'Flood' ? '≈' : incident.type === 'Road Blockage' ? '⊗' : incident.type === 'Landslide' ? '⛰' : incident.type === 'Accident' ? '⊙' : '⌂',
      distance: `${Math.max(2, Math.min(18, incident.riskScore / 5))} km`,
      location: incident.location,
      severity: incident.severity,
      time: incident.reportedTime,
      status: incident.status,
    }));
  }, [areaIncidentRecords]);

  const highestSeverity = areaIncidents.length
    ? areaIncidents.reduce((max, incident) => {
        const order = { CRITICAL: 4, HIGH: 3, MODERATE: 2, LOW: 1 };
        return order[incident.severity] > order[max.severity] ? incident : max;
      }, areaIncidents[0]).severity
    : 'LOW';

  const accessibilityScore = areaIncidents.length
    ? Math.max(32, 100 - areaIncidents.reduce((sum, incident) => sum + (incident.severity === 'CRITICAL' ? 26 : incident.severity === 'HIGH' ? 18 : incident.severity === 'MODERATE' ? 10 : 4), 0) / areaIncidents.length)
    : 72;

  const kpis = [
    { label: 'Assigned Tasks', value: String(priorityTasks.length), icon: '☑', color: '#17324D', sub: priorityTasks.length ? 'Live' : 'No data' },
    { label: 'Pending Tasks', value: String(priorityTasks.filter(task => task.status === 'Assigned' || task.status === 'Accepted').length), icon: '◷', color: '#C4861A', sub: priorityTasks.length ? 'Live' : 'No data' },
    { label: 'Active Incidents', value: String(areaIncidents.length), icon: '◆', color: '#C25A1A', sub: areaIncidents.length ? 'Live' : 'No data' },
    { label: 'Critical Alerts', value: String(areaIncidents.filter(incident => incident.severity === 'CRITICAL' || incident.severity === 'HIGH').length), icon: '◬', color: '#BE2424', sub: areaIncidents.length ? 'Live' : 'No data' },
  ];
  const [profile, setProfile] = useState(() => {
    try {
      return profileService.getProfile();
    } catch (error) {
      console.error('Error loading profile in FieldOfficerDashboard:', error);
      // Return a safe fallback
      return {
        label: 'Field Officer',
        profileName: 'Field Officer',
        profileInitials: 'FO',
        officerId: 'UNKNOWN',
        department: 'Field Operations',
        region: 'Unknown District',
        phone: '',
        email: '',
        lastLogin: 'Unknown',
        status: 'Active',
      };
    }
  });

  // Subscribe to profile changes
  useEffect(() => {
    const unsubscribe = profileService.subscribe((updatedProfile) => {
      try {
        setProfile(updatedProfile);
      } catch (error) {
        console.error('Error updating profile in FieldOfficerDashboard:', error);
      }
    });
    return unsubscribe;
  }, []);

  useEffect(() => subscribeToTasks(tasks => setPriorityTasks(tasks.filter(task => task.assignedOfficer === 'FO-1024').map(toDashboardTask))), []);

  const startTask = (id: string) => {
    const task = priorityTasks.find(item => item.id === id);
    if (!task || (task.status !== 'Assigned' && task.status !== 'Accepted')) return;
    updateTask(id, { status: 'In Progress' });
  };

  return (
    <div className="space-y-6 max-w-screen-2xl">

      {/* Page header */}
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>Field Officer Dashboard</h1>
          <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>
            {profile.profileName} · Assigned Area: <span style={{ color: '#2F6F7E', fontWeight: 500 }}>{profile.region}</span>
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="inline-flex items-center gap-1.5 text-xs px-2.5 py-1 rounded border"
            style={{ background: '#EAF4EE', borderColor: '#A8D4B8', color: '#2D6B4F' }}>
            <span className="w-1.5 h-1.5 rounded-full bg-green-500 inline-block" />
            Online · Field data synced
          </span>
          <button onClick={() => setPage?.('fo-report')}
            className="text-xs px-3 py-1.5 rounded border font-medium transition-colors"
            style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
            + Report Incident
          </button>
        </div>
      </div>

      {/* KPI cards */}
      <div className="grid grid-cols-2 xl:grid-cols-4 gap-4">
        {kpis.map(kpi => (
          <Card key={kpi.label} className="p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-lg" style={{ color: kpi.color }}>{kpi.icon}</span>
              <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: kpi.color + '18', color: kpi.color }}>
                {kpi.sub}
              </span>
            </div>
            <div className="text-3xl font-bold leading-none mb-1" style={{ color: '#17212B' }}>{kpi.value}</div>
            <div className="text-xs font-medium" style={{ color: '#5A6670' }}>{kpi.label}</div>
          </Card>
        ))}
      </div>

      {/* Row: Area situation + Nearby incidents */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">

        {/* Current Area Situation */}
        <Card className="xl:col-span-1">
          <div className="px-4 py-3 border-b" style={{ borderColor: BORDER }}>
            <div className="text-xs uppercase tracking-widest" style={{ color: '#8A9098', fontSize: 10 }}>Area Status</div>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>{profile.region || 'Assigned District'}</h2>
          </div>
          <div className="p-4 space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <div className="text-xs mb-1" style={{ color: '#8A9098' }}>Accessibility Score</div>
                <AccessibilityBadge score={Math.round(accessibilityScore)} />
              </div>
              <div>
                <div className="text-xs mb-1" style={{ color: '#8A9098' }}>Risk Level</div>
                <SeverityBadge severity={highestSeverity as Severity} />
              </div>
              <div>
                <div className="text-xs mb-1" style={{ color: '#8A9098' }}>Nearby Incidents</div>
                <div className="text-xl font-bold" style={{ color: '#17212B' }}>{areaIncidents.length}</div>
              </div>
              <div>
                <div className="text-xs mb-1" style={{ color: '#8A9098' }}>Weather</div>
                <div className="text-sm font-medium" style={{ color: '#17212B' }}>{areaIncidents.length ? 'Active monitoring' : 'No critical conditions'}</div>
              </div>
            </div>

            <div>
              <div className="flex items-center justify-between text-xs mb-1" style={{ color: '#5A6670' }}>
                <span>Route accessibility</span><span className="font-semibold">{Math.round(accessibilityScore)}%</span>
              </div>
              <div className="h-2 rounded-full overflow-hidden" style={{ background: BORDER }}>
                <div className="h-full rounded-full" style={{ width: `${Math.round(accessibilityScore)}%`, background: accessibilityScore <= 50 ? '#C25A1A' : accessibilityScore <= 75 ? '#C4861A' : '#2D6B4F' }} />
              </div>
            </div>

            <div className="flex items-center justify-between pt-1 text-xs" style={{ color: '#8A9098' }}>
              <span>Last updated: just now</span>
              <button className="font-medium" style={{ color: '#2F6F7E' }}>Refresh ↻</button>
            </div>
          </div>
        </Card>

        {/* Nearby Incidents */}
        <Card className="xl:col-span-2 flex flex-col">
          <div className="px-4 py-3 border-b flex items-center justify-between" style={{ borderColor: BORDER }}>
            <div>
              <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Nearby Incidents</h2>
              <p className="text-xs" style={{ color: '#8A9098' }}>Within your assigned area</p>
            </div>
            <button onClick={() => setPage?.('fo-alerts')}
              className="text-xs font-medium px-3 py-1.5 rounded border transition-colors"
              style={{ borderColor: BORDER, color: '#2F6F7E' }}>
              View All Incidents →
            </button>
          </div>
          <div className="border-b" style={{ borderColor: BORDER }}>
            <MapViz incidents={areaIncidentRecords} height={260} rounded="0" center={PLACES.dimapur} zoom={10} showLegend={false} />
          </div>
          <div className="divide-y" style={{ borderColor: SURFACE_2 }}>
            {areaIncidents.length ? areaIncidents.map((inc, i) => (
              <div key={`${inc.type}-${i}`} className="px-4 py-3 flex items-center gap-4 transition-colors hover:bg-black/[0.02]">
                <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 text-lg"
                  style={{ background: SURFACE_2, color: '#17324D' }}>
                  {inc.icon}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold" style={{ color: '#17212B' }}>{inc.type}</span>
                    <span className="text-xs" style={{ color: '#8A9098' }}>· {inc.distance}</span>
                  </div>
                  <div className="text-xs" style={{ color: '#5A6670' }}>{inc.location} · {inc.time}</div>
                </div>
                <SeverityBadge severity={inc.severity} />
                <StatusBadge status={inc.status} />
                <button className="text-xs font-medium" style={{ color: '#2F6F7E' }}>View →</button>
              </div>
            )) : (
              <div className="px-4 py-8 text-center text-sm" style={{ color: '#8A9098' }}>
                No active incidents in your assigned area right now.
              </div>
            )}
          </div>
        </Card>
      </div>

      {/* My Priority Tasks */}
      <Card>
        <div className="px-4 py-3 border-b flex items-center justify-between" style={{ borderColor: BORDER }}>
          <div>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>My Priority Tasks</h2>
            <p className="text-xs" style={{ color: '#8A9098' }}>Sorted by priority and due time</p>
          </div>
          <button onClick={() => setPage?.('fo-tasks')}
            className="text-xs font-medium px-3 py-1.5 rounded border transition-colors"
            style={{ borderColor: BORDER, color: '#2F6F7E' }}>
            View My Tasks →
          </button>
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 p-4">
          {priorityTasks.map(task => {
            const canStart = task.status === 'Assigned' || task.status === 'Accepted';
            return (
              <div key={task.id} className="rounded-lg border p-4 flex flex-col transition-all"
                style={{ background: SURFACE_2, borderColor: BORDER }}>
                <div className="flex items-center justify-between mb-2">
                  <span className="font-mono text-xs font-semibold" style={{ color: '#2F6F7E' }}>#{task.id}</span>
                  <SeverityBadge severity={task.priority} />
                </div>
                <h3 className="font-semibold text-sm mb-2" style={{ color: '#17212B' }}>{task.title}</h3>
                <div className="space-y-1 text-xs mb-3 flex-1" style={{ color: '#5A6670' }}>
                  <div><span style={{ color: '#8A9098' }}>Location:</span> {task.location}</div>
                  <div><span style={{ color: '#8A9098' }}>Due:</span> {task.due}</div>
                  <div className="flex items-center gap-1.5 pt-0.5">
                    <span style={{ color: '#8A9098' }}>Status:</span>
                    <StatusBadge status={task.status} />
                  </div>
                </div>
                <button
                  onClick={() => startTask(task.id)}
                  disabled={!canStart}
                  className="w-full text-xs font-medium px-3 py-2 rounded transition-all"
                  style={{
                    background: canStart ? '#17324D' : '#EAF4EE',
                    color: canStart ? 'white' : '#2D6B4F',
                    minHeight: 44,
                  }}>
                  {canStart ? 'Start Task' : task.status === 'In Progress' ? 'Task Started ✓' : task.status}
                </button>
              </div>
            );
          })}
          {priorityTasks.length === 0 && <p className="p-4 text-sm" style={{ color: '#8A9098' }}>No tasks assigned yet.</p>}
        </div>
      </Card>

      {/* Quick Actions */}
      <Card>
        <div className="px-4 py-3 border-b flex items-center justify-between" style={{ borderColor: BORDER }}>
          <div>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Quick Actions</h2>
            <p className="text-xs" style={{ color: '#8A9098' }}>Report a field incident directly</p>
          </div>
          <span className="text-xs px-2 py-0.5 rounded border" style={{ borderColor: '#F5CDA8', background: '#FEF1E6', color: '#C25A1A' }}>
            Primary Operation
          </span>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4 p-4">
          {quickActions.map(action => (
            <button key={action.label} onClick={() => setPage?.('fo-report')}
              className="rounded-lg border p-4 flex flex-col items-center gap-2 text-center transition-all hover:-translate-y-0.5 hover:shadow-md"
              style={{ background: SURFACE_2, borderColor: BORDER, minHeight: 44 }}>
              <span className="w-11 h-11 rounded-full flex items-center justify-center text-xl"
                style={{ background: action.color + '18', color: action.color }}>
                {action.icon}
              </span>
              <span className="text-xs font-medium" style={{ color: '#17212B' }}>{action.label}</span>
            </button>
          ))}
        </div>
      </Card>
    </div>
  );
}
