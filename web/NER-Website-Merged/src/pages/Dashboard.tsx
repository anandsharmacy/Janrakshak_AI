import { useEffect, useMemo, useState } from 'react';
import MapViz from '@/components/MapViz';
import { SeverityBadge, StatusBadge } from '@/components/StatusBadge';
import { getIncidents, subscribeToIncidents } from '@/lib/incidentStore';
import { getTasks, subscribeToTasks } from '@/lib/taskStore';
import { routes, vehicles, aiInsights } from '@/data/demo';
import type { Alert } from '@/data/demo';
import { profileService, type ProfileMeta } from '@/lib/profileService';

const toMinutesSince = (reportedTime: string) => {
  const parsed = new Date(reportedTime);
  if (Number.isNaN(parsed.getTime())) return 0;
  return Math.max(0, Math.round((Date.now() - parsed.getTime()) / 60000));
};

function buildAlerts(incidentList: ReturnType<typeof getIncidents>, taskList: ReturnType<typeof getTasks>): Alert[] {
  const incidentAlerts: Alert[] = incidentList.map(incident => ({
    id: `incident-${incident.id}`,
    severity: incident.severity,
    category: incident.type === 'Road Blockage' ? 'Route Closure' : incident.type === 'Flood' ? 'Flood' : incident.type === 'Landslide' ? 'Landslide' : incident.status === 'ESCALATED' ? 'Escalation' : incident.type,
    title: incident.status === 'ESCALATED' ? `Escalated: ${incident.type}` : `Pending ${incident.type.toLowerCase()} report`,
    location: incident.location,
    time: incident.reportedTime,
    description: incident.description,
    source: incident.reportedBy,
    acknowledged: incident.status === 'RESOLVED',
  }));

  const taskAlerts: Alert[] = taskList.filter(task => ['New', 'In Progress', 'Escalated'].includes(task.status)).map(task => {
    const category = /logistics|convoy|supply/i.test(task.title) ? 'Logistics Delay' : task.status === 'Escalated' ? 'Escalation' : 'Task';
    return {
      id: `task-${task.id}`,
      severity: task.priority,
      category,
      title: task.status === 'Escalated' ? `Task escalated: ${task.title}` : `Task update: ${task.title}`,
      location: task.location,
      time: task.created,
      description: task.description,
      source: task.assignedOfficer ?? 'System',
      acknowledged: task.status === 'Completed' || task.status === 'Escalated',
    };
  });

  return [...incidentAlerts, ...taskAlerts].sort((a, b) => new Date(b.time).getTime() - new Date(a.time).getTime());
}

