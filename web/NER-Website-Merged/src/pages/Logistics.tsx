import { useState } from 'react';
import { StatusBadge } from '@/components/StatusBadge';
import MapViz from '@/components/MapViz';
import { useDemoData } from '@/data/useDemoData';
import { groupRidersByState, riderKpis } from '@/data/demoRiders';
import { useLiveRiders } from '@/lib/riderTracking';
import { useDemoMode } from '@/lib/demoMode';

export default function Logistics() {
  const { demo } = useDemoMode();
  const { routes, riders: demoRiders } = useDemoData();
  const riders = useLiveRiders(demoRiders);
  const [selectedRiderId, setSelectedRiderId] = useState<string | null>(null);

  const counts = riderKpis(riders);
  const kpis = [
    { label: 'Active Vehicles', value: counts.active, color: '#2F6F7E', bg: '#E6F0F4' },
    { label: 'Delayed Vehicles', value: counts.delayed, color: '#C4861A', bg: '#FEF8E6' },
    { label: 'At-Risk Shipments', value: counts.atRisk, color: '#C25A1A', bg: '#FEF1E6' },
    { label: 'Stopped / Inactive', value: counts.inactive, color: '#BE2424', bg: '#FEE9E9' },
  ];
  const byState = groupRidersByState(riders);
  const toggleRider = (id: string) => setSelectedRiderId(current => (current === id ? null : id));

  return (
    <div className="space-y-5 max-w-screen-2xl">
      <div>
        <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>Logistics</h1>
        <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>District logistics monitoring and rider tracking</p>
      </div>

      <div className="grid grid-cols-4 gap-4">
        {kpis.map(k => (
          <div key={k.label} className="rounded-xl border p-4 shadow-sm"
            style={{ background: k.bg, borderColor: 'rgba(180,162,136,0.55)' }}>
            <div className="text-3xl font-bold" style={{ color: k.color }}>{k.value}</div>
            <div className="text-xs font-medium mt-1" style={{ color: k.color }}>{k.label}</div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-5">
        <div className="xl:col-span-2 rounded-xl border shadow-sm overflow-hidden"
          style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b flex items-center justify-between gap-3" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Active Riders — District Map</h2>
            <div className="flex items-center gap-2">
              {selectedRiderId && (
                <button type="button" onClick={() => setSelectedRiderId(null)} className="text-xs font-medium" style={{ color: '#2F6F7E' }}>
                  Show all
                </button>
              )}
              {demo && <StatusBadge status="DEMO DATA" />}
            </div>
          </div>
          <MapViz incidents={[]} routes={routes} riders={riders} selectedRiderId={selectedRiderId} onSelectRider={setSelectedRiderId}
            height={340} showLegend />
        </div>

        <div className="rounded-xl border shadow-sm" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Riders by State</h2>
          </div>
          <div className="divide-y" style={{ borderColor: 'rgba(238,228,210,0.88)' }}>
            {byState.map(group => (
              <div key={group.state} className="px-4 py-3">
                <div className="flex items-center justify-between mb-1.5">
                  <span className="text-xs font-semibold" style={{ color: '#17212B' }}>{group.state}</span>
                  <span className="text-xs" style={{ color: '#8A9098' }}>
                    {group.riders.length} rider{group.riders.length === 1 ? '' : 's'} · {group.riders.filter(r => r.status === 'Active').length} active
                  </span>
                </div>
                {group.districts.map(district => (
                  <div key={district.district} className="mb-1.5 last:mb-0">
                    <div className="text-xs mb-0.5" style={{ color: '#5A6670' }}>{district.district}</div>
                    {district.riders.map(rider => {
                      const selected = rider.id === selectedRiderId;
                      return (
                        <button key={rider.id} type="button" onClick={() => toggleRider(rider.id)} aria-pressed={selected}
                          className="w-full flex items-center justify-between gap-2 rounded px-2 py-1 text-left transition-colors"
                          style={{ background: selected ? 'rgba(47,111,126,0.12)' : 'transparent' }}>
                          <span className="flex items-center gap-2 min-w-0">
                            <span className="font-mono text-xs font-semibold" style={{ color: '#2F6F7E' }}>{rider.id}</span>
                            <span className="text-xs truncate" style={{ color: '#17212B' }}>{rider.name}</span>
                          </span>
                          <StatusBadge status={rider.diverted ? 'Diverted' : rider.status} />
                        </button>
                      );
                    })}
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="rounded-xl border shadow-sm overflow-hidden" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
        <div className="px-4 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
          <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Logistics Table</h2>
          {demo && <StatusBadge status="DEMO DATA" />}
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: 'rgba(243,235,220,0.55)' }}>
                {['Rider ID', 'Rider Name', 'Phone', 'State', 'District', 'Vehicle Type', 'Rating', 'Status', 'Current Location'].map(h => (
                  <th key={h} className="text-left px-4 py-2.5 text-xs font-semibold uppercase tracking-wider whitespace-nowrap"
                    style={{ color: '#5A6670' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {riders.length === 0 && (
                <tr>
                  <td colSpan={9} className="px-4 py-8 text-center text-xs" style={{ color: '#8A9098' }}>
                    No riders to show. Turn on Demo Data in the header to preview sample riders.
                  </td>
                </tr>
              )}
              {riders.map((r, i) => {
                const selected = r.id === selectedRiderId;
                return (
                  <tr key={r.id} onClick={() => toggleRider(r.id)} className="cursor-pointer" aria-selected={selected}
                    style={{ background: selected ? 'rgba(47,111,126,0.12)' : i % 2 === 0 ? 'rgba(250,247,240,0.82)' : 'rgba(243,235,220,0.55)' }}>
                    <td className="px-4 py-2.5 font-mono text-xs font-semibold" style={{ color: '#2F6F7E' }}>{r.id}</td>
                    <td className="px-4 py-2.5 text-xs font-medium" style={{ color: '#17212B' }}>{r.name}</td>
                    <td className="px-4 py-2.5 font-mono text-xs" style={{ color: '#5A6670' }}>{r.phone}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: '#17212B' }}>{r.state}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: '#17212B' }}>{r.district}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670' }}>{r.vehicleType}</td>
                    <td className="px-4 py-2.5 text-xs font-semibold" style={{ color: '#17212B' }}>{r.rating.toFixed(1)}</td>
                    <td className="px-4 py-2.5"><StatusBadge status={r.status} /></td>
                    <td className="px-4 py-2.5 text-xs whitespace-nowrap" style={{ color: '#17212B' }}>
                      {r.currentLocation}
                      {r.diverted && <span className="ml-1.5 text-xs font-semibold" style={{ color: '#C4861A' }}>· diverted</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
