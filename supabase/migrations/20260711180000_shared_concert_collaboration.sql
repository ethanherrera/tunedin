-- Stage 4: shared concerts.
--
-- Collaborative changes are exposed only through hardened transactional RPCs.
-- The helpers in this migration intentionally centralize current-access checks so
-- removing a friend, blocking someone, or removing an editor revokes reads at
-- query time without leaving behind a private fork.

alter table public.concerts
  add column version bigint not null default 1,
  add constraint concerts_version_positive_check check (version > 0);

alter table public.concert_events
  -- Subject IDs may point to either a profile (tag/transfer) or a comment.
  -- They remain opaque, never user content, and are intentionally not a
  -- polymorphic foreign key.
  add column subject_id uuid,
  add column metadata jsonb not null default '{}'::jsonb,
  add constraint concert_events_metadata_object_check check (jsonb_typeof(metadata) = 'object');

create table public.concert_collaborators (
  concert_id uuid not null references public.concerts (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  tagged_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (concert_id, profile_id)
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  concert_id uuid not null references public.concerts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint comments_body_state_check check (
    (deleted_at is null and private.is_normalized_concert_text(body, 1000))
    or (deleted_at is not null and body is null)
  )
);

-- This is an internal outbox for a later APNs Edge Function. It records only
-- opaque IDs and an action type; it never stores concert, setlist, or comment
-- text. The mobile app has no direct access to it.
create table public.direct_collaboration_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  concert_id uuid not null references public.concerts (id) on delete cascade,
  kind text not null check (
    kind in ('collaborator_tagged', 'concert_updated', 'comment_added', 'ownership_transferred')
  ),
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);

create index concert_collaborators_profile on public.concert_collaborators (profile_id, concert_id);
create index comments_concert_cursor on public.comments (concert_id, created_at desc, id desc);
create index comments_author_rate_limit on public.comments (author_id, created_at desc);
create index direct_collaboration_notifications_delivery
  on public.direct_collaboration_notifications (recipient_id, delivered_at, created_at);
create index concert_events_actor_activity on public.concert_events (actor_id, occurred_at desc, id desc);

create or replace function private.touch_concert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- A comment only advances the activity timestamp. Content, permissions, and
  -- ownership changes advance the optimistic-concurrency version.
  if new.updated_at is not distinct from old.updated_at
    and new.owner_id is not distinct from old.owner_id
    and new.venue_name is not distinct from old.venue_name
    and new.city is not distinct from old.city
    and new.concert_date is not distinct from old.concert_date
    and new.starts_at is not distinct from old.starts_at
    and new.venue_time_zone is not distinct from old.venue_time_zone
    and new.tour is not distinct from old.tour
    and new.visibility is not distinct from old.visibility
  then
    new.updated_at := old.updated_at;
    new.version := old.version;
  else
    new.updated_at := clock_timestamp();
    new.last_activity_at := clock_timestamp();
    new.version := old.version + 1;
  end if;

  return new;
end;
$$;

create function private.touch_comment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create function private.touch_concert_collaborator()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger set_comment_timestamps
before update on public.comments
for each row execute function private.touch_comment();

create trigger set_concert_collaborator_timestamps
before update on public.concert_collaborators
for each row execute function private.touch_concert_collaborator();

create function private.is_concert_editor_as(p_user_id uuid, p_concert_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.concerts as concert
    where concert.id = p_concert_id
      and (
        concert.owner_id = p_user_id
        or exists (
          select 1
          from public.concert_collaborators as collaborator
          where collaborator.concert_id = concert.id
            and collaborator.profile_id = p_user_id
        )
      )
  );
$$;

