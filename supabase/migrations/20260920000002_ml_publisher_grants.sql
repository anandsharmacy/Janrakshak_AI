-- Grants the ml_publisher loader role needs (found by the Phase 1 rollback dry-run, ML_GO_LIVE_PLAN.md).
-- The role's login and password are set by hand and are NOT part of any migration.
--   * bypassrls: COPY FROM is refused on tables with row-level security. The role's table privileges
--     are limited to the ml_* tables, so this does not widen what it can reach.
--   * usage on schema extensions: the coverage load calls PostGIS functions living there.
alter role ml_publisher bypassrls;
grant usage on schema extensions to ml_publisher;
