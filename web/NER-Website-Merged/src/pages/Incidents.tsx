import { useEffect, useMemo, useState } from 'react';
import MapViz from '@/components/MapViz';
import { SeverityBadge, StatusBadge } from '@/components/StatusBadge';
import { incidents as initialIncidents } from '@/data/demo';
import type { Incident, IncidentStatus } from '@/data/demo';
import { getIncidents, subscribeToIncidents, updateIncident } from '@/lib/incidentStore';
import { createTaskFromIncident } from '@/lib/taskStore';

const tabs: { key: string; label: string; filter: (i: Incident) => boolean }[] = [
  { key: 'all', label: 'All', filter: () => true },
  { key: 'pending', label: 'Pending Verification', filter: i => i.status === 'PENDING_VERIFICATION' || i.status === 'UNDER_REVIEW' },
  { key: 'active', label: 'Active', filter: i => i.status === 'ACTIVE' },
  { key: 'escalated', label: 'Escalated', filter: i => i.status === 'ESCALATED' },
  { key: 'resolved', label: 'Resolved', filter: i => i.status === 'RESOLVED' },
];

const timeline = ['Reported', 'Verified', 'Assigned', 'Response in Progress', 'Resolved'];

function getTimelineStep(status: IncidentStatus) {
  if (status === 'PENDING_VERIFICATION' || status === 'UNDER_REVIEW') return 0;
  if (status === 'ACTIVE') return 3;
  if (status === 'ESCALATED') return 3;
  if (status === 'RESOLVED') return 4;
  return 0;
}

