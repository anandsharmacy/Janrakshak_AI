-- PMO (Prime Minister's Office) role. Kept in its own migration: a new enum value
-- cannot be used until the transaction that adds it has committed.
alter type public.user_role_enum add value if not exists 'pmo';
