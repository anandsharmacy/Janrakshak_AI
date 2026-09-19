import { useState, useEffect, useMemo } from 'react';
import type { Role } from '@/roles';
import ProfilePanel, { type ProfileMeta } from '@/components/ProfilePanel';
import { fetchMlStatus, useMlQuery } from '@/lib/ml';
import type { SessionSource } from '@/lib/auth';
import { profileService } from '@/lib/profileService';
import { getIncidents, subscribeToIncidents } from '@/lib/incidentStore';
import { getTasks, subscribeToTasks } from '@/lib/taskStore';
import { useLanguage } from '@/lib/i18n';
import { useDemoMode } from '@/lib/demoMode';

const NAV = [
  { key: 'dashboard', label: 'Dashboard',     icon: '⊞' },
  { key: 'map',       label: 'District Map',  icon: '◉' },
  { key: 'incidents', label: 'Incidents',     icon: '◆', badge: 5 },
  { key: 'routes',    label: 'Routes',        icon: '→' },
  { key: 'logistics', label: 'Logistics',     icon: '⊟' },
  { key: 'tasks',     label: 'Tasks',         icon: '☑' },
  { key: 'ai',        label: 'AI Insights',   icon: '✦', gold: true },
  { key: 'alerts',    label: 'Alerts',        icon: '◬', badge: 3 },
  { key: 'reports',   label: 'Reports',       icon: '⊡' },
  { key: 'analytics', label: 'Analytics',     icon: '▨' },
];

const FO_NAV = [
  { key: 'fo-dashboard', label: 'Dashboard',       icon: '⊞' },
  { key: 'fo-tasks',     label: 'My Tasks',        icon: '☑' },
  { key: 'fo-report',    label: 'Report Incident', icon: '⊕', gold: true },
  { key: 'fo-alerts',    label: 'Alerts',          icon: '◬', badge: 2 },
  { key: 'fo-reports',   label: 'Reports',         icon: '⊡' },
];

const CR_NAV = [
  { key: 'cr-command', label: 'Command Center', icon: '◈', gold: true },
  { key: 'map',        label: 'Regional Map',   icon: '◉' },
  { key: 'logistics',  label: 'Live Logistics', icon: '⊟' },
  { key: 'ai',         label: 'AI Predictions', icon: '✦' },
  { key: 'incidents',  label: 'Incidents',      icon: '◆' },
  { key: 'routes',     label: 'Routes',         icon: '→' },
  { key: 'alerts',     label: 'Alerts',         icon: '◬' },
  { key: 'analytics',  label: 'Analytics',      icon: '▨' },
  { key: 'cr-approvals', label: 'Account Approvals', icon: '✓' },
];

const TITLES: Record<string, string> = {
  'cr-command': 'Command Center',
  'cr-approvals': 'Account Approvals',
  dashboard: 'Dashboard', map: 'District Map', incidents: 'Incidents',
  routes: 'Routes', logistics: 'Logistics',
  tasks: 'Tasks', ai: 'AI Insights', alerts: 'Alerts',
  reports: 'Reports', analytics: 'Analytics',
  'fo-dashboard': 'Field Dashboard', 'fo-tasks': 'My Tasks', 'fo-report': 'Report Incident',
  'fo-alerts': 'Alerts',
  'fo-reports': 'Reports',
};

const ROLE_META: Record<Role, {
  label: string; short: string; subtitle: string; nav: typeof NAV;
  contextLabel: string; context: string;
}> = {
  control: {
    label: 'Control Officer', short: 'CO', subtitle: 'Janrakshak AI Command Center', nav: CR_NAV,
    contextLabel: 'Active Region', context: 'North Eastern Region',
  },
  district: {
    label: 'District Officer', short: 'DO', subtitle: 'Janrakshak AI Operations Portal', nav: NAV,
    contextLabel: 'Active District', context: 'Kamrup Metro, Assam',
  },
  field: {
    label: 'Field Officer', short: 'FO', subtitle: 'Janrakshak AI Field Operations', nav: FO_NAV,
    contextLabel: 'Assigned Area', context: 'Dimapur District, Nagaland',
  },
};

interface ShellProps {
  role: Role;
  page: string;
  setPage: (p: string) => void;
  onSwitchRole: (r: Role) => void;
  onLogout?: () => void;
  sessionSource?: SessionSource;
  children: React.ReactNode;
}

