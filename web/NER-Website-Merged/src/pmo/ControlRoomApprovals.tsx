import { useCallback, useEffect, useRef, useState } from 'react';
import { StatusBadge } from '@/components/StatusBadge';
import { decideControlRoomRequest, listControlRoomRequests, PmoAccessError } from './pmoApi';
import type { ControlRoomRequest, RequestStatus } from './types';

const TABS: { id: RequestStatus; label: string; badge: string }[] = [
  { id: 'pending', label: 'Pending', badge: 'Pending' },
  { id: 'approved', label: 'Approved', badge: 'Approved' },
  { id: 'rejected', label: 'Rejected', badge: 'Rejected' },
];

const when = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }) : '—';

interface Props {
  onAccessDenied: () => void;
  onPendingCount?: (count: number) => void;
}

export default function ControlRoomApprovals({ onAccessDenied, onPendingCount }: Props) {
  const [requests, setRequests] = useState<ControlRoomRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [tab, setTab] = useState<RequestStatus>('pending');
  const [detail, setDetail] = useState<ControlRoomRequest | null>(null);
  const [confirm, setConfirm] = useState<{ request: ControlRoomRequest; approve: boolean } | null>(null);
  const [busy, setBusy] = useState(false);

  // Parent callbacks go through a ref so a re-render upstream never triggers a refetch.
  const callbacks = useRef({ onAccessDenied, onPendingCount });
  callbacks.current = { onAccessDenied, onPendingCount };

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const rows = await listControlRoomRequests();
      setRequests(rows);
      setError(null);
      callbacks.current.onPendingCount?.(rows.filter(r => r.status === 'pending').length);
    } catch (e) {
      if (e instanceof PmoAccessError) callbacks.current.onAccessDenied();
      setError(e instanceof Error ? e.message : 'Could not load requests.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const decide = async () => {
    if (!confirm || busy) return;
    const { request, approve } = confirm;
    setBusy(true);
    setNotice(null);
    try {
      await decideControlRoomRequest(request.id, approve);
      setNotice(`${approve ? 'Approved' : 'Rejected'} the Control Room request from ${request.fullName || request.email}.`);
      setError(null);
    } catch (e) {
      if (e instanceof PmoAccessError) onAccessDenied();
      setError(e instanceof Error ? e.message : 'The decision could not be saved.');
    } finally {
      setBusy(false);
      setConfirm(null);
      await load(); // also picks up a decision made by another PMO user in the meantime
    }
  };

  const counts = (s: RequestStatus) => requests.filter(r => r.status === s).length;
  const rows = requests.filter(r => r.status === tab);

  return (
    <section className="pmo-card" aria-labelledby="pmo-approvals-h">
      <div className="flex flex-wrap items-center justify-between gap-2 px-4 pt-3">
        <div>
          <h2 id="pmo-approvals-h" className="pmo-h2">Control Room Account Approval</h2>
          <p className="pmo-muted">Control Room accounts stay inactive until a PMO officer approves the request.</p>
        </div>
        <button type="button" className="pmo-btn pmo-btn-sm" onClick={() => void load()} disabled={loading}>
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {(error || notice) && (
        <div className="px-4 pt-3">
          <p role={error ? 'alert' : 'status'} className={`pmo-alert ${error ? '' : 'pmo-ok'}`}>{error ?? notice}</p>
        </div>
      )}

      <div role="tablist" aria-label="Request status" className="flex gap-1 px-4 pt-2 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
        {TABS.map(t => (
          <button key={t.id} type="button" role="tab" id={`pmo-tab-${t.id}`} className="pmo-tab"
            aria-selected={tab === t.id} aria-controls="pmo-approvals-panel" onClick={() => setTab(t.id)}>
            {t.label} ({counts(t.id)})
          </button>
        ))}
      </div>

      <div id="pmo-approvals-panel" role="tabpanel" aria-labelledby={`pmo-tab-${tab}`} className="pmo-scroll-x p-2">
        <table className="pmo-table">
          <thead>
            <tr>
              <th>Applicant</th>
              <th>Requested state</th>
              <th>Submitted</th>
              {tab !== 'pending' && <th>{tab === 'approved' ? 'Approved' : 'Rejected'}</th>}
              {tab !== 'pending' && <th>Decided by</th>}
              <th>Status</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr><td colSpan={7} className="pmo-muted" style={{ padding: 16 }}>
                {loading ? 'Loading requests…' : `No ${tab} requests.`}
              </td></tr>
            )}
            {rows.map(r => (
              <tr key={r.id}>
                <td>
                  <div style={{ fontWeight: 600 }}>{r.fullName || '—'}</div>
                  <div className="pmo-muted">{r.email}</div>
                </td>
                <td>
                  {r.requestedState || '—'}
                  {r.requestedRegion && <div className="pmo-muted">{r.requestedRegion} region</div>}
                </td>
                <td>{when(r.createdAt)}</td>
                {tab !== 'pending' && <td>{when(r.decidedAt)}</td>}
                {tab !== 'pending' && <td>{r.decidedByName || '—'}</td>}
                <td><StatusBadge status={TABS.find(t => t.id === r.status)!.badge} /></td>
                <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                  <button type="button" className="pmo-btn pmo-btn-sm" onClick={() => setDetail(r)}>View details</button>
                  {r.status === 'pending' && (
                    <>
                      {' '}
                      <button type="button" className="pmo-btn pmo-btn-sm pmo-btn-primary" disabled={busy}
                        onClick={() => setConfirm({ request: r, approve: true })}>Approve</button>
                      {' '}
                      <button type="button" className="pmo-btn pmo-btn-sm pmo-btn-danger" disabled={busy}
                        onClick={() => setConfirm({ request: r, approve: false })}>Reject</button>
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {detail && (
        <Modal title="Control Room request" onClose={() => setDetail(null)}
          actions={<button type="button" className="pmo-btn" onClick={() => setDetail(null)}>Close</button>}>
          <dl className="pmo-dl">
            <dt>Name</dt><dd>{detail.fullName || '—'}</dd>
            <dt>Email</dt><dd>{detail.email}</dd>
            <dt>Region</dt><dd>{detail.requestedRegion || '—'}</dd>
            <dt>State</dt><dd>{detail.requestedState || '—'}</dd>
            <dt>Reason</dt><dd style={{ whiteSpace: 'pre-wrap' }}>{detail.reason || 'No reason provided.'}</dd>
            <dt>Submitted</dt><dd>{when(detail.createdAt)}</dd>
            <dt>Status</dt><dd><StatusBadge status={TABS.find(t => t.id === detail.status)!.badge} /></dd>
            {detail.status !== 'pending' && (
              <>
                <dt>Decided</dt><dd>{when(detail.decidedAt)}</dd>
                <dt>Decided by</dt><dd>{detail.decidedByName || '—'}</dd>
              </>
            )}
          </dl>
        </Modal>
      )}

      {confirm && (
        <Modal title={confirm.approve ? 'Approve Control Room account?' : 'Reject Control Room request?'}
          onClose={() => !busy && setConfirm(null)}
          actions={
            <>
              <button type="button" className="pmo-btn" disabled={busy} onClick={() => setConfirm(null)}>Cancel</button>
              <button type="button" className={`pmo-btn ${confirm.approve ? 'pmo-btn-primary' : 'pmo-btn-danger'}`} disabled={busy}
                onClick={() => void decide()}>
                {busy ? 'Saving…' : confirm.approve ? 'Approve account' : 'Reject request'}
              </button>
            </>
          }>
          <p style={{ fontSize: 13 }}>
            {confirm.approve
              ? <>This gives <strong>{confirm.request.fullName || confirm.request.email}</strong> ({confirm.request.email}) full Control Room access for <strong>{confirm.request.requestedState || 'the requested state'}</strong>.</>
              : <>This declines the request from <strong>{confirm.request.fullName || confirm.request.email}</strong> ({confirm.request.email}). They will not be able to sign in.</>}
          </p>
          <p className="pmo-muted" style={{ marginTop: 8 }}>The decision is recorded with your name and the time, and cannot be repeated.</p>
        </Modal>
      )}
    </section>
  );
}

/** Native <dialog>: focus trapping, Escape and the backdrop come from the browser. */
function Modal({ title, onClose, actions, children }: { title: string; onClose: () => void; actions: React.ReactNode; children: React.ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (dialog && !dialog.open) dialog.showModal();
  }, []);
  return (
    <dialog ref={ref} className="pmo-dialog" role="alertdialog" aria-labelledby="pmo-dialog-title" onCancel={e => { e.preventDefault(); onClose(); }}>
      <div style={{ padding: 20 }}>
        <h3 id="pmo-dialog-title" className="pmo-h2" style={{ marginBottom: 12 }}>{title}</h3>
        {children}
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 18 }}>{actions}</div>
      </div>
    </dialog>
  );
}
