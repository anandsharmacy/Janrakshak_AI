-- District Officer "Create Task": lets a district officer / control room list the field officers
-- they may assign to, and guards task inserts (creator, district, assignee).
-- Applied to cloud project sjcqwxthimfuxmrodsbs as migration `district_task_assignment`.

create or replace function public.get_assignable_field_officers()
returns table(user_id uuid, full_name text, officer_id text, district_name text)
language sql
stable
security definer
set search_path to 'public'
as $$
  select ur.user_id, p.full_name, p.officer_id, l.district
  from public.user_roles ur
  join public.profiles p on p.id = ur.user_id
  left join public.locations l on l.id = ur.district_id
  where ur.role = 'field_officer'
    and ur.is_active
    and p.is_active
    and public.is_active_user()
    and (
      public.has_role('control_room')
      or (public.has_role('district_officer')
          and ur.district_id is not null
          and ur.district_id = public.my_district_id())
    )
  order by p.full_name;
$$;

revoke all on function public.get_assignable_field_officers() from public, anon;
grant execute on function public.get_assignable_field_officers() to authenticated;

create or replace function public.enforce_task_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- Service-role / internal jobs have no auth.uid(); only user inserts are guarded.
  if auth.uid() is null then
    return new;
  end if;

  new.created_by := auth.uid();

  if public.has_role('district_officer') and not public.has_role('control_room') then
    new.district := public.my_district_name();
  end if;

  if new.assigned_to is not null then
    if not exists (
      select 1
      from public.user_roles ur
      join public.profiles p on p.id = ur.user_id
      where ur.user_id = new.assigned_to
        and ur.role = 'field_officer'
        and ur.is_active
        and p.is_active
        and (
          public.has_role('control_room')
          or (ur.district_id is not null and ur.district_id = public.my_district_id())
        )
    ) then
      raise exception 'Tasks can only be assigned to an active field officer in your district.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_task_insert() from public, anon, authenticated;

create trigger trg_tasks_enforce_insert
  before insert on public.tasks
  for each row execute function public.enforce_task_insert();
