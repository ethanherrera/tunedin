-- Stage 5: current-visibility Friends activity and targeted Realtime refresh.
--
-- Feed rows are projections of concert_events, never a separately writable
-- activity model. Every read checks the concert's visibility and relationship
-- state at query time, so unfriend, block, and collaborator removal hide old
-- activity immediately.

alter table public.direct_collaboration_notifications
  add column first_activity_at timestamptz not null default now(),
  add column latest_activity_at timestamptz not null default now(),
  add column activity_count integer not null default 1 check (activity_count > 0),
  add column summary_due_at timestamptz not null default now();

create index direct_collaboration_notifications_aggregate
  on public.direct_collaboration_notifications (recipient_id, concert_id, delivered_at, latest_activity_at desc);
create index concert_events_feed_cursor on public.concert_events (occurred_at desc, id desc);

create or replace function private.enqueue_collaboration_notification(
  p_recipient_id uuid,
  p_actor_id uuid,
  p_concert_id uuid,
  p_kind text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id uuid;
begin
  if p_recipient_id = p_actor_id
    or private.has_relationship_block(p_recipient_id, p_actor_id)
  then
    return;
  end if;

  -- Serialize the recipient/concert pair so rapid edits produce a single
  -- five-minute summary job rather than an APNs burst.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_recipient_id::text || p_concert_id::text, 0)
  );

  select id
  into v_existing_id
  from public.direct_collaboration_notifications
  where recipient_id = p_recipient_id
    and concert_id = p_concert_id
    and delivered_at is null
    and latest_activity_at >= clock_timestamp() - interval '5 minutes'
  order by latest_activity_at desc
  limit 1
  for update;

  if found then
    update public.direct_collaboration_notifications
    set
      latest_activity_at = clock_timestamp(),
      activity_count = activity_count + 1,
      summary_due_at = clock_timestamp() + interval '5 minutes'
    where id = v_existing_id;
    return;
  end if;

  insert into public.direct_collaboration_notifications (
    recipient_id,
    actor_id,
    concert_id,
    kind,
    first_activity_at,
    latest_activity_at,
    summary_due_at
  )
  values (
    p_recipient_id,
    p_actor_id,
    p_concert_id,
    p_kind,
    clock_timestamp(),
    clock_timestamp(),
    clock_timestamp() + interval '5 minutes'
  );
end;
$$;

create or replace function public.profile_concert_history(
  p_profile_id uuid,
  p_search text default null,
  p_year integer default null,
  p_visibility public.concert_visibility default null,
  p_cursor_date date default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  owner_id uuid,
  venue_name text,
  city text,
  concert_date date,
  starts_at timestamptz,
  venue_time_zone text,
  tour text,
  visibility text,
  created_at timestamptz,
  updated_at timestamptz,
  last_activity_at timestamptz,
  primary_artist text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 30));
  v_search text := nullif(private.normalize_concert_text(coalesce(p_search, '')), '');
begin
  if not private.has_completed_profile(p_profile_id) then
    return;
  end if;

  if p_profile_id <> v_caller_id
    and not private.are_accepted_friends(v_caller_id, p_profile_id)
  then
    raise exception 'Only friends can view this concert history'
      using errcode = '42501';
  end if;

  return query
  select
    concert.id,
    concert.owner_id,
    concert.venue_name,
    concert.city,
    concert.concert_date,
    concert.starts_at,
    concert.venue_time_zone,
    concert.tour,
    concert.visibility::text,
    concert.created_at,
    concert.updated_at,
    concert.last_activity_at,
    artist.artist_name
  from public.concerts as concert
  join lateral (
    select artist_name
    from public.concert_artists
    where concert_id = concert.id and is_primary
    limit 1
  ) as artist on true
  where (
      concert.owner_id = p_profile_id
      or exists (
        select 1
        from public.concert_collaborators as collaborator
        where collaborator.concert_id = concert.id
          and collaborator.profile_id = p_profile_id
      )
    )
    and private.can_view_concert_as(v_caller_id, concert.id)
    and (p_year is null or extract(year from concert.concert_date)::integer = p_year)
    and (p_visibility is null or concert.visibility = p_visibility)
    and (
      v_search is null
      or concert.venue_name ilike '%' || v_search || '%'
      or coalesce(concert.city, '') ilike '%' || v_search || '%'
      or coalesce(concert.tour, '') ilike '%' || v_search || '%'
      or artist.artist_name ilike '%' || v_search || '%'
    )
    and (
      p_cursor_date is null
      or concert.concert_date < p_cursor_date
      or (concert.concert_date = p_cursor_date and concert.id < p_cursor_id)
    )
  order by concert.concert_date desc, concert.id desc
  limit v_limit;
end;
$$;

create function public.friends_activity_feed(
  p_cursor_occurred_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  concert_id uuid,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  event_type text,
  occurred_at timestamptz,
  primary_artist text,
  venue_name text,
  concert_date date
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 30));
begin
  return query
  select
    event.id,
    event.concert_id,
    event.actor_id,
    actor.username,
    actor.display_name,
    event.event_type::text,
    event.occurred_at,
    primary_artist.artist_name,
    concert.venue_name,
    concert.concert_date
  from public.concert_events as event
  join public.concerts as concert on concert.id = event.concert_id
  join public.profiles as actor on actor.id = event.actor_id
  join lateral (
    select lineup.artist_name
    from public.concert_artists as lineup
    where lineup.concert_id = concert.id and lineup.is_primary
    limit 1
  ) as primary_artist on true
  where private.are_accepted_friends(v_caller_id, event.actor_id)
    and private.can_view_concert_as(v_caller_id, concert.id)
    and private.can_view_concert_event_as(v_caller_id, concert.id, event.event_type)
    and (
      p_cursor_occurred_at is null
      or event.occurred_at < p_cursor_occurred_at
      or (event.occurred_at = p_cursor_occurred_at and event.id < p_cursor_id)
    )
  order by event.occurred_at desc, event.id desc
  limit v_limit;
end;
$$;

-- Realtime delivers only a signal. The app always refetches the permitted
-- concert, comment page, or feed slice through the normal RLS/RPC path.
alter table public.concerts replica identity full;
alter table public.concert_collaborators replica identity full;
alter table public.comments replica identity full;
alter table public.concert_events replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.concerts;
exception when duplicate_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.concert_collaborators;
exception when duplicate_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.comments;
exception when duplicate_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.concert_events;
exception when duplicate_object then null;
end;
$$;

revoke all on function public.friends_activity_feed(timestamptz, uuid, integer) from public, anon;
grant execute on function public.friends_activity_feed(timestamptz, uuid, integer) to authenticated;
