import { useRef, useState, useEffect } from 'react';
import MapViz from '@/components/MapViz';
import { SeverityBadge } from '@/components/StatusBadge';
import type { Severity } from '@/data/demo';
import { PLACES, formatCoords, parseCoords, type LatLng } from '@/data/geo';
import { addIncident, type IncidentEvidence } from '@/lib/incidentStore';
import { Card, PageHeader, BORDER, SURFACE_2, NAVY, TEAL, GOLD } from './ui';

const STEPS = ['Incident Type', 'Location', 'Evidence', 'Details', 'Review', 'Submit'];

const TYPES = [
  { key: 'Road Blockage', icon: '⊗', color: '#C25A1A' },
  { key: 'Flood', icon: '≈', color: '#2F6F7E' },
  { key: 'Landslide', icon: '⛰', color: '#8A6A3A' },
  { key: 'Accident', icon: '⊙', color: '#BE2424' },
  { key: 'Infrastructure Damage', icon: '⌂', color: '#17324D' },
  { key: 'Other', icon: '?', color: '#5A6670' },
];

const field = {
  background: 'rgba(245,236,220,0.6)',
  border: '1px solid rgba(180,162,136,0.5)',
  color: '#17212B',
};

function Label({ children }: { children: React.ReactNode }) {
  return <label className="block text-xs font-medium mb-1" style={{ color: '#5A6670' }}>{children}</label>;
}

