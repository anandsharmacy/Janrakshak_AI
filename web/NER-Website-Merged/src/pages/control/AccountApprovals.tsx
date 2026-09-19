import { useCallback, useEffect, useRef, useState } from 'react';
import { StatusBadge } from '@/components/StatusBadge';
import { getSessionSource } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Card, PageHeader, SURFACE, SURFACE_2, BORDER } from '../fo/ui';

/* Sign-ups stay inactive until approved: District Officers by a Control Officer, Field Officers by a District Officer of their district.
   The list and the decision both go through the existing database functions, which check the caller's role and district. */

type Target = 'district_officer' | 'field_officer';
const LABEL: Record<Target, string> = { district_officer: 'District Officer', field_officer: 'Field Officer' };

interface PendingRow {
  user_id: string; full_name: string | null; email: string | null;
  requested_role: string; district_name: string | null; requested_at: string;
}

const when = (iso: string) => new Date(iso).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });

export default function AccountApprovals({ target = 'district_officer' }: { target?: Target }) {
  const label = LABEL[target];
  const live = !!supabase && getSessionSource() === 'supabase';
  const [rows, setRows] = useState<PendingRow[]>([]);
  const [loading, setLoading] = useState(live);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<{ row: PendingRow; approve: boolean } | null>(null);
  const [busy, setBusy] = useState(false);
  const inFlight = useRef(false);

  const load = useCallback(async () => {
    if (!supabase) return;
    setLoading(true);
    const { data, error: rpcError } = await supabase.rpc('get_pending_approvals');
    if (rpcError) setError('Could not load account requests. Please try again.');
    else {
      setRows(((data ?? []) as PendingRow[]).filter(r => r.requested_role === target));
      setError(null);
    }
    setLoading(false);
  }, [target]);

  useEffect(() => { if (live) void load(); }, [live, load]);

  const decide = async () => {
    if (!confirm || !supabase || inFlight.current) return;
    const { row, approve } = confirm;
    const name = row.full_name || row.email || 'the applicant';
    inFlight.current = true;
    setBusy(true);
    setNotice(null);
    const { error: rpcError } = await supabase.rpc('decide_role_request', { p_user_id: row.user_id, p_approve: approve });
    if (rpcError) {
      setError(rpcError.code === 'P0002' ? 'This request has already been decided. The list has been refreshed.'
        : rpcError.code === '42501' ? 'You are not permitted to decide this request.'
        : 'The decision could not be saved. Please try again.');
    } else {
      setError(null);
      setNotice(`${approve ? 'Approved' : 'Rejected'} the ${label} account for ${name}.`);
    }
    inFlight.current = false;
    setBusy(false);
    setConfirm(null);
    await load();
  };

  return (
    <div className="space-y-6 max-w-screen-2xl">
      <PageHeader title="Account Approvals" sub={`${label} accounts stay inactive until you approve them`}
        right={live && (
          <button onClick={() => void load()} disabled={loading} className="text-xs font-medium px-3 py-2 rounded border disabled:opacity-60"
            style={{ borderColor: BORDER, color: '#2F6F7E' }}>{loading ? 'Refreshing…' : 'Refresh'}</button>
        )} />

      {error && <div role="alert" className="text-xs rounded p-2" style={{ background: '#FEE9E9', color: '#BE2424' }}>{error}</div>}
      {notice && <div role="status" className="text-xs rounded p-2" style={{ background: '#EAF4EE', color: '#2D6B4F' }}>{notice}</div>}

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: SURFACE_2 }}>
                {['Applicant', 'Requested Role', 'District', 'Submitted', 'Status', 'Actions'].map(h => (
                  <th key={h} className="text-left px-4 py-2.5 text-xs font-semibold uppercase tracking-wider whitespace-nowrap" style={{ color: '#5A6670' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={r.user_id} style={{ background: i % 2 === 0 ? SURFACE : 'rgba(243,235,220,0.55)' }}>
                  <td className="px-4 py-2.5">
                    <div className="text-xs font-medium" style={{ color: '#17212B' }}>{r.full_name || '—'}</div>
                    <div className="text-xs mt-0.5" style={{ color: '#8A9098' }}>{r.email}</div>
                  </td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670' }}>{label}</td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#5A6670' }}>{r.district_name || '—'}</td>
                  <td className="px-4 py-2.5 text-xs" style={{ color: '#8A9098' }}>{when(r.requested_at)}</td>
                  <td className="px-4 py-2.5"><StatusBadge status="Pending" /></td>
                  <td className="px-4 py-2.5 whitespace-nowrap">
                    <button onClick={() => setConfirm({ row: r, approve: true })} disabled={busy}
                      className="text-xs font-medium px-2.5 py-1 rounded border mr-1.5 disabled:opacity-60"
                      style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>Approve</button>
                    <button onClick={() => setConfirm({ row: r, approve: false })} disabled={busy}
                      className="text-xs font-medium px-2.5 py-1 rounded border disabled:opacity-60"
                      style={{ borderColor: '#F5B8B8', color: '#BE2424' }}>Reject</button>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr><td colSpan={6} className="px-4 py-10 text-center text-sm" style={{ color: '#8A9098' }}>
                  {!live ? `Sign in with a live account to review ${label} requests.` : loading ? 'Loading requests…' : `No pending ${label} requests.`}
                </td></tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>

      {confirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/20 backdrop-blur-[2px] p-4" onClick={() => !busy && setConfirm(null)}>
          <div role="alertdialog" aria-labelledby="approval-dialog-title" className="w-full max-w-md rounded-2xl border p-5 shadow-2xl"
            style={{ background: '#FFFDF9', borderColor: 'rgba(180,162,136,0.5)' }} onClick={event => event.stopPropagation()}>
            <h2 id="approval-dialog-title" className="font-semibold text-lg mb-2" style={{ color: '#17212B' }}>
              {confirm.approve ? `Approve ${label} account?` : `Reject ${label} request?`}
            </h2>
            <p className="text-sm" style={{ color: '#5A6670' }}>
              {confirm.approve
                ? <>This gives <strong>{confirm.row.full_name || confirm.row.email}</strong> access as {label}{confirm.row.district_name ? <> for <strong>{confirm.row.district_name}</strong></> : null}.</>
                : <>This declines the request from <strong>{confirm.row.full_name || confirm.row.email}</strong>. They will not be able to sign in as a {label}.</>}
            </p>
            <p className="text-xs mt-2" style={{ color: '#8A9098' }}>The decision is recorded with your name and the time.</p>
            <div className="flex justify-end gap-2 mt-4">
              <button onClick={() => setConfirm(null)} disabled={busy} className="text-xs font-medium px-3 py-2 rounded border"
                style={{ borderColor: BORDER, color: '#5A6670' }}>Cancel</button>
              <button onClick={() => void decide()} disabled={busy} className="text-xs font-medium px-3 py-2 rounded border disabled:opacity-60"
                style={confirm.approve ? { background: '#17324D', color: 'white', borderColor: '#17324D' } : { background: '#BE2424', color: 'white', borderColor: '#BE2424' }}>
                {busy ? 'Saving…' : confirm.approve ? 'Approve account' : 'Reject request'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
