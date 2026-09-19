import { useMemo, useState, useEffect } from 'react';
import { getIncidents } from '@/lib/incidentStore';
import { getTasks } from '@/lib/taskStore';
import { profileService } from '@/lib/profileService';

const reportTypes = [
  'Daily Situation Report', 'District Logistics Report', 'Route Risk Report',
  'Incident Report', 'Disruption Report', 'AI Risk Report',
];

const severityMap: Record<string, string> = {
  Critical: 'CRITICAL',
  High: 'HIGH',
  Moderate: 'MODERATE',
  Low: 'LOW',
};

function escapePdfText(value: string) {
  return value.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
}

function buildPdfBlob(lines: string[]) {
  const content = lines
    .map((line, index) => `BT /F1 9 Tf 52 ${760 - index * 14} Td (${escapePdfText(line)}) Tj ET`)
    .join('\n');

  const objects: string[] = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ];

  let pdf = '%PDF-1.4\n';
  const offsets: number[] = [0];

  objects.forEach((obj, index) => {
    offsets.push(pdf.length);
    pdf += `${index + 1} 0 obj\n${obj}\nendobj\n`;
  });

  const xrefStart = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n`;
  pdf += '0000000000 65535 f \n';
  for (let i = 1; i <= objects.length; i += 1) {
    pdf += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
  }

  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF`;
  return new Blob([pdf], { type: 'application/pdf' });
}

function createDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

