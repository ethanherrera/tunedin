-- Phase 2: durable Going/Went state, audience-aware attendee discovery, and Plans.
--
-- Attendance is intentionally independent from a personal concert diary. A
-- person can keep a lightweight plan or Went history without publishing a
-- review, and changing an attendance audience never changes a diary audience.

create type public.catalog_event_attendance_status as enum (
  'going',
  'went',
  'did_not_go'
);
create type public.catalog_event_audience as enum (
  'private',
  'friends',
  'community'
);

create table public.catalog_event_attendance (
  event_id uuid not null references public.catalog_events (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  status public.catalog_event_attendance_status not null,
  audience public.catalog_event_audience not null default 'friends',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (event_id, profile_id)
);

create index catalog_event_attendance_event_visibility
  on public.catalog_event_attendance (event_id, audience, status, updated_at desc, profile_id);
create index catalog_event_attendance_profile_plans
  on public.catalog_event_attendance (profile_id, status, updated_at desc, event_id);

create table private.catalog_event_attendance_quota (
  singleton boolean primary key default true check (singleton),
  rolling_hour_limit integer not null check (rolling_hour_limit > 0),
  rolling_day_limit integer not null check (rolling_day_limit >= rolling_hour_limit)
);

insert into private.catalog_event_attendance_quota (
  singleton, rolling_hour_limit, rolling_day_limit
) values (true, 60, 500);

create table private.catalog_event_attendance_mutations (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  event_id uuid not null references public.catalog_events (id) on delete cascade,
  created_at timestamptz not null default clock_timestamp()
);

create index catalog_event_attendance_mutations_actor_window
  on private.catalog_event_attendance_mutations (profile_id, created_at desc);

create function private.touch_catalog_event_attendance()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.created_at := old.created_at;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger set_catalog_event_attendance_updated_at
before update on public.catalog_event_attendance
for each row execute function private.touch_catalog_event_attendance();

-- A person who already has a plan retains access if a creator later makes the
-- occurrence unlisted. This prevents a plan from becoming an unusable orphan.
create or replace function private.can_read_catalog_event_as(p_user_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_completed_profile(p_user_id)
    and exists (
      select 1
      from public.catalog_events as event
      where event.id = p_event_id
        and event.row_state = 'active'
        and (
          event.listing = 'listed'
          or event.created_by = p_user_id
          or exists (
            select 1
            from public.catalog_event_attendance as attendance
            where attendance.event_id = event.id
              and attendance.profile_id = p_user_id
          )
        )
    )
$$;

create function private.can_read_catalog_event_attendance_as(
  p_viewer_id uuid,
  p_event_id uuid,
  p_profile_id uuid,
  p_audience public.catalog_event_audience
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_read_catalog_event_as(p_viewer_id, p_event_id)
    and private.has_completed_profile(p_profile_id)
    and (
      p_viewer_id = p_profile_id
      or (
        not private.has_relationship_block(p_viewer_id, p_profile_id)
        and (
          p_audience = 'community'
          or (
            p_audience = 'friends'
            and private.are_accepted_friends(p_viewer_id, p_profile_id)
          )
        )
      )
    )
$$;

alter table public.catalog_event_attendance enable row level security;

create policy "catalog_event_attendance_select_allowed"
on public.catalog_event_attendance for select to authenticated
using (
  private.can_read_catalog_event_attendance_as(
    auth.uid(), event_id, profile_id, audience
  )
);

revoke all on table public.catalog_event_attendance from public, anon, authenticated;

create function private.consume_catalog_event_attendance_quota(
  p_profile_id uuid,
  p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hour_limit integer;
  v_day_limit integer;
  v_hour_count integer;
  v_day_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-event-attendance:' || p_profile_id::text, 0)
  );

  delete from private.catalog_event_attendance_mutations as mutation
  where mutation.profile_id = p_profile_id
    and mutation.created_at < clock_timestamp() - interval '24 hours';

  select quota.rolling_hour_limit, quota.rolling_day_limit
  into v_hour_limit, v_day_limit
  from private.catalog_event_attendance_quota as quota
  where quota.singleton;

  select
    count(*) filter (where mutation.created_at >= clock_timestamp() - interval '1 hour'),
    count(*)
  into v_hour_count, v_day_count
  from private.catalog_event_attendance_mutations as mutation
  where mutation.profile_id = p_profile_id
    and mutation.created_at >= clock_timestamp() - interval '24 hours';

  if v_hour_count >= v_hour_limit or v_day_count >= v_day_limit then
    raise exception 'You are changing concert plans too quickly. Try again later.'
      using errcode = 'P0001';
  end if;

  insert into private.catalog_event_attendance_mutations (profile_id, event_id)
  values (p_profile_id, p_event_id);
end;
$$;

create function public.set_catalog_event_attendance(
  p_event_id uuid,
  p_status public.catalog_event_attendance_status default null,
  p_audience public.catalog_event_audience default 'friends'
)
returns table (
  event_id uuid,
  status public.catalog_event_attendance_status,
  audience public.catalog_event_audience,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_event public.catalog_events%rowtype;
  v_previous_status public.catalog_event_attendance_status;
  v_previous_audience public.catalog_event_audience;
  v_attendance public.catalog_event_attendance%rowtype;
begin
  if v_event_id is null or not private.can_read_catalog_event_as(v_actor_id, v_event_id) then
    raise exception 'This event is unavailable'
      using errcode = '42501';
  end if;

  select source.* into v_event
  from public.catalog_events as source
  where source.id = v_event_id
  for update;

  if p_status = 'going' and (
    v_event.lifecycle in ('cancelled', 'completed')
    or v_event.memory_unlock_at <= clock_timestamp()
  ) then
    raise exception 'Going is available only before the concert'
      using errcode = '22023';
  end if;
  if p_status in ('went', 'did_not_go') and (
    v_event.lifecycle = 'cancelled'
    or (
      v_event.lifecycle <> 'completed'
      and v_event.memory_unlock_at > clock_timestamp()
    )
  ) then
    raise exception 'Went can be confirmed only after the concert'
      using errcode = '22023';
  end if;

  select attendance.status, attendance.audience
  into v_previous_status, v_previous_audience
  from public.catalog_event_attendance as attendance
  where attendance.event_id = v_event_id
    and attendance.profile_id = v_actor_id
  for update;

  if p_status is null then
    if v_previous_status is null then
      return query select v_event_id, null::public.catalog_event_attendance_status,
        null::public.catalog_event_audience, clock_timestamp();
      return;
    end if;

    perform private.consume_catalog_event_attendance_quota(v_actor_id, v_event_id);

    delete from public.catalog_event_attendance as attendance
    where attendance.event_id = v_event_id
      and attendance.profile_id = v_actor_id;

    return query select v_event_id, null::public.catalog_event_attendance_status,
      null::public.catalog_event_audience, clock_timestamp();
    return;
  end if;

  if p_status is not distinct from v_previous_status
    and p_audience is not distinct from v_previous_audience
  then
    return query
    select attendance.event_id, attendance.status, attendance.audience, attendance.updated_at
    from public.catalog_event_attendance as attendance
    where attendance.event_id = v_event_id
      and attendance.profile_id = v_actor_id;
    return;
  end if;

  perform private.consume_catalog_event_attendance_quota(v_actor_id, v_event_id);

  insert into public.catalog_event_attendance as attendance (
    event_id, profile_id, status, audience
  ) values (
    v_event_id, v_actor_id, p_status, p_audience
  )
  on conflict on constraint catalog_event_attendance_pkey do update
  set status = excluded.status,
      audience = excluded.audience
  returning attendance.* into v_attendance;

  update public.catalog_events as event
  set last_material_activity_at = clock_timestamp()
  where event.id = v_event_id;

  if p_status is distinct from v_previous_status and p_status in ('going', 'went') then
    insert into public.social_activity_events (actor_id, action, event_id, metadata)
    values (
      v_actor_id,
      case p_status
        when 'going' then 'marked_going'::public.social_activity_action
        else 'marked_went'::public.social_activity_action
      end,
      v_event_id,
      jsonb_build_object('audience', p_audience)
    );
  end if;

  return query select
    v_attendance.event_id,
    v_attendance.status,
    v_attendance.audience,
    v_attendance.updated_at;
end;
$$;

create function public.get_catalog_event_social_summaries(p_event_ids uuid[])
returns table (
  event_id uuid,
  current_user_status public.catalog_event_attendance_status,
  current_user_audience public.catalog_event_audience,
  friend_previews jsonb,
  community_going_count integer,
  community_went_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  if p_event_ids is null
    or cardinality(p_event_ids) not between 1 and 50
    or array_position(p_event_ids, null) is not null
  then
    raise exception 'Event summary IDs must contain between 1 and 50 events'
      using errcode = '22023';
  end if;

  return query
  select
    requested.event_id,
    own.status,
    own.audience,
    coalesce(previews.items, '[]'::jsonb),
    coalesce(community.going_count, 0)::integer,
    coalesce(community.went_count, 0)::integer
  from (
    select distinct requested_id as event_id
    from unnest(p_event_ids) as requested_id
  ) as requested
  left join public.catalog_event_attendance as own
    on own.event_id = requested.event_id and own.profile_id = v_caller_id
  left join lateral (
    select jsonb_agg(candidate.item order by candidate.updated_at desc, candidate.profile_id) as items
    from (
      select
        attendance.profile_id,
        attendance.updated_at,
        jsonb_build_object(
          'profile_id', profile.id,
          'username', profile.username,
          'display_name', profile.display_name,
          'relationship', 'friends',
          'avatar_object_path', profile.avatar_object_path,
          'avatar_version', profile.avatar_version,
          'status', attendance.status
        ) as item
      from public.catalog_event_attendance as attendance
      join public.profiles as profile on profile.id = attendance.profile_id
      where attendance.event_id = requested.event_id
        and attendance.profile_id <> v_caller_id
        and attendance.status in ('going', 'went')
        and private.are_accepted_friends(v_caller_id, attendance.profile_id)
        and private.can_read_catalog_event_attendance_as(
          v_caller_id, requested.event_id, attendance.profile_id, attendance.audience
        )
      order by attendance.updated_at desc, attendance.profile_id
      limit 3
    ) as candidate
  ) as previews on true
  left join lateral (
    select
      count(*) filter (where attendance.status = 'going') as going_count,
      count(*) filter (where attendance.status = 'went') as went_count
    from public.catalog_event_attendance as attendance
    where attendance.event_id = requested.event_id
      and attendance.audience = 'community'
      and attendance.status in ('going', 'went')
      and private.can_read_catalog_event_attendance_as(
        v_caller_id, requested.event_id, attendance.profile_id, attendance.audience
      )
  ) as community on true
  where private.can_read_catalog_event_as(v_caller_id, requested.event_id)
  order by requested.event_id;
end;
$$;

create function public.list_catalog_event_attendees(
  p_event_id uuid,
  p_scope text default 'all',
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  username text,
  display_name text,
  relationship text,
  avatar_object_path text,
  avatar_version bigint,
  status public.catalog_event_attendance_status,
  audience public.catalog_event_audience,
  updated_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_cursor_updated_at timestamptz;
  v_cursor_profile_id uuid;
begin
  if v_event_id is null or not private.can_read_catalog_event_as(v_caller_id, v_event_id) then
    raise exception 'This event is unavailable'
      using errcode = '42501';
  end if;
  if p_scope not in ('all', 'friends', 'community') then
    raise exception 'Attendee scope is invalid'
      using errcode = '22023';
  end if;
  if p_limit not between 1 and 50 then
    raise exception 'Attendee limit must be between 1 and 50'
      using errcode = '22023';
  end if;

  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'updated_at' - 'profile_id') <> '{}'::jsonb
      or not (p_cursor ?& array['updated_at', 'profile_id'])
    then
      raise exception 'Attendee cursor is invalid'
        using errcode = '22023';
    end if;
    begin
      v_cursor_updated_at := (p_cursor ->> 'updated_at')::timestamptz;
      v_cursor_profile_id := (p_cursor ->> 'profile_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Attendee cursor is invalid'
        using errcode = '22023';
    end;
  end if;

  return query
  select
    profile.id,
    profile.username,
    profile.display_name,
    private.relationship_label(v_caller_id, profile.id),
    profile.avatar_object_path,
    profile.avatar_version,
    attendance.status,
    attendance.audience,
    attendance.updated_at,
    jsonb_build_object(
      'updated_at', attendance.updated_at,
      'profile_id', profile.id
    )
  from public.catalog_event_attendance as attendance
  join public.profiles as profile on profile.id = attendance.profile_id
  where attendance.event_id = v_event_id
    and attendance.status in ('going', 'went')
    and private.can_read_catalog_event_attendance_as(
      v_caller_id, v_event_id, attendance.profile_id, attendance.audience
    )
    and (
      p_scope = 'all'
      or (
        p_scope = 'friends'
        and private.are_accepted_friends(v_caller_id, attendance.profile_id)
      )
      or (
        p_scope = 'community'
        and attendance.audience = 'community'
        and not private.are_accepted_friends(v_caller_id, attendance.profile_id)
        and attendance.profile_id <> v_caller_id
      )
    )
    and (
      p_cursor is null
      or attendance.updated_at < v_cursor_updated_at
      or (
        attendance.updated_at = v_cursor_updated_at
        and attendance.profile_id > v_cursor_profile_id
      )
    )
  order by attendance.updated_at desc, attendance.profile_id
  limit p_limit;
end;
$$;

create function public.list_my_catalog_event_plans(
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns table (
  event_id uuid,
  artists jsonb,
  catalog_place_id uuid,
  catalog_area_id uuid,
  catalog_tour_id uuid,
  venue_name text,
  area_name text,
  tour_name text,
  event_date date,
  starts_at timestamptz,
  time_zone_identifier text,
  memory_unlock_at timestamptz,
  lifecycle public.catalog_event_lifecycle,
  listing public.catalog_event_listing,
  integrity public.catalog_event_integrity,
  row_state public.catalog_event_row_state,
  source_label text,
  version integer,
  created_at timestamptz,
  updated_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_cursor_bucket integer;
  v_cursor_date_key integer;
  v_cursor_event_id uuid;
begin
  if p_limit not between 1 and 50 then
    raise exception 'Plans limit must be between 1 and 50'
      using errcode = '22023';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'bucket' - 'date_key' - 'event_id') <> '{}'::jsonb
      or not (p_cursor ?& array['bucket', 'date_key', 'event_id'])
    then
      raise exception 'Plans cursor is invalid'
        using errcode = '22023';
    end if;
    begin
      v_cursor_bucket := (p_cursor ->> 'bucket')::integer;
      v_cursor_date_key := (p_cursor ->> 'date_key')::integer;
      v_cursor_event_id := (p_cursor ->> 'event_id')::uuid;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Plans cursor is invalid'
        using errcode = '22023';
    end;
  end if;

  return query
  with ranked as (
    select
      projection.*,
      case when projection.event_date >= current_date then 0 else 1 end as sort_bucket,
      case
        when projection.event_date >= current_date
          then projection.event_date - date '2000-01-01'
        else -(projection.event_date - date '2000-01-01')
      end as sort_date_key
    from public.catalog_event_attendance as attendance
    join private.catalog_event_projections as projection
      on projection.event_id = attendance.event_id
    where attendance.profile_id = v_caller_id
      and attendance.status in ('going', 'went')
      and projection.row_state = 'active'
      and private.can_read_catalog_event_as(v_caller_id, projection.event_id)
  ), page as (
    select ranked.*
    from ranked
    where p_cursor is null
      or ranked.sort_bucket > v_cursor_bucket
      or (
        ranked.sort_bucket = v_cursor_bucket
        and ranked.sort_date_key > v_cursor_date_key
      )
      or (
        ranked.sort_bucket = v_cursor_bucket
        and ranked.sort_date_key = v_cursor_date_key
        and ranked.event_id > v_cursor_event_id
      )
    order by ranked.sort_bucket, ranked.sort_date_key, ranked.event_id
    limit p_limit
  )
  select
    page.event_id,
    page.artists,
    page.catalog_place_id,
    page.catalog_area_id,
    page.catalog_tour_id,
    page.venue_name,
    page.area_name,
    page.tour_name,
    page.event_date,
    page.starts_at,
    page.time_zone_identifier,
    page.memory_unlock_at,
    page.lifecycle,
    page.listing,
    page.integrity,
    page.row_state,
    'Community added'::text,
    page.version,
    page.created_at,
    page.updated_at,
    jsonb_build_object(
      'bucket', page.sort_bucket,
      'date_key', page.sort_date_key,
      'event_id', page.event_id
    )
  from page
  order by page.sort_bucket, page.sort_date_key, page.event_id;
end;
$$;

revoke all on function private.touch_catalog_event_attendance() from public;
revoke all on table private.catalog_event_attendance_quota
  from public, anon, authenticated;
revoke all on table private.catalog_event_attendance_mutations
  from public, anon, authenticated;
revoke all on function private.consume_catalog_event_attendance_quota(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.can_read_catalog_event_attendance_as(
  uuid, uuid, uuid, public.catalog_event_audience
) from public, anon, authenticated;

revoke all on function public.set_catalog_event_attendance(
  uuid, public.catalog_event_attendance_status, public.catalog_event_audience
) from public, anon;
revoke all on function public.get_catalog_event_social_summaries(uuid[]) from public, anon;
revoke all on function public.list_catalog_event_attendees(uuid, text, jsonb, integer) from public, anon;
revoke all on function public.list_my_catalog_event_plans(jsonb, integer) from public, anon;

grant execute on function public.set_catalog_event_attendance(
  uuid, public.catalog_event_attendance_status, public.catalog_event_audience
) to authenticated;
grant execute on function public.get_catalog_event_social_summaries(uuid[]) to authenticated;
grant execute on function public.list_catalog_event_attendees(uuid, text, jsonb, integer)
  to authenticated;
grant execute on function public.list_my_catalog_event_plans(jsonb, integer) to authenticated;

revoke all on type public.catalog_event_attendance_status from anon;
revoke all on type public.catalog_event_audience from anon;
