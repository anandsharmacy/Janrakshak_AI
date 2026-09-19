import { INCIDENT_TYPES } from './incidentTypes';
import { scopeLabel, type PmoFilters } from './filters';

interface Props {
  stats: { total: number; byType: Record<string, number> };
  filters: PmoFilters;
  onToggleType: (typeId: string) => void;
}

/** Counts for the selected geography. Clicking a type card toggles that type filter. */
export default function StatsCards({ stats, filters, onToggleType }: Props) {
  return (
    <section aria-label={`Incident statistics for ${scopeLabel(filters)}`}>
      <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-7 gap-3">
        <div className="pmo-card pmo-stat pmo-stat-total" style={{ borderLeftColor: '#17324D' }}>
          <div className="text-3xl font-bold leading-none tabular-nums" style={{ color: '#17212B' }}>{stats.total}</div>
          <div className="text-xs font-medium mt-1" style={{ color: '#17212B' }}>
            {filters.includeResolved ? 'Total Incidents' : 'Active Incidents'}
          </div>
          <div className="pmo-muted truncate" title={scopeLabel(filters)}>{scopeLabel(filters)}</div>
        </div>
        {INCIDENT_TYPES.map(t => (
          <button key={t.id} type="button" className="pmo-card pmo-stat" style={{ borderLeftColor: t.color }}
            aria-pressed={filters.types.includes(t.id)} onClick={() => onToggleType(t.id)}
            title={`Filter map by ${t.label}`}>
            <div className="text-3xl font-bold leading-none tabular-nums" style={{ color: '#17212B' }}>{stats.byType[t.id] ?? 0}</div>
            <div className="text-xs font-medium mt-1" style={{ color: '#17212B' }}>{t.label}</div>
            <div className="pmo-muted">{filters.types.includes(t.id) ? 'Filter on' : 'Click to filter'}</div>
          </button>
        ))}
      </div>
    </section>
  );
}