function IncidentDetail({ inc, onClose, onVerify, onAssign, onStatusChange, onCreateTask }: {
  inc: Incident; onClose: () => void;
  onVerify: (id: string) => void; onAssign: (id: string) => void;
  onStatusChange: (id: string, status: IncidentStatus) => void;
  onCreateTask: (id: string) => void;
}) {
  const step = getTimelineStep(inc.status);
  const [preview, setPreview] = useState<{ name: string; type: string; dataUrl: string } | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const mapIncidents = useMemo(() => [inc], [inc]);
        return (
          <div className="fixed inset-0 z-50 flex">
            <div className="flex-1 bg-black/30" onClick={onClose} />
            <div className="w-full max-w-2xl overflow-y-auto shadow-2xl"
        style={{ background: 'rgba(250,247,240,0.82)', borderLeft: '1px solid rgba(180,162,136,0.55)' }}>
        <div className="px-5 py-4 border-b flex items-start justify-between"
                style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.96)' }}>
          <div>
            <div className="font-mono text-xs mb-1" style={{ color: '#5A6670' }}>{inc.id}</div>
            <h2 className="font-semibold text-lg" style={{ color: '#17212B' }}>{inc.type} — {inc.location}</h2>
            <div className="flex gap-2 mt-1">
              <SeverityBadge severity={inc.severity} />
              <StatusBadge status={inc.status} />
            </div>
          </div>
          <button onClick={onClose} className="text-xl" style={{ color: '#8A9098' }}>✕</button>
        </div>

        <div className="px-5 py-4 space-y-5">
          <div className="rounded-lg border p-3 flex flex-wrap items-center justify-between gap-3" style={{ background: 'rgba(238,228,210,0.88)', borderColor: 'rgba(180,162,136,0.55)' }}>
            <div>
              <div className="text-xs uppercase tracking-wider" style={{ color: '#8A9098' }}>Current workflow state</div>
              <div className="mt-1"><StatusBadge status={inc.status} /></div>
            </div>
            <div className="flex flex-wrap gap-2">
              {inc.verification === 'Pending' && <button onClick={() => { setActionMessage('Incident verified and moved to Active.'); onVerify(inc.id); }} className="text-xs font-medium px-3 py-2 rounded" style={{ background: '#17324D', color: 'white' }}>Verify</button>}
              {inc.status !== 'ESCALATED' && inc.status !== 'RESOLVED' && <button onClick={() => { setActionMessage('Incident escalated to Control Officer.'); onStatusChange(inc.id, 'ESCALATED'); }} className="text-xs font-medium px-3 py-2 rounded border" style={{ color: '#BE2424', borderColor: '#F5B8B8', background: '#FEE9E9' }}>Escalate</button>}
              {inc.status === 'ACTIVE' && <button onClick={() => { setActionMessage('Incident marked as resolved.'); onStatusChange(inc.id, 'RESOLVED'); }} className="text-xs font-medium px-3 py-2 rounded border" style={{ color: '#2D6B4F', borderColor: '#A8D4B8', background: '#EAF4EE' }}>Resolve</button>}
            </div>
          </div>
          {/* Timeline */}
          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wider mb-3" style={{ color: '#5A6670' }}>Response Timeline</h3>
            <div className="flex items-center gap-0">
              {timeline.map((t, i) => (
                <div key={t} className="flex items-center flex-1">
                  <div className="flex flex-col items-center">
                    <div className="w-5 h-5 rounded-full border-2 flex items-center justify-center text-xs font-bold"
                      style={{
                        background: i <= step ? '#17324D' : 'rgba(238,228,210,0.88)',
                        borderColor: i <= step ? '#17324D' : 'rgba(180,162,136,0.55)',
                        color: i <= step ? 'white' : '#8A9098',
                      }}>
                      {i < step ? '✓' : i + 1}
                    </div>
                    <span className="text-xs text-center mt-1 leading-tight w-16" style={{ color: i <= step ? '#17212B' : '#8A9098', fontSize: 9 }}>
                      {t}
                    </span>
                  </div>
                  {i < timeline.length - 1 && (
                    <div className="flex-1 h-0.5 mx-1" style={{ background: i < step ? '#17324D' : 'rgba(180,162,136,0.55)' }} />
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Info */}
          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wider mb-2" style={{ color: '#5A6670' }}>Incident Information</h3>
            <div className="rounded-lg border" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
              {[
                { label: 'Type', value: inc.type },
                { label: 'Location', value: inc.location },
                { label: 'Route', value: inc.route },
                { label: 'Reported By', value: inc.reportedBy },
                { label: 'Reported Time', value: inc.reportedTime },
                { label: 'GPS Coordinates', value: inc.gpsCoords },
                { label: 'Verification', value: inc.verification },
                { label: 'Assigned Officer', value: inc.assignedOfficer ?? '— Not Assigned' },
              ].map((row, i) => (
                <div key={row.label} className="flex px-3 py-2" style={{ background: i % 2 === 0 ? 'rgba(250,247,240,0.82)' : 'rgba(243,235,220,0.55)' }}>
                  <span className="w-36 flex-shrink-0 text-xs" style={{ color: '#8A9098' }}>{row.label}</span>
                  <span className="text-xs font-medium" style={{ color: '#17212B' }}>{row.value}</span>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wider mb-2" style={{ color: '#5A6670' }}>Location Map</h3>
            <div className="rounded-lg border overflow-hidden" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
              <MapViz incidents={mapIncidents} height={220} rounded="0" showLegend={false} />
            </div>
          </div>

          {/* Description */}
          <div className="rounded-lg p-3 border" style={{ background: 'rgba(238,228,210,0.88)', borderColor: 'rgba(180,162,136,0.55)' }}>
            <p className="text-xs leading-relaxed" style={{ color: '#5A6670' }}>{inc.description}</p>
          </div>

          {inc.evidence && inc.evidence.length > 0 && (
            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wider mb-2" style={{ color: '#5A6670' }}>Evidence</h3>
              <div className="grid grid-cols-2 gap-3">
                {inc.evidence.map(file => (
                  <button type="button" key={`${inc.id}-${file.name}`} onClick={() => setPreview(file)}
                    className="rounded-lg border overflow-hidden text-left" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
                    {file.type.startsWith('image/') ? (
                      <img src={file.dataUrl} alt={file.name} className="h-32 w-full object-cover" />
                    ) : (
                      <div className="h-32 flex items-center justify-center" style={{ background: 'rgba(238,228,210,0.88)', color: '#17324D' }}>Video evidence</div>
                    )}
                    <div className="px-2 py-1.5 text-xs truncate" style={{ color: '#2F6F7E' }}>{file.name}</div>
                  </button>
                ))}
              </div>
            </div>
          )}

          {preview && (
            <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/70 p-4" onClick={() => setPreview(null)}>
              <div className="relative max-w-4xl max-h-[90vh] rounded-lg overflow-hidden" onClick={event => event.stopPropagation()} style={{ background: '#17212B' }}>
                <button type="button" onClick={() => setPreview(null)} className="absolute top-2 right-2 z-10 rounded-full px-2 py-1 text-lg" aria-label="Close evidence preview" style={{ background: 'rgba(0,0,0,0.65)', color: 'white' }}>✕</button>
                {preview.type.startsWith('image/') ? <img src={preview.dataUrl} alt={preview.name} className="max-h-[85vh] max-w-[90vw] object-contain" /> : <video src={preview.dataUrl} controls className="max-h-[85vh] max-w-[90vw]" />}
              </div>
            </div>
          )}

          {/* AI Risk */}
          <div className="rounded-lg border p-3" style={{ background: '#FEF8E6', borderColor: '#F5DFA8' }}>
            <div className="flex items-center gap-1.5 mb-2">
              <span style={{ color: '#D7A73A' }}>✦</span>
              <h3 className="text-xs font-semibold uppercase tracking-wider" style={{ color: '#5A6670' }}>AI Risk Assessment</h3>
            </div>
            <div className="flex items-center gap-3 mb-2">
              <div className="text-3xl font-bold" style={{ color: '#17212B' }}>{inc.riskScore}</div>
              <div>
                <div className="text-xs" style={{ color: '#5A6670' }}>Risk Score / 100</div>
                <SeverityBadge severity={inc.riskScore > 75 ? 'CRITICAL' : inc.riskScore > 50 ? 'HIGH' : inc.riskScore > 25 ? 'MODERATE' : 'LOW'} />
              </div>
              <div className="flex-1 ml-2">
                <div className="h-2 rounded-full overflow-hidden" style={{ background: 'rgba(180,162,136,0.55)' }}>
                  <div style={{ width: `${inc.riskScore}%`, background: inc.riskScore > 75 ? '#BE2424' : '#E07840' }} className="h-full rounded-full" />
                </div>
              </div>
            </div>
            <p className="text-xs" style={{ color: '#8A9098' }}>AI-generated estimate · Affected logistics: {inc.affectedLogistics} convoys · {inc.estimatedDisruption}</p>
          </div>

          {/* Actions */}
          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wider mb-2" style={{ color: '#5A6670' }}>Actions</h3>
            <div className="flex flex-wrap gap-2">
              {inc.verification === 'Pending' && (
                <button onClick={() => { setActionMessage('Incident verified and moved to Active.'); onVerify(inc.id); }}
                  className="text-xs font-medium px-3 py-2 rounded border"
                  style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
                  ✓ Verify Incident
                </button>
              )}
              <button onClick={() => { setActionMessage('Officer assignment saved.'); onAssign(inc.id); }}
                className="text-xs font-medium px-3 py-2 rounded border"
                style={{ background: '#2F6F7E', color: 'white', borderColor: '#2F6F7E' }}>
                Assign Officer
              </button>
              <button onClick={() => { setActionMessage('Task created from this incident.'); onCreateTask(inc.id); }} className="text-xs font-medium px-3 py-2 rounded border"
                style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>
                Create Task
              </button>
              <button onClick={() => { setActionMessage('Incident escalated to Control Officer.'); onStatusChange(inc.id, 'ESCALATED'); }} className="text-xs font-medium px-3 py-2 rounded border"
                style={{ borderColor: '#F5B8B8', color: '#BE2424', background: '#FEE9E9' }}>
                Escalate
              </button>
              {inc.status === 'ACTIVE' && (
                <button onClick={() => { setActionMessage('Incident marked as resolved.'); onStatusChange(inc.id, 'RESOLVED'); }} className="text-xs font-medium px-3 py-2 rounded border"
                  style={{ borderColor: '#A8D4B8', color: '#2D6B4F', background: '#EAF4EE' }}>
                  ✓ Resolve Incident
                </button>
              )}
            </div>
            {actionMessage && <p className="text-xs mt-2" style={{ color: '#2D6B4F' }}>{actionMessage}</p>}
          </div>
        </div>
      </div>
    </div>
  );
}

export default function Incidents() {
  const [tab, setTab] = useState('all');
  const [severityFilter, setSeverityFilter] = useState('All Severity');
  const [typeFilter, setTypeFilter] = useState('All Types');
  const [selected, setSelected] = useState<string | null>(null);
  const [incList, setIncList] = useState<Incident[]>(() => [...initialIncidents, ...getIncidents()]);

  useEffect(() => subscribeToIncidents(stored => setIncList([...initialIncidents, ...stored])), []);

  const current = tabs.find(t => t.key === tab)!;
  const filtered = incList.filter(current.filter).filter(incident =>
    (severityFilter === 'All Severity' || incident.severity === severityFilter.toUpperCase()) &&
    (typeFilter === 'All Types' || incident.type === typeFilter)
  );
  const selectedInc = incList.find(i => i.id === selected);

  const handleVerify = (id: string) => {
    updateIncident(id, { verification: 'Verified', status: 'ACTIVE' });
    setIncList(prev => prev.map(i => i.id === id ? { ...i, verification: 'Verified' as const, status: 'ACTIVE' as const } : i));
  };
  const handleAssign = (id: string) => {
    updateIncident(id, { assignedOfficer: 'FO-101', status: 'ACTIVE' });
    setIncList(prev => prev.map(i => i.id === id ? { ...i, assignedOfficer: 'FO-101', status: 'ACTIVE' as const } : i));
  };
  const handleStatusChange = (id: string, status: IncidentStatus) => {
    updateIncident(id, { status });
    setIncList(prev => prev.map(i => i.id === id ? { ...i, status } : i));
  };
  const handleCreateTask = (id: string) => {
    const incident = incList.find(item => item.id === id);
    if (!incident) return;
    createTaskFromIncident({
      incidentId: incident.id,
      title: `Follow up: ${incident.type} at ${incident.location}`,
      location: incident.location,
      priority: incident.severity,
      description: incident.description,
    });
    setIncList(prev => prev.map(i => i.id === id ? { ...i, status: i.status === 'PENDING_VERIFICATION' ? 'ACTIVE' : i.status } : i));
    updateIncident(id, { status: 'ACTIVE' });
  };

  return (
    <div className="space-y-5 max-w-screen-2xl">
      <div>
        <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>Incidents</h1>
        <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>Manage and verify incident reports across the district</p>
      </div>

      {/* Summary stats */}
      <div className="grid grid-cols-5 gap-3">
        {tabs.map(t => {
          const count = incList.filter(t.filter).length;
          return (
            <button key={t.key} onClick={() => setTab(t.key)}
              className="rounded-xl border p-3 text-left transition-all"
              style={{
                background: tab === t.key ? '#17324D' : 'rgba(250,247,240,0.82)',
                borderColor: tab === t.key ? '#17324D' : 'rgba(180,162,136,0.55)',
              }}>
              <div className="text-2xl font-bold" style={{ color: tab === t.key ? 'white' : '#17212B' }}>{count}</div>
              <div className="text-xs mt-0.5" style={{ color: tab === t.key ? '#8AAFC8' : '#5A6670' }}>{t.label}</div>
            </button>
          );
        })}
      </div>

      {/* Tabs */}
      <div className="flex gap-0 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
        {tabs.map(t => (
          <button key={t.key} onClick={() => setTab(t.key)}
            className="px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors"
            style={{
              borderBottomColor: tab === t.key ? '#17324D' : 'transparent',
              color: tab === t.key ? '#17324D' : '#5A6670',
            }}>
            {t.label}
            <span className="ml-1.5 text-xs px-1.5 py-0.5 rounded-full"
              style={{ background: 'rgba(238,228,210,0.88)', color: '#5A6670' }}>
              {incList.filter(t.filter).length}
            </span>
          </button>
        ))}
      </div>

      {/* Table */}
      <div className="rounded-xl border shadow-sm overflow-hidden"
        style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>

        {/* Table header with actions */}
        <div className="px-4 py-3 border-b flex items-center justify-between"
          style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
          <span className="text-sm font-medium" style={{ color: '#17212B' }}>
            {filtered.length} incident{filtered.length !== 1 ? 's' : ''}
          </span>
          <div className="flex gap-2">
            <select value={severityFilter} onChange={event => setSeverityFilter(event.target.value)} className="text-xs px-2 py-1.5 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(250,247,240,0.82)' }}>
              <option>All Severity</option>
              <option>Critical</option>
              <option>High</option>
              <option>Moderate</option>
            </select>
            <select value={typeFilter} onChange={event => setTypeFilter(event.target.value)} className="text-xs px-2 py-1.5 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(250,247,240,0.82)' }}>
              <option>All Types</option>
              <option>Flood</option>
              <option>Landslide</option>
              <option>Road Blockage</option>
              <option>Accident</option>
              <option>Infrastructure Damage</option>
            </select>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: 'rgba(243,235,220,0.55)' }}>
                {['Incident ID', 'Type', 'Location', 'Route', 'Severity', 'Reported By', 'Time', 'Verification', 'Assigned', 'Status', 'Actions'].map(h => (
                  <th key={h} className="text-left px-4 py-2.5 text-xs font-semibold uppercase tracking-wider whitespace-nowrap"
                    style={{ color: '#5A6670' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map((inc, i) => (
                <tr key={inc.id}
                  className="hover:bg-opacity-50 transition-colors cursor-pointer"
                  style={{ background: i % 2 === 0 ? 'rgba(250,247,240,0.82)' : 'rgba(243,235,220,0.55)' }}
                  onClick={() => setSelected(inc.id)}>
                  <td className="px-4 py-2.5 font-mono text-xs font-medium" style={{ color: '#2F6F7E' }}>{inc.id}</td>
                  <td className="px-4 py-2.5 text-xs whitespace-nowrap" style={{ color: '#17212B' }}>{inc.type}</td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670', maxWidth: 160 }}>{inc.location}</td>
                  <td className="px-4 py-2.5 font-mono text-xs" style={{ color: '#2F6F7E' }}>{inc.route}</td>
                  <td className="px-4 py-2.5"><SeverityBadge severity={inc.severity} /></td>
                  <td className="px-4 py-2.5 font-mono text-xs" style={{ color: '#5A6670' }}>{inc.reportedBy}</td>
                  <td className="px-4 py-2.5 text-xs whitespace-nowrap" style={{ color: '#8A9098' }}>{inc.reportedTime}</td>
                  <td className="px-4 py-2.5"><StatusBadge status={inc.verification} /></td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: inc.assignedOfficer ? '#17212B' : '#8A9098' }}>
                    {inc.assignedOfficer ?? '—'}
                  </td>
                  <td className="px-4 py-2.5"><StatusBadge status={inc.status} /></td>
                  <td className="px-4 py-2.5">
                    <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                      <button onClick={() => setSelected(inc.id)}
                        className="text-xs px-2 py-1 rounded border"
                        style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#2F6F7E' }}>View</button>
                      {inc.verification === 'Pending' && (
                        <button onClick={() => handleVerify(inc.id)}
                          className="text-xs px-2 py-1 rounded border"
                          style={{ borderColor: '#A8D4B8', color: '#2D6B4F' }}>Verify</button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {filtered.length === 0 && <div className="px-4 py-12 text-center text-sm" style={{ color: '#8A9098' }}>No incidents match this view.</div>}
        </div>
      </div>

      {selectedInc && (
        <IncidentDetail
          inc={selectedInc}
          onClose={() => setSelected(null)}
          onVerify={handleVerify}
          onAssign={handleAssign}
          onStatusChange={handleStatusChange}
          onCreateTask={handleCreateTask}
        />
      )}
    </div>
  );
}
