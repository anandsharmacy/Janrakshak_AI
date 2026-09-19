import { useId, useMemo, useState } from 'react';
import { REGIONS, STATES, districtsOf, regionOfState, searchLocations, statesOf, type LocationMatch } from '@/data/indiaLocations';
import { INCIDENT_TYPES, typeDef } from './incidentTypes';
import { EMPTY_FILTERS, type PmoFilters } from './filters';

interface Props {
  filters: PmoFilters;
  onChange: (next: PmoFilters) => void;
}

export default function FilterBar({ filters, onChange }: Props) {
  const states = filters.region ? statesOf(filters.region) : STATES;
  const stateRegion = filters.state ? regionOfState(filters.state) ?? filters.region : filters.region;
  const districts = filters.state ? districtsOf(stateRegion, filters.state) : [];

  const pick = (m: LocationMatch) =>
    onChange({
      ...filters,
      region: m.region,
      state: m.kind === 'region' ? '' : m.kind === 'state' ? m.name : m.state ?? '',
      district: m.kind === 'district' ? m.name : '',
    });

  const chips: { key: string; label: string; clear: () => void }[] = [];
  if (filters.region) chips.push({ key: 'region', label: `Region: ${filters.region}`, clear: () => onChange({ ...filters, region: '', state: '', district: '' }) });
  if (filters.state) chips.push({ key: 'state', label: `State: ${filters.state}`, clear: () => onChange({ ...filters, state: '', district: '' }) });
  if (filters.district) chips.push({ key: 'district', label: `District: ${filters.district}`, clear: () => onChange({ ...filters, district: '' }) });
  for (const id of filters.types) {
    chips.push({ key: `type-${id}`, label: typeDef(id).label, clear: () => onChange({ ...filters, types: filters.types.filter(t => t !== id) }) });
  }
  if (filters.includeResolved) chips.push({ key: 'resolved', label: 'Including resolved', clear: () => onChange({ ...filters, includeResolved: false }) });

  return (
    <div className="pmo-card p-3 space-y-3" role="search" aria-label="Filter incidents">
      <div className="flex flex-wrap items-end gap-3">
        <div className="pmo-field grow basis-[240px]">
          <LocationSearch onPick={pick} />
        </div>

        <div className="pmo-field grow basis-[150px]">
          <label htmlFor="pmo-region">Region</label>
          <select id="pmo-region" className="pmo-input" value={filters.region}
            onChange={e => onChange({ ...filters, region: e.target.value, state: '', district: '' })}>
            <option value="">All regions</option>
            {REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
          </select>
        </div>

        <div className="pmo-field grow basis-[170px]">
          <label htmlFor="pmo-state">State</label>
          <select id="pmo-state" className="pmo-input" value={filters.state}
            onChange={e => {
              const state = e.target.value;
              onChange({ ...filters, state, region: state ? regionOfState(state) ?? filters.region : filters.region, district: '' });
            }}>
            <option value="">{filters.region ? `All states in ${filters.region}` : 'All states'}</option>
            {states.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>

        <div className="pmo-field grow basis-[170px]">
          <label htmlFor="pmo-district">District</label>
          <select id="pmo-district" className="pmo-input" value={filters.district} disabled={!filters.state}
            onChange={e => onChange({ ...filters, district: e.target.value })}>
            <option value="">{filters.state ? 'All districts' : 'Select a state first'}</option>
            {districts.map(d => <option key={d} value={d}>{d}</option>)}
          </select>
        </div>

        <TypeFilter selected={filters.types} onApply={types => onChange({ ...filters, types })} />

        <label className="flex items-center gap-2 h-[34px] text-[13px] cursor-pointer" style={{ color: '#17212B' }}>
          <input type="checkbox" checked={filters.includeResolved}
            onChange={e => onChange({ ...filters, includeResolved: e.target.checked })} />
          Include resolved
        </label>

        <button type="button" className="pmo-btn" onClick={() => onChange(EMPTY_FILTERS)}>Reset all</button>
      </div>

      <div className="flex flex-wrap items-center gap-2 min-h-[24px]" aria-live="polite">
        <span className="pmo-label">Current filters</span>
        {chips.length === 0 && <span className="pmo-muted">None — showing all active incidents across India</span>}
        {chips.map(c => (
          <span key={c.key} className="pmo-tag">
            {c.label}
            <button type="button" onClick={c.clear} aria-label={`Remove filter ${c.label}`}>×</button>
          </span>
        ))}
      </div>
    </div>
  );
}

function LocationSearch({ onPick }: { onPick: (m: LocationMatch) => void }) {
  const id = useId();
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const results = useMemo(() => searchLocations(query), [query]);

  const choose = (m: LocationMatch) => {
    onPick(m);
    setQuery('');
    setOpen(false);
  };

  return (
    <div className="relative" onBlur={e => { if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false); }}>
      <label htmlFor={`${id}-input`} className="pmo-label block mb-1">Search region, state or district</label>
      <input
        id={`${id}-input`}
        className="pmo-input"
        type="search"
        autoComplete="off"
        placeholder="e.g. Hyderabad, Kerala, South"
        role="combobox"
        aria-expanded={open && results.length > 0}
        aria-controls={`${id}-list`}
        aria-autocomplete="list"
        aria-activedescendant={open && results.length ? `${id}-opt-${active}` : undefined}
        value={query}
        onChange={e => { setQuery(e.target.value); setActive(0); setOpen(true); }}
        onFocus={() => setOpen(true)}
        onKeyDown={e => {
          if (e.key === 'ArrowDown') { e.preventDefault(); setOpen(true); setActive(i => Math.min(i + 1, results.length - 1)); }
          else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(i => Math.max(i - 1, 0)); }
          else if (e.key === 'Enter' && open && results[active]) { e.preventDefault(); choose(results[active]); }
          else if (e.key === 'Escape') setOpen(false);
        }}
      />
      {open && query.trim() && (
        <ul id={`${id}-list`} className="pmo-suggest" role="listbox" aria-label="Matching locations">
          {results.length === 0 && <li aria-disabled="true" style={{ cursor: 'default' }}>No matching location</li>}
          {results.map((m, i) => (
            <li key={`${m.kind}-${m.name}-${m.state ?? ''}`} id={`${id}-opt-${i}`} role="option" aria-selected={i === active}
              onMouseDown={e => { e.preventDefault(); choose(m); }} onMouseEnter={() => setActive(i)}>
              <span>{m.name}</span>
              <small>{m.kind === 'region' ? 'Region' : m.kind === 'state' ? `State · ${m.region}` : `District · ${m.state}`}</small>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** Multi-select with an explicit Apply, so a several-type choice changes the map once. */
function TypeFilter({ selected, onApply }: { selected: string[]; onApply: (types: string[]) => void }) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<string[]>(selected);

  const toggleOpen = () => {
    if (!open) setDraft(selected);
    setOpen(!open);
  };
  const toggle = (typeId: string) => setDraft(d => (d.includes(typeId) ? d.filter(t => t !== typeId) : [...d, typeId]));

  return (
    <div className="pmo-field grow basis-[150px] relative"
      onBlur={e => { if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false); }}
      onKeyDown={e => { if (e.key === 'Escape') setOpen(false); }}>
      <label htmlFor={`${id}-btn`}>Incident type</label>
      <button id={`${id}-btn`} type="button" className="pmo-input text-left" aria-haspopup="true" aria-expanded={open} onClick={toggleOpen}>
        {selected.length === 0 ? 'All types' : selected.length === 1 ? typeDef(selected[0]).label : `${selected.length} types selected`} ▾
      </button>
      {open && (
        <div className="pmo-pop" role="group" aria-label="Incident types">
          {INCIDENT_TYPES.map(t => (
            <label key={t.id}>
              <input type="checkbox" checked={draft.includes(t.id)} onChange={() => toggle(t.id)} />
              <span className="pmo-dot" style={{ background: t.color }} aria-hidden="true" />
              {t.label}
            </label>
          ))}
          <div className="flex justify-between gap-2 pt-2">
            <button type="button" className="pmo-btn pmo-btn-sm" onClick={() => { setDraft([]); onApply([]); setOpen(false); }}>Clear</button>
            <button type="button" className="pmo-btn pmo-btn-sm pmo-btn-primary" onClick={() => { onApply(draft); setOpen(false); }}>Apply</button>
          </div>
        </div>
      )}
    </div>
  );
}
