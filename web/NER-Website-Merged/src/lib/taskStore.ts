import type { Severity, Task, TaskStatus } from '@/data/demo';

export type StoredTask = Task;

const STORAGE_KEY = 'ner-tasks';
const TASKS_CHANGED = 'ner-tasks-changed';

function readTasks(): StoredTask[] {
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
  publish([...readTasks(), task]);
  return task;
}

export function updateTask(id: string, updates: Partial<Pick<Task, 'status' | 'assignedOfficer'>>) {
  publish(readTasks().map(task => task.id === id ? { ...task, ...updates } : task));
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
