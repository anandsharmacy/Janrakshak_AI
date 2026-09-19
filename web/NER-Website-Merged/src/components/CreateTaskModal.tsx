import { useEffect, useRef, useState } from 'react';
import type { Severity } from '@/data/demo';
import { createAssignedTask, listAssignableFieldOfficers, type AssignableOfficer } from '@/lib/taskStore';

const field = {
  background: 'rgba(245,236,220,0.6)',
  border: '1px solid rgba(180,162,136,0.5)',
  color: '#17212B',
};
const priorities: { label: string; value: Severity }[] = [
  { label: 'Critical', value: 'CRITICAL' },
  { label: 'High', value: 'HIGH' },
  { label: 'Moderate', value: 'MODERATE' },
  { label: 'Low', value: 'LOW' },
];

function Label({ children }: { children: React.ReactNode }) {
  return <label className="text-xs font-medium block mb-1" style={{ color: '#5A6670' }}>{children}</label>;
}

export default function CreateTaskModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [officers, setOfficers] = useState<AssignableOfficer[] | null>(null);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [location, setLocation] = useState('');
  const [priority, setPriority] = useState<Severity>('MODERATE');
  const [assignedTo, setAssignedTo] = useState('');
  const [deadline, setDeadline] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const inFlight = useRef(false);

  useEffect(() => {
    let active = true;
    listAssignableFieldOfficers()
      .then(list => { if (active) setOfficers(list); })
      .catch(e => { if (active) { setOfficers([]); setError(e.message); } });
    return () => { active = false; };
  }, []);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (inFlight.current) return;
    if (!title.trim() || !location.trim() || !assignedTo || !deadline) {
      setError('Enter a title, location, field officer and deadline.');
      return;
    }
    if (new Date(deadline).getTime() <= Date.now()) {
      setError('The deadline must be in the future.');
      return;
    }
    inFlight.current = true;
    setSubmitting(true);
    setError(null);
    try {
      await createAssignedTask({ title: title.trim(), description: description.trim(), location: location.trim(), priority, assignedTo, deadline });
      onCreated();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not create the task. Please try again.');
      inFlight.current = false;
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/20 backdrop-blur-[2px] p-4" onClick={onClose}>
      <form onSubmit={submit} className="w-full max-w-lg rounded-2xl border p-5 shadow-2xl"
        style={{ background: '#FFFDF9', borderColor: 'rgba(180,162,136,0.5)' }} onClick={event => event.stopPropagation()}>
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-semibold text-lg" style={{ color: '#17212B' }}>Create Task</h2>
          <button type="button" onClick={onClose} aria-label="Close" className="text-sm" style={{ color: '#5A6670' }}>✕</button>
        </div>

        <div className="space-y-3">
          <div><Label>Task Title</Label>
            <input value={title} onChange={e => setTitle(e.target.value)} className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
          <div><Label>Description</Label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={3} className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>Location</Label>
              <input value={location} onChange={e => setLocation(e.target.value)} className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
            <div><Label>Priority</Label>
              <select value={priority} onChange={e => setPriority(e.target.value as Severity)} className="w-full rounded px-3 py-2 text-sm outline-none" style={field}>
                {priorities.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
              </select></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label>Assign to Field Officer</Label>
              <select value={assignedTo} onChange={e => setAssignedTo(e.target.value)} disabled={officers === null} className="w-full rounded px-3 py-2 text-sm outline-none" style={field}>
                <option value="">{officers === null ? 'Loading…' : officers.length ? 'Select officer' : 'No field officers available'}</option>
                {(officers ?? []).map(o => <option key={o.userId} value={o.userId}>{o.name}{o.officerId ? ` · ${o.officerId}` : ''}</option>)}
              </select></div>
            <div><Label>Deadline</Label>
              <input type="datetime-local" value={deadline} onChange={e => setDeadline(e.target.value)} className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
          </div>
        </div>

        {error && <div role="alert" className="text-xs rounded p-2 mt-3" style={{ background: '#FEE9E9', color: '#BE2424' }}>{error}</div>}

        <div className="flex justify-end gap-2 mt-4">
          <button type="button" onClick={onClose} className="text-xs font-medium px-3 py-2 rounded border" style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>Cancel</button>
          <button type="submit" disabled={submitting} className="text-xs font-medium px-3 py-2 rounded border disabled:opacity-60"
            style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
            {submitting ? 'Creating…' : 'Create Task'}
          </button>
        </div>
      </form>
    </div>
  );
}