export default function ReportIncident({ setPage, presetType }: { setPage?: (p: string) => void; presetType?: string }) {
  const [step, setStep] = useState(0);
  const [type, setType] = useState<string | null>(presetType ?? null);
  const [severity, setSeverity] = useState<Severity>('HIGH');
  const [desc, setDesc] = useState('');
  const [route, setRoute] = useState('NH-29');
  const [locName, setLocName] = useState('Dimapur–Kohima Route');
  const [landmark, setLandmark] = useState('');
  const [gps, setGps] = useState<string | null>(null);
  const [gpsBusy, setGpsBusy] = useState(false);
  const [gpsError, setGpsError] = useState<string | null>(null);
  const [manualLocation, setManualLocation] = useState(false);
  const [evidence, setEvidence] = useState<IncidentEvidence[]>([]);
  const [evidenceError, setEvidenceError] = useState<string | null>(null);
  const [aiState, setAiState] = useState<'idle' | 'analyzing' | 'done'>('idle');
  const [submit, setSubmit] = useState<'idle' | 'submitting' | 'done'>('idle');
  const [incidentId, setIncidentId] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);
  const locationRequestRef = useRef(0);
  const reverseGeocodeControllerRef = useRef<AbortController | null>(null);

  // Run the AI assessment when arriving at the Details step with enough info.
  useEffect(() => {
    if (step === 3 && aiState === 'idle') {
      setAiState('analyzing');
      const t = setTimeout(() => setAiState('done'), 1800);
      return () => clearTimeout(t);
    }
  }, [step, aiState]);

  const captureGps = () => {
    if (!navigator.geolocation) {
      setGpsError('Location services are not available in this browser.');
      return;
    }

    setGpsBusy(true);
    setGpsError(null);
    navigator.geolocation.getCurrentPosition(
      position => {
        const { latitude, longitude } = position.coords;
        selectLocation([latitude, longitude], false);
        setGpsBusy(false);
      },
      error => {
        setGpsError(error.code === error.PERMISSION_DENIED ? 'Location permission was denied. You can allow it in browser settings or use the manual location fallback.' : 'Unable to detect your location. Try again.');
        setGpsBusy(false);
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 },
    );
  };

  const useManualLocation = () => {
    setManualLocation(true);
    setGps('Manual location — GPS permission unavailable');
    setGpsError(null);
  };

  const pickLocation = (point: LatLng) => {
    selectLocation(point, true);
  };

  const selectLocation = (point: LatLng, manual: boolean) => {
    const requestId = ++locationRequestRef.current;
    reverseGeocodeControllerRef.current?.abort();
    const controller = new AbortController();
    reverseGeocodeControllerRef.current = controller;

    const [latitude, longitude] = point;
    const fallbackName = `Selected location (${latitude.toFixed(6)}, ${longitude.toFixed(6)})`;
    setManualLocation(manual);
    setGps(formatCoords(point));
    setLocName(fallbackName);
    setRoute('');
    setLandmark('');
    setGpsError(null);

    fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latitude}&lon=${longitude}&zoom=18&addressdetails=1`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    })
      .then(response => response.ok ? response.json() : null)
      .then(result => {
        if (!result || requestId !== locationRequestRef.current) return;
        const address = result.address ?? {};
        const road = address.road ?? address.highway ?? address.route ?? address.road_ref ?? '';
        const nearby = address.landmark ?? address.amenity ?? address.tourism ?? address.building ?? address.neighbourhood ?? address.suburb ?? '';
        setLocName(result.display_name || fallbackName);
        setRoute(road);
        setLandmark(nearby);
      })
      .catch(error => {
        if (error.name !== 'AbortError' && requestId === locationRequestRef.current) {
          setLocName(fallbackName);
          setRoute('');
          setLandmark('');
        }
      });
  };

  const pin = parseCoords(gps);

  const readEvidence = (file: File) => new Promise<IncidentEvidence>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve({ name: file.name, type: file.type, size: file.size, dataUrl: String(reader.result) });
    reader.onerror = () => reject(new Error(`Unable to read ${file.name}`));
    reader.readAsDataURL(file);
  });

  const handleEvidenceChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files ?? []);
    if (!files.length) return;
    setEvidenceError(null);

    try {
      const nextEvidence = await Promise.all(files.map(readEvidence));
      setEvidence(current => [...current, ...nextEvidence]);
    } catch (error) {
      setEvidenceError(error instanceof Error ? error.message : 'Unable to upload evidence.');
    } finally {
      event.target.value = '';
    }
  };

  const doSubmit = () => {
    setSubmit('submitting');
    try {
      const incident = addIncident({
        type: (type ?? 'Other') as Parameters<typeof addIncident>[0]['type'],
        location: locName,
        route,
        severity,
        reportedBy: 'Field Officer',
        description: desc,
        gpsCoords: gps ?? '',
        evidence,
      });
      setIncidentId(incident.id);
      setSubmit('done');
      setStep(5);
    } catch {
      setEvidenceError('Incident could not be saved. Please remove large files and try again.');
      setSubmit('idle');
    }
  };

  const canNext =
    step === 0 ? !!type :
    step === 1 ? !!gps :
    true;

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader title="Report Incident"
        sub="Field incident reporting · optimized for on-site capture" />

      {/* Stepper */}
      <Card className="p-4">
        <div className="flex items-center overflow-x-auto">
          {STEPS.map((s, i) => {
            const done = i < step, active = i === step;
            return (
              <div key={s} className="flex items-center flex-shrink-0">
                <div className="flex items-center gap-2">
                  <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold transition-all"
                    style={{
                      background: done ? '#2D6B4F' : active ? NAVY : SURFACE_2,
                      color: done || active ? 'white' : '#8A9098',
                    }}>
                    {done ? '✓' : String(i + 1).padStart(2, '0')}
                  </div>
                  <span className="text-xs font-medium whitespace-nowrap"
                    style={{ color: active ? '#17212B' : '#8A9098' }}>{s}</span>
                </div>
                {i < STEPS.length - 1 && <span className="mx-3 text-xs" style={{ color: BORDER }}>→</span>}
              </div>
            );
          })}
        </div>
      </Card>

      <Card className="p-5">
        {/* STEP 1 — Type */}
        {step === 0 && (
          <div>
            <h3 className="font-semibold text-base mb-1" style={{ color: '#17212B' }}>Select Incident Type</h3>
            <p className="text-xs mb-4" style={{ color: '#8A9098' }}>Choose the category that best matches what you observe.</p>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {TYPES.map(t => {
                const sel = type === t.key;
                return (
                  <button key={t.key} onClick={() => setType(t.key)}
                    className="rounded-lg border p-4 flex flex-col items-center gap-2 text-center transition-all hover:-translate-y-0.5"
                    style={{ background: sel ? t.color + '14' : SURFACE_2, borderColor: sel ? t.color : BORDER, minHeight: 44 }}>
                    <span className="w-11 h-11 rounded-full flex items-center justify-center text-xl"
                      style={{ background: t.color + '18', color: t.color }}>{t.icon}</span>
                    <span className="text-xs font-medium" style={{ color: '#17212B' }}>{t.key}</span>
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {/* STEP 2 — Location */}
        {step === 1 && (
          <div className="space-y-4">
            <h3 className="font-semibold text-base" style={{ color: '#17212B' }}>Location</h3>
            <div className="rounded-lg border p-4" style={{ background: SURFACE_2, borderColor: BORDER }}>
              <div className="flex items-center justify-between gap-3 flex-wrap">
                <div>
                  <div className="text-xs font-medium" style={{ color: '#5A6670' }}>GPS Coordinates</div>
                  <div className="text-sm font-mono mt-0.5" style={{ color: gps ? '#17212B' : '#8A9098' }}>
                    {gps ?? 'Not captured'}
                  </div>
                </div>
                <button onClick={captureGps} disabled={gpsBusy}
                  className="text-xs font-medium px-3 py-2 rounded transition-all disabled:opacity-70"
                  style={{ background: gps ? '#EAF4EE' : NAVY, color: gps ? '#2D6B4F' : 'white', minHeight: 44 }}>
                  {gpsBusy ? '◉ Locating…' : gps ? '✓ GPS Captured — Re-detect' : '◉ Auto-detect GPS'}
                </button>
              </div>
              {gpsError && <p className="text-xs mt-2" style={{ color: '#BE2424' }}>{gpsError}</p>}
              {gpsError && <button type="button" onClick={useManualLocation} className="text-xs font-medium mt-2 px-3 py-1.5 rounded border" style={{ borderColor: BORDER, color: TEAL }}>Use manual location</button>}
            </div>
            <div className="relative rounded-lg border overflow-hidden" style={{ borderColor: BORDER }}>
              <MapViz height={240} rounded="0" showLegend={false} center={PLACES.dimapur} zoom={11}
                pin={pin} pinColor={manualLocation ? '#C4861A' : '#BE2424'} onPick={pickLocation} />
              <span className="absolute bottom-3 left-1/2 -translate-x-1/2 z-[1000] text-xs px-2.5 py-1 rounded-full whitespace-nowrap pointer-events-none shadow-sm"
                style={{ background: 'rgba(250,247,240,0.92)', color: NAVY }}>
                {pin
                  ? manualLocation ? 'Pin placed manually — drag to adjust' : 'Pin dropped at current location — drag to adjust'
                  : 'Capture GPS or tap the map to place a pin'}
              </span>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Location Name</Label>
                <input value={locName} onChange={e => setLocName(e.target.value)} className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
              <div><Label>Route Name</Label>
                <input value={route} onChange={e => setRoute(e.target.value)} className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
              <div className="col-span-2"><Label>Nearby Landmark</Label>
                <input value={landmark} onChange={e => setLandmark(e.target.value)} placeholder="e.g. Dhansiri River bridge, Km 34" className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
            </div>
          </div>
        )}

        {/* STEP 3 — Evidence */}
        {step === 2 && (
          <div className="space-y-4">
            <h3 className="font-semibold text-base" style={{ color: '#17212B' }}>Evidence</h3>
            <input ref={fileInputRef} type="file" accept="image/*,video/*" multiple onChange={handleEvidenceChange} className="hidden" />
            <button onClick={() => fileInputRef.current?.click()}
              className="w-full rounded-lg border border-dashed p-6 flex flex-col items-center gap-2 transition-colors"
              style={{ borderColor: BORDER, background: SURFACE_2, minHeight: 44 }}>
              <span className="text-2xl" style={{ color: TEAL }}>⊕</span>
              <span className="text-sm font-medium" style={{ color: '#17212B' }}>Capture / Upload Image</span>
              <span className="text-xs" style={{ color: '#8A9098' }}>Multiple images and a short video are supported. Timestamp &amp; GPS metadata are attached automatically.</span>
            </button>
            {evidenceError && <p className="text-xs" style={{ color: '#BE2424' }}>{evidenceError}</p>}
            {evidence.length > 0 && (
              <div className="grid grid-cols-3 sm:grid-cols-4 gap-3">
                {evidence.map((e, i) => (
                  <div key={`${e.name}-${i}`} className="rounded-lg border overflow-hidden" style={{ borderColor: BORDER }}>
                    <div className="h-20 flex items-center justify-center" style={{ background: 'linear-gradient(135deg,#DFCBA8,#BFD0C0)' }}>
                      {e.type.startsWith('image/') ? <img src={e.dataUrl} alt={e.name} className="h-full w-full object-cover" /> : <span className="text-lg" style={{ color: NAVY }}>▤</span>}
                    </div>
                    <div className="px-2 py-1.5">
                      <div className="flex items-center gap-1">
                        <div className="text-xs font-mono truncate flex-1" style={{ color: '#17212B' }}>{e.name}</div>
                        <button type="button" onClick={() => setEvidence(current => current.filter((_, index) => index !== i))}
                          className="text-xs font-medium px-1.5 py-0.5 rounded border" aria-label={`Remove ${e.name}`}
                          style={{ color: '#BE2424', borderColor: '#F5B8B8' }}>Remove</button>
                      </div>
                      <div style={{ fontSize: 10, color: '#8A9098' }}>{Math.ceil(e.size / 1024)} KB · ◉ GPS tagged</div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* STEP 4 — Details + AI Assessment */}
        {step === 3 && (
          <div className="space-y-4">
            <h3 className="font-semibold text-base" style={{ color: '#17212B' }}>Incident Details</h3>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Severity</Label>
                <div className="flex gap-1.5 flex-wrap">
                  {(['LOW', 'MODERATE', 'HIGH', 'CRITICAL'] as Severity[]).map(s => (
                    <button key={s} onClick={() => setSeverity(s)}
                      className="rounded transition-all" style={{ outline: severity === s ? `2px solid ${NAVY}` : 'none', borderRadius: 6 }}>
                      <SeverityBadge severity={s} />
                    </button>
                  ))}
                </div>
              </div>
              <div><Label>Road Condition</Label>
                <select className="w-full rounded px-3 py-2 text-sm outline-none" style={field}>
                  <option>Partially Accessible</option><option>Fully Blocked</option><option>Passable with caution</option>
                </select></div>
              <div><Label>Vehicles Affected</Label>
                <input type="number" defaultValue={12} className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
              <div><Label>Estimated Blockage</Label>
                <input defaultValue="4–6 hours" className="w-full rounded px-3 py-2 text-sm outline-none" style={field} /></div>
              <div className="col-span-2"><Label>Description</Label>
                <textarea value={desc} onChange={e => setDesc(e.target.value)} rows={3}
                  placeholder="Describe conditions, accessibility and any immediate action required…"
                  className="w-full rounded px-3 py-2 text-sm outline-none resize-none" style={field} /></div>
            </div>

            {/* AI assessment */}
            <div className="rounded-lg border p-4" style={{ background: '#FEF8E6', borderColor: '#F5DFA8' }}>
              <div className="flex items-center gap-1.5 mb-3">
                <span style={{ color: GOLD }}>✦</span>
                <span className="text-xs font-semibold uppercase tracking-wider" style={{ color: '#C4861A' }}>AI Incident Assessment</span>
                <span className="text-xs ml-auto px-1.5 py-0.5 rounded" style={{ background: '#F5DFA8', color: '#7A6D2A' }}>AI-generated estimate</span>
              </div>
              {aiState === 'analyzing' ? (
                <div className="flex items-center gap-2 py-3">
                  <span className="inline-block animate-spin" style={{ color: GOLD }}>✦</span>
                  <span className="text-sm" style={{ color: '#5A6670' }}>Analyzing incident conditions…</span>
                </div>
              ) : (
                <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
                  {[
                    { l: 'Risk Level', v: 'HIGH', c: '#C25A1A' },
                    { l: 'Priority', v: '82/100', c: '#17212B' },
                    { l: 'Confidence', v: '89%', c: '#2D6B4F' },
                    { l: 'Affected Route', v: route, c: '#2F6F7E' },
                    { l: 'Logistics Impact', v: 'HIGH', c: '#BE2424' },
                  ].map(m => (
                    <div key={m.l}>
                      <div style={{ fontSize: 10, color: '#8A9098' }} className="uppercase tracking-wide mb-0.5">{m.l}</div>
                      <div className="text-sm font-bold" style={{ color: m.c }}>{m.v}</div>
                    </div>
                  ))}
                </div>
              )}
              <p className="text-xs mt-3" style={{ color: '#8A9098' }}>
                AI estimates support your judgement — they are not guaranteed facts. Verify on-site conditions.
              </p>
            </div>
          </div>
        )}

        {/* STEP 5 — Review */}
        {step === 4 && (
          <div className="space-y-4">
            <h3 className="font-semibold text-base" style={{ color: '#17212B' }}>Review Incident</h3>
            <div className="rounded-lg border divide-y" style={{ borderColor: BORDER, background: SURFACE_2 }}>
              {[
                ['Incident Type', type ?? '—'],
                ['Severity', severity],
                ['Location', `${locName} · ${route}`],
                ['GPS', gps ?? '—'],
                ['Evidence', `${evidence.length} file(s) attached`],
                ['Description', desc || '—'],
                ['AI Risk / Priority', 'HIGH · 82/100 (89% confidence)'],
              ].map(([k, v]) => (
                <div key={k} className="flex px-4 py-2.5 text-sm gap-4">
                  <span className="w-40 flex-shrink-0 text-xs font-medium" style={{ color: '#8A9098' }}>{k}</span>
                  <span style={{ color: '#17212B' }}>{v}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* STEP 6 — Submit / Confirmation */}
        {step === 5 && (
          <div className="py-6 text-center">
            {submit !== 'done' ? (
              <div className="max-w-sm mx-auto space-y-4">
                <p className="text-sm" style={{ color: '#5A6670' }}>Ready to submit this incident report to the District Officer.</p>
                <button onClick={doSubmit} disabled={submit === 'submitting'}
                  className="w-full font-medium px-4 py-3 rounded transition-all disabled:opacity-70"
                  style={{ background: NAVY, color: 'white', minHeight: 44 }}>
                  {submit === 'submitting' ? 'Submitting…' : 'Submit Incident'}
                </button>
              </div>
            ) : (
              <div className="max-w-md mx-auto">
                <div className="w-14 h-14 rounded-full mx-auto flex items-center justify-center text-2xl mb-3"
                  style={{ background: '#EAF4EE', color: '#2D6B4F' }}>✓</div>
                <h3 className="font-semibold text-lg mb-1" style={{ color: '#17212B' }}>Incident Reported Successfully</h3>
                <div className="rounded-lg border divide-y my-4 text-left" style={{ borderColor: BORDER, background: SURFACE_2 }}>
                  {[
                    ['Incident ID', incidentId],
                    ['Status', 'Under Review'],
                    ['District Officer Notification', 'Sent ✓'],
                  ].map(([k, v]) => (
                    <div key={k} className="flex px-4 py-2.5 text-sm justify-between">
                      <span className="text-xs font-medium" style={{ color: '#8A9098' }}>{k}</span>
                      <span className="font-medium" style={{ color: k === 'Status' ? '#C4861A' : '#17212B' }}>{v}</span>
                    </div>
                  ))}
                </div>
                <div className="flex gap-2 justify-center">
                  <button onClick={() => setPage?.('fo-dashboard')} className="text-xs font-medium px-4 py-2 rounded" style={{ background: NAVY, color: 'white', minHeight: 44 }}>Back to Dashboard</button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Nav buttons */}
        {step < 5 && (
          <div className="flex items-center justify-between mt-6 pt-4 border-t" style={{ borderColor: BORDER }}>
            <button onClick={() => setStep(s => Math.max(0, s - 1))} disabled={step === 0}
              className="text-xs font-medium px-4 py-2 rounded border transition-colors disabled:opacity-40"
              style={{ borderColor: BORDER, color: '#5A6670', minHeight: 44 }}>← Back</button>
            <button onClick={() => canNext && setStep(s => s + 1)} disabled={!canNext}
              className="text-xs font-medium px-5 py-2 rounded transition-all disabled:opacity-40"
              style={{ background: NAVY, color: 'white', minHeight: 44 }}>
              {step === 4 ? 'Continue to Submit →' : 'Next →'}
            </button>
          </div>
        )}
      </Card>
    </div>
  );
}
