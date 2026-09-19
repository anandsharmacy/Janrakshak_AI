import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';

/**
 * ML road-disruption risk (sih-ml model, published daily into Supabase).
 *
 * Every call goes through a SECURITY DEFINER RPC in
 * supabase/migrations/20260912000003_ml_integration.sql; the database decides what
 * the signed-in role may see. The Flutter app calls the same RPCs, so both show
 * the same versioned prediction for a route.
 *
 * Display rules (ML-006/008/011): rank by risk_percentile, never show
 * p_calibrated as a probability, always label replay/stale/unavailable, and
 * never mix ML output into human or rule-based lists unlabelled.
 */

export type MlState = 'live' | 'replay' | 'stale' | 'unavailable' | 'signed_out';
export type MlTier = 'none' | 'alert' | 'human_review';
export type MlBand = 'high' | 'review' | 'low' | 'no_coverage';

export interface MlMeta {
  state: MlState;
  run_id?: number;
  score_date?: string;
  mode?: 'live' | 'replay';
  model_version?: string;
  bundle_hash?: string;
  published_at?: string;
  expires_at?: string | null;
  caveat?: string;
}

export interface MlStatus extends MlMeta {
  tier_counts?: Partial<Record<MlTier, number>>;
  coverage_bbox?: [number, number, number, number] | null;
  alert_capacity?: number;
}

export interface MlSegment {
  segment_id: string;
  along_m?: number;
  lat: number;
  lon: number;
  risk_percentile: number;
  tier: MlTier;
  steep: boolean;
}

export interface RouteRiskSummary {
  n_matched: number;
  n_alert: number;
  n_human_review: number;
  max_percentile: number | null;
  band: MlBand;
  worst: MlSegment | null;
}

export interface RouteRisk extends MlMeta {
  route_id?: string | null;
  route_length_m?: number;
  buffer_m?: number;
  coverage_fraction?: number;
  summary?: RouteRiskSummary;
  segments?: MlSegment[];
}

export interface RouteSummaryRow {
  route_id: string;
  route_number: string;
  name: string;
  route_length_m: number;
  coverage_fraction: number;
  summary: RouteRiskSummary;
}

export interface RoutesSummary extends MlMeta {
  routes: RouteSummaryRow[];
}

export interface TopAlertRow extends MlSegment {
  tier_rank: number;
  near_place: string | null;
  near_district: string | null;
  near_state: string | null;
  near_km: number | null;
  promoted_alert_id: string | null;
}

export interface TopAlerts extends MlMeta {
  tier?: MlTier;
  scope?: string;
  capacity?: number;
  n_in_tier?: number;
  rows: TopAlertRow[];
}

export class MlSignedOutError extends Error {
  constructor() {
    super('ML risk needs a live sign-in.');
  }
}

async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  if (!supabase) throw new MlSignedOutError();
  const { data: session } = await supabase.auth.getSession();
  if (!session.session) throw new MlSignedOutError();
  const { data, error } = await supabase.rpc(fn, args ?? {});
  if (error) throw new Error(error.message);
  return data as T;
}

export const fetchMlStatus = () => rpc<MlStatus>('ml_status');

export const fetchRouteRisk = (routeId: string) =>
  rpc<RouteRisk>('get_route_ml_risk', { p_route_id: routeId });

export const fetchRoutesSummary = () => rpc<RoutesSummary>('get_routes_ml_summary');

export const fetchTopAlerts = (tier: 'alert' | 'human_review' = 'alert') =>
  rpc<TopAlerts>('get_ml_top_alerts', { p_tier: tier });

export const fetchMlSegmentsInBbox = (
  bbox: { west: number; south: number; east: number; north: number },
  minTier: 'alert' | 'human_review' = 'human_review',
) =>
  rpc<MlSegment[]>('get_ml_segments_in_bbox', {
    p_west: bbox.west, p_south: bbox.south, p_east: bbox.east, p_north: bbox.north,
    p_min_tier: minTier, p_limit: 1000,
  });

export const promoteMlAlert = (segmentId: string, runId?: number, note?: string) =>
  rpc<string>('promote_ml_alert', { p_segment_id: segmentId, p_run_id: runId ?? null, p_note: note ?? null });

// ── Realtime: one shared subscription; every ML view refetches on a new day ──

const runListeners = new Set<() => void>();
let runChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null;

function onMlRunChange(listener: () => void): () => void {
  runListeners.add(listener);
  if (supabase && !runChannel) {
    runChannel = supabase
      .channel('ml-batch-runs')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ml_batch_runs' }, () => {
        runListeners.forEach((l) => l());
      })
      .subscribe();
  }
  return () => {
    runListeners.delete(listener);
    if (runListeners.size === 0 && runChannel && supabase) {
      void supabase.removeChannel(runChannel);
      runChannel = null;
    }
  };
}

export interface MlQuery<T> {
  data: T | null;
  loading: boolean;
  signedOut: boolean;
  error: string | null;
  reload: () => void;
}

/** Runs an ML fetch, and re-runs it when a new day is published. */
export function useMlQuery<T>(fetcher: () => Promise<T>, deps: unknown[] = []): MlQuery<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [signedOut, setSignedOut] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const seq = useRef(0);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const run = useCallback(fetcher, deps);

  const load = useCallback(() => {
    const id = ++seq.current;
    setLoading(true);
    run()
      .then((d) => {
        if (id !== seq.current) return;
        setData(d);
        setSignedOut(false);
        setError(null);
      })
      .catch((e: unknown) => {
        if (id !== seq.current) return;
        if (e instanceof MlSignedOutError) setSignedOut(true);
        else setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => {
        if (id === seq.current) setLoading(false);
      });
  }, [run]);

  useEffect(() => {
    load();
    return onMlRunChange(load);
  }, [load]);

  return { data, loading, signedOut, error, reload: load };
}

// ── Formatting shared by every ML component ──────────────────────────────────

export function formatMlDate(isoDate?: string): string {
  if (!isoDate) return '';
  const d = new Date(`${isoDate}T00:00:00`);
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

/** "Top 0.01%" — the share of corridor roads riskier than or equal to this one. */
export function topShare(percentile: number | null | undefined): string {
  if (percentile == null) return '—';
  const share = Math.max(100 - percentile, 0.01);
  const text = share < 1 ? share.toFixed(2) : share < 10 ? share.toFixed(1) : share.toFixed(0);
  return `Top ${text}%`;
}

export function stateLabel(meta: Pick<MlMeta, 'state' | 'score_date'> | null, signedOut = false): string {
  if (signedOut) return 'ML · sign in for live risk';
  if (!meta) return 'ML · loading';
  switch (meta.state) {
    case 'live': return `ML · live · ${formatMlDate(meta.score_date)}`;
    case 'replay': return `ML · replay · rainfall of ${formatMlDate(meta.score_date)}`;
    case 'stale': return `ML · stale · last ${formatMlDate(meta.score_date)}`;
    default: return 'ML · unavailable';
  }
}

export const TIER_LABEL: Record<MlTier, string> = {
  alert: 'High disruption risk',
  human_review: 'Needs officer review',
  none: 'Low',
};

export const BAND_LABEL: Record<MlBand, string> = {
  high: 'High risk on route',
  review: 'Segments need review',
  low: 'Low risk',
  no_coverage: 'Outside model coverage',
};
