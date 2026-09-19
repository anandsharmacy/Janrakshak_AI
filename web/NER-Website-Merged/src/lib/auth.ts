import type { Role } from '@/roles';
import { profileService, type ProfileMeta } from '@/lib/profileService';
import { supabase } from '@/lib/supabase';

/**
 * Sign-in for the officer website.
 *
 * Supabase checks the password and the database decides the role (SRS AUTH-001,
 * AUTH-003). Only when the backend can't be reached — never on a wrong password —
 * does the site fall back to the local demo login, labelled "offline demo". Live
 * panels such as ML risk need a real session; the database enforces that.
 */
export type SessionSource = 'supabase' | 'demo-offline';

export type SignInResult =
  | { ok: true; role: Role; source: SessionSource }
  | { ok: false; message: string };

const SOURCE_KEY = 'ner-session-source';

// Seeded demo officer IDs -> their Supabase emails (supabase/seed.sql).
const OFFICER_ID_EMAILS: Record<string, string> = {
  'ner-fo-4471': 'a.sangma@ner.gov.in',
  'ner-do-2210': 'r.borah@kamrup.gov.in',
  'ner-do-2281': 'r.borah@kamrup.gov.in',
  'ner-cr-0007': 's.khongsdier@ner.gov.in',
  'ner-co-0012': 's.khongsdier@ner.gov.in',
  'ner-rd-1184': 'p.lyngdoh@ner.gov.in',
};

const DB_ROLES: Record<string, Role> = {
  field_officer: 'field',
  district_officer: 'district',
  control_room: 'control',
};

const ROLE_LABELS: Record<Role, string> = {
  control: 'Control Officer',
  district: 'District Officer',
  field: 'Field Officer',
};

function setSource(source: SessionSource | null) {
  try {
    if (source) window.localStorage.setItem(SOURCE_KEY, source);
    else window.localStorage.removeItem(SOURCE_KEY);
  } catch {
    /* storage unavailable: the session still works for this page load */
  }
}

export function getSessionSource(): SessionSource | null {
  try {
    const v = window.localStorage.getItem(SOURCE_KEY);
    return v === 'supabase' || v === 'demo-offline' ? v : null;
  } catch {
    return null;
  }
}

/** Network failure, timeout or server error — as opposed to rejected credentials. */
function isUnreachable(error: { name?: string; status?: number; message?: string }): boolean {
  if (error.name === 'AuthRetryableFetchError') return true;
  const status = error.status ?? 0;
  if (status === 0 || status >= 500) return true;
  return /failed to fetch|network|load failed|timeout/i.test(error.message ?? '');
}

function initials(name: string): string {
  return name.split(/\s+/).filter(Boolean).map((p) => p[0]).join('').slice(0, 2).toUpperCase() || 'NE';
}

/** Role and profile from the database for the signed-in user. */
async function loadAccount(): Promise<{ role: Role } | { error: string }> {
  if (!supabase) return { error: 'The sign-in service is not configured for this build.' };
  const { data: userData } = await supabase.auth.getUser();
  const user = userData.user;
  if (!user) return { error: 'Your session has expired. Please sign in again.' };

  const [{ data: dbRole }, { data: district }, { data: prof }] = await Promise.all([
    supabase.rpc('my_role'),
    supabase.rpc('my_district_name'),
    supabase.from('profiles').select('full_name, officer_id, phone, organization, department, region, is_active')
      .eq('id', user.id).maybeSingle(),
  ]);

  if (dbRole === 'rider') {
    return { error: 'Rider accounts use the Janrakshak AI mobile app.' };
  }
  const role = typeof dbRole === 'string' ? DB_ROLES[dbRole] : undefined;
  if (!role || prof?.is_active === false) {
    return { error: 'Your account has no active operational role. Contact your district administrator.' };
  }

  const name = prof?.full_name || user.email || 'Officer';
  // The avatar isn't in the `profiles` table yet, so carry over whatever was
  // saved locally for this account (profileService persists it across logins).
  const savedAvatar = user.email ? profileService.findAccount(user.email)?.avatarUrl : undefined;
  const profile: ProfileMeta = {
    label: ROLE_LABELS[role],
    profileName: name,
    profileInitials: initials(name),
    officerId: prof?.officer_id ?? '',
    department: prof?.department ?? prof?.organization ?? '',
    region: (district as string | null) ?? prof?.region ?? 'North Eastern Region',
    district: (district as string | null) ?? undefined,
    phone: prof?.phone ?? '',
    email: user.email ?? '',
    lastLogin: `Today, ${new Date().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })} IST`,
    status: 'Active',
    avatarUrl: savedAvatar,
  };
  profileService.adoptProfile(profile, role);
  return { role };
}

function demoSignIn(identity: string): SignInResult {
  const { role } = profileService.loginWithIdentity(identity);
  setSource('demo-offline');
  return { ok: true, role, source: 'demo-offline' };
}

export async function signIn(identity: string, password: string): Promise<SignInResult> {
  const id = identity.trim();
  if (!id || !password) return { ok: false, message: 'Enter your email and password to continue.' };
  if (!supabase) return demoSignIn(id);

  const email = id.includes('@') ? id : OFFICER_ID_EMAILS[id.toLowerCase()];
  if (!email) return { ok: false, message: 'Sign in with your official email address or officer ID.' };

  let error: { name?: string; status?: number; message?: string } | null = null;
  try {
    ({ error } = await supabase.auth.signInWithPassword({ email, password }));
  } catch (e) {
    error = { name: 'AuthRetryableFetchError', message: String(e) };
  }
  if (error) {
    return isUnreachable(error) ? demoSignIn(id) : { ok: false, message: 'The email or password is incorrect.' };
  }

  const account = await loadAccount();
  if ('error' in account) {
    await supabase.auth.signOut().catch(() => undefined);
    return { ok: false, message: account.error };
  }
  setSource('supabase');
  return { ok: true, role: account.role, source: 'supabase' };
}

/** Restores the session on page load; null means "show the login screen". */
export async function restoreSession(): Promise<{ role: Role; source: SessionSource } | null> {
  const source = getSessionSource();
  const stored = profileService.getCurrentRole();
  if (source === 'demo-offline' && stored) return { role: stored, source };
  if (source !== 'supabase' || !supabase) {
    profileService.clearSession();
    setSource(null);
    return null;
  }
  const { data } = await supabase.auth.getSession();
  if (!data.session) {
    profileService.clearSession();
    setSource(null);
    return null;
  }
  try {
    const account = await loadAccount();
    if ('error' in account) {
      await signOut();
      return null;
    }
    return { role: account.role, source };
  } catch {
    // Backend briefly unreachable: keep the stored role; the database still guards the data.
    return stored ? { role: stored, source } : null;
  }
}

export async function signOut(): Promise<void> {
  if (supabase && getSessionSource() === 'supabase') {
    await supabase.auth.signOut().catch(() => undefined);
  }
  profileService.clearSession();
  setSource(null);
}