export default function Dashboard({ setPage }: { setPage: (p: string) => void }) {
  const [incidents, setIncidents] = useState<ReturnType<typeof getIncidents>>(() => getIncidents());
  const [tasks, setTasks] = useState<ReturnType<typeof getTasks>>(() => getTasks());
  const [profile, setProfile] = useState<ProfileMeta>(() => {
    try {
      return profileService.getProfile();
    } catch {
      return {
        label: 'District Officer',
        profileName: 'District Officer',
        profileInitials: 'DO',
        officerId: 'NER-DO-0000',
        department: 'District Operations',
        region: 'Kamrup Metro, Assam',
        phone: '',
        email: '',
        lastLogin: 'Current session',
        status: 'Active',
      };
    }
  });

  useEffect(() => subscribeToIncidents(stored => setIncidents(stored)), []);
  useEffect(() => subscribeToTasks(stored => setTasks(stored)), []);
  useEffect(() => {
    const unsubscribe = profileService.subscribe(updated => setProfile(updated));
    return unsubscribe;
  }, []);

  const pendingIncidents = useMemo(() => incidents.filter(i => i.status === 'PENDING_VERIFICATION' || i.status === 'UNDER_REVIEW'), [incidents]);
  const activeIncidents = useMemo(() => incidents.filter(i => i.status === 'ACTIVE' || i.status === 'ESCALATED'), [incidents]);
  const blockedRoutes = useMemo(() => new Set(incidents.filter(i => i.status === 'ACTIVE' || i.status === 'ESCALATED').map(i => i.route)).size, [incidents]);
  const highRiskRoutes = useMemo(() => new Set(incidents.filter(i => i.severity === 'HIGH' || i.severity === 'CRITICAL').map(i => i.route)).size, [incidents]);
  const activeLogistics = useMemo(() => tasks.filter(task => task.status === 'New' || task.status === 'In Progress' || task.status === 'Escalated').length, [tasks]);
  const avgResponseMinutes = incidents.length ? Math.round(incidents.reduce((sum, incident) => sum + toMinutesSince(incident.reportedTime), 0) / incidents.length) : 0;
  const alerts = useMemo(() => buildAlerts(incidents, tasks), [incidents, tasks]);
  const criticalAlerts = alerts.filter(a => !a.acknowledged && (a.severity === 'CRITICAL' || a.severity === 'HIGH'));
  const highAlerts = alerts.filter(a => !a.acknowledged && a.severity === 'HIGH');

  const kpis = [
    { label: 'Active Incidents', value: String(activeIncidents.length), icon: '◆', change: `${pendingIncidents.length} pending review`, changeUp: false, color: '#BE2424' },
    { label: 'Blocked Routes', value: String(blockedRoutes), icon: '→', change: blockedRoutes ? 'Live route impact' : 'No blocked routes', changeUp: false, color: '#C25A1A' },
    { label: 'High-Risk Routes', value: String(highRiskRoutes), icon: '▲', change: highRiskRoutes ? 'Priority monitoring' : 'Stable', changeUp: false, color: '#C4861A' },
    { label: 'Active Logistics', value: String(activeLogistics), icon: '⊟', change: activeLogistics ? 'Field operations active' : 'No active logistics', changeUp: false, color: '#2F6F7E' },
    { label: 'Pending Reports', value: String(pendingIncidents.length), icon: '⊡', change: pendingIncidents.length ? 'Awaiting verification' : 'All clear', changeUp: false, color: '#17324D' },
    { label: 'Avg Response Time', value: `${avgResponseMinutes} min`, icon: '◷', change: avgResponseMinutes <= 45 ? 'Within SLA' : 'Needs attention', changeUp: avgResponseMinutes <= 45, color: '#C4861A' },
  ];

  return (
    <div className="space-y-6 max-w-screen-2xl">

      {/* Page header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>District Operations</h1>
          <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>
            {profile.region ? `${profile.region} · ` : ''}Real-time district connectivity, logistics and incident intelligence
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="inline-flex items-center gap-1.5 text-xs px-2.5 py-1 rounded border"
            style={{ background: '#EAF4EE', borderColor: '#A8D4B8', color: '#2D6B4F' }}>
            <span className="w-1.5 h-1.5 rounded-full bg-green-500 inline-block"></span>
            Live Monitoring Active
          </span>
          <button className="text-xs px-3 py-1.5 rounded border font-medium transition-colors"
            style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
            Generate Report
          </button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-4">
        {kpis.map(kpi => (
          <div key={kpi.label} className="rounded-xl border p-4 shadow-sm"
            style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
            <div className="flex items-center justify-between mb-2">
              <span className="text-lg" style={{ color: kpi.color }}>{kpi.icon}</span>
              <span className="text-xs px-1.5 py-0.5 rounded"
                style={{ background: kpi.color + '18', color: kpi.color }}>
                {kpi.changeUp ? '▲' : '▼'}
              </span>
            </div>
            <div className="text-3xl font-bold leading-none mb-1" style={{ color: '#17212B' }}>{kpi.value}</div>
            <div className="text-xs font-medium mb-1" style={{ color: '#5A6670' }}>{kpi.label}</div>
            <div className="text-xs" style={{ color: '#8A9098' }}>{kpi.change}</div>
          </div>
        ))}
      </div>

      {/* Main grid */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">

        {/* Map — spans 2 cols */}
        <div className="xl:col-span-2 rounded-xl border shadow-sm overflow-hidden"
          style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b flex items-center justify-between"
            style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
            <div>
              <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>
                {profile.region ? `${profile.region} Map` : 'District Map'}
              </h2>
              <p className="text-xs" style={{ color: '#8A9098' }}>Live incident and route status</p>
            </div>
            <button onClick={() => setPage('map')}
              className="text-xs font-medium px-3 py-1.5 rounded border transition-colors"
              style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#2F6F7E' }}>
              Full Map →
            </button>
          </div>
          <MapViz incidents={incidents} routes={routes} vehicles={vehicles} height={380} />
        </div>

        {/* Critical Alerts panel */}
        <div className="rounded-xl border shadow-sm flex flex-col"
          style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b flex items-center justify-between"
            style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
            <div>
              <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Critical Alerts</h2>
              <p className="text-xs" style={{ color: '#8A9098' }}>{criticalAlerts.length + highAlerts.length} unacknowledged</p>
            </div>
            <button onClick={() => setPage('alerts')}
              className="text-xs font-medium px-3 py-1.5 rounded border transition-colors"
              style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#2F6F7E' }}>
              View All
            </button>
          </div>
          <div className="flex-1 overflow-y-auto divide-y" style={{ borderColor: 'rgba(238,228,210,0.88)' }}>
            {alerts.filter(a => !a.acknowledged).map(alert => (
              <div key={alert.id} className="px-4 py-3">
                <div className="flex items-start gap-2 mb-1">
                  <SeverityBadge severity={alert.severity} />
                  <span className="text-xs font-medium flex-1" style={{ color: '#17212B' }}>{alert.title}</span>
                </div>
                <div className="text-xs mb-1" style={{ color: '#5A6670' }}>{alert.location}</div>
                <div className="text-xs" style={{ color: '#8A9098' }}>{alert.time} · {alert.source}</div>
                <div className="flex gap-2 mt-2">
                  <button className="text-xs px-2 py-1 rounded border"
                    style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#2F6F7E' }}>View</button>
                  <button className="text-xs px-2 py-1 rounded border"
                    style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>Acknowledge</button>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Bottom row */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">

        {/* Incident Queue */}
        <div className="lg:col-span-2 rounded-xl border shadow-sm"
          style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b flex items-center justify-between"
            style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Incident Queue</h2>
            <button onClick={() => setPage('incidents')}
              className="text-xs font-medium px-3 py-1.5 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#2F6F7E' }}>
              Manage All →
            </button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr style={{ background: 'rgba(238,228,210,0.88)' }}>
                  {['ID', 'Type', 'Location', 'Severity', 'Status', 'Actions'].map(h => (
                    <th key={h} className="text-left px-4 py-2.5 text-xs font-semibold uppercase tracking-wider"
                      style={{ color: '#5A6670' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {incidents.slice(0, 5).map((inc, i) => (
                  <tr key={inc.id} style={{ background: i % 2 === 0 ? 'rgba(250,247,240,0.82)' : 'rgba(243,235,220,0.55)' }}>
                    <td className="px-4 py-2.5 font-mono text-xs" style={{ color: '#2F6F7E' }}>{inc.id}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: '#17212B' }}>{inc.type}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670' }}>{inc.location}</td>
                    <td className="px-4 py-2.5"><SeverityBadge severity={inc.severity} /></td>
                    <td className="px-4 py-2.5"><StatusBadge status={inc.status} /></td>
                    <td className="px-4 py-2.5">
                      <button className="text-xs font-medium" style={{ color: '#2F6F7E' }}>View →</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* AI Insights snapshot */}
        <div className="rounded-xl border shadow-sm flex flex-col"
          style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b flex items-center justify-between"
            style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
            <div className="flex items-center gap-2">
              <span style={{ color: '#D7A73A' }}>✦</span>
              <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>AI Insights</h2>
            </div>
            <button onClick={() => setPage('ai')} className="text-xs" style={{ color: '#2F6F7E' }}>View All →</button>
          </div>
          <div className="p-4 space-y-3">
            <div className="text-xs font-semibold uppercase tracking-wider mb-1" style={{ color: '#8A9098' }}>
              Risk Predictions
            </div>
            {aiInsights.riskPredictions.map(p => (
              <div key={p.route} className="rounded-lg p-3"
                style={{ background: 'rgba(238,228,210,0.88)', border: '1px solid rgba(180,162,136,0.55)' }}>
                <div className="flex items-center justify-between mb-1">
                  <span className="font-semibold text-xs" style={{ color: '#17212B' }}>{p.route}</span>
                  <span className="text-xs font-bold" style={{ color: '#BE2424' }}>{p.probability}%</span>
                </div>
                <div className="text-xs" style={{ color: '#5A6670' }}>
                  Disruption probability · {p.window}
                </div>
                <div className="mt-2 h-1.5 rounded-full overflow-hidden" style={{ background: 'rgba(180,162,136,0.55)' }}>
                  <div className="h-full rounded-full" style={{ width: `${p.probability}%`, background: p.probability > 80 ? '#BE2424' : p.probability > 60 ? '#E07840' : '#C4861A' }} />
                </div>
                <div className="flex items-center gap-1 mt-1">
                  <span style={{ color: '#D7A73A' }}>✦</span>
                  <span className="text-xs" style={{ color: '#8A9098' }}>AI-generated estimate · Confidence: {p.confidence}%</span>
                </div>
              </div>
            ))}
            {aiInsights.resourceRecommendations.slice(0, 1).map((rec, i) => (
              <div key={i} className="rounded-lg p-3 border" style={{ background: '#FEF8E6', borderColor: '#F5DFA8' }}>
                <div className="flex items-center gap-1.5 mb-1">
                  <span style={{ color: '#D7A73A' }}>✦</span>
                  <span className="text-xs font-semibold" style={{ color: '#C4861A' }}>Resource Recommendation</span>
                </div>
                <p className="text-xs" style={{ color: '#5A6670' }}>{rec}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
