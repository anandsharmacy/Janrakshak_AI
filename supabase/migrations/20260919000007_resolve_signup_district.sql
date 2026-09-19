-- Field/district officer sign-ups were left with district_id NULL whenever `locations` had no matching row
-- (it was empty), so get_pending_approvals() never showed a Field Officer to the District Officer of the same
-- district. Sign-up now finds the district's location row, or creates it, and existing accounts are backfilled.
-- Applied to cloud project sjcqwxthimfuxmrodsbs as migration `resolve_signup_district`.

create or replace function public.resolve_district_location(p_district text, p_state text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_district text := left(nullif(btrim(p_district), ''), 100);
  v_state    text := left(nullif(btrim(p_state), ''), 100);
  v_id       uuid;
begin
  if v_district is null then
    return null;
  end if;

  -- One resolver at a time, so two sign-ups for the same new district cannot create it twice.
  perform pg_advisory_xact_lock(hashtext('resolve_district_location'));

  select id into v_id
  from public.locations
  where (lower(district) = lower(v_district) or lower(name) = lower(v_district))
    and (v_state is null or state is null or lower(state) = lower(v_state))
  order by (location_type = 'district_hq') desc, created_at
  limit 1;

  if v_id is null then
    insert into public.locations (name, district, state, location_type)
    values (v_district, v_district, v_state, 'district_hq')
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.resolve_district_location(text, text) from public, anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  requested_role        public.user_role_enum;
  requested_district_id uuid;
  requested_district    text;
  role_is_active        boolean;
begin
  requested_role := case new.raw_user_meta_data->>'requested_role'
    when 'field_officer'    then 'field_officer'::public.user_role_enum
    when 'district_officer' then 'district_officer'::public.user_role_enum
    when 'control_room'     then 'control_room'::public.user_role_enum
    when 'rider'            then 'rider'::public.user_role_enum
    when 'citizen'          then 'citizen'::public.user_role_enum
    else null
  end;

  requested_district := new.raw_user_meta_data->>'district';

  if requested_role in ('district_officer'::public.user_role_enum, 'field_officer'::public.user_role_enum) then
    -- Approval routing depends on this id: find the district's row, or create it.
    requested_district_id := public.resolve_district_location(requested_district, new.raw_user_meta_data->>'state');
  elsif requested_role is not null and requested_role <> 'control_room'::public.user_role_enum then
    select id
    into requested_district_id
    from public.locations
    where name = requested_district
       or district = requested_district
       or state = requested_district
    order by (location_type = 'district_hq') desc
    limit 1;
  end if;

  role_is_active := requested_role in ('rider'::public.user_role_enum, 'citizen'::public.user_role_enum);

  insert into public.profiles (id, full_name, phone, is_active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    nullif(new.raw_user_meta_data->>'phone', ''),
    true
  )
  on conflict (id) do update
    set is_active = true;

  if requested_role is not null then
    insert into public.user_roles (user_id, role, district_id, is_active)
    values (new.id, requested_role, requested_district_id, role_is_active)
    on conflict (user_id) do update
      set role        = excluded.role,
          district_id = excluded.district_id,
          is_active   = excluded.is_active;
  end if;

  if requested_role = 'control_room'::public.user_role_enum then
    insert into public.control_room_requests (user_id, full_name, email, requested_region, requested_state, reason)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', ''),
      coalesce(new.email, ''),
      left(nullif(new.raw_user_meta_data->>'region', ''), 100),
      left(coalesce(new.raw_user_meta_data->>'state', ''), 100),
      left(coalesce(new.raw_user_meta_data->>'request_reason', ''), 1000)
    )
    on conflict (user_id) do nothing;
  end if;

  if requested_role = 'rider'::public.user_role_enum then
    insert into public.rider_profiles (user_id, vehicle_registration, vehicle_type, phone)
    values (
      new.id,
      nullif(new.raw_user_meta_data->>'vehicle_registration', ''),
      nullif(new.raw_user_meta_data->>'vehicle_type', ''),
      nullif(new.raw_user_meta_data->>'phone', '')
    )
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

-- Backfill: officers who signed up while no matching location existed.
update public.user_roles ur
set district_id = public.resolve_district_location(u.raw_user_meta_data->>'district', u.raw_user_meta_data->>'state')
from auth.users u
where u.id = ur.user_id
  and ur.role in ('district_officer', 'field_officer')
  and ur.district_id is null
  and nullif(btrim(u.raw_user_meta_data->>'district'), '') is not null;
