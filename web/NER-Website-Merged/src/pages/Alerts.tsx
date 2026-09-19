import { useEffect, useMemo, useState } from 'react';
import { SeverityBadge } from '@/components/StatusBadge';
import { getIncidents, subscribeToIncidents, updateIncident } from '@/lib/incidentStore';
import { getTasks, subscribeToTasks, updateTask } from '@/lib/taskStore';
import type { Alert, Severity } from '@/data/demo';

const categories = ['All', 'Critical', 'Route Closure', 'Flood', 'Landslide', 'Logistics Delay', 'Escalation', 'AI Warning'];

function buildAlertList(incidentList: ReturnType<typeof getIncidents>, taskList: ReturnType<typeof getTasks>): Alert[] {
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

  const taskAlerts: Alert[] = taskList.filter(task => ['New', 'In Progress', 'Escalated'].includes(task.status)).map(task => ({
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
}

export default function Alerts() {
  const [incidentList, setIncidentList] = useState<ReturnType<typeof getIncidents>>(() => getIncidents());
  const [taskList, setTaskList] = useState<ReturnType<typeof getTasks>>(() => getTasks());
  const [category, setCategory] = useState('All');
  const [expandedIds, setExpandedIds] = useState<string[]>([]);

  useEffect(() => subscribeToIncidents(stored => setIncidentList(stored)), []);
  useEffect(() => subscribeToTasks(stored => setTaskList(stored)), []);

  const alertList = useMemo(() => buildAlertList(incidentList, taskList), [incidentList, taskList]);
  const filtered = alertList.filter(a => category === 'All' || a.severity === category.toUpperCase() || a.category === category);

  const syncIncident = (id: string, updates: Partial<{ assignedOfficer: string | null; status: string; verification: string }>) => {
    setIncidentList(current => current.map(item => item.id === id ? { ...item, ...updates } : item));
    updateIncident(id, updates as Parameters<typeof updateIncident>[1]);
  };

  const syncTask = (id: string, updates: Partial<{ assignedOfficer: string | null; status: string }>) => {
    setTaskList(current => current.map(item => item.id === id ? { ...item, ...updates } : item));
    updateTask(id, updates as Parameters<typeof updateTask>[1]);
  };

  const acknowledge = (id: string) => {
    if (id.startsWith('incident-')) {
      const incidentId = id.replace('incident-', '');
      const incident = incidentList.find(item => item.id === incidentId);
      if (incident && incident.status !== 'RESOLVED') {
        syncIncident(incidentId, { status: 'RESOLVED' });
      }
      return;
    }

    if (id.startsWith('task-')) {
      const taskId = id.replace('task-', '');
      const task = taskList.find(item => item.id === taskId);
      if (task && task.status !== 'Completed') {
        syncTask(taskId, { status: 'Completed' });
      }
    }
  };

  const acknowledgeAll = () => {
    const incidentIds = incidentList
      .filter(incident => incident.status !== 'RESOLVED')
      .map(incident => incident.id);

    const taskIds = taskList
      .filter(task => task.status !== 'Completed')
      .map(task => task.id);

    if (incidentIds.length) {
      setIncidentList(current => current.map(item => incidentIds.includes(item.id) ? { ...item, status: 'RESOLVED' } : item));
      incidentIds.forEach(id => updateIncident(id, { status: 'RESOLVED' }));
    }

    if (taskIds.length) {
      setTaskList(current => current.map(item => taskIds.includes(item.id) ? { ...item, status: 'Completed' } : item));
      taskIds.forEach(id => updateTask(id, { status: 'Completed' }));
    }
  };

  const assign = (id: string) => {
    if (id.startsWith('incident-')) {
      const incidentId = id.replace('incident-', '');
      const incident = incidentList.find(item => item.id === incidentId);
      if (incident && incident.assignedOfficer !== 'FO-1024') {
        syncIncident(incidentId, { assignedOfficer: 'FO-1024', status: 'ACTIVE' });
      }
      return;
    }

    if (id.startsWith('task-')) {
      const taskId = id.replace('task-', '');
      const task = taskList.find(item => item.id === taskId);
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

  const unacknowledgedCount = alertList.filter(a => !a.acknowledged).length;

  return (
    <div className="space-y-5 max-w-screen-2xl">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>Alerts</h1>
          <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>
            Operational notification center — {unacknowledgedCount} unacknowledged
          </p>
        </div>
        <button className="text-xs font-medium px-3 py-2 rounded border"
          style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}
          onClick={acknowledgeAll}>
          Acknowledge All
        </button>
      </div>

      {/* Category tabs */}
      <div className="flex flex-wrap gap-1">
        {categories.map(c => (
          <button key={c} onClick={() => setCategory(c)}
            className="text-xs px-3 py-1.5 rounded-full border transition-colors"
            style={{
              background: category === c ? '#17324D' : 'rgba(250,247,240,0.82)',
              color: category === c ? 'white' : '#5A6670',
              borderColor: category === c ? '#17324D' : 'rgba(180,162,136,0.55)',
            }}>
            {c}
          </button>
        ))}
      </div>

      <div className="space-y-3">
        {filtered.map(alert => (
          <div key={alert.id}
            className="rounded-xl border shadow-sm p-4 transition-opacity"
            style={{
              background: alert.acknowledged ? 'rgba(243,235,220,0.55)' : 'rgba(250,247,240,0.82)',
              borderColor: alert.acknowledged ? 'rgba(180,162,136,0.55)' : (
                alert.severity === 'CRITICAL' ? '#F5B8B8' :
                alert.severity === 'HIGH' ? '#F5CDA8' : 'rgba(180,162,136,0.55)'
              ),
              opacity: alert.acknowledged ? 0.7 : 1,
              borderLeftWidth: 3,
              borderLeftColor: alert.severity === 'CRITICAL' ? '#BE2424' : alert.severity === 'HIGH' ? '#E07840' : alert.severity === 'MODERATE' ? '#C4861A' : '#2D6B4F',
            }}>
            <div className="flex items-start gap-3">
              <div className="flex-shrink-0 mt-0.5">
                <SeverityBadge severity={alert.severity} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-start justify-between gap-2">
                  <h3 className="font-semibold text-sm" style={{ color: '#17212B' }}>{alert.title}</h3>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    <span className="text-xs" style={{ color: '#8A9098' }}>{alert.time}</span>
                    {alert.acknowledged && (
                      <span className="text-xs px-1.5 py-0.5 rounded" style={{ background: 'rgba(238,228,210,0.88)', color: '#8A9098' }}>
                        Acknowledged
                      </span>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-3 text-xs mt-0.5 mb-2" style={{ color: '#8A9098' }}>
                  <span>◉ {alert.location}</span>
                  <span>· {alert.category}</span>
                  <span>· Source: {alert.source}</span>
                </div>
                <p className="text-xs leading-relaxed" style={{ color: '#5A6670' }}>{alert.description}</p>
                {!alert.acknowledged && (
                  <div className="flex gap-2 mt-3 flex-wrap">
                    <button onClick={() => toggleExpanded(alert.id)}
                      className="text-xs font-medium px-3 py-1.5 rounded border"
                      style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
                      {expandedIds.includes(alert.id) ? 'Hide' : 'View'}
                    </button>
                    <button onClick={() => acknowledge(alert.id)}
                      className="text-xs font-medium px-3 py-1.5 rounded border"
                      style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>
                      Acknowledge
                    </button>
                    <button onClick={() => assign(alert.id)} className="text-xs font-medium px-3 py-1.5 rounded border"
                      style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>
                      Assign
                    </button>
                    {alert.severity === 'CRITICAL' || alert.severity === 'HIGH' ? (
                      <button onClick={() => escalate(alert.id)} className="text-xs font-medium px-3 py-1.5 rounded border"
                        style={{ borderColor: '#F5B8B8', color: '#BE2424', background: '#FEE9E9' }}>
                        Escalate
                      </button>
                    ) : null}
                  </div>
                )}
                {expandedIds.includes(alert.id) && (
                  <div className="mt-3 rounded-lg border p-3 text-xs" style={{ background: 'rgba(238,228,210,0.88)', borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>
                    <div className="font-semibold mb-1" style={{ color: '#17212B' }}>Alert details</div>
                    <div>{alert.description}</div>
                    <div className="mt-1">Source: {alert.source}</div>
                    <div>Severity: {alert.severity}</div>
                  </div>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
