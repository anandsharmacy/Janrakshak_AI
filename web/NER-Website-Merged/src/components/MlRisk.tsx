import { useState } from 'react';
import {
  BAND_LABEL, TIER_LABEL, fetchRoutesSummary, fetchTopAlerts, formatMlDate, promoteMlAlert, stateLabel, topShare, useMlQuery,
  type MlBand, type MlMeta, type MlTier, type RouteRiskSummary, type TopAlertRow,
} from '@/lib/ml';

// Palette shared with StatusBadge; ML identity is navy + mono so it never blends
// into human or rule-based items (WEB-007).
const TONE = {
  red: { bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  amber: { bg: '#FEF8E6', text: '#9A6412', border: '#F5DFA8' },
  green: { bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  navy: { bg: '#E6EDF4', text: '#17324D', border: '#A8BCCF' },
  grey: { bg: '#F0EFED', text: '#5A6670', border: 'rgba(180,162,136,0.55)' },
};

function Pill({ tone, children, title }: { tone: keyof typeof TONE; children: React.ReactNode; title?: string }) {
  const c = TONE[tone];
  return (
    <span title={title} style={{ background: c.bg, color: c.text, borderColor: c.border }}
      className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-semibold border whitespace-nowrap">
      {children}
    </span>
  );
}

export function MlSourceTag({ version }: { version?: string }) {
  return (
    <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold tracking-wide whitespace-nowrap"
      style={{ background: '#17324D', color: '#FAF7F0', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' }}>
      ML · {version ?? 'model'}
    </span>
  );
}

export function MlStatePill({ meta, signedOut = false }: { meta: MlMeta | null; signedOut?: boolean }) {
  const tone = signedOut || !meta ? 'grey'
    : meta.state === 'live' ? 'green' : meta.state === 'replay' ? 'navy' : 'grey';
  const icon = meta?.state === 'replay' ? '↺' : meta?.state === 'live' ? '●' : '○';
  const title = meta?.state === 'replay'
    ? 'Historical rainfall replayed through the model — not today\'s conditions.'
    : meta?.caveat;
  return <Pill tone={tone} title={title}>{icon} {stateLabel(meta, signedOut).replace(/^ML · /, '')}</Pill>;
}

export function MlTierBadge({ tier, steep }: { tier: MlTier; steep?: boolean }) {
  if (tier === 'alert') return <Pill tone="red">▲ {TIER_LABEL.alert}</Pill>;
  if (tier === 'human_review') return <Pill tone="amber">◆ {TIER_LABEL.human_review}{steep ? ' · steep terrain' : ''}</Pill>;
  return <Pill tone="green">✓ {TIER_LABEL.none}</Pill>;
}

export function MlBandPill({ band }: { band: MlBand }) {
  const tone = band === 'high' ? 'red' : band === 'review' ? 'amber' : band === 'low' ? 'green' : 'grey';
  const icon = band === 'high' ? '▲' : band === 'review' ? '◆' : band === 'low' ? '✓' : '○';
  return <Pill tone={tone}>{icon} {BAND_LABEL[band]}</Pill>;
}

/** Five-step bar for a risk percentile; the text carries the number, the bar the gist. */
export function MlPercentileBar({ percentile }: { percentile: number | null | undefined }) {
  const steps = percentile == null ? 0 : percentile >= 99 ? 5 : percentile >= 95 ? 4 : percentile >= 80 ? 3 : percentile >= 50 ? 2 : 1;
  const color = steps >= 5 ? '#BE2424' : steps >= 4 ? '#C25A1A' : steps >= 3 ? '#C4861A' : '#2D6B4F';
  return (
    <span className="inline-flex items-center gap-2" aria-label={`${topShare(percentile)} of corridor roads`}>
      <span className="inline-grid gap-0.5" style={{ gridTemplateColumns: 'repeat(5, 10px)' }} aria-hidden="true">
        {[1, 2, 3, 4, 5].map((i) => (
          <span key={i} style={{ height: 8, borderRadius: 1, background: i <= steps ? color : 'rgba(180,162,136,0.45)' }} />
        ))}
      </span>
      <span className="text-xs font-semibold tabular-nums" style={{ color: '#17212B' }}>{topShare(percentile)}</span>
    </span>
  );
}

/** Empty / signed-out / unavailable / error states, in words people act on. */
export function MlNotice({ signedOut, error, meta }: { signedOut?: boolean; error?: string | null; meta?: MlMeta | null }) {
  let text: string;
  if (signedOut) text = 'ML risk needs a live sign-in. This is the offline demo, so no model output is shown.';
  else if (error) text = `ML risk could not be loaded: ${error}`;
  else if (meta?.state === 'unavailable') text = 'No ML run is published yet. Rule-based and reported alerts still apply.';
  else return null;
  return (
    <div className="rounded-lg border px-3 py-2 text-xs" style={{ background: 'rgba(240,239,237,0.8)', borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>
      {text}
    </div>
  );
}

export function MlCaveat({ meta }: { meta: MlMeta | null }) {
  if (!meta || meta.state === 'unavailable') return null;
  return (
    <p className="text-[11px] leading-relaxed" style={{ color: '#8A9098' }}>
      {meta.state === 'replay'
        ? `Replay of historical rainfall (${formatMlDate(meta.score_date)}) — not today's conditions. `
        : ''}
      Ranked against every corridor road for that day. Advisory only: verify before rerouting or closing a road.
    </p>
  );
}

/** Compact ML block for one route: band, coverage, counts, worst segment. */
export function MlRouteSummary({ meta, summary, coverage, lengthM, showState = true }: {
  meta: MlMeta | null; summary?: RouteRiskSummary | null; coverage?: number; lengthM?: number;
  /** Hide the replay/live pill when the surrounding panel already shows it. */
  showState?: boolean;
}) {
  if (!summary) return null;
  const pct = Math.round((coverage ?? 0) * 100);
  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <MlSourceTag version={meta?.model_version} />
        <MlBandPill band={summary.band} />
        {showState && <MlStatePill meta={meta} />}
      </div>
      {summary.band === 'no_coverage' ? (
        <p className="text-xs" style={{ color: '#5A6670' }}>
          The model covers the Siliguri corridor, Sikkim and North Bengal. This route is outside it — rely on
          incident reports and rule-based alerts here.
        </p>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
          <div><div style={{ color: '#8A9098' }}>Model covers</div><div className="font-semibold tabular-nums" style={{ color: '#17212B' }}>{pct}% of {lengthM ? `${Math.round(lengthM / 1000)} km` : 'route'}</div></div>
          <div><div style={{ color: '#8A9098' }}>High-risk segments</div><div className="font-semibold tabular-nums" style={{ color: '#BE2424' }}>{summary.n_alert}</div></div>
          <div><div style={{ color: '#8A9098' }}>Need review</div><div className="font-semibold tabular-nums" style={{ color: '#9A6412' }}>{summary.n_human_review}</div></div>
          <div><div style={{ color: '#8A9098' }}>Riskiest segment</div><MlPercentileBar percentile={summary.max_percentile} /></div>
        </div>
      )}
      {summary.worst && summary.band !== 'no_coverage' && summary.worst.along_m != null && (
        <p className="text-xs" style={{ color: '#5A6670' }}>
          Riskiest point {Math.round(summary.worst.along_m / 1000)} km from the start
          ({summary.worst.lat.toFixed(4)}, {summary.worst.lon.toFixed(4)}) · <MlTierBadge tier={summary.worst.tier} steep={summary.worst.steep} />
        </p>
      )}
    </div>
  );
}

/**
 * Today's top-N ML segments for the signed-in officer's scope (the database picks
 * the scope and N). Control room and district officers can promote a segment to
 * an operational alert; nothing is promoted automatically.
 */
export function MlTopAlertsPanel({ canPromote = false, compact = false }: { canPromote?: boolean; compact?: boolean }) {
  const q = useMlQuery(() => fetchTopAlerts('alert'));
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const data = q.data;

  const promote = async (row: TopAlertRow) => {
    setBusy(row.segment_id);
    setMessage(null);
    try {
      await promoteMlAlert(row.segment_id, data?.run_id);
      setMessage(`Alert created for ${row.segment_id}${row.near_place ? ` near ${row.near_place}` : ''}.`);
      q.reload();
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };

  const rows = data?.rows ?? [];
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <MlSourceTag version={data?.model_version} />
        <MlStatePill meta={data} signedOut={q.signedOut} />
        {data?.capacity != null && data.n_in_tier != null && (
          <span className="text-xs" style={{ color: '#5A6670' }}>
            Top {Math.min(data.capacity, rows.length)} of {data.n_in_tier.toLocaleString('en-IN')} high-risk segments
            {data.scope && data.scope !== 'region' ? ` · ${data.scope}` : ' · region'}
          </span>
        )}
      </div>
      <MlNotice signedOut={q.signedOut} error={q.error} meta={data} />
      {q.loading && !data && !q.signedOut && <div className="text-xs" style={{ color: '#8A9098' }}>Loading ML risk…</div>}
      {data && data.state !== 'unavailable' && rows.length === 0 && (
        <div className="text-xs rounded-lg border px-3 py-2" style={{ color: '#5A6670', borderColor: 'rgba(180,162,136,0.55)' }}>
          No high-risk ML segments in {data.scope === 'region' ? 'the region' : data.scope}. The model covers the Siliguri
          corridor, Sikkim and North Bengal only.
        </div>
      )}
      {rows.length > 0 && (
        <ul className="divide-y rounded-lg border" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
          {rows.slice(0, compact ? 5 : rows.length).map((row) => (
            <li key={row.segment_id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2" style={{ borderColor: 'rgba(180,162,136,0.35)' }}>
              <span className="text-xs font-semibold tabular-nums" style={{ color: '#17212B', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' }}>{row.segment_id}</span>
              <MlPercentileBar percentile={row.risk_percentile} />
              <span className="text-xs flex-1 min-w-[140px]" style={{ color: '#5A6670' }}>
                {row.near_place ? `${row.near_km} km from ${row.near_place}` : `${row.lat.toFixed(3)}, ${row.lon.toFixed(3)}`}
                {row.steep ? ' · steep' : ''}
              </span>
              {row.promoted_alert_id ? (
                <span className="text-xs font-semibold" style={{ color: '#2D6B4F' }}>✓ Alert raised</span>
              ) : canPromote ? (
                <button type="button" disabled={busy === row.segment_id} onClick={() => promote(row)}
                  className="text-xs font-semibold px-2 py-1 rounded border transition-colors"
                  style={{ borderColor: '#17324D', color: '#17324D', background: busy === row.segment_id ? 'rgba(23,50,77,0.08)' : 'transparent' }}>
                  {busy === row.segment_id ? 'Raising…' : 'Raise alert'}
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      {message && <p className="text-xs" role="status" style={{ color: '#17324D' }}>{message}</p>}
      <MlCaveat meta={data} />
    </div>
  );
}

/** Every stored route with its ML summary (officer Routes pages). */
export function MlRoutesBoard() {
  const q = useMlQuery(fetchRoutesSummary);
  const rows = q.data?.routes ?? [];
  return (
    <div className="rounded-xl border shadow-sm" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
      <div className="px-4 py-3 border-b flex flex-wrap items-center justify-between gap-2"
        style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
        <div>
          <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Road Disruption Risk by Route</h2>
          <p className="text-xs" style={{ color: '#8A9098' }}>Model output for each planned route · advisory</p>
        </div>
        <MlStatePill meta={q.data} signedOut={q.signedOut} />
      </div>
      <div className="p-4 space-y-3">
        <MlNotice signedOut={q.signedOut} error={q.error} meta={q.data} />
        {q.loading && !q.data && !q.signedOut && <div className="text-xs" style={{ color: '#8A9098' }}>Loading routes…</div>}
        <div className="grid grid-cols-1 xl:grid-cols-2 gap-3">
          {rows.map((r) => (
            <div key={r.route_id} className="rounded-lg border p-3" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(255,253,249,0.6)' }}>
              <div className="flex items-baseline gap-2 mb-2">
                <span className="font-mono text-xs font-semibold" style={{ color: '#2F6F7E' }}>{r.route_number}</span>
                <span className="text-sm font-semibold" style={{ color: '#17212B' }}>{r.name}</span>
              </div>
              <MlRouteSummary meta={q.data} summary={r.summary} coverage={r.coverage_fraction} lengthM={r.route_length_m} showState={false} />
            </div>
          ))}
        </div>
        <MlCaveat meta={q.data} />
      </div>
    </div>
  );
}
