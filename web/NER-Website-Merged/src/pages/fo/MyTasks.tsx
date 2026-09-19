import { useState, useEffect } from 'react';
import { SeverityBadge, StatusBadge } from '@/components/StatusBadge';
import type { Severity } from '@/data/demo';
import { Card, PageHeader, BORDER, SURFACE, SURFACE_2, TEAL } from './ui';
import { profileService } from '@/lib/profileService';
import { getTasks, subscribeToTasks, updateTask } from '@/lib/taskStore';

type Life = 'Assigned' | 'Accepted' | 'In Progress' | 'Completed' | 'Verified';

interface FOTask {
  id: string; title: string; location: string; priority: Severity;
  assigned: string; due: string; status: Life;
}

const TABS = ['All', 'Pending', 'In Progress', 'Completed', 'Overdue'] as const;
const NEXT: Record<Life, Life | null> = { Assigned: 'Accepted', Accepted: 'In Progress', 'In Progress': 'Completed', Completed: 'Verified', Verified: null };
const ACTION_LABEL: Record<Life, string> = { Assigned: 'Accept Task', Accepted: 'Start Task', 'In Progress': 'Complete Task', Completed: 'Awaiting Verification', Verified: 'Verified' };

function toFieldTask(task: ReturnType<typeof getTasks>[number]): FOTask {
  return {
    id: task.id,
    title: task.title,
    location: task.location,
    priority: task.priority,
    assigned: task.created,
    due: task.deadline,
    status: task.status === 'New' ? 'Assigned' : task.status as Life,
  };
}

export default function MyTasks() {
  const [tab, setTab] = useState<typeof TABS[number]>('All');
  const [tasks, setTasks] = useState<FOTask[]>(() => getTasks().filter(task => task.assignedOfficer === 'FO-1024').map(toFieldTask));
  const [busy, setBusy] = useState<string | null>(null);
  const [profile, setProfile] = useState(() => {
    try {
      return profileService.getProfile();
    } catch (error) {
      console.error('Error loading profile in MyTasks:', error);
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
        console.error('Error updating profile in MyTasks:', error);
      }
    });
    return unsubscribe;
  }, []);

  useEffect(() => subscribeToTasks(stored => setTasks(stored.filter(task => task.assignedOfficer === 'FO-1024').map(toFieldTask))), []);

  const advance = (id: string) => {
    const t = tasks.find(x => x.id === id);
    if (!t || !NEXT[t.status]) return;
    setBusy(id);
    setTimeout(() => {
      setTasks(ts => ts.map(x => x.id === id ? { ...x, status: NEXT[x.status]! } : x));
      updateTask(id, { status: NEXT[t.status]! });
      setBusy(null);
    }, 800);
  };

  const filtered = tasks.filter(t => {
    if (tab === 'All') return true;
    if (tab === 'Pending') return t.status === 'Assigned' || t.status === 'Accepted';
    if (tab === 'In Progress') return t.status === 'In Progress';
    if (tab === 'Completed') return t.status === 'Completed' || t.status === 'Verified';
    if (tab === 'Overdue') return t.due.startsWith('Yesterday') && t.status !== 'Completed' && t.status !== 'Verified';
    return true;
  });

  return (
    <div className="space-y-6 max-w-screen-2xl">
      <PageHeader title="My Tasks" sub={`Field tasks assigned to you · ${profile.profileName} · ${profile.region}`} />

      {/* Tabs */}
      <div className="flex gap-1 border-b overflow-x-auto" style={{ borderColor: BORDER }}>
        {TABS.map(t => {
          const active = tab === t;
          const count = t === 'All' ? tasks.length : tasks.filter(x =>
            t === 'Pending' ? (x.status === 'Assigned' || x.status === 'Accepted') :
            t === 'In Progress' ? x.status === 'In Progress' :
            t === 'Completed' ? (x.status === 'Completed' || x.status === 'Verified') :
            x.due.startsWith('Yesterday') && x.status !== 'Completed' && x.status !== 'Verified'
          ).length;
          return (
            <button key={t} onClick={() => setTab(t)}
              className="px-4 py-2 text-sm font-medium transition-all whitespace-nowrap"
              style={{
                color: active ? '#17212B' : '#8A9098',
                borderBottom: `2px solid ${active ? TEAL : 'transparent'}`,
                marginBottom: -1,
              }}>
              {t} <span className="text-xs" style={{ color: '#8A9098' }}>({count})</span>
            </button>
          );
        })}
      </div>

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: SURFACE_2 }}>
                {['Task ID', 'Task', 'Location', 'Priority', 'Assigned', 'Due', 'Status', 'Action'].map(h => (
                  <th key={h} className="text-left px-4 py-2.5 text-xs font-semibold uppercase tracking-wider" style={{ color: '#5A6670' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map((t, i) => (
                <tr key={t.id} className="transition-colors" style={{ background: i % 2 === 0 ? SURFACE : 'rgba(243,235,220,0.55)' }}>
                  <td className="px-4 py-2.5 font-mono text-xs" style={{ color: TEAL }}>#{t.id}</td>
                  <td className="px-4 py-2.5 text-xs font-medium" style={{ color: '#17212B' }}>{t.title}</td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670' }}>{t.location}</td>
                  <td className="px-4 py-2.5"><SeverityBadge severity={t.priority} /></td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#8A9098' }}>{t.assigned}</td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#8A9098' }}>{t.due}</td>
                  <td className="px-4 py-2.5"><StatusBadge status={t.status} /></td>
                  <td className="px-4 py-2.5">
                    {NEXT[t.status] ? (
                      <button onClick={() => advance(t.id)} disabled={busy === t.id}
                        className="text-xs font-medium px-2.5 py-1 rounded border transition-all disabled:opacity-60"
                        style={{ borderColor: BORDER, color: TEAL, minHeight: 32 }}>
                        {busy === t.id ? 'Updating…' : ACTION_LABEL[t.status]}
                      </button>
                    ) : (
                      <span className="text-xs" style={{ color: '#2D6B4F' }}>✓ {ACTION_LABEL[t.status]}</span>
                    )}
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr><td colSpan={8} className="px-4 py-10 text-center text-sm" style={{ color: '#8A9098' }}>No tasks in this view.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
