import { useEffect, useMemo, useState } from 'react';
import { SeverityBadge } from '@/components/StatusBadge';
import { getIncidents, subscribeToIncidents, updateIncident } from '@/lib/incidentStore';
import { getTasks, subscribeToTasks, updateTask } from '@/lib/taskStore';
import type { Severity } from '@/data/demo';
import { Card, PageHeader, BORDER, SURFACE_2, NAVY, TEAL } from './ui';

const TABS: { key: string; sev?: Severity }[] = [
  { key: 'Critical', sev: 'CRITICAL' },
  { key: 'High', sev: 'HIGH' },
  { key: 'Moderate', sev: 'MODERATE' },
  { key: 'Low', sev: 'LOW' },
];

const ACKNOWLEDGED_ALERTS_KEY = 'ner-field-alert-acknowledged';

function readAcknowledgedAlerts() {
  if (typeof window === 'undefined') return {};
  try {
    const stored = JSON.parse(window.localStorage.getItem(ACKNOWLEDGED_ALERTS_KEY) ?? '{}');
    return stored && typeof stored === 'object' ? stored as Record<string, true> : {};
  } catch {
    return {};
  }
}

const REC: Record<string, string> = {
  Flood: 'Avoid affected section and inspect alternate access route.',
  Infrastructure: 'Do not permit heavy vehicles. Await structural assessment.',
  'Logistics Delay': 'Notify convoys and coordinate rerouting where possible.',
  Escalation: 'Report current on-site status to the District Officer.',
  'AI Warning': 'Increase monitoring frequency on the flagged section.',
  'Route Closure': 'Redirect any inbound field movement to alternate routes.',
};

