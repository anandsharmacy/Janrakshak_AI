/* Shared Field Officer UI tokens & primitives — mirror the District Officer system exactly. */
export const SURFACE = 'rgba(250,247,240,0.82)';
export const SURFACE_2 = 'rgba(238,228,210,0.88)';
export const BORDER = 'rgba(180,162,136,0.55)';
export const NAVY = '#17324D';
export const TEAL = '#2F6F7E';
export const GOLD = '#D7A73A';

export function Card({ children, className = '', style }: { children: React.ReactNode; className?: string; style?: React.CSSProperties }) {
  return (
    <div className={`rounded-xl border shadow-sm ${className}`} style={{ background: SURFACE, borderColor: BORDER, ...style }}>
      {children}
    </div>
  );
}

export function CardHeader({ title, sub, action }: { title: string; sub?: string; action?: React.ReactNode }) {
  return (
    <div className="px-4 py-3 border-b flex items-center justify-between gap-3" style={{ borderColor: BORDER }}>
      <div>
        <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>{title}</h2>
        {sub && <p className="text-xs" style={{ color: '#8A9098' }}>{sub}</p>}
      </div>
      {action}
    </div>
  );
}

export function PageHeader({ title, sub, right }: { title: string; sub?: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between flex-wrap gap-3">
      <div>
        <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>{title}</h1>
        {sub && <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>{sub}</p>}
      </div>
      {right}
    </div>
  );
}

export function GhostBtn({ children, onClick }: { children: React.ReactNode; onClick?: () => void }) {
  return (
    <button onClick={onClick}
      className="text-xs font-medium px-3 py-1.5 rounded border transition-colors"
      style={{ borderColor: BORDER, color: TEAL }}>
      {children}
    </button>
  );
}

export function PrimaryBtn({ children, onClick, disabled, style }: { children: React.ReactNode; onClick?: () => void; disabled?: boolean; style?: React.CSSProperties }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="text-xs font-medium px-3 py-2 rounded transition-all disabled:opacity-70"
      style={{ background: NAVY, color: 'white', minHeight: 44, ...style }}>
      {children}
    </button>
  );
}
