/* ────────────────────────────────────────────────────────────────
   Live rider movement (demo). Advances every Active rider along
   its district route; Inactive riders never move. A rider whose
   route has a blocked section leaves the original road at the
   block and follows the detour instead.
──────────────────────────────────────────────────────────────── */

import { useEffect, useMemo, useRef, useState } from 'react';
import type { LatLng } from '@/data/geo';
import { DEMO_RIDERS, DEMO_RIDER_ROUTES, type DemoRider, type RiderRoute, type RiderWaypoint } from '@/data/demoRiders';

export interface LiveRider extends DemoRider {
  position: LatLng;
  currentLocation: string;
  /** True while the rider is being simulated along its route. */
  moving: boolean;
  /** True once the rider has left the blocked road for the detour. */
  diverted: boolean;
}

/** Degrees per tick (~40 m). */
const STEP = 0.00038;
const TICK_MS = 1000;

interface Segment {
  from: LatLng;
  to: LatLng;
  length: number;
  label: string;
  onDetour: boolean;
}

interface Track {
  segments: Segment[];
  length: number;
}

function dist(a: LatLng, b: LatLng) {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

/** The road the rider actually drives: the original path with the blocked stretch replaced by the detour. */
export function drivenWaypoints(route: RiderRoute): (RiderWaypoint & { onDetour: boolean })[] {
  const { path, blocked } = route;
  if (!blocked) return path.map(p => ({ ...p, onDetour: false }));
  return [
    ...path.slice(0, blocked.from + 1).map(p => ({ ...p, onDetour: false })),
    ...blocked.detour.map(p => ({ ...p, onDetour: true })),
    ...path.slice(blocked.to).map(p => ({ ...p, onDetour: false })),
  ];
}

function buildTrack(route: RiderRoute): Track {
  const points = drivenWaypoints(route);
  const segments: Segment[] = [];
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i];
    const b = points[i + 1];
    segments.push({ from: a.at, to: b.at, length: dist(a.at, b.at), label: b.label, onDetour: a.onDetour || b.onDetour });
  }
  return { segments, length: segments.reduce((sum, s) => sum + s.length, 0) };
}

function sample(track: Track, distance: number, fallback: RiderWaypoint) {
  if (!track.segments.length) return { position: fallback.at, label: fallback.label, onDetour: false };
  let remaining = Math.max(0, Math.min(distance, track.length));
  for (const seg of track.segments) {
    if (remaining <= seg.length || seg === track.segments[track.segments.length - 1]) {
      const t = seg.length ? Math.min(1, remaining / seg.length) : 1;
      const position: LatLng = [seg.from[0] + (seg.to[0] - seg.from[0]) * t, seg.from[1] + (seg.to[1] - seg.from[1]) * t];
      return { position, label: seg.label, onDetour: seg.onDetour };
    }
    remaining -= seg.length;
  }
  const last = track.segments[track.segments.length - 1];
  return { position: last.to, label: last.label, onDetour: last.onDetour };
}

interface Progress {
  distance: number;
  direction: 1 | -1;
}

/**
 * Simulated live positions for the given riders (defaults to the demo dataset).
 * Active riders shuttle along their route; Inactive riders stay at their first waypoint.
 */
export function useLiveRiders(riders: DemoRider[] = DEMO_RIDERS): LiveRider[] {
  const tracks = useMemo(() => new Map(riders.map(r => [r.id, DEMO_RIDER_ROUTES[r.id] ? buildTrack(DEMO_RIDER_ROUTES[r.id]) : null])), [riders]);
  const progressRef = useRef(new Map<string, Progress>());
  const [tick, setTick] = useState(0);

  useEffect(() => {
    const movers = riders.filter(r => r.status === 'Active' && (tracks.get(r.id)?.length ?? 0) > 0);
    if (!movers.length) return;
    const timer = window.setInterval(() => {
      movers.forEach(rider => {
        const track = tracks.get(rider.id)!;
        const current = progressRef.current.get(rider.id) ?? { distance: 0, direction: 1 };
        let distance = current.distance + STEP * current.direction;
        let direction = current.direction;
        if (distance >= track.length) { distance = track.length; direction = -1; }
        if (distance <= 0) { distance = 0; direction = 1; }
        progressRef.current.set(rider.id, { distance, direction });
      });
      setTick(t => t + 1);
    }, TICK_MS);
    return () => window.clearInterval(timer);
  }, [riders, tracks]);

  return useMemo(() => riders.map(rider => {
    const route = DEMO_RIDER_ROUTES[rider.id];
    const track = tracks.get(rider.id);
    const origin: RiderWaypoint = route?.path[0] ?? { at: [26.2, 92.9], label: rider.district };
    if (rider.status !== 'Active' || !track || !track.length) {
      return { ...rider, position: origin.at, currentLocation: origin.label, moving: false, diverted: false };
    }
    const progress = progressRef.current.get(rider.id) ?? { distance: 0, direction: 1 };
    const { position, label, onDetour } = sample(track, progress.distance, origin);
    return { ...rider, position, currentLocation: label, moving: true, diverted: onDetour };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [riders, tracks, tick]);
}