export default function Alerts() {
  const [tab, setTab] = useState('Critical');
  const [ack, setAck] = useState<Record<string, 'busy' | 'done'>>(() =>
    Object.fromEntries(Object.keys(readAcknowledgedAlerts()).map(id => [id, 'done'])) as Record<string, 'busy' | 'done'>
  );
  const [incidents, setIncidents] = useState(() => getIncidents());
  const [tasks, setTasks] = useState(() => getTasks());
  const [expandedIds, setExpandedIds] = useState<string[]>([]);

  useEffect(() => subscribeToIncidents(stored => setIncidents(stored)), []);
  useEffect(() => subscribeToTasks(stored => setTasks(stored)), []);

  const alertList = useMemo(() => {
    const incidentAlerts = incidents.filter(incident =>
      ['PENDING_VERIFICATION', 'ACTIVE', 'ESCALATED', 'UNDER_REVIEW'].includes(incident.status) ||
      incident.severity === 'CRITICAL' ||
      incident.severity === 'HIGH'
    ).map(incident => ({
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

    const taskAlerts = tasks.filter(task => task.assignedOfficer === 'FO-1024' && ['New', 'In Progress', 'Escalated'].includes(task.status)).map(task => ({
      id: `task-${task.id}`,
      severity: task.priority,
      category: /logistics|convoy|supply/i.test(task.title) ? 'Logistics Delay' : task.status === 'Escalated' ? 'Escalation' : 'Task',
      title: task.status === 'Escalated' ? `Task escalated: ${task.title}` : `Task update: ${task.title}`,
      location: task.location,
      time: task.created,
      description: task.description,
      source: task.assignedOfficer ?? 'System',
      acknowledged: task.status === 'Completed' || task.status === 'Escalated',
    }));

    return [...incidentAlerts, ...taskAlerts].sort((a, b) => new Date(b.time).getTime() - new Date(a.time).getTime());
  }, [incidents, tasks]);

  const syncIncident = (id: string, updates: Partial<{ assignedOfficer: string | null; status: string; verification: string }>) => {
    setIncidents(current => current.map(item => item.id === id ? { ...item, ...updates } : item));
    updateIncident(id, updates as Parameters<typeof updateIncident>[1]);
  };

  const syncTask = (id: string, updates: Partial<{ assignedOfficer: string | null; status: string }>) => {
    setTasks(current => current.map(item => item.id === id ? { ...item, ...updates } : item));
    updateTask(id, updates as Parameters<typeof updateTask>[1]);
  };

  const acknowledge = (id: string) => {
    if (ack[id]) return;
    setAck(a => ({ ...a, [id]: 'busy' }));
    const acknowledged = { ...readAcknowledgedAlerts(), [id]: true };
    window.localStorage.setItem(ACKNOWLEDGED_ALERTS_KEY, JSON.stringify(acknowledged));

    setTimeout(() => setAck(a => ({ ...a, [id]: 'done' })), 600);
  };

  const assign = (id: string) => {
    if (id.startsWith('incident-')) {
      const incidentId = id.replace('incident-', '');
      const incident = incidents.find(item => item.id === incidentId);
      if (incident && incident.assignedOfficer !== 'FO-1024') {
        syncIncident(incidentId, { assignedOfficer: 'FO-1024', status: 'ACTIVE' });
      }
      return;
    }

    if (id.startsWith('task-')) {
      const taskId = id.replace('task-', '');
      const task = tasks.find(item => item.id === taskId);
      if (task && task.assignedOfficer !== 'FO-1024') {
        syncTask(taskId, { assignedOfficer: 'FO-1024', status: 'In Progress' });
      }
    }
  };

  const escalate = (id: string) => {
    if (id.startsWith('incident-')) {
      const incidentId = id.replace('incident-', '');
      syncIncident(incidentId, { status: 'ESCALATED', assignedOfficer: 'FO-1024' });
      return;
    }

    if (id.startsWith('task-')) {
      const taskId = id.replace('task-', '');
      syncTask(taskId, { status: 'Escalated', assignedOfficer: 'FO-1024' });
    }
  };

  const toggleExpanded = (id: string) => {
    setExpandedIds(current => current.includes(id) ? current.filter(item => item !== id) : [...current, id]);
  };

  const sev = TABS.find(t => t.key === tab)?.sev;
  const list = alertList.filter(a => a.severity === sev);

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader title="Alerts" sub="Operational alerts for your assigned area" />

      <div className="flex gap-1 border-b overflow-x-auto" style={{ borderColor: BORDER }}>
        {TABS.map(t => {
          const n = alertList.filter(a => a.severity === t.sev).length;
          const active = tab === t.key;
          return (
            <button key={t.key} onClick={() => setTab(t.key)}
              className="px-4 py-2 text-sm font-medium whitespace-nowrap transition-all"
              style={{ color: active ? '#17212B' : '#8A9098', borderBottom: `2px solid ${active ? TEAL : 'transparent'}`, marginBottom: -1 }}>
              {t.key} <span className="text-xs" style={{ color: '#8A9098' }}>({n})</span>
            </button>
          );
        })}
      </div>

      <div className="space-y-4">
        {list.map(a => {
          const state = ack[a.id];
          const critical = a.severity === 'CRITICAL';
          return (
            <Card key={a.id} className="p-4" style={critical ? { borderColor: '#F5B8B8', borderLeftWidth: 4, borderLeftColor: '#BE2424' } : undefined}>
              <div className="flex items-start gap-3">
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <SeverityBadge severity={a.severity} />
                    <span className="text-xs" style={{ color: '#8A9098' }}>{a.category} · {a.time}</span>
                  </div>
                  <h3 className="font-semibold text-sm mb-1" style={{ color: '#17212B' }}>{a.title}</h3>
                  <div className="text-xs mb-2" style={{ color: '#5A6670' }}>{a.location} · {a.description}</div>
                  <div className="rounded-lg border p-2.5 mb-3" style={{ background: SURFACE_2, borderColor: BORDER }}>
                    <span className="text-xs font-semibold" style={{ color: '#C4861A' }}>Recommended Action: </span>
                    <span className="text-xs" style={{ color: '#5A6670' }}>{REC[a.category] ?? 'Review and respond per field protocol.'}</span>
                  </div>
                  <div className="flex gap-2 flex-wrap">
                    <button onClick={() => toggleExpanded(a.id)} className="text-xs font-medium px-3 py-2 rounded border" style={{ borderColor: BORDER, color: TEAL, minHeight: 40 }}>
                      {expandedIds.includes(a.id) ? 'Hide Details' : 'View Incident'}
                    </button>
                    <button onClick={() => acknowledge(a.id)} disabled={!!state}
                      className="text-xs font-medium px-3 py-2 rounded transition-all disabled:opacity-70"
                      style={{ background: state === 'done' ? '#EAF4EE' : NAVY, color: state === 'done' ? '#2D6B4F' : 'white', minHeight: 40 }}>
                      {state === 'busy' ? 'Acknowledging…' : state === 'done' ? 'Acknowledged ✓' : 'Acknowledge'}
                    </button>
                  </div>
                  {expandedIds.includes(a.id) && (
                    <div className="mt-3 rounded-lg border p-2.5 text-xs" style={{ background: SURFACE_2, borderColor: BORDER, color: '#5A6670' }}>
                      <div className="font-semibold mb-1" style={{ color: '#17212B' }}>Alert details</div>
                      <div>{a.description}</div>
                      <div className="mt-1">Source: {a.source}</div>
                    </div>
                  )}
                </div>
              </div>
            </Card>
          );
        })}
        {list.length === 0 && (
          <Card className="p-10 text-center"><span className="text-sm" style={{ color: '#8A9098' }}>No {tab.toLowerCase()} alerts.</span></Card>
        )}
      </div>
    </div>
  );
}
