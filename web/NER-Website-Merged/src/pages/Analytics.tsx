import { useEffect, useMemo, useState } from 'react';
import { getIncidents, subscribeToIncidents } from '@/lib/incidentStore';
import { getTasks, subscribeToTasks } from '@/lib/taskStore';
import {
  NORTHEAST_DISTRICTS,
  NORTHEAST_STATES,
  getDistrictsForState,
  matchLocationToDistrictAndState,
} from '@/data/northeastDistricts';

const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Today'];

function LineChart({ data, color, height = 80 }: { data: number[]; color: string; height?: number }) {
  if (!data.length) {
    return <div className="text-xs" style={{ color: '#8A9098' }}>No trend data available.</div>;
  }

  const max = Math.max(...data);
  const min = Math.min(...data);
  const range = max - min || 1;
  const w = 400; const h = height;
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * w},${h - ((v - min) / range) * (h - 8) - 4}`).join(' ');
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" style={{ height }}>
      <polyline points={pts} fill="none" stroke={color} strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
      {data.map((v, i) => (
        <circle key={i} cx={(i / (data.length - 1)) * w} cy={h - ((v - min) / range) * (h - 8) - 4} r="3" fill={color} />
      ))}
    </svg>
  );
}

function BarChart({ data, colors }: { data: { name: string; accessible: number; restricted: number }[]; colors: string[] }) {
  if (!data.length) {
    return <div className="text-xs py-4 text-center" style={{ color: '#8A9098' }}>No route accessibility data available.</div>;
  }

  return (
    <div className="space-y-2">
      {data.map(d => (
        <div key={d.name}>
          <div className="flex justify-between text-xs mb-0.5" style={{ color: '#5A6670' }}>
            <span className="font-medium" style={{ color: '#17212B' }}>{d.name}</span>
            <span>{d.accessible}% accessible</span>
          </div>
          <div className="h-3 rounded-full overflow-hidden flex" style={{ background: 'rgba(180,162,136,0.55)' }}>
            <div style={{ width: `${d.accessible}%`, background: colors[0] }} className="h-full" />
            <div style={{ width: `${d.restricted}%`, background: colors[1] }} className="h-full" />
          </div>
        </div>
      ))}
    </div>
  );
}

function ChartCard({ title, subtitle, children }: { title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border shadow-sm p-4" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
      <h3 className="font-semibold text-sm mb-0.5" style={{ color: '#17212B' }}>{title}</h3>
      {subtitle && <p className="text-xs mb-3" style={{ color: '#8A9098' }}>{subtitle}</p>}
      {children}
    </div>
  );
}

export default function Analytics() {
  const [incidents, setIncidents] = useState(() => getIncidents());
  const [tasks, setTasks] = useState(() => getTasks());

  const [selectedState, setSelectedState] = useState<string>('ALL');
  const [selectedDistrict, setSelectedDistrict] = useState<string>('ALL');

  useEffect(() => subscribeToIncidents(stored => setIncidents(stored)), []);
  useEffect(() => subscribeToTasks(stored => setTasks(stored)), []);

  const availableDistricts = useMemo(() => {
    return getDistrictsForState(selectedState);
  }, [selectedState]);

  const handleStateChange = (newState: string) => {
    setSelectedState(newState);
    if (selectedDistrict !== 'ALL' && newState !== 'ALL') {
      const validDistricts = getDistrictsForState(newState);
      if (!validDistricts.includes(selectedDistrict)) {
        setSelectedDistrict('ALL');
      }
    }
  };

  const filteredIncidents = useMemo(() => {
    return incidents.filter(incident => {
      const matched = matchLocationToDistrictAndState(`${incident.location || ''} ${incident.description || ''} ${incident.route || ''}`);

      if (selectedState !== 'ALL') {
        if (matched.state) {
          if (matched.state !== selectedState) return false;
        } else {
          const text = `${incident.location || ''} ${incident.description || ''} ${incident.route || ''}`.toLowerCase();
          if (!text.includes(selectedState.toLowerCase())) return false;
        }
      }

      if (selectedDistrict !== 'ALL') {
        if (matched.district) {
          if (matched.district !== selectedDistrict) return false;
        } else {
          const text = `${incident.location || ''} ${incident.description || ''} ${incident.route || ''}`.toLowerCase();
          if (!text.includes(selectedDistrict.toLowerCase())) return false;
        }
      }

      return true;
    });
  }, [incidents, selectedState, selectedDistrict]);

  const filteredTasks = useMemo(() => {
    return tasks.filter(task => {
      const matched = matchLocationToDistrictAndState(`${task.location || ''} ${task.description || ''}`);

      if (selectedState !== 'ALL') {
        if (matched.state) {
          if (matched.state !== selectedState) return false;
        } else {
          const text = `${task.location || ''} ${task.description || ''}`.toLowerCase();
          if (!text.includes(selectedState.toLowerCase())) return false;
        }
      }

      if (selectedDistrict !== 'ALL') {
        if (matched.district) {
          if (matched.district !== selectedDistrict) return false;
        } else {
          const text = `${task.location || ''} ${task.description || ''}`.toLowerCase();
          if (!text.includes(selectedDistrict.toLowerCase())) return false;
        }
      }

      return true;
    });
  }, [tasks, selectedState, selectedDistrict]);

  const lastNineDays = useMemo(() => {
    return Array.from({ length: 9 }, (_, index) => {
      const date = new Date();
      date.setDate(date.getDate() - (8 - index));
      return date;
    });
  }, []);

  const incidentTrend = useMemo(() => {
    return lastNineDays.map(date => {
      const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
      const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
      return filteredIncidents.filter(incident => {
        const timestamp = new Date(incident.reportedTime);
        return !Number.isNaN(timestamp.getTime()) && timestamp >= start && timestamp < end;
      }).length;
    });
  }, [filteredIncidents, lastNineDays]);

  const routeAccessibility = useMemo(() => {
    const routeMap = new Map<string, { accessible: number; restricted: number }>();

    filteredIncidents.forEach(incident => {
      const routeName = incident.route || 'Local Access Route';
      const existing = routeMap.get(routeName) ?? { accessible: 72, restricted: 28 };
      const riskPenalty = incident.severity === 'CRITICAL' ? 26 : incident.severity === 'HIGH' ? 18 : incident.severity === 'MODERATE' ? 10 : 4;
      const accessible = Math.max(18, Math.min(96, existing.accessible - riskPenalty));
      const restricted = Math.max(4, 100 - accessible);
      routeMap.set(routeName, { accessible, restricted });
    });

    if (routeMap.size === 0) {
      const scopeLabel = selectedDistrict !== 'ALL' ? selectedDistrict : selectedState !== 'ALL' ? selectedState : 'All Regions';
      return [{ name: `${scopeLabel} Route`, accessible: 100, restricted: 0 }];
    }

    return Array.from(routeMap.entries()).slice(0, 4).map(([name, value]) => ({ name, ...value }));
  }, [filteredIncidents, selectedState, selectedDistrict]);

  const responseTime = useMemo(() => {
    return lastNineDays.map(date => {
      const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
      const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
      const dayIncidents = filteredIncidents.filter(incident => {
        const timestamp = new Date(incident.reportedTime);
        return !Number.isNaN(timestamp.getTime()) && timestamp >= start && timestamp < end;
      });

      if (!dayIncidents.length) return 0;
      return Math.round(dayIncidents.reduce((sum, incident) => {
        const ts = new Date(incident.reportedTime).getTime();
        const mins = Number.isNaN(ts) ? 20 : Math.max(0, Math.round((Date.now() - ts) / 60000));
        return sum + mins;
      }, 0) / dayIncidents.length);
    });
  }, [filteredIncidents, lastNineDays]);

  const riskTrend = useMemo(() => {
    return lastNineDays.map(date => {
      const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
      const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
      const dayIncidents = filteredIncidents.filter(incident => {
        const timestamp = new Date(incident.reportedTime);
        return !Number.isNaN(timestamp.getTime()) && timestamp >= start && timestamp < end;
      });
      if (!dayIncidents.length) return 0;
      return Math.round(dayIncidents.reduce((sum, incident) => sum + Number(incident.riskScore || 0), 0) / dayIncidents.length);
    });
  }, [filteredIncidents, lastNineDays]);

  const summary = useMemo(() => {
    const totalIncidents = filteredIncidents.length;
    const avgResponseMinutes = filteredIncidents.length
      ? Math.round(filteredIncidents.reduce((sum, incident) => {
          const ts = new Date(incident.reportedTime).getTime();
          const mins = Number.isNaN(ts) ? 20 : Math.max(0, Math.round((Date.now() - ts) / 60000));
          return sum + mins;
        }, 0) / filteredIncidents.length)
      : 0;
    const accessibility = routeAccessibility.length
      ? Math.round(routeAccessibility.reduce((sum, route) => sum + route.accessible, 0) / routeAccessibility.length)
      : 100;
    const onTimeLogistics = filteredTasks.length ? Math.round((filteredTasks.filter(task => task.status === 'Completed').length / filteredTasks.length) * 100) : 100;
    const unresolved = filteredIncidents.filter(item => ['PENDING_VERIFICATION', 'ACTIVE', 'UNDER_REVIEW', 'ESCALATED'].includes(item.status)).length;
    return {
      totalIncidents,
      avgResponseMinutes,
      accessibility,
      onTimeLogistics,
      unresolved,
    };
  }, [filteredIncidents, routeAccessibility, filteredTasks]);

  const districtTable = useMemo(() => {
    let districtsToDisplay = NORTHEAST_DISTRICTS;

    if (selectedState !== 'ALL') {
      districtsToDisplay = districtsToDisplay.filter(d => d.state === selectedState);
    }

    if (selectedDistrict !== 'ALL') {
      districtsToDisplay = districtsToDisplay.filter(d => d.district === selectedDistrict);
    }

    const rows = districtsToDisplay.map(({ district, state }) => {
      const distIncidents = incidents.filter(i => {
        const m = matchLocationToDistrictAndState(`${i.location || ''} ${i.description || ''} ${i.route || ''}`);
        return m.district === district || (!m.district && (i.location || '').toLowerCase().includes(district.toLowerCase()));
      });

      const distTasks = tasks.filter(t => {
        const m = matchLocationToDistrictAndState(`${t.location || ''} ${t.description || ''}`);
        return m.district === district || (!m.district && (t.location || '').toLowerCase().includes(district.toLowerCase()));
      });

      const incCount = distIncidents.length;
      const avgResp = incCount > 0
        ? Math.round(distIncidents.reduce((s, i) => {
            const ts = new Date(i.reportedTime).getTime();
            const mins = Number.isNaN(ts) ? 20 : Math.max(0, Math.round((Date.now() - ts) / 60000));
            return s + mins;
          }, 0) / incCount)
        : 0;

      const access = incCount > 0
        ? distIncidents.reduce((acc, i) => {
            const penalty = i.severity === 'CRITICAL' ? 26 : i.severity === 'HIGH' ? 18 : i.severity === 'MODERATE' ? 10 : 4;
            return Math.max(18, acc - penalty);
          }, 100)
        : 100;

      const delays = distTasks.filter(t => ['New', 'In Progress', 'Escalated'].includes(t.status)).length;
      const unresolved = distIncidents.filter(i => ['PENDING_VERIFICATION', 'ACTIVE', 'UNDER_REVIEW', 'ESCALATED'].includes(i.status)).length;

      return {
        district,
        state,
        incidents: incCount,
        response: `${avgResp} min`,
        access: `${access}%`,
        delays,
        unresolved,
      };
    });

    return rows.sort((a, b) => {
      if (b.incidents !== a.incidents) return b.incidents - a.incidents;
      if (b.unresolved !== a.unresolved) return b.unresolved - a.unresolved;
      if (a.state !== b.state) return a.state.localeCompare(b.state);
      return a.district.localeCompare(b.district);
    });
  }, [incidents, tasks, selectedState, selectedDistrict]);

  return (
    <div className="space-y-5 max-w-screen-2xl">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>Analytics</h1>
          <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>Decision-focused district performance analytics</p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2">
            <label htmlFor="state-filter" className="text-xs font-semibold" style={{ color: '#5A6670' }}>State:</label>
            <select
              id="state-filter"
              value={selectedState}
              onChange={e => handleStateChange(e.target.value)}
              className="text-xs px-3 py-1.5 rounded-lg border font-medium outline-none cursor-pointer"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(250,247,240,0.82)', color: '#17212B' }}
            >
              <option value="ALL">All States</option>
              {NORTHEAST_STATES.map(st => (
                <option key={st} value={st}>{st}</option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2">
            <label htmlFor="district-filter" className="text-xs font-semibold" style={{ color: '#5A6670' }}>District:</label>
            <select
              id="district-filter"
              value={selectedDistrict}
              onChange={e => setSelectedDistrict(e.target.value)}
              className="text-xs px-3 py-1.5 rounded-lg border font-medium outline-none cursor-pointer"
              style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(250,247,240,0.82)', color: '#17212B' }}
            >
              <option value="ALL">All Districts</option>
              {availableDistricts.map(d => (
                <option key={d} value={d}>{d}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
        {[
          { label: 'Total Incidents (7d)', value: String(summary.totalIncidents), delta: `${incidentTrend.reduce((sum, val) => sum + val, 0)} in last 9 days`, up: true },
          { label: 'Avg Response Time', value: `${summary.avgResponseMinutes} min`, delta: summary.avgResponseMinutes <= 35 ? 'Within target' : 'Needs attention', up: summary.avgResponseMinutes <= 35 },
          { label: 'Route Accessibility', value: `${summary.accessibility}%`, delta: `${summary.accessibility >= 70 ? 'Stable' : 'Watchlist'} access`, up: summary.accessibility >= 70 },
          { label: 'Logistics On-Time', value: `${summary.onTimeLogistics}%`, delta: `${summary.onTimeLogistics >= 80 ? 'Strong' : 'Monitoring'} flow`, up: summary.onTimeLogistics >= 80 },
          { label: 'Unresolved >24h', value: String(summary.unresolved), delta: summary.unresolved === 0 ? 'All clear' : 'Needs follow-up', up: summary.unresolved === 0 },
        ].map(k => (
          <div key={k.label} className="rounded-xl border p-3 shadow-sm" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
            <div className="text-2xl font-bold" style={{ color: '#17212B' }}>{k.value}</div>
            <div className="text-xs font-medium mt-0.5" style={{ color: '#5A6670' }}>{k.label}</div>
            <div className="text-xs mt-1" style={{ color: k.up ? '#2D6B4F' : '#C25A1A' }}>{k.up ? '▲' : '▼'} {k.delta}</div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <ChartCard title="Incident Trend" subtitle="Incidents reported over the last 9 days">
          <LineChart data={incidentTrend} color="#17324D" />
          <div className="flex justify-between mt-1">
            {days.map((d, i) => (
              <span key={i} className="text-xs" style={{ color: '#8A9098' }}>{d}</span>
            ))}
          </div>
        </ChartCard>

        <ChartCard title="Route Accessibility" subtitle="Accessible vs restricted by route">
          <BarChart data={routeAccessibility} colors={['#2D6B4F', '#E07840']} />
          <div className="flex gap-4 mt-3">
            <div className="flex items-center gap-1.5 text-xs" style={{ color: '#5A6670' }}>
              <div className="w-3 h-3 rounded-sm" style={{ background: '#2D6B4F' }} />Accessible
            </div>
            <div className="flex items-center gap-1.5 text-xs" style={{ color: '#5A6670' }}>
              <div className="w-3 h-3 rounded-sm" style={{ background: '#E07840' }} />Restricted
            </div>
          </div>
        </ChartCard>

        <ChartCard title="Average Response Time (minutes)" subtitle="Target: 35 minutes">
          <div className="relative">
            <LineChart data={responseTime} color="#2F6F7E" />
            <div className="absolute inset-0 flex items-center pointer-events-none">
              <div className="w-full border-dashed border-t-2" style={{ borderColor: '#D7A73A', opacity: 0.6 }} />
            </div>
          </div>
          <div className="flex justify-between mt-1">
            {days.map((d, i) => (
              <span key={i} className="text-xs" style={{ color: '#8A9098' }}>{d}</span>
            ))}
          </div>
          <div className="flex items-center gap-1.5 text-xs mt-2" style={{ color: '#8A9098' }}>
            <div className="w-6 border-dashed border-t-2" style={{ borderColor: '#D7A73A' }} />
            35-minute target
          </div>
        </ChartCard>

        <ChartCard title="Risk Score Trend" subtitle="Composite risk score over time">
          <LineChart data={riskTrend} color="#BE2424" />
          <div className="flex justify-between mt-1">
            {days.map((d, i) => (
              <span key={i} className="text-xs" style={{ color: '#8A9098' }}>{d}</span>
            ))}
          </div>
          <div className="mt-3 rounded p-2 text-xs" style={{ background: '#FEE9E9', color: '#BE2424' }}>
            {riskTrend.length ? `▲ Risk trend ${riskTrend[riskTrend.length - 1] >= (riskTrend[0] || 0) ? 'increasing' : 'stable'} — ${riskTrend[riskTrend.length - 1]}/100 today.` : 'No risk data available for the selected filter.'}
          </div>
        </ChartCard>
      </div>

      <div className="rounded-xl border shadow-sm overflow-hidden" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
        <div className="px-4 py-3 border-b flex items-center justify-between" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
          <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>District Performance Comparison</h2>
          <span className="text-xs font-medium" style={{ color: '#5A6670' }}>
            Showing {districtTable.length} district{districtTable.length !== 1 ? 's' : ''}
          </span>
        </div>
        <div className="overflow-x-auto max-h-[480px] overflow-y-auto">
          <table className="w-full text-sm">
            <thead className="sticky top-0 z-10">
              <tr style={{ background: 'rgba(238,228,210,0.98)' }}>
                {['District', 'State', 'Incidents', 'Avg Response', 'Route Access', 'Logistics Delays', 'Unresolved'].map(h => (
                  <th key={h} className="text-left px-4 py-2.5 text-xs font-semibold uppercase tracking-wider"
                    style={{ color: '#5A6670' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {districtTable.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-8 text-center text-xs" style={{ color: '#8A9098' }}>
                    No district analytics data found for the selected filter.
                  </td>
                </tr>
              ) : (
                districtTable.map((row, i) => (
                  <tr key={`${row.state}-${row.district}`} style={{ background: i % 2 === 0 ? 'rgba(250,247,240,0.82)' : 'rgba(243,235,220,0.55)' }}>
                    <td className="px-4 py-2.5 text-xs font-semibold" style={{ color: '#17212B' }}>{row.district}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670' }}>{row.state}</td>
                    <td className="px-4 py-2.5 text-xs font-semibold" style={{ color: row.incidents > 20 ? '#BE2424' : '#17212B' }}>{row.incidents}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: parseInt(row.response) > 45 ? '#BE2424' : '#2D6B4F' }}>{row.response}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: parseInt(row.access) < 50 ? '#C25A1A' : '#2D6B4F' }}>{row.access}</td>
                    <td className="px-4 py-2.5 text-xs" style={{ color: row.delays > 40 ? '#BE2424' : '#17212B' }}>{row.delays}</td>
                    <td className="px-4 py-2.5 text-xs font-semibold text-center" style={{ color: row.unresolved > 5 ? '#BE2424' : '#17212B' }}>{row.unresolved}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
