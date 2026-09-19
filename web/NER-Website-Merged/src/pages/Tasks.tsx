import { useEffect, useState } from 'react';
import { SeverityBadge, StatusBadge } from '@/components/StatusBadge';
import { getTasks, subscribeToTasks } from '@/lib/taskStore';

const tabKeys = ['All', 'New', 'In Progress', 'Completed', 'Escalated'];

export default function Tasks() {
  const [tab, setTab] = useState('All');
  const [tasks, setTasks] = useState<ReturnType<typeof getTasks>>(() => getTasks());
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);

  useEffect(() => subscribeToTasks(stored => setTasks(stored)), []);

  const filtered = tasks.filter(t => tab === 'All' || t.status === tab);
  const selectedTask = tasks.find(task => task.id === selectedTaskId) ?? null;

  return (
    <div className="space-y-5 max-w-screen-2xl">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>Tasks</h1>
          <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>Field task management and assignment</p>
        </div>
        <button className="text-xs font-medium px-3 py-2 rounded border"
          style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
          + Create Task
        </button>
      </div>

      {/* Summary */}
      <div className="grid grid-cols-5 gap-3">
        {tabKeys.map(t => {
          const count = t === 'All' ? tasks.length : tasks.filter(task => task.status === t).length;
          return (
            <button key={t} onClick={() => setTab(t)}
              className="rounded-xl border p-3 text-left transition-all"
              style={{ background: tab === t ? '#17324D' : 'rgba(250,247,240,0.82)', borderColor: tab === t ? '#17324D' : 'rgba(180,162,136,0.55)' }}>
              <div className="text-2xl font-bold" style={{ color: tab === t ? 'white' : '#17212B' }}>{count}</div>
              <div className="text-xs mt-0.5" style={{ color: tab === t ? '#8AAFC8' : '#5A6670' }}>{t}</div>
            </button>
          );
        })}
      </div>

      <div className="flex gap-0 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
        {tabKeys.map(t => (
          <button key={t} onClick={() => setTab(t)}
            className="px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors"
            style={{ borderBottomColor: tab === t ? '#17324D' : 'transparent', color: tab === t ? '#17324D' : '#5A6670' }}>
            {t}
          </button>
        ))}
      </div>

      <div className="rounded-xl border shadow-sm overflow-hidden" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: 'rgba(238,228,210,0.88)' }}>
                {['Task ID', 'Title', 'Location', 'Priority', 'Assigned Officer', 'Created', 'Deadline', 'Status', 'Actions'].map(h => (
                  <th key={h} className="text-left px-4 py-2.5 text-xs font-semibold uppercase tracking-wider whitespace-nowrap"
                    style={{ color: '#5A6670' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map((task, i) => (
                <tr key={task.id} style={{ background: i % 2 === 0 ? 'rgba(250,247,240,0.82)' : 'rgba(243,235,220,0.55)' }}>
                  <td className="px-4 py-2.5 font-mono text-xs font-semibold" style={{ color: '#2F6F7E' }}>{task.id}</td>
                  <td className="px-4 py-2.5">
                    <div className="text-xs font-medium" style={{ color: '#17212B' }}>{task.title}</div>
                    {task.relatedIncident && (
                      <div className="text-xs mt-0.5" style={{ color: '#8A9098' }}>↳ {task.relatedIncident}</div>
                    )}
                  </td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670' }}>{task.location}</td>
                  <td className="px-4 py-2.5"><SeverityBadge severity={task.priority} /></td>
                  <td className="px-4 py-2.5 font-mono text-xs" style={{ color: task.assignedOfficer ? '#17212B' : '#8A9098' }}>
                    {task.assignedOfficer ?? '— Unassigned'}
                  </td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#8A9098' }}>{task.created}</td>
                  <td className="px-4 py-2.5 text-xs font-medium" style={{ color: '#17212B' }}>{task.deadline}</td>
                  <td className="px-4 py-2.5"><StatusBadge status={task.status} /></td>
                  <td className="px-4 py-2.5">
                    <button
                      onClick={() => setSelectedTaskId(selectedTaskId === task.id ? null : task.id)}
                      className="text-xs px-2 py-1 rounded border"
                      style={{ borderColor: 'rgba(180,162,136,0.55)', color: selectedTaskId === task.id ? '#17324D' : '#2F6F7E' }}>
                      {selectedTaskId === task.id ? 'Hide' : 'View'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {selectedTask && (
        <div className="rounded-xl border p-4" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="text-xs uppercase tracking-wider" style={{ color: '#8A9098' }}>Task Details</div>
              <h3 className="mt-1 font-semibold text-base" style={{ color: '#17212B' }}>{selectedTask.title}</h3>
            </div>
            <button onClick={() => setSelectedTaskId(null)} className="text-xs font-medium px-2 py-1 rounded border" style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>Close</button>
          </div>
          <div className="mt-3 grid grid-cols-1 md:grid-cols-2 gap-3 text-xs" style={{ color: '#5A6670' }}>
            <div><span className="font-semibold" style={{ color: '#17212B' }}>Task ID:</span> {selectedTask.id}</div>
            <div><span className="font-semibold" style={{ color: '#17212B' }}>Priority:</span> <SeverityBadge severity={selectedTask.priority} /></div>
            <div><span className="font-semibold" style={{ color: '#17212B' }}>Location:</span> {selectedTask.location}</div>
            <div><span className="font-semibold" style={{ color: '#17212B' }}>Assigned:</span> {selectedTask.assignedOfficer ?? 'Unassigned'}</div>
            <div><span className="font-semibold" style={{ color: '#17212B' }}>Created:</span> {selectedTask.created}</div>
            <div><span className="font-semibold" style={{ color: '#17212B' }}>Deadline:</span> {selectedTask.deadline}</div>
            <div className="md:col-span-2"><span className="font-semibold" style={{ color: '#17212B' }}>Description:</span> {selectedTask.description}</div>
          </div>
        </div>
      )}
    </div>
  );
}