const ROLE_SWITCHER: { key: Role; label: string; short: string }[] = [
  { key: 'field', label: 'Field Officer', short: 'FO' },
  { key: 'district', label: 'District Officer', short: 'DO' },
  { key: 'control', label: 'Control Officer', short: 'CO' },
];

export default function Shell({ role, page, setPage, onSwitchRole, onLogout, sessionSource = 'supabase', children }: ShellProps) {
  const { t } = useLanguage();
  const { demo, setDemo } = useDemoMode();
  const baseMeta = ROLE_META[role] ?? ROLE_META.district;
  const offlineDemo = sessionSource === 'demo-offline';
  const mlStatus = useMlQuery(fetchMlStatus);
  const [incidents, setIncidents] = useState(() => getIncidents());
  const [tasks, setTasks] = useState(() => getTasks());
  const [profile, setProfile] = useState<ProfileMeta>(() => {
    try {
      return profileService.getProfile();
    } catch (error) {
      console.error('Error loading profile:', error);
      // Return a safe fallback profile
      return {
        label: baseMeta.label,
        profileName: 'User',
        profileInitials: 'U',
        officerId: 'UNKNOWN',
        department: 'Unknown',
        region: 'Unknown',
        phone: '',
        email: '',
        lastLogin: 'Unknown',
        status: 'Active',
      };
    }
  });
  const [collapsed, setCollapsed] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchOpen, setSearchOpen] = useState(false);
  const [now] = useState(
    new Date().toLocaleString('en-IN', {
      timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short',
    })
  );

  useEffect(() => subscribeToIncidents(stored => setIncidents(stored)), []);
  useEffect(() => subscribeToTasks(stored => setTasks(stored)), []);

  // Subscribe to profile changes
  useEffect(() => {
    const unsubscribe = profileService.subscribe((updatedProfile) => {
      try {
        setProfile(updatedProfile);
      } catch (error) {
        console.error('Error updating profile:', error);
      }
    });
    return unsubscribe;
  }, []);

  const navBadges = useMemo(() => {
    const activeIncidents = incidents.filter(item => !['RESOLVED', 'CLOSED'].includes(item.status));
    const activeTasks = tasks.filter(item => !['Completed', 'Closed'].includes(item.status));
    const urgentIncidents = incidents.filter(item => ['PENDING_VERIFICATION', 'ACTIVE', 'ESCALATED', 'UNDER_REVIEW'].includes(item.status));
    const districtAlerts = urgentIncidents.length + tasks.filter(task => ['New', 'In Progress', 'Escalated'].includes(task.status)).length;
    const fieldAlerts = tasks.filter(task => task.assignedOfficer === 'FO-1024' && ['New', 'In Progress', 'Escalated'].includes(task.status)).length + incidents.filter(incident =>
      ['PENDING_VERIFICATION', 'ACTIVE', 'ESCALATED', 'UNDER_REVIEW'].includes(incident.status) &&
      (incident.assignedOfficer === 'FO-1024' || incident.reportedBy === 'FO-1024' || /dimapur/i.test(incident.location) || /nh-/i.test(incident.route))
    ).length;
    const controlAlerts = incidents.filter(item => ['CRITICAL', 'HIGH'].includes(item.severity) && !['RESOLVED', 'CLOSED'].includes(item.status)).length + tasks.filter(task => ['CRITICAL', 'HIGH'].includes(task.priority) && !['Completed', 'Closed'].includes(task.status)).length;

    return {
      incidents: activeIncidents.length,
      tasks: activeTasks.length,
      alerts: role === 'field' ? fieldAlerts : role === 'control' ? controlAlerts : districtAlerts,
    };
  }, [incidents, tasks, role]);

  const searchResults = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) return [];

    const results: Array<{ label: string; route: string; type: string; }> = [];

    incidents.forEach(incident => {
      const haystack = [incident.type, incident.location, incident.route, incident.description, incident.severity].join(' ').toLowerCase();
      if (haystack.includes(query)) {
        results.push({
          label: `${incident.type} · ${incident.location}`,
          route: role === 'field' ? 'fo-dashboard' : role === 'control' ? 'incidents' : 'incidents',
          type: 'Incident',
        });
      }
    });

    tasks.forEach(task => {
      const haystack = [task.title, task.location, task.description, task.status, task.priority].join(' ').toLowerCase();
      if (haystack.includes(query)) {
        results.push({
          label: `${task.title} · ${task.location}`,
          route: role === 'field' ? 'fo-tasks' : role === 'control' ? 'tasks' : 'tasks',
          type: 'Task',
        });
      }
    });

    return results.slice(0, 6);
  }, [incidents, tasks, role, searchQuery]);

  const saveProfile = async (updates: Partial<ProfileMeta>) => {
    const result = await profileService.updateProfile(updates);
    if (result.success) {
      const newRole = profileService.getCurrentRole();
      if (newRole && newRole !== role) {
        onSwitchRole(newRole);
      }
    }
    return result;
  };

  return (
    /*
      Root sits directly over the CSS gradient background defined in index.css.
      Sidebar is the only fully-opaque surface (solid navy per ops.md).
      Everything else lets the gradient show through via rgba/backdrop-blur.
    */
    <div className="flex h-full overflow-hidden">

      {/* ── Sidebar — solid navy, per ops.md ─────────────────────── */}
      <aside
        className="flex-shrink-0 flex flex-col h-full overflow-hidden transition-all duration-200"
        style={{
          width: collapsed ? 0 : 244,
          minWidth: collapsed ? 0 : 244,
          background: '#17324D',
          borderRight: '1px solid #0F2538',
        }}
      >
        {/* Brand */}
        <div className="flex items-center gap-3 px-5 py-4 border-b flex-shrink-0"
          style={{ borderColor: '#0F2538' }}>
          <div className="w-7 h-7 rounded flex items-center justify-center flex-shrink-0 text-xs font-bold"
            style={{ background: '#D7A73A', color: '#17212B' }}>
            {baseMeta.short}
          </div>
          <div>
            <div className="font-semibold text-sm leading-tight" style={{ color: '#FAF7F0' }}>
              {t(profile.label)}
            </div>
            <div className="text-xs leading-tight" style={{ color: '#4A6A82' }}>
              {baseMeta.subtitle}
            </div>
          </div>
        </div>

        {/* Active context */}
        <div className="px-5 py-3 border-b flex-shrink-0"
          style={{ background: '#122840', borderColor: '#0F2538' }}>
          <div className="text-xs uppercase tracking-widest mb-0.5"
            style={{ color: '#4A6A82', fontSize: 10 }}>
            {t(baseMeta.contextLabel)}
          </div>
          <div className="font-medium text-sm" style={{ color: '#FAF7F0' }}>
            {profile.region}
          </div>
          <div className="flex items-center gap-1.5 mt-1">
            <span className="w-1.5 h-1.5 rounded-full inline-block" style={{ background: '#5DBB8A' }} />
            <span className="text-xs" style={{ color: '#4A6A82' }}>System Online</span>
          </div>
        </div>

        {/* Nav — only the active role's menu */}
        <nav className="flex-1 overflow-y-auto px-3 py-3">
          <div className="text-xs uppercase tracking-widest mb-2 px-2"
            style={{ color: '#4A6A82', fontSize: 10 }}>
            {t('Main Menu')}
          </div>
          <ul className="space-y-0.5">
            {baseMeta.nav.map(item => {
              const active = page === item.key;
              return (
                <li key={item.key}>
                  <button
                    onClick={() => setPage(item.key)}
                    className="w-full flex items-center gap-3 px-3 py-2 rounded text-sm transition-all text-left"
                    style={{
                      background: active ? '#1C3F5A' : 'transparent',
                      color: active ? '#FAF7F0' : '#8AAFC8',
                      borderLeft: `3px solid ${active ? '#D7A73A' : 'transparent'}`,
                    }}
                    onMouseEnter={e => { if (!active) { (e.currentTarget as HTMLElement).style.background = 'rgba(255,255,255,0.06)'; (e.currentTarget as HTMLElement).style.color = '#D6E4EF'; } }}
                    onMouseLeave={e => { if (!active) { (e.currentTarget as HTMLElement).style.background = 'transparent'; (e.currentTarget as HTMLElement).style.color = '#8AAFC8'; } }}
                  >
                    <span className="text-sm w-4 text-center flex-shrink-0"
                      style={{ color: (item as any).gold ? '#D7A73A' : active ? '#D7A73A' : '#4A6A82' }}>
                      {item.icon}
                    </span>
                    <span className="flex-1">{t(item.label)}</span>
                    {((item.key === 'incidents' && navBadges.incidents) ||
                      (item.key === 'tasks' && navBadges.tasks) ||
                      (item.key === 'alerts' && navBadges.alerts) ||
                      (item.key === 'fo-tasks' && navBadges.tasks) ||
                      (item.key === 'fo-alerts' && navBadges.alerts)) && (
                      <span className="text-xs rounded-full px-1.5 py-0.5 font-semibold min-w-[20px] text-center"
                        style={{ background: navBadges.alerts > 2 || navBadges.incidents > 2 ? '#BE2424' : '#D7A73A', color: 'white' }}>
                        {item.key === 'incidents' ? navBadges.incidents : item.key === 'tasks' || item.key === 'fo-tasks' ? navBadges.tasks : navBadges.alerts}
                      </span>
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>

        {/* Bottom */}
        <div className="px-3 py-3 border-t flex-shrink-0" style={{ borderColor: '#0F2538' }}>
          {/* Role switcher — demo sessions only; a real session's role comes from the database (AUTH-003) */}
          {!offlineDemo ? (
            <div className="mb-2 px-1 text-xs" style={{ color: '#4A6A82' }}>
              {t('Role set by your account')}
            </div>
          ) : (
          <div className="mb-2">
            <div className="text-xs uppercase tracking-widest mb-1.5 px-1" style={{ color: '#4A6A82', fontSize: 10 }}>
              {t('Viewing As')}
            </div>
            <div className="grid grid-cols-3 gap-1">
              {ROLE_SWITCHER.map(r => {
                const active = role === r.key;
                return (
                  <button key={r.key} onClick={() => onSwitchRole(r.key)} title={r.label}
                    className="py-1.5 rounded text-xs font-semibold transition-all"
                    style={{
                      background: active ? '#D7A73A' : '#122840',
                      color: active ? '#17212B' : '#8AAFC8',
                    }}>
                    {r.short}
                  </button>
                );
              })}
            </div>
          </div>
          )}
          {[
            { label: 'Help & Support', icon: '?' },
            { label: 'Logout',         icon: '→' },
          ].map(item => (
            <button key={item.label}
              className="w-full flex items-center gap-3 px-3 py-2 rounded text-sm text-left transition-colors"
              style={{ color: '#4A6A82' }}
              onClick={() => {
                if (item.label === 'Logout') {
                  profileService.clearSession();
                  onLogout?.();
                  return;
                }
                if (item.label === 'Help & Support') {
                  setHelpOpen(true);
                }
              }}
              onMouseEnter={e => ((e.currentTarget as HTMLElement).style.color = '#FAF7F0')}
              onMouseLeave={e => ((e.currentTarget as HTMLElement).style.color = '#4A6A82')}>
              <span className="w-4 text-center">{item.icon}</span>
              {t(item.label)}
            </button>
          ))}
        </div>
      </aside>

      {/* ── Main column ──────────────────────────────────────────── */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">

        {/*
          Header — semi-transparent so the gradient shows through.
          Matches the image's minimal top strip: breadcrumb left, status right.
        */}
        <header
          className="flex-shrink-0 flex items-center gap-3 px-5"
          style={{
            height: 52,
            background: 'rgba(245, 236, 220, 0.72)',
            backdropFilter: 'blur(12px)',
            borderBottom: '1px solid rgba(180,162,136,0.35)',
          }}
        >
          <button
            onClick={() => setCollapsed(!collapsed)}
            className="w-8 h-8 flex items-center justify-center rounded text-lg transition-colors"
            style={{ color: '#17324D' }}
            onMouseEnter={e => ((e.currentTarget as HTMLElement).style.background = 'rgba(200,180,150,0.3)')}
            onMouseLeave={e => ((e.currentTarget as HTMLElement).style.background = 'transparent')}
          >
            ≡
          </button>

          {/*
            Breadcrumb — small-caps, exactly matching the image's
            "MYTRACKER › FIELD OFFICER ACCESS" treatment.
          */}
          <nav className="flex items-center gap-1 min-w-0" style={{ fontSize: 10 }}>
            <span className="uppercase tracking-widest" style={{ color: 'rgba(90,102,112,0.8)' }}>{t('JANRAKSHAK AI')}</span>
            <span style={{ color: 'rgba(180,162,136,0.8)', margin: '0 2px' }}>›</span>
            <span className="uppercase tracking-widest" style={{ color: 'rgba(90,102,112,0.8)' }}>{t(profile.label).toUpperCase()}</span>
            <span style={{ color: 'rgba(180,162,136,0.8)', margin: '0 2px' }}>›</span>
            <span className="uppercase tracking-widest font-semibold" style={{ color: '#17324D' }}>
              {t(TITLES[page] ?? page.toUpperCase())}
            </span>
          </nav>

          <div className="flex-1" />

          {/* Search */}
          {role === 'district' && <div className="relative hidden sm:block z-30">
            <div className="relative" style={{ width: 220 }}>
              <input
                value={searchQuery}
                onFocus={() => setSearchOpen(true)}
                onBlur={() => window.setTimeout(() => setSearchOpen(false), 120)}
                onChange={event => {
                  setSearchQuery(event.target.value);
                  setSearchOpen(true);
                }}
                placeholder={t('Search incidents, routes, officers…')}
                className="pl-8 pr-4 py-1.5 rounded border text-xs outline-none w-full"
                style={{
                  background: 'rgba(245,236,220,0.6)',
                  borderColor: 'rgba(180,162,136,0.5)',
                  color: '#17212B',
                  backdropFilter: 'blur(8px)',
                }}
              />
              <span className="absolute left-2.5 top-1/2 -translate-y-1/2 text-xs"
                style={{ color: '#8A9098' }}>⊕</span>
            </div>
            {searchOpen && searchQuery.trim() && (
              <div className="absolute right-0 top-full mt-2 w-[320px] max-w-[calc(100vw-24px)] rounded-lg border shadow-xl z-40 overflow-hidden" style={{ background: '#FFFDF9', borderColor: 'rgba(180,162,136,0.45)' }}>
                {searchResults.length ? (
                  <div className="max-h-64 overflow-y-auto p-1">
                    {searchResults.map(result => (
                      <button
                        key={`${result.type}-${result.label}`}
                        onClick={() => {
                          setPage(result.route);
                          setSearchQuery('');
                          setSearchOpen(false);
                        }}
                        className="w-full text-left px-3 py-2 rounded text-xs transition-colors"
                        style={{ color: '#17212B' }}
                        onMouseEnter={e => ((e.currentTarget as HTMLElement).style.background = 'rgba(23,50,77,0.06)')}
                        onMouseLeave={e => ((e.currentTarget as HTMLElement).style.background = 'transparent')}
                      >
                        <div className="font-semibold">{result.type}</div>
                        <div style={{ color: '#5A6670' }}>{result.label}</div>
                      </button>
                    ))}
                  </div>
                ) : (
                  <div className="px-3 py-2 text-xs" style={{ color: '#5A6670' }}>No matching incidents or tasks found.</div>
                )}
              </div>
            )}
          </div>}

          {/* Demo data switch — sample incidents, routes, convoys, riders and AI insights */}
          <button
            type="button"
            role="switch"
            aria-checked={demo}
            onClick={() => setDemo(!demo)}
            title={demo ? t('Demo data is on — click to hide sample data') : t('Demo data is off — click to show sample data')}
            className="inline-flex items-center gap-2 px-2.5 py-1 rounded border transition-colors"
            style={{
              background: demo ? 'rgba(215,167,58,0.16)' : 'rgba(245,236,220,0.5)',
              borderColor: demo ? 'rgba(196,134,26,0.55)' : 'rgba(180,162,136,0.5)',
              color: demo ? '#7A5A12' : '#5A6670',
              fontSize: 10,
              letterSpacing: '0.06em',
            }}>
            <span className="uppercase font-semibold">{t('Demo data')}</span>
            <span aria-hidden className="relative inline-block rounded-full transition-colors"
              style={{ width: 26, height: 14, background: demo ? '#C4861A' : '#B9B2A4' }}>
              <span className="absolute rounded-full bg-white transition-all"
                style={{ top: 2, left: demo ? 14 : 2, width: 10, height: 10 }} />
            </span>
            <span className="uppercase font-semibold" style={{ minWidth: 16 }}>{demo ? t('ON') : t('OFF')}</span>
          </button>

          {/* Time */}
          <div className="hidden md:block uppercase tracking-widest"
            style={{ fontSize: 10, color: 'rgba(90,102,112,0.8)' }}>
            {now} IST
          </div>

          {/* Notification */}
          {role !== 'control' && (
            <button className="relative w-8 h-8 flex items-center justify-center rounded transition-colors"
              style={{ background: 'rgba(245,236,220,0.5)', border: '1px solid rgba(180,162,136,0.4)' }}>
              <span style={{ color: '#17324D', fontSize: 14 }}>◬</span>
              <span className="absolute top-0.5 right-0.5 w-2 h-2 rounded-full" style={{ background: '#BE2424' }} />
            </button>
          )}

          {/* Profile */}
          <button
            onClick={() => setProfileOpen(true)}
            className="flex items-center gap-2.5 pl-1 pr-2 py-1 ml-1 rounded-full border transition-all"
            style={{ borderColor: 'rgba(120,140,160,0.35)', background: 'rgba(255,255,255,0.45)' }}
            onMouseEnter={e => ((e.currentTarget as HTMLElement).style.background = 'rgba(255,255,255,0.7)')}
            onMouseLeave={e => ((e.currentTarget as HTMLElement).style.background = 'rgba(255,255,255,0.45)')}>
            {profile.avatarUrl ? (
              <img src={profile.avatarUrl} alt="" className="w-8 h-8 rounded-full object-cover flex-shrink-0"
                style={{ boxShadow: '0 0 0 2px rgba(215,167,58,0.55)' }} />
            ) : (
              <span className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                style={{ background: '#17324D', color: 'white', boxShadow: '0 0 0 2px rgba(215,167,58,0.55)' }}>
                {profile.profileInitials}
              </span>
            )}
            <span className="hidden sm:flex flex-col items-start leading-none">
              <span className="text-xs font-semibold whitespace-nowrap" style={{ color: '#16222E' }}>{profile.profileName}</span>
              <span className="whitespace-nowrap mt-0.5" style={{ fontSize: 10, color: '#6B7885' }}>{t(profile.label)}</span>
            </span>
            <span className="hidden sm:block text-xs" style={{ color: '#8A9098' }}>▾</span>
          </button>
        </header>

        {/* Page content — transparent so the gradient shows as ambient bg */}
        <main className="flex-1 overflow-y-auto p-6" style={{ background: 'transparent' }}>
          <div key={page} className="ui-page">
            {children}
          </div>
        </main>
      </div>

      {helpOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/20 backdrop-blur-[2px]" onClick={() => setHelpOpen(false)}>
          <div className="w-full max-w-md rounded-2xl border p-5 shadow-2xl" style={{ background: '#FFFDF9', borderColor: 'rgba(180,162,136,0.5)' }} onClick={event => event.stopPropagation()}>
            <div className="flex items-center justify-between mb-3">
              <h2 className="font-semibold text-lg" style={{ color: '#17212B' }}>{t('Help & Support')}</h2>
              <button onClick={() => setHelpOpen(false)} className="text-sm" style={{ color: '#5A6670' }}>✕</button>
            </div>

            <div className="space-y-3 text-sm" style={{ color: '#5A6670' }}>
              <div className="rounded-lg border p-3" style={{ borderColor: 'rgba(180,162,136,0.45)', background: 'rgba(250,247,240,0.9)' }}>
                <div className="font-semibold mb-1" style={{ color: '#17212B' }}>{t('Operations desk')}</div>
                <div>+91 98765 43210</div>
              </div>
              <div className="rounded-lg border p-3" style={{ borderColor: 'rgba(180,162,136,0.45)', background: 'rgba(250,247,240,0.9)' }}>
                <div className="font-semibold mb-1" style={{ color: '#17212B' }}>{t('Support mail')}</div>
                <div>ops-support@ner.gov.in</div>
              </div>
            </div>

            <div className="mt-4 flex gap-2">
              <button onClick={() => { window.location.href = 'tel:+919876543210'; }} className="flex-1 rounded px-3 py-2 text-xs font-medium" style={{ background: '#17324D', color: 'white' }}>{t('Call Desk')}</button>
              <button onClick={() => { window.location.href = 'mailto:ops-support@ner.gov.in'; }} className="flex-1 rounded px-3 py-2 text-xs font-medium" style={{ border: '1px solid rgba(180,162,136,0.5)', color: '#17212B', background: 'rgba(245,236,220,0.7)' }}>{t('Email Support')}</button>
            </div>
          </div>
        </div>
      )}

      {/* Role-aware profile / settings slide-over */}
      <ProfilePanel open={profileOpen} onClose={() => setProfileOpen(false)} meta={profile} onSave={saveProfile} />
    </div>
  );
}
