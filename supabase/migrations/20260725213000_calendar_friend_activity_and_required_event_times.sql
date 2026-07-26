-- Calendar beta: every concert has a concrete start instant, and friends can
-- retrieve a single privacy-filtered, de-duplicated calendar feed.

update public.catalog_events
set starts_at = (event_date + time '20:00:00') at time zone 'America/Los_Angeles',
    time_zone_identifier = 'America/Los_Angeles'
where starts_at is null;

alter table public.catalog_events
  alter column starts_at set not null;

alter table public.catalog_events
  drop constraint catalog_events_starts_on_event_date_check,
  add constraint catalog_events_starts_on_event_date_check check (
    (starts_at at time zone time_zone_identifier)::date = event_date
  );

create function public.list_catalog_friend_calendar(
  p_cursor jsonb default null,
  p_limit integer default 100
)
returns table (event jsonb)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  if p_cursor is not null then
    raise exception 'Friends calendar does not support cursors' using errcode = '22023';
  end if;
  if p_limit not between 1 and 100 then
    raise exception 'Friends calendar limit must be between 1 and 100' using errcode = '22023';
  end if;

  return query
  with visible_friend_events as (
    select distinct private.resolve_catalog_event_id(attendance.event_id) as event_id
    from public.catalog_event_attendance as attendance
    where attendance.profile_id <> v_caller_id
      and attendance.status in ('going', 'went')
      and attendance.superseded_by_attendance_id is null
      and private.are_accepted_friends(v_caller_id, attendance.profile_id)
      and private.can_read_catalog_event_history_attendance_as(
        v_caller_id,
        attendance.event_id,
        attendance.profile_id,
        attendance.audience
      )
  )
  select private.catalog_event_projection_json(visible_friend_events.event_id)
  from visible_friend_events
  join public.catalog_events as catalog_event on catalog_event.id = visible_friend_events.event_id
  where catalog_event.row_state = 'active'
    and private.catalog_event_projection_json(visible_friend_events.event_id) is not null
  order by catalog_event.starts_at asc, catalog_event.id asc
  limit p_limit;
end;
$$;

revoke all on function public.list_catalog_friend_calendar(jsonb, integer) from public, anon;
grant execute on function public.list_catalog_friend_calendar(jsonb, integer) to authenticated;
