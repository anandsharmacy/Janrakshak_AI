-- PMO dashboard: Control Room approval workflow + national incident read model.
--
-- Security model (all enforced here, not in the browser):
--   * 'pmo' can never be self-registered: handle_new_user ignores it, admin_set_user_role refuses it.
--     Grant it by SQL only (see the note at the bottom).
--   * Control Room sign-ups are inactive until a PMO user approves them. Nobody else can activate one
--     (decide_role_request and admin_set_user_role are tightened below).
--   * control_room_requests has RLS on and no grants: it is reachable only through the RPCs below.

-- 1. Request history (who asked, why, and who decided when) ----------------------------------------
create table public.control_room_requests (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null unique references auth.users (id) on delete cascade,
  full_name        text not null default '',
  email            text not null default '',
  requested_region text,
  requested_state  text not null default '',
  reason           text not null default '',
  status           text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_by       uuid references auth.users (id) on delete set null,
  decided_at       timestamptz,
  created_at       timestamptz not null default now(),
  constraint control_room_requests_decision_consistent check ((status = 'pending') = (decided_at is null))
);
create index control_room_requests_status_idx on public.control_room_requests (status, created_at desc);

alter table public.control_room_requests enable row level security;
revoke all on public.control_room_requests from anon, authenticated;
comment on table public.control_room_requests is
  'Control Room account requests. RLS on, no policies or grants on purpose: read/write only via pmo_* RPCs and handle_new_user.';

-- 2. Sign-up: Control Room now waits for PMO approval and records its request ------------------------
create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
    else null
  end;

  requested_district := new.raw_user_meta_data->>'district';

  if requested_role is not null and requested_role <> 'control_room'::public.user_role_enum then
    select id
    into requested_district_id
    from public.locations
    where name = requested_district
       or district = requested_district
       or state = requested_district
    order by (location_type = 'district_hq') desc
    limit 1;
  end if;

  -- Only riders are active at once; district/field officers wait for their approver and
  -- control room accounts wait for the PMO.
  role_is_active := requested_role = 'rider'::public.user_role_enum;

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
$function$;

-- 3. Close the paths that would let a non-PMO user approve control room / grant PMO -----------------
create or replace function public.decide_role_request(p_user_id uuid, p_approve boolean default true)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_target public.user_roles;
begin
  if auth.uid() is null or not public.is_active_user() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select * into v_target from public.user_roles where user_id = p_user_id for update;
  if not found or v_target.is_active then
    raise exception 'no pending request for this user' using errcode = 'P0002';
  end if;

  -- Control room requests are decided by the PMO (pmo_decide_control_room_request), never here.
  if v_target.role not in ('district_officer', 'field_officer') then
    raise exception 'you cannot decide this request' using errcode = '42501';
  end if;

  if not (
    public.has_role('control_room')
    or (public.has_role('district_officer')
        and v_target.role = 'field_officer'
        and v_target.district_id is not null
        and v_target.district_id = public.my_district_id())
  ) then
    raise exception 'you cannot decide this request' using errcode = '42501';
  end if;

  if p_approve then
    update public.user_roles set is_active = true where user_id = p_user_id;
  else
    delete from public.user_roles where user_id = p_user_id;
  end if;

  insert into public.audit_logs (user_id, action, entity_type, entity_id, old_value, new_value)
  values (auth.uid(),
          case when p_approve then 'role_approved' else 'role_rejected' end,
          'user_roles', p_user_id,
          to_jsonb(v_target),
          case when p_approve then jsonb_build_object('is_active', true) end);
end;
$function$;

create or replace function public.admin_set_user_role(
  p_user_id uuid,
  p_role public.user_role_enum,
  p_district_id uuid default null,
  p_is_active boolean default true)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_old public.user_roles;
begin
  if auth.uid() is null or not public.is_active_user()
     or not (public.has_role('control_room') or public.has_role('pmo')) then
    raise exception 'only control room can change roles' using errcode = '42501';
  end if;
  if p_role = 'pmo' then
    raise exception 'the PMO role can only be granted by a database administrator' using errcode = '42501';
  end if;

  select * into v_old from public.user_roles where user_id = p_user_id for update;

  if v_old.role = 'pmo' then
    raise exception 'PMO accounts cannot be changed here' using errcode = '42501';
  end if;
  -- Newly activating a control room account is the PMO's decision (pmo_decide_control_room_request).
  if p_role = 'control_room' and p_is_active and not public.has_role('pmo')
     and (v_old.user_id is null or v_old.role <> 'control_room' or not v_old.is_active) then
    raise exception 'control room access is granted through PMO approval' using errcode = '42501';
  end if;

  -- Keep at least the caller's own control-room access so the last admin cannot lock themselves out.
  if p_user_id = auth.uid() and (p_role <> 'control_room' or not p_is_active) then
    raise exception 'you cannot remove your own control-room access' using errcode = '42501';
  end if;
  if p_role in ('district_officer', 'field_officer') and p_district_id is null then
    raise exception 'district_id is required for district and field officers' using errcode = '22023';
  end if;

  insert into public.user_roles (user_id, role, district_id, is_active)
  values (p_user_id, p_role,
          case when p_role = 'control_room' then null else p_district_id end,
          p_is_active)
  on conflict (user_id) do update
    set role        = excluded.role,
        district_id = excluded.district_id,
        is_active   = excluded.is_active;

  insert into public.audit_logs (user_id, action, entity_type, entity_id, old_value, new_value)
  values (auth.uid(), 'role_change', 'user_roles', p_user_id,
          case when v_old.user_id is not null then to_jsonb(v_old) end,
          jsonb_build_object('role', p_role, 'district_id', p_district_id, 'is_active', p_is_active));
