-- ML pipeline failure alerts for the PMO dashboard (ML_GO_LIVE_PLAN.md, Phase 1 / tasks 2.2-2.3).
--
--   * ml_pipeline_events has RLS on and no policies or grants: reachable only through the RPCs below
--     (same pattern as control_room_requests). It is NOT public.alerts, because control_room has ALL
--     on alerts and untargeted rows are readable by every active user.
--   * ml_report_pipeline_failure is executable by the ml_publisher role only (the GitHub Actions job).
--   * pmo_list_pipeline_events / pmo_ack_pipeline_event are PMO-only.

create table if not exists public.ml_pipeline_events (
  id               bigint generated always as identity primary key,
  created_at       timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  event_day        date not null default ((now() at time zone 'Asia/Kolkata')::date),
  stage            text not null check (stage in ('assets', 'segments', 'publish', 'other')),
  severity         text not null default 'high' check (severity in ('high', 'critical')),
  message          text not null check (char_length(message) <= 500),
  run_url          text check (run_url is null or char_length(run_url) <= 300),
  occurrences      integer not null default 1,
  acknowledged_by  uuid,
  acknowledged_at  timestamptz,
  unique (stage, event_day)
);
alter table public.ml_pipeline_events enable row level security;
revoke all on public.ml_pipeline_events from anon, authenticated;
comment on table public.ml_pipeline_events is
  'ML publish pipeline failures shown in the PMO Alerts section. RLS on, no policies or grants on purpose: written by ml_report_pipeline_failure (ml_publisher only), read/acknowledged via pmo_* RPCs. One row per stage per IST day; repeats bump occurrences.';

create or replace function public.ml_report_pipeline_failure(p_stage text, p_message text, p_run_url text default null)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_stage text := case when p_stage in ('assets', 'segments', 'publish') then p_stage else 'other' end;
  v_id    bigint;
begin
  insert into public.ml_pipeline_events (stage, message, run_url)
  values (v_stage, left(coalesce(nullif(btrim(p_message), ''), 'pipeline failed'), 500), left(p_run_url, 300))
  on conflict (stage, event_day) do update
    set occurrences  = public.ml_pipeline_events.occurrences + 1,
        last_seen_at = now(),
        message      = excluded.message,
        run_url      = coalesce(excluded.run_url, public.ml_pipeline_events.run_url)
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.pmo_list_pipeline_events(p_limit integer default 50)
 returns table (
   id bigint, created_at timestamptz, last_seen_at timestamptz, stage text, severity text,
   message text, run_url text, occurrences integer,
   acknowledged_at timestamptz, acknowledged_by_name text)
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
  select e.id, e.created_at, e.last_seen_at, e.stage, e.severity, e.message, e.run_url, e.occurrences,
         e.acknowledged_at, p.full_name
  from public.ml_pipeline_events e
  left join public.profiles p on p.id = e.acknowledged_by
  order by (e.acknowledged_at is null) desc, e.last_seen_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$function$;

create or replace function public.pmo_ack_pipeline_event(p_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if auth.uid() is null or not public.is_active_user() or not public.has_role('pmo') then
    raise exception 'PMO access required' using errcode = '42501';
  end if;

  update public.ml_pipeline_events
     set acknowledged_by = auth.uid(), acknowledged_at = now()
   where id = p_id and acknowledged_at is null;
  if not found then
    raise exception 'event not found or already acknowledged' using errcode = 'P0002';
  end if;
end;
$function$;

revoke all on function public.ml_report_pipeline_failure(text, text, text) from public, anon, authenticated;
revoke all on function public.pmo_list_pipeline_events(integer)            from public, anon;
revoke all on function public.pmo_ack_pipeline_event(bigint)               from public, anon;
grant execute on function public.ml_report_pipeline_failure(text, text, text) to ml_publisher;
grant execute on function public.pmo_list_pipeline_events(integer)            to authenticated;
grant execute on function public.pmo_ack_pipeline_event(bigint)               to authenticated;
