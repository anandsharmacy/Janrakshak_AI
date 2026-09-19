import type { Severity, Task, TaskStatus } from '@/data/demo';
import { getSessionSource } from '@/lib/auth';
import { supabase } from '@/lib/supabase';

/** `assignedToMe` is set on database tasks the signed-in user is assigned (the database only returns those to a field officer). */
export type StoredTask = Task & { assignedToMe?: boolean };

const STORAGE_KEY = 'ner-tasks';
const TASKS_CHANGED = 'ner-tasks-changed';

/** Tasks from the database for the signed-in user (row-level security decides which). Kept in memory only, so they never outlive the session in browser storage. */
let serverTasks: StoredTask[] = [];

function readLocalTasks(): StoredTask[] {
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

function readTasks(): StoredTask[] {
  return [...readLocalTasks(), ...serverTasks];
}

function publish(tasks: StoredTask[]) {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
  window.dispatchEvent(new CustomEvent(TASKS_CHANGED, { detail: tasks }));
}

function createTaskId() {
  return `TSK-${Date.now().toString().slice(-6)}`;
}

export function getTasks() {
  return readTasks();
}

export function createTaskFromIncident(input: {
  incidentId: string;
  title: string;
  location: string;
  priority: Severity;
  description: string;
  assignedOfficer?: string;
}) {
  const task: StoredTask = {
    id: createTaskId(),
    title: input.title,
    location: input.location,
    priority: input.priority,
    assignedOfficer: input.assignedOfficer ?? 'FO-1024',
    created: new Date().toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }),
    deadline: 'Pending review',
    status: 'New',
    relatedIncident: input.incidentId,
    description: input.description,
  };
  publish([...readLocalTasks(), task]);
  return task;
}

export function updateTask(id: string, updates: Partial<Pick<Task, 'status' | 'assignedOfficer'>>) {
  if (serverTasks.some(task => task.id === id)) {
    // Database task: only the status is persisted; the row is the source of truth on the next sync.
    if (!updates.status) return;
    serverTasks = serverTasks.map(task => task.id === id ? { ...task, status: updates.status! } : task);
    window.dispatchEvent(new CustomEvent(TASKS_CHANGED));
    void supabase?.from('tasks').update({ status: STATUS_TO_DB[updates.status] ?? 'new' }).eq('task_ref', id)
      .then(({ error }) => { if (error) void syncTasksFromServer(); });
    return;
  }
  publish(readLocalTasks().map(task => task.id === id ? { ...task, ...updates } : task));
}

export function subscribeToTasks(listener: (tasks: StoredTask[]) => void) {
  if (typeof window === 'undefined') return () => {};
  const notify = () => listener(readTasks());
  window.addEventListener(TASKS_CHANGED, notify);
  window.addEventListener('storage', notify);
  return () => {
    window.removeEventListener(TASKS_CHANGED, notify);
    window.removeEventListener('storage', notify);
  };
}

// ---- Database-backed tasks (Supabase `tasks` table) -------------------------------------------

const isLive = () => !!supabase && getSessionSource() === 'supabase';

const PRIORITY_FROM_DB: Record<string, Severity> = { critical: 'CRITICAL', high: 'HIGH', moderate: 'MODERATE', medium: 'MODERATE', low: 'LOW', info: 'LOW' };
// The field UI also uses 'Accepted', which the database keeps as `pending`.
const STATUS_FROM_DB: Record<string, string> = { new: 'New', pending: 'Accepted', in_progress: 'In Progress', completed: 'Completed', escalated: 'Escalated', overdue: 'Escalated' };
const STATUS_TO_DB: Record<string, string> = { New: 'new', Assigned: 'new', Accepted: 'pending', 'In Progress': 'in_progress', Completed: 'completed', Verified: 'completed', Escalated: 'escalated' };

const formatWhen = (iso: string) => new Date(iso).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });

interface TaskRow {
  task_ref: string | null; id: string; title: string; description: string | null; location_text: string | null;
  assigned_to: string | null; priority: string; status: string; deadline: string | null; created_at: string;
}

/** Reloads the tasks the signed-in user may see and notifies every task view. No-op (and clears database tasks) without a live session. */
export async function syncTasksFromServer(): Promise<void> {
  if (!supabase || !isLive()) {
    if (serverTasks.length) {
      serverTasks = [];
      window.dispatchEvent(new CustomEvent(TASKS_CHANGED));
    }
    return;
  }
  const [{ data: session }, { data: rows, error }] = await Promise.all([
    supabase.auth.getSession(),
    supabase.from('tasks').select('id, task_ref, title, description, location_text, assigned_to, priority, status, deadline, created_at').order('created_at', { ascending: true }),
  ]);
  if (error || !rows) return;

  const me = session.session?.user.id;
  const ids = [...new Set((rows as TaskRow[]).map(row => row.assigned_to).filter((id): id is string => !!id))];
  const { data: profiles } = ids.length ? await supabase.from('profiles').select('id, officer_id, full_name').in('id', ids) : { data: [] };
  const names = new Map((profiles ?? []).map(p => [p.id as string, (p.officer_id || p.full_name || '') as string]));

  serverTasks = (rows as TaskRow[]).map(row => ({
    id: row.task_ref ?? row.id,
    title: row.title,
    location: row.location_text ?? '',
    priority: PRIORITY_FROM_DB[row.priority] ?? 'MODERATE',
    assignedOfficer: row.assigned_to ? names.get(row.assigned_to) || row.assigned_to.slice(0, 8) : null,
    created: formatWhen(row.created_at),
    deadline: row.deadline ? formatWhen(row.deadline) : 'Not set',
    status: (STATUS_FROM_DB[row.status] ?? 'New') as TaskStatus,
    relatedIncident: null,
    description: row.description ?? '',
    assignedToMe: !!me && row.assigned_to === me,
  }));
  window.dispatchEvent(new CustomEvent(TASKS_CHANGED));
}

export interface AssignableOfficer { userId: string; name: string; officerId: string; district: string }

/** Field officers the signed-in district officer (or control room) may assign to; the database decides who that is. */
export async function listAssignableFieldOfficers(): Promise<AssignableOfficer[]> {
  if (!supabase || !isLive()) return [];
  const { data, error } = await supabase.rpc('get_assignable_field_officers');
  if (error) throw new Error('Could not load field officers. Please try again.');
  return (data ?? []).map((o: { user_id: string; full_name: string | null; officer_id: string | null; district_name: string | null }) => ({
    userId: o.user_id, name: o.full_name ?? 'Field Officer', officerId: o.officer_id ?? '', district: o.district_name ?? '',
  }));
}

/** Creates a task in the database, assigned to the given field officer's user id. Creator, district and initial status (`new`) are set by the database. */
export async function createAssignedTask(input: {
  title: string; description: string; location: string; priority: Severity; assignedTo: string; deadline: string;
}): Promise<void> {
  if (!supabase || !isLive()) throw new Error('Sign in with a live account to assign tasks.');
  const { error } = await supabase.from('tasks').insert({
    title: input.title,
    description: input.description || null,
    location_text: input.location,
    priority: input.priority.toLowerCase(),
    assigned_to: input.assignedTo,
    deadline: new Date(input.deadline).toISOString(),
  });
  if (error) {
    if (/field officer in your district/i.test(error.message)) throw new Error(error.message);
    throw new Error(error.code === '42501' ? 'You are not permitted to create tasks.' : 'Could not create the task. Please try again.');
  }
  await syncTasksFromServer();
}
