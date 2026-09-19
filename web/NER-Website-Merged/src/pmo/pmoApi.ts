import { supabase } from '@/lib/supabase';
import { makeIncident } from './incidents';
import type { ControlRoomRequest, NationalIncident, RequestStatus } from './types';

/** The database refused the call because the signed-in user is not an active PMO user. */
export class PmoAccessError extends Error {
  constructor() {
    super('Your account is not authorised for PMO access.');
    this.name = 'PmoAccessError';
  }
}

function client() {
  if (!supabase) throw new Error('The secure backend is not configured for this build.');
  return supabase;
}

function fail(error: { code?: string; message: string }): never {
  if (error.code === '42501') throw new PmoAccessError();
  if (error.code === '55000') throw new Error('This request has already been decided. The list has been refreshed.');
  if (error.code === 'P0002') throw new Error('This request no longer exists.');
  throw new Error(error.message);
}

interface IncidentRow {
  id: string; reference: string | null; source: string; category: string;
  title: string | null; description: string | null; severity: string | null; status: string;
  state: string | null; district: string | null; latitude: number | null; longitude: number | null;
  reported_at: string | null; reporter: string | null;
}

/** Field reports and disaster events, read through the PMO-only RPC. */
export async function fetchNationalIncidents(): Promise<NationalIncident[]> {
  const { data, error } = await client().rpc('pmo_national_incidents');
  if (error) fail(error);
  return ((data ?? []) as IncidentRow[]).map(r =>
    makeIncident({
      id: r.id, reference: r.reference, source: r.source, rawType: r.category,
      title: r.title ?? '', description: r.description ?? '', severity: r.severity, status: r.status,
      state: r.state, district: r.district, lat: r.latitude, lng: r.longitude,
      reportedAt: r.reported_at, reporter: r.reporter,
    }),
  );
}

interface RequestRow {
  id: string; user_id: string; full_name: string; email: string; requested_region: string | null;
  requested_state: string; reason: string; status: RequestStatus; created_at: string;
  decided_at: string | null; decided_by_name: string | null;
}

export async function listControlRoomRequests(): Promise<ControlRoomRequest[]> {
  const { data, error } = await client().rpc('pmo_list_control_room_requests');
  if (error) fail(error);
  return ((data ?? []) as RequestRow[]).map(r => ({
    id: r.id, userId: r.user_id, fullName: r.full_name, email: r.email,
    requestedRegion: r.requested_region, requestedState: r.requested_state, reason: r.reason,
    status: r.status, createdAt: r.created_at, decidedAt: r.decided_at, decidedByName: r.decided_by_name,
  }));
}

export async function decideControlRoomRequest(requestId: string, approve: boolean): Promise<void> {
  const { error } = await client().rpc('pmo_decide_control_room_request', {
    p_request_id: requestId,
    p_approve: approve,
  });
  if (error) fail(error);
}