end;
$function$;

-- 4. PMO RPCs -------------------------------------------------------------------------------------
create or replace function public.pmo_list_control_room_requests()
 returns table (
   id uuid, user_id uuid, full_name text, email text,
   requested_region text, requested_state text, reason text, status text,
   created_at timestamptz, decided_at timestamptz, decided_by uuid, decided_by_name text)
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
begin
  if auth.uid() is null or not public.is_active_user() or not public.has_role('pmo') then
    raise exception 'PMO access required' using errcode = '42501';
  end if;

  return query
  select r.id, r.user_id, r.full_name, r.email, r.requested_region, r.requested_state, r.reason,
         r.status, r.created_at, r.decided_at, r.decided_by, p.full_name
  from public.control_room_requests r
  left join public.profiles p on p.id = r.decided_by
  order by (r.status = 'pending') desc, coalesce(r.decided_at, r.created_at) desc;
end;
$function$;

create or replace function public.pmo_decide_control_room_request(p_request_id uuid, p_approve boolean)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_req public.control_room_requests;
begin
  if auth.uid() is null or not public.is_active_user() or not public.has_role('pmo') then
    raise exception 'PMO access required' using errcode = '42501';
  end if;

  -- Row lock + status check: a second approve/reject of the same request fails instead of repeating.
  select * into v_req from public.control_room_requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request already %', v_req.status using errcode = '55000';
  end if;

  update public.control_room_requests
     set status     = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(),
         decided_at = now()
   where id = v_req.id;

  if p_approve then
    insert into public.user_roles (user_id, role, district_id, is_active)
    values (v_req.user_id, 'control_room', null, true)
    on conflict (user_id) do update
      set role = 'control_room', district_id = null, is_active = true
      where public.user_roles.role <> 'pmo';
    update public.profiles set is_active = true where id = v_req.user_id;
  else
    delete from public.user_roles
     where user_id = v_req.user_id and role = 'control_room' and not is_active;
  end if;

  insert into public.audit_logs (user_id, action, entity_type, entity_id, old_value, new_value)
  values (auth.uid(),
          case when p_approve then 'control_room_approved' else 'control_room_rejected' end,
          'control_room_requests', v_req.id,
          to_jsonb(v_req),
          jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end));
end;
$function$;

-- Field reports and disaster feed as one national list. Coordinates come from the incident's own
-- geometry, else its location. Region is NOT stored: the app derives it from the state.
create or replace function public.pmo_national_incidents(p_limit integer default 5000)
 returns table (
   id text, reference text, source text, category text, title text, description text,
   severity text, status text, state text, district text,
   latitude double precision, longitude double precision, reported_at timestamptz, reporter text)
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'extensions'
as $function$
#variable_conflict use_column
begin
  if auth.uid() is null or not public.is_active_user() or not public.has_role('pmo') then
    raise exception 'PMO access required' using errcode = '42501';
  end if;

  return query
  select u.id, u.reference, u.source, u.category, u.title, u.description, u.severity, u.status,
         u.state, u.district, u.latitude, u.longitude, u.reported_at, u.reporter
  from (
    select ri.id::text as id, ri.incident_ref as reference, 'field_report'::text as source,
           ri.category::text as category, ri.title as title, ri.description as description,
           ri.severity::text as severity, ri.status::text as status,
           coalesce(ri.state, l.state) as state, coalesce(ri.district, l.district) as district,
           coalesce(st_y(ri.geometry::geometry), l.latitude) as latitude,
           coalesce(st_x(ri.geometry::geometry), l.longitude) as longitude,
           ri.created_at as reported_at, coalesce(pr.full_name, ri.sync_source) as reporter
    from public.road_incidents ri
    left join public.locations l on l.id = ri.location_id
    left join public.profiles pr on pr.id = ri.reported_by
    union all
    select de.id::text, null::text, 'disaster_feed'::text,
           de.type::text, de.title, de.description,
           case when de.severity is null then null else 'level ' || de.severity::text end,
           case when de.ended_at is null then 'active' else 'resolved' end,
           coalesce(de.state, l.state), coalesce(de.district, l.district),
           coalesce(st_y(de.geometry::geometry), l.latitude),
           coalesce(st_x(de.geometry::geometry), l.longitude),
           coalesce(de.started_at, de.created_at), de.source
    from public.disaster_events de
    left join public.locations l on l.id = de.location_id
  ) u
  order by u.reported_at desc nulls last
  limit greatest(p_limit, 1);
end;
$function$;

-- Callable by signed-in users only; each function rejects everyone who is not an active PMO user.
revoke all on function public.pmo_list_control_room_requests()                 from public, anon;
revoke all on function public.pmo_decide_control_room_request(uuid, boolean)   from public, anon;
revoke all on function public.pmo_national_incidents(integer)                  from public, anon;
grant execute on function public.pmo_list_control_room_requests()               to authenticated;
grant execute on function public.pmo_decide_control_room_request(uuid, boolean) to authenticated;
grant execute on function public.pmo_national_incidents(integer)                to authenticated;

-- Granting PMO access (Supabase SQL editor, as the project owner; there is deliberately no API for it):
--   1. Authentication > Users > Add user (auto-confirm), with the officer's official email.
--   2. insert into public.user_roles (user_id, role, is_active)
--      select id, 'pmo', true from auth.users where email = '<official email>'
--      on conflict (user_id) do update set role = 'pmo', is_active = true, district_id = null;
