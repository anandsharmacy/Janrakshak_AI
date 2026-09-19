import { useEffect, useMemo, useState } from 'react';
import { regionOfState } from '@/data/indiaLocations';
import { supabase } from '@/lib/supabase';
import { useDemoMode } from '@/lib/demoMode';
import ControlRoomApprovals from './ControlRoomApprovals';
import FilterBar from './FilterBar';
import IndiaMap from './IndiaMap';
import StatsCards from './StatsCards';
import { applyFilters, computeStats, EMPTY_FILTERS, type PmoFilters } from './filters';
import { useNationalIncidents } from './useNationalIncidents';
import './pmo.css';

const regionFor = (state: string, fallback: string) => regionOfState(state) ?? fallback;

function usePmoUser() {
  const [user, setUser] = useState<{ name: string; email: string } | null>(null);
  useEffect(() => {
    if (!supabase) return;
    let cancelled = false;
    void (async () => {
      const { data } = await supabase!.auth.getUser();
      if (!data.user || cancelled) return;
      const { data: profile } = await supabase!.from('profiles').select('full_name').eq('id', data.user.id).maybeSingle();
      if (!cancelled) setUser({ name: profile?.full_name || 'PMO Officer', email: data.user.email ?? '' });
    })();
    return () => { cancelled = true; };
  }, []);
  return user;
}

export default function PmoDashboard({ onLogout }: { onLogout: () => void }) {
  const { demo, setDemo } = useDemoMode();
  const user = usePmoUser();
  const [filters, setFilters] = useState<PmoFilters>(EMPTY_FILTERS);
  const [pending, setPending] = useState(0);
  const { incidents, loading, error, updatedAt, refresh } = useNationalIncidents(onLogout);

  const visible = useMemo(() => applyFilters(incidents, filters), [incidents, filters]);
  const stats = useMemo(() => computeStats(incidents, filters), [incidents, filters]);

  const toggleType = (id: string) =>
    setFilters(f => ({ ...f, types: f.types.includes(id) ? f.types.filter(t => t !== id) : [...f.types, id] }));

  return (
    <div className="h-full overflow-y-auto">
      <header className="sticky top-0 z-[1500] flex flex-wrap items-center justify-between gap-3 px-4 py-2.5"
        style={{ background: '#17324D', borderBottom: '1px solid #0F2538' }}>
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded flex items-center justify-center text-xs font-bold" style={{ background: '#D7A73A', color: '#17212B' }}>PMO</div>
          <div>
            <h1 className="text-sm font-semibold leading-tight" style={{ color: '#FAF7F0' }}>Prime Minister&rsquo;s Office · National Situation Room</h1>
            <p className="text-xs leading-tight" style={{ color: '#9FB6C8' }}>Janrakshak AI</p>
          </div>
        </div>

        <nav className="flex items-center gap-1" aria-label="PMO sections">
          <a href="#pmo-map" className="pmo-navlink">Situation map</a>
          <a href="#pmo-approvals" className="pmo-navlink">
            Approvals{pending > 0 && <span className="pmo-navbadge" aria-label={`${pending} pending`}>{pending}</span>}
          </a>
        </nav>

        <div className="flex items-center gap-3">
          <label className="flex items-center gap-1.5 text-xs cursor-pointer" style={{ color: '#D5E1EA' }}>
            <input type="checkbox" checked={demo} onChange={e => setDemo(e.target.checked)} /> Demo data
          </label>
          <div className="text-right leading-tight hidden sm:block">
            <div className="text-xs font-semibold" style={{ color: '#FAF7F0' }}>{user?.name ?? 'Signed in'}</div>
            <div className="text-[11px]" style={{ color: '#9FB6C8' }}>{user?.email}</div>
          </div>
          <button type="button" onClick={onLogout} className="pmo-btn pmo-btn-sm">Log out</button>
        </div>
      </header>

      <main className="mx-auto w-full max-w-screen-2xl space-y-4 p-4">
        <section id="pmo-map" className="space-y-3 scroll-mt-16" aria-labelledby="pmo-map-h">
          <div className="flex flex-wrap items-end justify-between gap-2">
            <div>
              <h2 id="pmo-map-h" className="text-xl font-semibold" style={{ color: '#17212B' }}>National Situation</h2>
              <p className="pmo-muted">
                Incidents across India{demo && <> · <strong style={{ color: '#7A6D2A' }}>DEMO DATA</strong> (northeast sample; switch off for live data)</>}
              </p>
            </div>
            <div className="flex items-center gap-2 pmo-muted">
              {updatedAt && <span>Updated {updatedAt.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}</span>}
              <button type="button" className="pmo-btn pmo-btn-sm" onClick={() => void refresh()} disabled={loading}>
                {loading ? 'Refreshing…' : 'Refresh'}
              </button>
            </div>
          </div>

          {error && <p role="alert" className="pmo-alert">Incidents could not be loaded: {error}</p>}

          <StatsCards stats={stats} filters={filters} onToggleType={toggleType} />
          <FilterBar filters={filters} onChange={setFilters} />

          <div className="pmo-card overflow-hidden" style={{ height: 'clamp(420px, calc(100vh - 320px), 780px)' }}>
            <IndiaMap
              incidents={visible}
              filters={filters}
              onSelectState={state => setFilters(f => ({ ...f, state, region: regionFor(state, f.region), district: '' }))}
              onSelectDistrict={(state, district) => setFilters(f => ({ ...f, state, region: regionFor(state, f.region), district }))}
              onResetView={() => setFilters(f => ({ ...f, region: '', state: '', district: '' }))}
            />
          </div>
        </section>

        <div id="pmo-approvals" className="scroll-mt-16">
          <ControlRoomApprovals onAccessDenied={onLogout} onPendingCount={setPending} />
        </div>
      </main>
    </div>
  );
}
