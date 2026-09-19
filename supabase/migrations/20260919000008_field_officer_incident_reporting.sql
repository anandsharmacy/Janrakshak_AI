-- Field Officer incident reports on the website: store the free-text location and route the dashboards show,
-- expose the point's coordinates as plain numbers, stamp the reporter's district, and let field officers upload evidence.
-- Applied to cloud project sjcqwxthimfuxmrodsbs as migration `field_officer_incident_reporting`.

alter table public.road_incidents
  add column if not exists location_text text,
  add column if not exists route_text text,
  add column if not exists latitude double precision
    generated always as (case when geometrytype(geometry::geometry) = 'POINT' then st_y(geometry::geometry) end) stored,
  add column if not exists longitude double precision
    generated always as (case when geometrytype(geometry::geometry) = 'POINT' then st_x(geometry::geometry) end) stored;

-- A field officer's report always carries their own district/state, so district officers of that district
-- (and only them) see it, and it cannot be filed under another district.
create or replace function public.enforce_incident_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_district text;
  v_state    text;
begin
  -- Service-role / internal jobs have no auth.uid(); only user inserts are guarded.
  if auth.uid() is null then
    return new;
  end if;

  if public.has_role('field_officer') then
    select l.district, l.state into v_district, v_state
    from public.user_roles ur
    join public.locations l on l.id = ur.district_id
    where ur.user_id = auth.uid() and ur.is_active
    limit 1;
    if found then
      new.district := v_district;
      new.state    := v_state;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_incident_insert() from public, anon, authenticated;

create trigger trg_incidents_enforce_insert
  before insert on public.road_incidents
  for each row execute function public.enforce_incident_insert();

-- Evidence: same private bucket and own-folder rule the citizen app uses.
create policy "incident-media: field officer upload own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'incident-media'
    and public.has_role('field_officer')
    and public.is_active_user()
    and (storage.foldername(name))[1] = auth.uid()::text
  );