create function private.can_view_concert_as(p_user_id uuid, p_concert_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_concert_editor_as(p_user_id, p_concert_id)
    or exists (
      select 1
      from public.concerts as concert
      where concert.id = p_concert_id
        and concert.visibility = 'friends'
        and private.are_accepted_friends(concert.owner_id, p_user_id)
    );
$$;

create or replace function private.can_view_concert(p_concert_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_view_concert_as(auth.uid(), p_concert_id);
$$;

create function private.can_view_concert_event_as(
  p_user_id uuid,
  p_concert_id uuid,
  p_event_type public.concert_event_type
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_concert_editor_as(p_user_id, p_concert_id)
    or (
      private.can_view_concert_as(p_user_id, p_concert_id)
      and p_event_type in (
        'concert_created',
        'concert_updated',
        'setlist_updated',
        'comment_added',
        'comment_updated',
        'comment_deleted'
      )
    );
$$;

create function private.require_concert_editor(p_concert_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
begin
  if not private.is_concert_editor_as(v_actor_id, p_concert_id) then
    raise exception 'You no longer have permission to edit this concert'
      using errcode = '42501';
  end if;

  return v_actor_id;
end;
$$;

create function private.require_concert_owner(p_concert_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
begin
  if not exists (
    select 1
    from public.concerts
    where id = p_concert_id
      and owner_id = v_actor_id
  ) then
    raise exception 'Only the concert owner can do that'
      using errcode = '42501';
  end if;

  return v_actor_id;
end;
$$;

create function private.assert_expected_concert_version(
  p_concert public.concerts,
  p_expected_version bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_expected_version is null or p_concert.version <> p_expected_version then
    raise exception 'This concert changed elsewhere. Refresh and try again.'
      using errcode = '40001';
  end if;
end;
$$;

create function private.touch_concert_activity(p_concert_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.concerts
  set last_activity_at = clock_timestamp()
  where id = p_concert_id;
$$;

create function private.bump_concert_version(p_concert_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.concerts
  set updated_at = clock_timestamp(), last_activity_at = clock_timestamp()
  where id = p_concert_id;
$$;

create function private.validate_concert_payload(
  p_artists jsonb,
  p_setlist jsonb
)
returns table (
  artists jsonb,
  setlist jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_artist jsonb;
  v_setlist_item jsonb;
  v_position integer;
  v_primary_count integer := 0;
  v_artists jsonb := '[]'::jsonb;
  v_setlist jsonb := '[]'::jsonb;
  v_artist_name text;
  v_song_title text;
begin
  if p_artists is null or jsonb_typeof(p_artists) <> 'array'
    or jsonb_array_length(p_artists) not between 1 and 10
  then
    raise exception 'Concerts require between 1 and 10 artists'
      using errcode = '22023';
  end if;

  if p_setlist is null or jsonb_typeof(p_setlist) <> 'array'
    or jsonb_array_length(p_setlist) > 50
  then
    raise exception 'Concerts may have no more than 50 setlist entries'
      using errcode = '22023';
  end if;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(p_artists) with ordinality as item(value, ordinality)
  loop
    if jsonb_typeof(v_artist) <> 'object'
      or not (v_artist ? 'name')
      or not (v_artist ? 'is_primary')
      or jsonb_typeof(v_artist -> 'name') <> 'string'
      or jsonb_typeof(v_artist -> 'is_primary') <> 'boolean'
      or (v_artist - 'name' - 'is_primary') <> '{}'::jsonb
    then
      raise exception 'Every artist must contain only name and is_primary fields'
        using errcode = '22023';
    end if;

    v_artist_name := private.require_concert_text(v_artist ->> 'name', 160, 'Artist name');
    v_primary_count := v_primary_count + case when (v_artist ->> 'is_primary')::boolean then 1 else 0 end;
    v_artists := v_artists || jsonb_build_array(
      jsonb_build_object('name', v_artist_name, 'is_primary', (v_artist ->> 'is_primary')::boolean)
    );
  end loop;

  if v_primary_count <> 1 then
    raise exception 'Concerts require exactly one primary artist'
      using errcode = '22023';
  end if;

  for v_setlist_item, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(p_setlist) with ordinality as item(value, ordinality)
  loop
    if jsonb_typeof(v_setlist_item) <> 'string' then
      raise exception 'Every setlist entry must be a string'
        using errcode = '22023';
    end if;

    v_song_title := private.require_concert_text(v_setlist_item #>> '{}', 160, 'Song title');
    v_setlist := v_setlist || to_jsonb(v_song_title);
  end loop;

  return query select v_artists, v_setlist;
end;
$$;

create function private.record_concert_event(
  p_concert_id uuid,
  p_actor_id uuid,
  p_event_type public.concert_event_type,
  p_subject_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  if jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Event metadata must be an object'
      using errcode = '22023';
  end if;

  if p_metadata ?| array['body', 'comment', 'comment_text', 'song_title', 'setlist', 'photo_url'] then
    raise exception 'Event metadata cannot include user content'
      using errcode = '22023';
  end if;

  insert into public.concert_events (concert_id, actor_id, event_type, subject_id, metadata)
  values (p_concert_id, p_actor_id, p_event_type, p_subject_id, p_metadata)
  returning id into v_event_id;

  return v_event_id;
end;
$$;

create function private.enqueue_collaboration_notification(
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
begin
  if p_recipient_id = p_actor_id
    or private.has_relationship_block(p_recipient_id, p_actor_id)
  then
    return;
  end if;

  insert into public.direct_collaboration_notifications (
    recipient_id,
    actor_id,
    concert_id,
    kind
  )
  values (p_recipient_id, p_actor_id, p_concert_id, p_kind);
end;
$$;

create function private.notify_concert_editors(
  p_concert_id uuid,
  p_actor_id uuid,
  p_kind text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient_id uuid;
begin
  for v_recipient_id in
    select owner_id
    from public.concerts
    where id = p_concert_id
    union
    select profile_id
    from public.concert_collaborators
    where concert_id = p_concert_id
  loop
    perform private.enqueue_collaboration_notification(
      v_recipient_id,
      p_actor_id,
      p_concert_id,
      p_kind
    );
  end loop;
end;
$$;

create function private.assert_comment_rate_limit(p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recent_count integer;
  v_latest_at timestamptz;
begin
  select count(*), max(created_at)
  into v_recent_count, v_latest_at
  from public.comments
  where author_id = p_actor_id
    and created_at >= now() - interval '24 hours';

  if v_recent_count >= 100 then
    raise exception 'You have reached the comment limit for today'
      using errcode = 'P0001';
  end if;

  if v_latest_at is not null and v_latest_at > clock_timestamp() - interval '2 seconds' then
    raise exception 'Wait a moment before posting another comment'
      using errcode = 'P0001';
  end if;
end;
$$;

create function public.list_concert_collaborators(p_concert_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  is_owner boolean,
  tagged_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_concert_editor(p_concert_id);
begin
  return query
  select
    profile.id,
    profile.username,
    profile.display_name,
    profile.id = concert.owner_id as is_owner,
    case when profile.id = concert.owner_id then concert.created_at else collaborator.created_at end as tagged_at
  from public.concerts as concert
  join public.profiles as profile on profile.id = concert.owner_id
  left join public.concert_collaborators as collaborator
    on collaborator.concert_id = concert.id
    and collaborator.profile_id = profile.id
  where concert.id = p_concert_id

  union all

  select
    profile.id,
    profile.username,
    profile.display_name,
    false as is_owner,
    collaborator.created_at as tagged_at
  from public.concert_collaborators as collaborator
  join public.profiles as profile on profile.id = collaborator.profile_id
  where collaborator.concert_id = p_concert_id
  order by is_owner desc, tagged_at asc;
end;
$$;

create function public.update_concert(
  p_concert_id uuid,
  p_expected_version bigint,
  p_artists jsonb,
  p_venue_name text,
  p_concert_date date,
  p_city text default null,
  p_tour text default null,
  p_starts_at timestamptz default null,
  p_venue_time_zone text default null,
  p_setlist jsonb default '[]'::jsonb,
  p_visibility public.concert_visibility default 'private'
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_concert_editor(p_concert_id);
  v_concert public.concerts%rowtype;
  v_venue_name text;
  v_city text;
  v_tour text;
  v_time_zone text;
  v_artists jsonb;
  v_setlist jsonb;
  v_current_artists jsonb;
  v_current_setlist jsonb;
  v_changed_fields text[] := '{}';
  v_event_type public.concert_event_type;
  v_artist jsonb;
  v_song_title jsonb;
  v_position integer;
begin
  select *
  into v_concert
  from public.concerts
  where id = p_concert_id
  for update;

  if not found then
    raise exception 'That concert is no longer available'
      using errcode = 'P0001';
  end if;

  perform private.assert_expected_concert_version(v_concert, p_expected_version);

  if p_concert_date is null then
    raise exception 'Concert date is required'
      using errcode = '22023';
  end if;

  if (p_starts_at is null) <> (p_venue_time_zone is null) then
    raise exception 'Start time and venue time zone must be provided together'
      using errcode = '22023';
  end if;

  v_venue_name := private.require_concert_text(p_venue_name, 160, 'Venue name');
  v_city := private.optional_concert_text(p_city, 100, 'City');
  v_tour := private.optional_concert_text(p_tour, 160, 'Tour');
  v_time_zone := p_venue_time_zone;

  if v_time_zone is not null and (
    private.contains_control_characters(v_time_zone)
    or v_time_zone <> btrim(v_time_zone)
    or not private.is_iana_time_zone(v_time_zone)
  ) then
    raise exception 'Venue time zone must be a valid IANA time-zone identifier'
      using errcode = '22023';
  end if;

  select artists, setlist
  into v_artists, v_setlist
  from private.validate_concert_payload(p_artists, p_setlist);

  select coalesce(
    jsonb_agg(
      jsonb_build_object('name', artist_name, 'is_primary', is_primary)
      order by lineup_position
    ),
    '[]'::jsonb
  )
  into v_current_artists
  from public.concert_artists
  where concert_id = p_concert_id;

  select coalesce(jsonb_agg(song_title order by set_position), '[]'::jsonb)
  into v_current_setlist
  from public.setlist_items
  where concert_id = p_concert_id;

  if v_concert.venue_name is distinct from v_venue_name then
    v_changed_fields := array_append(v_changed_fields, 'venue');
  end if;
  if v_concert.city is distinct from v_city then
    v_changed_fields := array_append(v_changed_fields, 'city');
  end if;
  if v_concert.concert_date is distinct from p_concert_date then
    v_changed_fields := array_append(v_changed_fields, 'date');
  end if;
  if v_concert.starts_at is distinct from p_starts_at then
    v_changed_fields := array_append(v_changed_fields, 'start_time');
  end if;
  if v_concert.venue_time_zone is distinct from v_time_zone then
    v_changed_fields := array_append(v_changed_fields, 'time_zone');
  end if;
  if v_concert.tour is distinct from v_tour then
    v_changed_fields := array_append(v_changed_fields, 'tour');
  end if;
  if v_concert.visibility is distinct from p_visibility then
    v_changed_fields := array_append(v_changed_fields, 'visibility');
  end if;
  if v_current_artists is distinct from v_artists then
    v_changed_fields := array_append(v_changed_fields, 'lineup');
  end if;
  if v_current_setlist is distinct from v_setlist then
    v_changed_fields := array_append(v_changed_fields, 'setlist');
  end if;

  if cardinality(v_changed_fields) = 0 then
    return v_concert;
  end if;

  if v_concert.visibility <> 'private' and p_visibility = 'private' then
    raise exception 'Shared concerts cannot be made Private. Transfer ownership or delete it instead.'
      using errcode = '22023';
  end if;

  update public.concerts
  set
    venue_name = v_venue_name,
    city = v_city,
    concert_date = p_concert_date,
    starts_at = p_starts_at,
    venue_time_zone = v_time_zone,
    tour = v_tour,
    visibility = p_visibility,
    updated_at = clock_timestamp()
  where id = p_concert_id
  returning * into v_concert;

  if 'lineup' = any(v_changed_fields) then
    delete from public.concert_artists where concert_id = p_concert_id;
    for v_artist, v_position in
      select item.value, item.ordinality::integer
      from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
    loop
      insert into public.concert_artists (concert_id, lineup_position, artist_name, is_primary)
      values (
        p_concert_id,
        v_position,
        v_artist ->> 'name',
        (v_artist ->> 'is_primary')::boolean
      );
    end loop;
  end if;

  if 'setlist' = any(v_changed_fields) then
    delete from public.setlist_items where concert_id = p_concert_id;
    for v_song_title, v_position in
      select item.value, item.ordinality::integer
      from jsonb_array_elements(v_setlist) with ordinality as item(value, ordinality)
    loop
      insert into public.setlist_items (concert_id, set_position, song_title)
      values (p_concert_id, v_position, v_song_title #>> '{}');
    end loop;
  end if;

  v_event_type := case
    when v_changed_fields = array['setlist'] then 'setlist_updated'::public.concert_event_type
    when v_changed_fields = array['visibility'] then 'visibility_changed'::public.concert_event_type
    else 'concert_updated'::public.concert_event_type
  end;

  perform private.record_concert_event(
    p_concert_id,
    v_actor_id,
    v_event_type,
    null,
    jsonb_build_object('changed_fields', to_jsonb(v_changed_fields))
  );
  perform private.notify_concert_editors(p_concert_id, v_actor_id, 'concert_updated');

  return v_concert;
end;
$$;

create function public.tag_concert_collaborator(
  p_concert_id uuid,
  p_profile_id uuid,
  p_expected_version bigint
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_concert_editor(p_concert_id);
  v_concert public.concerts%rowtype;
begin
  if p_profile_id is null or p_profile_id = v_actor_id then
    raise exception 'Choose a friend other than yourself'
      using errcode = '22023';
  end if;

  select *
  into v_concert
  from public.concerts
  where id = p_concert_id
  for update;

  if not found then
    raise exception 'That concert is no longer available'
      using errcode = 'P0001';
  end if;

  perform private.assert_expected_concert_version(v_concert, p_expected_version);

  if v_concert.visibility = 'private' then
    raise exception 'Choose Collaborators or Friends before tagging someone'
      using errcode = '22023';
  end if;

  if p_profile_id = v_concert.owner_id then
    raise exception 'The owner is already part of this concert'
      using errcode = '22023';
  end if;

  if not private.has_completed_profile(p_profile_id)
    or not private.are_accepted_friends(v_actor_id, p_profile_id)
    or private.has_relationship_block(v_concert.owner_id, p_profile_id)
  then
    raise exception 'Only an available friend can be tagged'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.concert_collaborators
    where concert_id = p_concert_id and profile_id = p_profile_id
  ) then
    return v_concert;
  end if;

  insert into public.concert_collaborators (concert_id, profile_id, tagged_by)
  values (p_concert_id, p_profile_id, v_actor_id);
  perform private.bump_concert_version(p_concert_id);

  select * into v_concert from public.concerts where id = p_concert_id;
  perform private.record_concert_event(
    p_concert_id,
    v_actor_id,
    'collaborator_tagged',
    p_profile_id
  );
  perform private.enqueue_collaboration_notification(
    p_profile_id,
    v_actor_id,
    p_concert_id,
    'collaborator_tagged'
  );

  return v_concert;
end;
$$;

create function public.remove_concert_collaborator(
  p_concert_id uuid,
  p_profile_id uuid,
  p_expected_version bigint
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_concert_owner(p_concert_id);
  v_concert public.concerts%rowtype;
begin
  select *
  into v_concert
  from public.concerts
  where id = p_concert_id
  for update;

  perform private.assert_expected_concert_version(v_concert, p_expected_version);

  delete from public.concert_collaborators
  where concert_id = p_concert_id and profile_id = p_profile_id;

  if not found then
    raise exception 'That collaborator is no longer on this concert'
      using errcode = 'P0001';
  end if;

  perform private.bump_concert_version(p_concert_id);
  select * into v_concert from public.concerts where id = p_concert_id;
  perform private.record_concert_event(
    p_concert_id,
    v_actor_id,
    'collaborator_removed',
    p_profile_id
  );

  return v_concert;
end;
$$;

create function public.transfer_concert_ownership(
  p_concert_id uuid,
  p_new_owner_id uuid,
  p_expected_version bigint
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_concert_owner(p_concert_id);
  v_concert public.concerts%rowtype;
  v_recent_transfers integer;
begin
  select count(*)
  into v_recent_transfers
  from public.concert_events
  where actor_id = v_actor_id
    and event_type = 'ownership_transferred'
    and occurred_at >= now() - interval '24 hours';

  if v_recent_transfers >= 20 then
    raise exception 'You have reached the ownership-transfer limit for today'
      using errcode = 'P0001';
  end if;

  select *
  into v_concert
  from public.concerts
  where id = p_concert_id
  for update;

  perform private.assert_expected_concert_version(v_concert, p_expected_version);

  if not exists (
    select 1
    from public.concert_collaborators
    where concert_id = p_concert_id and profile_id = p_new_owner_id
  ) then
    raise exception 'Choose an existing tagged collaborator as the new owner'
      using errcode = '22023';
  end if;

  delete from public.concert_collaborators
  where concert_id = p_concert_id and profile_id = p_new_owner_id;

  insert into public.concert_collaborators (concert_id, profile_id, tagged_by)
  values (p_concert_id, v_actor_id, v_actor_id)
  on conflict (concert_id, profile_id) do nothing;

  update public.concerts
  set owner_id = p_new_owner_id, updated_at = clock_timestamp()
  where id = p_concert_id
  returning * into v_concert;

  perform private.record_concert_event(
    p_concert_id,
    v_actor_id,
    'ownership_transferred',
    p_new_owner_id
  );
  perform private.enqueue_collaboration_notification(
    p_new_owner_id,
    v_actor_id,
    p_concert_id,
    'ownership_transferred'
  );

  return v_concert;
end;
$$;

create function public.delete_concert(p_concert_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_concert_owner(p_concert_id);

  delete from public.concerts where id = p_concert_id;

  if not found then
    raise exception 'That concert is no longer available'
      using errcode = 'P0001';
  end if;
end;
$$;

create function public.list_concert_comments(
  p_concert_id uuid,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  concert_id uuid,
  author_id uuid,
  username text,
  display_name text,
  body text,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 30));
begin
  if not private.can_view_concert_as(v_caller_id, p_concert_id) then
    raise exception 'You no longer have access to this concert'
      using errcode = '42501';
  end if;

  return query
  select
    comment.id,
    comment.concert_id,
    comment.author_id,
    profile.username,
    profile.display_name,
    comment.body,
    comment.created_at,
    comment.updated_at,
    comment.deleted_at
  from public.comments as comment
  join public.profiles as profile on profile.id = comment.author_id
  where comment.concert_id = p_concert_id
    and (
      p_cursor_created_at is null
      or comment.created_at < p_cursor_created_at
      or (comment.created_at = p_cursor_created_at and comment.id < p_cursor_id)
    )
  order by comment.created_at desc, comment.id desc
  limit v_limit;
end;
$$;

create function public.create_concert_comment(
  p_concert_id uuid,
  p_body text
)
returns public.comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_comment public.comments%rowtype;
  v_body text := private.require_concert_text(p_body, 1000, 'Comment');
begin
  if not private.can_view_concert_as(v_actor_id, p_concert_id) then
    raise exception 'You no longer have access to this concert'
      using errcode = '42501';
  end if;

  perform private.assert_comment_rate_limit(v_actor_id);

  insert into public.comments (concert_id, author_id, body)
  values (p_concert_id, v_actor_id, v_body)
  returning * into v_comment;

  perform private.touch_concert_activity(p_concert_id);
  perform private.record_concert_event(p_concert_id, v_actor_id, 'comment_added', v_comment.id);
  perform private.notify_concert_editors(p_concert_id, v_actor_id, 'comment_added');

  return v_comment;
end;
$$;

create function public.update_concert_comment(
  p_comment_id uuid,
  p_body text
)
returns public.comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_comment public.comments%rowtype;
  v_body text := private.require_concert_text(p_body, 1000, 'Comment');
begin
  select *
  into v_comment
  from public.comments
  where id = p_comment_id
  for update;

  if not found or v_comment.author_id <> v_actor_id or v_comment.deleted_at is not null then
    raise exception 'Only the comment author can edit this comment'
      using errcode = '42501';
  end if;

  if not private.can_view_concert_as(v_actor_id, v_comment.concert_id) then
    raise exception 'You no longer have access to this concert'
      using errcode = '42501';
  end if;

  update public.comments
  set body = v_body
  where id = p_comment_id
  returning * into v_comment;

  perform private.touch_concert_activity(v_comment.concert_id);
  perform private.record_concert_event(v_comment.concert_id, v_actor_id, 'comment_updated', v_comment.id);

  return v_comment;
end;
$$;

create function public.delete_concert_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_comment public.comments%rowtype;
begin
  select *
  into v_comment
  from public.comments
  where id = p_comment_id
  for update;

  if not found or v_comment.author_id <> v_actor_id or v_comment.deleted_at is not null then
    raise exception 'Only the comment author can delete this comment'
      using errcode = '42501';
  end if;

  if not private.can_view_concert_as(v_actor_id, v_comment.concert_id) then
    raise exception 'You no longer have access to this concert'
      using errcode = '42501';
  end if;

  update public.comments
  set body = null, deleted_at = clock_timestamp()
  where id = p_comment_id;

  perform private.touch_concert_activity(v_comment.concert_id);
  perform private.record_concert_event(v_comment.concert_id, v_actor_id, 'comment_deleted', v_comment.id);
end;
$$;

drop policy if exists "concerts_select_accepted_friend" on public.concerts;
drop policy if exists "concert_artists_select_visible_concert" on public.concert_artists;
drop policy if exists "setlist_items_select_visible_concert" on public.setlist_items;
drop policy if exists "concert_events_select_visible_concert" on public.concert_events;

create policy "concerts_select_visible_concert"
on public.concerts
for select
to authenticated
using ((select private.can_view_concert(id)));

create policy "concert_artists_select_visible_concert"
on public.concert_artists
for select
to authenticated
using ((select private.can_view_concert(concert_id)));

create policy "setlist_items_select_visible_concert"
on public.setlist_items
for select
to authenticated
using ((select private.can_view_concert(concert_id)));

create policy "concert_events_select_currently_visible_event"
on public.concert_events
for select
to authenticated
using ((select private.can_view_concert_event_as(auth.uid(), concert_id, event_type)));

alter table public.concert_collaborators enable row level security;
alter table public.comments enable row level security;
alter table public.direct_collaboration_notifications enable row level security;

create policy "concert_collaborators_select_editor"
on public.concert_collaborators
for select
to authenticated
using ((select private.is_concert_editor_as(auth.uid(), concert_id)));

create policy "comments_select_visible_concert"
on public.comments
for select
to authenticated
using ((select private.can_view_concert(concert_id)));

revoke all on table public.concert_collaborators, public.comments, public.direct_collaboration_notifications from anon, authenticated;
grant select on table public.concert_collaborators, public.comments to authenticated;

revoke all on function private.touch_comment() from public;
revoke all on function private.touch_concert_collaborator() from public;
revoke all on function private.is_concert_editor_as(uuid, uuid) from public;
revoke all on function private.can_view_concert_as(uuid, uuid) from public;
revoke all on function private.can_view_concert_event_as(uuid, uuid, public.concert_event_type) from public;
revoke all on function private.require_concert_editor(uuid) from public;
revoke all on function private.require_concert_owner(uuid) from public;
revoke all on function private.assert_expected_concert_version(public.concerts, bigint) from public;
revoke all on function private.touch_concert_activity(uuid) from public;
revoke all on function private.bump_concert_version(uuid) from public;
revoke all on function private.validate_concert_payload(jsonb, jsonb) from public;
revoke all on function private.record_concert_event(uuid, uuid, public.concert_event_type, uuid, jsonb) from public;
revoke all on function private.enqueue_collaboration_notification(uuid, uuid, uuid, text) from public;
revoke all on function private.notify_concert_editors(uuid, uuid, text) from public;
revoke all on function private.assert_comment_rate_limit(uuid) from public;
revoke all on function public.list_concert_collaborators(uuid) from public, anon;
revoke all on function public.update_concert(uuid, bigint, jsonb, text, date, text, text, timestamptz, text, jsonb, public.concert_visibility) from public, anon;
revoke all on function public.tag_concert_collaborator(uuid, uuid, bigint) from public, anon;
revoke all on function public.remove_concert_collaborator(uuid, uuid, bigint) from public, anon;
revoke all on function public.transfer_concert_ownership(uuid, uuid, bigint) from public, anon;
revoke all on function public.delete_concert(uuid) from public, anon;
revoke all on function public.list_concert_comments(uuid, timestamptz, uuid, integer) from public, anon;
revoke all on function public.create_concert_comment(uuid, text) from public, anon;
revoke all on function public.update_concert_comment(uuid, text) from public, anon;
revoke all on function public.delete_concert_comment(uuid) from public, anon;

grant execute on function private.is_concert_editor_as(uuid, uuid) to authenticated;
grant execute on function private.can_view_concert_as(uuid, uuid) to authenticated;
grant execute on function private.can_view_concert_event_as(uuid, uuid, public.concert_event_type) to authenticated;
grant execute on function public.list_concert_collaborators(uuid) to authenticated;
grant execute on function public.update_concert(uuid, bigint, jsonb, text, date, text, text, timestamptz, text, jsonb, public.concert_visibility) to authenticated;
grant execute on function public.tag_concert_collaborator(uuid, uuid, bigint) to authenticated;
grant execute on function public.remove_concert_collaborator(uuid, uuid, bigint) to authenticated;
grant execute on function public.transfer_concert_ownership(uuid, uuid, bigint) to authenticated;
grant execute on function public.delete_concert(uuid) to authenticated;
grant execute on function public.list_concert_comments(uuid, timestamptz, uuid, integer) to authenticated;
grant execute on function public.create_concert_comment(uuid, text) to authenticated;
grant execute on function public.update_concert_comment(uuid, text) to authenticated;
grant execute on function public.delete_concert_comment(uuid) to authenticated;