function createCsvContent(rows: Array<Record<string, string | number>>) {
  if (!rows.length) return 'Report Type,Date,District,Summary\nNo data available,\n';

  const headers = Object.keys(rows[0]);
  const csvRows = [headers.join(',')];
  rows.forEach(row => {
    csvRows.push(headers.map(header => {
      const value = row[header];
      const escaped = String(value ?? '').replace(/"/g, '""');
      return `"${escaped}"`;
    }).join(','));
  });
  return `${csvRows.join('\n')}\n`;
}

export default function Reports() {
  const incidents = getIncidents();
  const tasks = getTasks();
  const [reportType, setReportType] = useState(reportTypes[0]);
  const [generated, setGenerated] = useState(false);
  const [reportDate, setReportDate] = useState(new Date().toISOString().split('T')[0]);
  const [district, setDistrict] = useState(() => profileService.getProfile().region || 'Kamrup Metro, Assam');
  const [incidentType, setIncidentType] = useState('All Types');
  const [severityFilter, setSeverityFilter] = useState('All Severity Levels');
  const [manualReport, setManualReport] = useState('');

  useEffect(() => {
    const unsub = profileService.subscribe(p => {
      if (p.region) setDistrict(p.region);
    });
    return unsub;
  }, []);

  const filteredIncidents = useMemo(() => {
    let list = incidents;
    if (incidentType !== 'All Types') list = list.filter(item => item.type === incidentType);
    if (severityFilter !== 'All Severity Levels') {
      const target = severityMap[severityFilter] ?? severityFilter.toUpperCase();
      list = list.filter(item => item.severity === target);
    }
    return list;
  }, [incidents, incidentType, severityFilter]);

  const filteredTasks = useMemo(() => {
    if (incidentType === 'All Types') return tasks;
    return tasks.filter(task => !task.relatedIncident || filteredIncidents.some(item => item.id === task.relatedIncident));
  }, [tasks, filteredIncidents, incidentType]);

  const summary = useMemo(() => {
    const activeIncidents = filteredIncidents.filter(item => ['PENDING_VERIFICATION', 'ACTIVE', 'ESCALATED', 'UNDER_REVIEW'].includes(item.status)).length;
    const blockedRoutes = new Set(filteredIncidents.filter(item => ['ACTIVE', 'ESCALATED'].includes(item.status)).map(item => item.route)).size;
    const delayedConvoys = filteredTasks.filter(task => ['New', 'In Progress', 'Escalated'].includes(task.status)).length;
    const criticalCount = filteredIncidents.filter(item => item.severity === 'CRITICAL' || item.severity === 'HIGH').length;
    const avgResponseMinutes = filteredIncidents.length
      ? Math.round(filteredIncidents.reduce((sum, item) => sum + Math.max(0, Math.round((Date.now() - new Date(item.reportedTime).getTime()) / 60000)), 0) / filteredIncidents.length)
      : 0;
    return { activeIncidents, blockedRoutes, delayedConvoys, criticalCount, avgResponseMinutes };
  }, [filteredIncidents, filteredTasks]);

  const today = new Date(reportDate).toLocaleDateString('en-IN', { dateStyle: 'long' });

  const buildReportText = () => [
    'Janrakshak AI District Operations Report',
    `Type: ${reportType}`,
    `Date: ${today}`,
    `District: ${district}`,
    `Filter: ${incidentType} / ${severityFilter}`,
    '',
    `Active incidents: ${summary.activeIncidents}`,
    `Blocked routes: ${summary.blockedRoutes}`,
    `Delayed convoys/tasks: ${summary.delayedConvoys}`,
    `Critical/high count: ${summary.criticalCount}`,
    `Average response time: ${summary.avgResponseMinutes} min`,
    '',
    ...filteredIncidents.slice(0, 10).map(item => `${item.id} | ${item.type} | ${item.severity} | ${item.status} | ${item.location}`),
  ].join('\n');

  const exportCsv = () => {
    const rows = filteredIncidents.map(item => ({
      ReportType: reportType,
      Date: reportDate,
      District: district,
      IncidentID: item.id,
      Type: item.type,
      Severity: item.severity,
      Status: item.status,
      Location: item.location,
      Route: item.route,
      ReportedBy: item.reportedBy,
      ResponseMinutes: Math.max(0, Math.round((Date.now() - new Date(item.reportedTime).getTime()) / 60000)),
      Notes: manualReport || 'No manual notes.'
    }));

    const csv = createCsvContent(rows);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    createDownload(blob, `${reportType.toLowerCase().replace(/\s+/g, '-')}-${reportDate}.csv`);
  };

  const exportPdf = () => {
    const lines = (manualReport || buildReportText()).split('\n');
    const blob = buildPdfBlob(lines);
    createDownload(blob, `${reportType.toLowerCase().replace(/\s+/g, '-')}-${reportDate}.pdf`);
  };

  return (
    <div className="space-y-5 max-w-screen-2xl">
      <div>
        <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>Reports</h1>
        <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>Generate and export operational reports</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        <div className="rounded-xl border shadow-sm p-4 space-y-4"
          style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Report Configuration</h2>

          <div>
            <label className="text-xs font-medium block mb-1" style={{ color: '#5A6670' }}>Report Type</label>
            <select value={reportType} onChange={e => { setReportType(e.target.value); setGenerated(false); }}
              className="w-full text-sm px-3 py-2 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)', color: '#17212B' }}>
              {reportTypes.map(r => <option key={r}>{r}</option>)}
            </select>
          </div>

          <div>
            <label className="text-xs font-medium block mb-1" style={{ color: '#5A6670' }}>Date</label>
            <input type="date" value={reportDate} onChange={e => { setReportDate(e.target.value); setGenerated(false); }}
              className="w-full text-sm px-3 py-2 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)', color: '#17212B' }} />
          </div>

          <div>
            <label className="text-xs font-medium block mb-1" style={{ color: '#5A6670' }}>District</label>
            <input value={district} onChange={e => { setDistrict(e.target.value); setGenerated(false); }}
              className="w-full text-sm px-3 py-2 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)', color: '#17212B' }} />
          </div>

          <div>
            <label className="text-xs font-medium block mb-1" style={{ color: '#5A6670' }}>Incident Type</label>
            <select value={incidentType} onChange={e => { setIncidentType(e.target.value); setGenerated(false); }}
              className="w-full text-sm px-3 py-2 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)', color: '#17212B' }}>
              <option>All Types</option>
              <option>Flood</option>
              <option>Landslide</option>
              <option>Road Blockage</option>
              <option>Infrastructure Damage</option>
              <option>Accident</option>
              <option>Vehicle Breakdown</option>
            </select>
          </div>

          <div>
            <label className="text-xs font-medium block mb-1" style={{ color: '#5A6670' }}>Severity Filter</label>
            <select value={severityFilter} onChange={e => { setSeverityFilter(e.target.value); setGenerated(false); }}
              className="w-full text-sm px-3 py-2 rounded border"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)', color: '#17212B' }}>
              <option>All Severity Levels</option>
              <option>Critical</option>
              <option>High</option>
              <option>Moderate</option>
              <option>Low</option>
            </select>
          </div>

          <button onClick={() => {
            setManualReport(buildReportText());
            setGenerated(true);
          }}
            className="w-full text-sm font-semibold py-2.5 rounded border transition-colors"
            style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
            Generate Report
          </button>

          {generated && (
            <div className="flex gap-2">
              <button onClick={exportPdf}
                className="flex-1 text-xs font-medium py-2 rounded border"
                style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#2F6F7E' }}>
                ↓ Export PDF
              </button>
              <button onClick={exportCsv}
                className="flex-1 text-xs font-medium py-2 rounded border"
                style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#2F6F7E' }}>
                ↓ Export CSV
              </button>
            </div>
          )}
        </div>

        <div className="lg:col-span-2 rounded-xl border shadow-sm overflow-hidden"
          style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          {generated ? (
            <>
              <div className="px-6 py-4 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
                <div className="flex items-center justify-between">
                  <div>
                    <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>{reportType}</h2>
                    <p className="text-xs" style={{ color: '#8A9098' }}>{today}</p>
                  </div>
                  <div className="text-xs px-2 py-1 rounded border" style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#8A9098' }}>
                    DRAFT
                  </div>
                </div>
              </div>

              <div className="p-6 space-y-5">
                <div className="grid grid-cols-3 gap-3">
                  {[
                    { label: 'Active Incidents', value: String(summary.activeIncidents) },
                    { label: 'Blocked Routes', value: String(summary.blockedRoutes) },
                    { label: 'Delayed Convoys', value: String(summary.delayedConvoys) },
                  ].map(k => (
                    <div key={k.label} className="rounded-lg p-3 text-center border" style={{ background: 'rgba(238,228,210,0.88)', borderColor: 'rgba(180,162,136,0.55)' }}>
                      <div className="text-2xl font-bold" style={{ color: '#17212B' }}>{k.value}</div>
                      <div className="text-xs" style={{ color: '#5A6670' }}>{k.label}</div>
                    </div>
                  ))}
                </div>

                {[
                  { label: 'Incident Summary', items: filteredIncidents.slice(0, 4).map(item => `${item.id} · ${item.type} · ${item.severity}`) },
                  { label: 'Route Status', items: [...new Set(filteredIncidents.map(item => item.route).slice(0, 4))].map(route => `${route} · ${route ? 'Monitoring active' : 'Not configured'}`) },
                  { label: 'Logistics Status', items: filteredTasks.slice(0, 4).map(task => `${task.id} · ${task.title} · ${task.status}`) },
                  { label: 'Risk Overview', items: [`Critical + high alerts: ${summary.criticalCount}`, `Average response time: ${summary.avgResponseMinutes} min`] },
                  { label: 'AI Recommendations', items: ['Live route risk coverage enabled', 'Field reassignment and convoy rerouting monitored'] },
                ].map(section => (
                  <div key={section.label}>
                    <h3 className="text-xs font-semibold uppercase tracking-wider mb-2 pb-1 border-b"
                      style={{ color: '#5A6670', borderColor: 'rgba(180,162,136,0.55)' }}>{section.label}</h3>
                    <div className="space-y-2">
                      {section.items.length ? section.items.map((item, idx) => (
                        <div key={`${section.label}-${idx}`} className="rounded p-2 text-xs" style={{ background: 'rgba(238,228,210,0.88)', color: '#5A6670' }}>
                          {item}
                        </div>
                      )) : (
                        <div className="rounded p-2 text-xs" style={{ background: 'rgba(238,228,210,0.88)', color: '#8A9098' }}>
                          No matching data available for this filter.
                        </div>
                      )}
                    </div>
                  </div>
                ))}

                <div>
                  <label className="text-xs font-semibold uppercase tracking-wider mb-2 block" style={{ color: '#5A6670' }}>Manual Report Notes</label>
                  <textarea value={manualReport} onChange={e => setManualReport(e.target.value)}
                    rows={8}
                    className="w-full rounded-lg border p-3 text-xs"
                    style={{ background: 'rgba(238,228,210,0.88)', borderColor: 'rgba(180,162,136,0.55)', color: '#17212B' }} />
                </div>

                <div className="text-xs text-center pt-4 border-t" style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#8A9098' }}>
                  Ministry of Development of North Eastern Region · Government of India
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-col items-center justify-center h-80" style={{ color: '#8A9098' }}>
              <div className="text-4xl mb-3">⊟</div>
              <div className="text-sm font-medium" style={{ color: '#5A6670' }}>Configure and generate a report</div>
              <div className="text-xs mt-1">Select report type and parameters on the left</div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
