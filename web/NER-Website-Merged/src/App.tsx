import { useEffect, useState } from 'react';
import LoginTab from './auth/LoginTab';
import CreateAccountTab from './auth/CreateAccountTab';
import IdentityPanel from './auth/IdentityPanel';
import FormShell from './auth/FormShell';
import TransitionOverlay from './auth/TransitionOverlay';
import GlassFilters from './auth/GlassFilters';
import Shell from '@/components/Shell';
import type { Role } from '@/roles';
import { profileService } from '@/lib/profileService';
import { restoreSession, signIn, signOut, type SessionSource } from '@/lib/auth';
import Dashboard from '@/pages/Dashboard';
import DistrictMap from '@/pages/DistrictMap';
import Incidents from '@/pages/Incidents';
import Routes from '@/pages/Routes';
import Logistics from '@/pages/Logistics';
import FieldOfficerDashboard from '@/pages/FieldOfficerDashboard';
import FOMyTasks from '@/pages/fo/MyTasks';
import FOReportIncident from '@/pages/fo/ReportIncident';
import FOAlerts from '@/pages/fo/Alerts';
import FOReports from '@/pages/fo/Reports';
import CommandCenter from '@/pages/control/CommandCenter';
import Tasks from '@/pages/Tasks';
import AIInsights from '@/pages/AIInsights';
import Alerts from '@/pages/Alerts';
import Reports from '@/pages/Reports';
import Analytics from '@/pages/Analytics';

type Screen = 'splash' | 'login' | 'create';
type Dir = 'forward' | 'back';
type Transition = { to: Screen; dir: Dir; stage: 'cover' | 'reveal' };

const DEFAULT_PAGE: Record<Role, string> = {
  control: 'cr-command',
  district: 'dashboard',
  field: 'fo-dashboard',
};

function roleFromIdentity(identity: string): Role | null {
  const value = identity.trim().toLowerCase();
  if (!value) return null;

  if (value.includes('field') || value.includes('field officer') || value.includes('fo-') || value.includes('fo@') || /^fo\d+/.test(value) || /ravi|kumar|nagaland/.test(value)) {
    return 'field';
  }

  if (value.includes('control') || value.includes('control officer') || value.includes('control room') || value.includes('co-') || value.includes('co@') || /^co\d+/.test(value) || /anjali|rao/.test(value)) {
    return 'control';
  }

  if (value.includes('district') || value.includes('district officer') || value.includes('do-') || value.includes('do@') || /^do\d+/.test(value) || /dinesh|joshi|assam/.test(value)) {
    return 'district';
  }

  const savedProfile = profileService.getProfile();
  const label = savedProfile?.label?.toLowerCase() ?? '';
  if (label.includes('field')) return 'field';
  if (label.includes('control')) return 'control';
  if (label.includes('district')) return 'district';

  return null;
}

function roleFromPath(pathname: string): Role | null {
  if (pathname.endsWith('/field')) return 'field';
  if (pathname.endsWith('/control')) return 'control';
  if (pathname.endsWith('/district')) return 'district';
  return null;
}

function dashboardPath(role: Role) {
  return `/dashboard/${role}`;
}

function screenFromPath(pathname: string): Screen {
  if (pathname === '/login') return 'login';
  if (pathname === '/create-account') return 'create';
  // Dashboard routes are handled by the session state, not screen state
  return 'splash';
}

