export type Role = 'control' | 'district' | 'field';

/** Roles that can hold a session. PMO has its own dashboard and never appears in the operational Role maps. */
export type SessionRole = Role | 'pmo';
