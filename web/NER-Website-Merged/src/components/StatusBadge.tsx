import type { Severity } from '@/data/demo';

const severityConfig: Record<Severity, { label: string; icon: string; bg: string; text: string; border: string }> = {
  CRITICAL: { label: 'Critical', icon: '!', bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  HIGH: { label: 'High', icon: '◆', bg: '#FEF1E6', text: '#C25A1A', border: '#F5CDA8' },
  MODERATE: { label: 'Moderate', icon: '▲', bg: '#FEF8E6', text: '#C4861A', border: '#F5DFA8' },
  LOW: { label: 'Low', icon: '✓', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
};

const statusConfig: Record<string, { label: string; bg: string; text: string; border: string }> = {
  PENDING_VERIFICATION: { label: 'Pending Verification', bg: '#F0EEE6', text: '#7A6D2A', border: '#D8D0A8' },
  UNDER_REVIEW: { label: 'Under Review', bg: '#F0EEE6', text: '#7A6D2A', border: '#D8D0A8' },
  ACTIVE: { label: 'Active', bg: '#FEF1E6', text: '#C25A1A', border: '#F5CDA8' },
  ESCALATED: { label: 'Escalated', bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  RESOLVED: { label: 'Resolved', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  Available: { label: 'Available', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  'On Task': { label: 'On Task', bg: '#E6F0F4', text: '#1E5A6E', border: '#A8CDD8' },
  Emergency: { label: 'Emergency', bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  Offline: { label: 'Offline', bg: '#F0EFED', text: '#8A9098', border: 'rgba(180,162,136,0.55)' },
  'On Time': { label: 'On Time', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  Delayed: { label: 'Delayed', bg: '#FEF8E6', text: '#C4861A', border: '#F5DFA8' },
  'At Risk': { label: 'At Risk', bg: '#FEF1E6', text: '#C25A1A', border: '#F5CDA8' },
  Stopped: { label: 'Stopped', bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  Open: { label: 'Open', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  Restricted: { label: 'Restricted', bg: '#FEF8E6', text: '#C4861A', border: '#F5DFA8' },
  Blocked: { label: 'Blocked', bg: '#FEF1E6', text: '#C25A1A', border: '#F5CDA8' },
  Closed: { label: 'Closed', bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  New: { label: 'New', bg: '#E6EDF4', text: '#17324D', border: '#A8BCCF' },
  'In Progress': { label: 'In Progress', bg: '#E6F0F4', text: '#1E5A6E', border: '#A8CDD8' },
  Completed: { label: 'Completed', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  Escalated: { label: 'Escalated', bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  Pending: { label: 'Pending', bg: '#F0EEE6', text: '#7A6D2A', border: '#D8D0A8' },
  Verified: { label: 'Verified', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  Rejected: { label: 'Rejected', bg: '#FEE9E9', text: '#BE2424', border: '#F5B8B8' },
  Approved: { label: 'Approved', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  Active: { label: 'Active', bg: '#EAF4EE', text: '#2D6B4F', border: '#A8D4B8' },
  Inactive: { label: 'Inactive', bg: '#F0EFED', text: '#8A9098', border: 'rgba(180,162,136,0.55)' },
  Diverted: { label: 'Diverted', bg: '#FEF8E6', text: '#C4861A', border: '#F5DFA8' },
  'DEMO DATA': { label: 'DEMO DATA', bg: '#F0EEE6', text: '#7A6D2A', border: '#D8D0A8' },
};

export function SeverityBadge({ severity }: { severity: Severity }) {
  const c = severityConfig[severity];
  return (
    <span style={{ background: c.bg, color: c.text, borderColor: c.border }}
      className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-semibold border">
      <span>{c.icon}</span>{c.label}
    </span>
  );
}

export function StatusBadge({ status }: { status: string }) {
  const c = statusConfig[status] ?? { label: status, bg: '#F0EFED', text: '#5A6670', border: 'rgba(180,162,136,0.55)' };
  return (
    <span style={{ background: c.bg, color: c.text, borderColor: c.border }}
      className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium border">
      {c.label}
    </span>
  );
}

export function AccessibilityBadge({ score }: { score: number }) {
  let label: string;
  let color: string;
  let icon: string;
  if (score <= 25) { label = 'Good'; color = '#2D6B4F'; icon = '✓'; }
  else if (score <= 50) { label = 'Moderate'; color = '#C4861A'; icon = '▲'; }
  else if (score <= 75) { label = 'Restricted'; color = '#C25A1A'; icon = '◆'; }
  else { label = 'Critical'; color = '#BE2424'; icon = '!'; }
  return (
    <span className="inline-flex items-center gap-1 text-xs font-semibold" style={{ color }}>
      {icon} {score}/100 <span className="font-normal opacity-80">{label}</span>
    </span>
  );
}