export default function App() {
  const [session, setSession] = useState<Role | null>(null);
  const [source, setSource] = useState<SessionSource>('supabase');
  const [sessionReady, setSessionReady] = useState(false);
  const [screen, setScreen] = useState<Screen>(() => screenFromPath(window.location.pathname));
  const [trans, setTrans] = useState<Transition | null>(null);
  const [loading, setLoading] = useState(false);

  const prefersReduced = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  useEffect(() => {
    let cancelled = false;
    restoreSession()
      .then((restored) => {
        if (cancelled) return;
        setSession(restored?.role ?? null);
        if (restored) setSource(restored.source);
        if (!restored && window.location.pathname.startsWith('/dashboard/')) {
          window.history.replaceState({}, '', '/');
        }
      })
      .catch((error) => {
        console.error('Error restoring session:', error);
        if (!cancelled) setSession(null);
      })
      .finally(() => {
        if (!cancelled) setSessionReady(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const handlePopState = () => {
      const pathRole = roleFromPath(window.location.pathname);
      if (pathRole && session === pathRole) return;
      setScreen(screenFromPath(window.location.pathname));
    };
    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, [session]);

  const navigate = (to: Screen, dir: Dir) => {
    if (trans) return;
    const path = to === 'login' ? '/login' : to === 'create' ? '/create-account' : '/';
    window.history.pushState({}, '', path);
    if (prefersReduced) {
      setScreen(to);
      return;
    }
    setTrans({ to, dir, stage: 'cover' });
  };

  const swap = (to: Screen) => {
    if (trans) return;
    window.history.pushState({}, '', to === 'login' ? '/login' : '/create-account');
    setScreen(to);
  };

  useEffect(() => {
    if (!trans) return;
    if (trans.stage === 'cover') {
      const timer = setTimeout(() => {
        setScreen(trans.to);
        setTrans((current) => current ? { ...current, stage: 'reveal' } : null);
      }, 850);
      return () => clearTimeout(timer);
    }
    const timer = setTimeout(() => setTrans(null), 950);
    return () => clearTimeout(timer);
  }, [trans]);

  // Returns an error message for the login form, or null on success.
  const login = async (identity: string, password: string): Promise<string | null> => {
    try {
      const result = await signIn(identity, password);
      if (!result.ok) return result.message;
      setSource(result.source);
      setSession(result.role);
      window.history.pushState({}, '', dashboardPath(result.role));
      return null;
    } catch (error) {
      console.error('Error during login:', error);
      return 'Sign-in failed. Please try again.';
    }
  };

  const logout = () => {
    setLoading(true);
    void signOut().finally(() => {
      setSession(null);
      window.history.pushState({}, '', '/');
      setScreen('splash');
      setLoading(false);
    });
  };

  if (!sessionReady || loading) {
    return (
      <div className="flex items-center justify-center h-screen" style={{ background: 'linear-gradient(135deg, #17324D 0%, #1E4A63 60%, #2F6F7E 130%)' }}>
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-white/30 border-t-white rounded-full animate-spin mx-auto mb-4" />
          <div className="text-white text-sm font-medium">Loading dashboard...</div>
          <div className="text-white/60 text-xs mt-2">Preparing your workspace and role permissions</div>
        </div>
      </div>
    );
  }

  if (session) {
    return <DashboardApp initialRole={session} source={source} onLogout={logout} />;
  }

  return (
    <>
      <div key={screen}>
        {screen === 'login' && (
          <FormShell
            onBack={() => navigate('splash', 'back')}
            title="Access your workspace"
            footerLink={{ label: "Don't have access?", action: 'Create an account', onClick: () => swap('create') }}
          >
            <LoginTab onLogin={login} />
          </FormShell>
        )}
        {screen === 'create' && (
          <FormShell
            onBack={() => navigate('splash', 'back')}
            title="Request platform access"
            footerLink={{ label: 'Already have access?', action: 'Log in', onClick: () => swap('login') }}
          >
            <CreateAccountTab />
          </FormShell>
        )}
        {screen === 'splash' && <IdentityPanel onLogin={() => navigate('login', 'forward')} onCreate={() => navigate('create', 'forward')} />}
      </div>
      {trans && <TransitionOverlay stage={trans.stage} dir={trans.dir} />}
      <GlassFilters />
    </>
  );
}

function DashboardApp({ initialRole, source, onLogout }: { initialRole: Role; source: SessionSource; onLogout: () => void }) {
  const [role, setRole] = useState<Role>(initialRole);
  const [page, setPage] = useState(DEFAULT_PAGE[initialRole]);
  const [error, setError] = useState<string | null>(null);

  // Validate the initial role
  useEffect(() => {
    if (!initialRole || !['field', 'district', 'control'].includes(initialRole)) {
      setError(`Invalid role: ${initialRole}. Please log in again.`);
      onLogout();
    }
  }, [initialRole, onLogout]);

  const switchRole = (nextRole: Role) => {
    if (source === 'supabase') return; // the database role is authoritative (AUTH-003)
    if (!nextRole || !['field', 'district', 'control'].includes(nextRole)) {
      console.error('Invalid role switch attempt:', nextRole);
      return;
    }
    setRole(nextRole);
    setPage(DEFAULT_PAGE[nextRole]);
    window.history.replaceState({}, '', dashboardPath(nextRole));
    profileService.setSessionRole(nextRole);
  };

  const renderPage = () => {
    if (error) {
      return (
        <div className="flex items-center justify-center h-full p-6">
          <div className="text-center">
            <div className="text-red-500 text-4xl mb-4">⚠</div>
            <h2 className="text-xl font-semibold mb-2" style={{ color: '#17212B' }}>Authentication Error</h2>
            <p className="text-sm mb-4" style={{ color: '#5A6670' }}>{error}</p>
            <button 
              onClick={onLogout}
              className="px-4 py-2 rounded-lg text-sm font-semibold"
              style={{ background: '#BE2424', color: 'white' }}
            >
              Return to Login
            </button>
          </div>
        </div>
      );
    }

    try {
      switch (page) {
        case 'dashboard': return <Dashboard setPage={setPage} />;
        case 'map': return <DistrictMap role={role} />;
        case 'incidents': return <Incidents />;
        case 'routes': return <Routes />;
        case 'logistics': return <Logistics />;
        case 'tasks': return <Tasks />;
        case 'ai': return <AIInsights />;
        case 'alerts': return <Alerts />;
        case 'reports': return <Reports />;
        case 'analytics': return <Analytics />;
        case 'fo-dashboard': return <FieldOfficerDashboard setPage={setPage} />;
        case 'fo-tasks': return <FOMyTasks />;
        case 'fo-report': return <FOReportIncident setPage={setPage} />;
        case 'fo-alerts': return <FOAlerts />;
        case 'fo-reports': return <FOReports />;
        case 'cr-command': return <CommandCenter setPage={setPage} />;
        default: return <Dashboard setPage={setPage} />;
      }
    } catch (err) {
      console.error('Error rendering page:', err);
      setError('Failed to load dashboard page. Please try again.');
      return null;
    }
  };

  if (error) {
    return (
      <div className="flex items-center justify-center h-screen" style={{ background: 'rgba(250,247,240,0.82)' }}>
        <div className="text-center p-6">
          <div className="text-red-500 text-4xl mb-4">⚠</div>
          <h2 className="text-xl font-semibold mb-2" style={{ color: '#17212B' }}>Authentication Error</h2>
          <p className="text-sm mb-4" style={{ color: '#5A6670' }}>{error}</p>
          <button 
            onClick={onLogout}
            className="px-4 py-2 rounded-lg text-sm font-semibold"
            style={{ background: '#BE2424', color: 'white' }}
          >
            Return to Login
          </button>
        </div>
      </div>
    );
  }

  return (
    <Shell role={role} page={page} setPage={setPage} onSwitchRole={switchRole} onLogout={onLogout} sessionSource={source}>
      {renderPage()}
    </Shell>
  );
}
