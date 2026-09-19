import { useEffect, useState } from 'react';
import { Card, CardHeader, PageHeader, BORDER, SURFACE_2, NAVY, TEAL } from './ui';
import { getIncidents, subscribeToIncidents } from '@/lib/incidentStore';
import { getTasks, subscribeToTasks } from '@/lib/taskStore';

const OFFICER_ID = 'FO-1024';

function formatTaskReport(task: ReturnType<typeof getTasks>[number]) {
  return {
    id: task.id,
    type: task.relatedIncident ? 'Incident Follow-up' : 'Field Task',
    title: task.title,
    date: task.created,
    status: task.status === 'New' ? 'Assigned' : task.status,
  };
}

export default function Reports() {
  const [gen, setGen] = useState<'idle' | 'busy' | 'done'>('idle');
  const [selectedReport, setSelectedReport] = useState<ReturnType<typeof formatTaskReport> | null>(null);
  const [manualReport, setManualReport] = useState('');
  const [tasks, setTasks] = useState(() => getTasks().filter(task => task.assignedOfficer === OFFICER_ID));
  const [incidentCount, setIncidentCount] = useState(() => getIncidents().filter(incident => incident.reportedBy === 'Field Officer').length);
  const generate = () => { setGen('busy'); setTimeout(() => setGen('done'), 1300); };

  useEffect(() => subscribeToTasks(stored => setTasks(stored.filter(task => task.assignedOfficer === OFFICER_ID))), []);
  useEffect(() => subscribeToIncidents(stored => setIncidentCount(stored.filter(incident => incident.reportedBy === 'Field Officer').length)), []);
  useEffect(() => {
    if (!selectedReport) {
      setManualReport('');
      return;
    }
    setManualReport([
      `Report ID: ${selectedReport.id}`,
      `Type: ${selectedReport.type}`,
      `Created: ${selectedReport.date}`,
      `Status: ${selectedReport.status}`,
      '',
      `Summary: ${selectedReport.title}`,
      'Notes: Update with your field observations, route conditions, resource impact, and any follow-up actions.',
    ].join('\n'));
  }, [selectedReport]);

  const reports = tasks.map(formatTaskReport);
  const completedCount = tasks.filter(task => task.status === 'Completed' || task.status === 'Verified').length;
  const routeInspectionCount = tasks.filter(task => /route|road|inspection|survey/i.test(task.title)).length;
  const logisticsCount = tasks.filter(task => /logistics|convoy|supply/i.test(task.title)).length;
  const summary = [
    { l: 'Incident Reports', v: String(incidentCount) },
    { l: 'Tasks Completed', v: String(completedCount) },
    { l: 'Route Inspections', v: String(routeInspectionCount) },
    { l: 'Logistics Observations', v: String(logisticsCount) },
  ];

  return (
    <div className="space-y-6 max-w-screen-2xl">
      <PageHeader title="Reports" sub="Your field reporting activity"
        right={
          <button onClick={generate} disabled={gen === 'busy'}
            className="text-xs font-medium px-3 py-2 rounded transition-all disabled:opacity-70"
            style={{ background: NAVY, color: 'white', minHeight: 44 }}>
            {gen === 'busy' ? 'Generating…' : gen === 'done' ? 'Daily Report Ready ✓' : '+ Generate Report'}
          </button>
        } />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {summary.map(s => (
          <Card key={s.l} className="p-4">
            <div className="text-3xl font-bold leading-none mb-1" style={{ color: '#17212B' }}>{s.v}</div>
            <div className="text-xs font-medium" style={{ color: '#5A6670' }}>{s.l}</div>
          </Card>
        ))}
      </div>

      <Card>
        <CardHeader title="Recent Reports" sub="Review submitted field activity" />
        <div className="divide-y" style={{ borderColor: SURFACE_2 }}>
          {reports.map(r => (
            <div key={r.id} className="px-4 py-3 flex items-center gap-4 transition-colors hover:bg-black/[0.02]">
              <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background: SURFACE_2, color: NAVY }}>⊡</div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium truncate" style={{ color: '#17212B' }}>{r.title}</div>
                <div className="text-xs" style={{ color: '#8A9098' }}>
                  <span className="font-mono">{r.id}</span> · {r.type} · {r.date}
                </div>
              </div>
              <span className="text-xs px-2 py-0.5 rounded border" style={{ background: '#EAF4EE', borderColor: '#A8D4B8', color: '#2D6B4F' }}>{r.status}</span>
              <button onClick={() => setSelectedReport(r)} className="text-xs font-medium px-2.5 py-1 rounded border" style={{ color: TEAL, borderColor: BORDER }}>View</button>
            </div>
          ))}
          {reports.length === 0 && <div className="px-4 py-10 text-center text-sm" style={{ color: '#8A9098' }}>No task activity to report yet.</div>}
        </div>
      </Card>

      {selectedReport && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/35 p-4" onClick={() => setSelectedReport(null)}>
          <div className="w-full max-w-lg rounded-xl border shadow-2xl" onClick={event => event.stopPropagation()} style={{ background: 'rgba(250,247,240,0.98)', borderColor: BORDER }}>
            <div className="flex items-start justify-between gap-4 px-5 py-4 border-b" style={{ borderColor: BORDER }}>
              <div>
                <div className="font-mono text-xs" style={{ color: '#8A9098' }}>{selectedReport.id}</div>
                <h2 className="font-semibold text-lg" style={{ color: '#17212B' }}>{selectedReport.title}</h2>
              </div>
              <button onClick={() => setSelectedReport(null)} className="text-xl" style={{ color: '#8A9098' }} aria-label="Close report">✕</button>
            </div>
            <div className="p-5 space-y-3 text-sm">
              <div className="flex justify-between gap-4"><span style={{ color: '#8A9098' }}>Type</span><span style={{ color: '#17212B' }}>{selectedReport.type}</span></div>
              <div className="flex justify-between gap-4"><span style={{ color: '#8A9098' }}>Created</span><span style={{ color: '#17212B' }}>{selectedReport.date}</span></div>
              <div className="flex justify-between gap-4"><span style={{ color: '#8A9098' }}>Status</span><span style={{ color: '#2D6B4F' }}>{selectedReport.status}</span></div>
              <textarea value={manualReport} onChange={event => setManualReport(event.target.value)} rows={8}
                className="w-full rounded-lg border p-3 text-xs"
                style={{ background: 'rgba(238,228,210,0.88)', borderColor: BORDER, color: '#17212B' }} />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
