-- Phase 1: provider-neutral community concert occurrences.
--
-- Catalog identities remain the reusable MusicBrainz/tunedIn layer. These rows
-- represent dated shared occurrences and preserve server-derived display
-- snapshots so an event stays understandable if a catalog entity is later
-- merged or retired. Ordinary clients read and mutate events only through the
-- bounded RPCs in this migration.

create type public.catalog_event_lifecycle as enum (
  'scheduled',
  'postponed',
  'cancelled',
  'completed'
);
create type public.catalog_event_listing as enum ('listed', 'unlisted');
create type public.catalog_event_integrity as enum (
  'community_added',
  'corroborated',
  'disputed'
);
create type public.catalog_event_row_state as enum ('active', 'merged', 'tombstoned');
create type public.social_activity_action as enum (
  'event_created',
  'event_updated',
  'marked_going',
  'marked_went',
  'invitation_accepted',
  'diary_published',
  'diary_media_added',
  'event_posted',
  'event_replied'
);

create table public.catalog_events (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles (id) on delete restrict,
  catalog_place_id uuid not null references public.catalog_places (id) on delete restrict,
  catalog_area_id uuid references public.catalog_areas (id) on delete restrict,
  catalog_tour_id uuid references public.catalog_tours (id) on delete restrict,
  headliner_catalog_artist_id uuid not null references public.catalog_artists (id) on delete restrict,
  event_date date not null,
  starts_at timestamptz,
  time_zone_identifier text not null,
  memory_unlock_at timestamptz not null,
  lifecycle public.catalog_event_lifecycle not null default 'scheduled',
  listing public.catalog_event_listing not null default 'listed',
  integrity public.catalog_event_integrity not null default 'community_added',
  row_state public.catalog_event_row_state not null default 'active',
  merged_into_event_id uuid references public.catalog_events (id) on delete restrict,
  version integer not null default 1,
  venue_name_snapshot text not null,
  area_name_snapshot text not null,
  tour_name_snapshot text,
  headliner_name_snapshot text not null,
  search_text text not null,
  exact_duplicate_key text not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  last_material_activity_at timestamptz not null default clock_timestamp(),
  constraint catalog_events_date_range_check check (
    event_date between date '1900-01-01' and date '2200-12-31'
  ),
  constraint catalog_events_time_zone_check check (
    char_length(time_zone_identifier) between 1 and 64
    and not private.contains_control_characters(time_zone_identifier)
  ),
  constraint catalog_events_starts_on_event_date_check check (
    starts_at is null
    or (starts_at at time zone time_zone_identifier)::date = event_date
  ),
  constraint catalog_events_unlock_check check (
    memory_unlock_at >= coalesce(
      starts_at,
      (event_date + time '00:00:00') at time zone time_zone_identifier
    )
  ),
  constraint catalog_events_version_check check (version > 0),
  constraint catalog_events_snapshot_checks check (
    private.is_normalized_concert_text(venue_name_snapshot, 160)
    and private.is_normalized_concert_text(area_name_snapshot, 160)
    and (tour_name_snapshot is null or private.is_normalized_concert_text(tour_name_snapshot, 160))
    and private.is_normalized_concert_text(headliner_name_snapshot, 160)
    and char_length(search_text) between 1 and 1000
    and not private.contains_control_characters(search_text)
  ),
  constraint catalog_events_duplicate_key_check check (
    exact_duplicate_key ~ '^[a-f0-9]{32}$'
  ),
  constraint catalog_events_merge_state_check check (
    (row_state = 'merged' and merged_into_event_id is not null and merged_into_event_id <> id)
    or (row_state <> 'merged' and merged_into_event_id is null)
  )
);

create unique index catalog_events_active_exact_duplicate
  on public.catalog_events (exact_duplicate_key)
  where row_state = 'active';
create index catalog_events_discovery_order
  on public.catalog_events (row_state, listing, event_date, id);
create index catalog_events_place_date
  on public.catalog_events (catalog_place_id, event_date, starts_at);
create index catalog_events_area_date
  on public.catalog_events (catalog_area_id, event_date);
create index catalog_events_headliner_date
  on public.catalog_events (headliner_catalog_artist_id, event_date);
create index catalog_events_search
  on public.catalog_events using gin (search_text gin_trgm_ops);
create index catalog_events_creator_quota
  on public.catalog_events (created_by, created_at desc);

create table public.catalog_event_artists (
  event_id uuid not null references public.catalog_events (id) on delete cascade,
  catalog_artist_id uuid not null references public.catalog_artists (id) on delete restrict,
  lineup_position smallint not null,
  is_headliner boolean not null default false,
  artist_name_snapshot text not null,
  primary key (event_id, lineup_position),
  constraint catalog_event_artists_identity_unique unique (event_id, catalog_artist_id),
  constraint catalog_event_artists_position_check check (lineup_position between 1 and 10),
  constraint catalog_event_artists_name_check check (
    private.is_normalized_concert_text(artist_name_snapshot, 160)
  )
);

create index catalog_event_artists_artist_event
  on public.catalog_event_artists (catalog_artist_id, event_id);

create table public.social_activity_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles (id) on delete restrict,
  action public.social_activity_action not null,
  event_id uuid not null references public.catalog_events (id) on delete restrict,
  subject_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint social_activity_events_metadata_check check (
    jsonb_typeof(metadata) = 'object'
    and pg_column_size(metadata) <= 1024
  )
);

create index social_activity_events_actor_time
  on public.social_activity_events (actor_id, occurred_at desc, id desc);
create index social_activity_events_event_time
  on public.social_activity_events (event_id, occurred_at desc, id desc);

-- Moderation content and full correction snapshots are deliberately private.
create table private.catalog_event_reports (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.catalog_events (id) on delete restrict,
  reporter_id uuid not null references public.profiles (id) on delete restrict,
  reason text not null check (
    reason in ('duplicate', 'wrong_date', 'wrong_venue', 'wrong_lineup', 'cancelled', 'other')
  ),
  note text,
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  constraint catalog_event_reports_note_check check (
    note is null or private.is_normalized_concert_text(note, 500)
  ),
  constraint catalog_event_reports_resolution_check check (
    (status = 'open' and resolved_at is null)
    or (status <> 'open' and resolved_at is not null)
  )
);

create unique index catalog_event_reports_one_open
  on private.catalog_event_reports (event_id, reporter_id)
  where status = 'open';
create index catalog_event_reports_reporter_quota
  on private.catalog_event_reports (reporter_id, created_at desc);

create table private.catalog_event_revisions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.catalog_events (id) on delete restrict,
  changed_by uuid not null references public.profiles (id) on delete restrict,
  previous_version integer not null check (previous_version > 0),
  next_version integer not null check (next_version = previous_version + 1),
  old_snapshot jsonb not null check (jsonb_typeof(old_snapshot) = 'object'),
  new_snapshot jsonb not null check (jsonb_typeof(new_snapshot) = 'object'),
  created_at timestamptz not null default clock_timestamp()
);

create index catalog_event_revisions_event_version
  on private.catalog_event_revisions (event_id, next_version desc);

create table private.catalog_event_creation_quota (
  singleton boolean primary key default true check (singleton),
  rolling_hour_limit integer not null check (rolling_hour_limit > 0),
  rolling_day_limit integer not null check (rolling_day_limit >= rolling_hour_limit)
);

insert into private.catalog_event_creation_quota (
  singleton, rolling_hour_limit, rolling_day_limit
)
values (true, 10, 50);

create function private.prevent_social_activity_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Social activity events are immutable'
    using errcode = '42501';
end;
$$;

create trigger social_activity_events_are_immutable
before update or delete on public.social_activity_events
for each row execute function private.prevent_social_activity_mutation();

create function private.assert_catalog_event_merge_target()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_target_state public.catalog_event_row_state;
begin
  if new.merged_into_event_id is null then
    return new;
  end if;

  select target.row_state
  into v_target_state
  from public.catalog_events as target
  where target.id = new.merged_into_event_id;

  if not found or v_target_state <> 'active' then
    raise exception 'A merged event must target an active event'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger catalog_events_validate_merge_target
before insert or update of row_state, merged_into_event_id on public.catalog_events
for each row execute function private.assert_catalog_event_merge_target();

create function private.assert_valid_catalog_event_lineup(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_headliner_count integer;
  v_headliner_id uuid;
begin
  select count(*), count(*) filter (where lineup.is_headliner)
  into v_count, v_headliner_count
  from public.catalog_event_artists as lineup
  where lineup.event_id = p_event_id;

  if v_count not between 1 and 10 or v_headliner_count <> 1 then
    raise exception 'Events require between 1 and 10 artists and exactly one headliner'
      using errcode = '23514';
  end if;

  select lineup.catalog_artist_id
  into v_headliner_id
  from public.catalog_event_artists as lineup
  where lineup.event_id = p_event_id and lineup.is_headliner;

  if v_headliner_id is distinct from (
    select event.headliner_catalog_artist_id
    from public.catalog_events as event
    where event.id = p_event_id
  ) then
    raise exception 'The event headliner snapshot must match its lineup'
      using errcode = '23514';
  end if;
end;
$$;

create function private.enforce_catalog_event_lineup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'catalog_events' then
    perform private.assert_valid_catalog_event_lineup(coalesce(new.id, old.id));
  else
    if tg_op <> 'DELETE' then
      perform private.assert_valid_catalog_event_lineup(new.event_id);
    end if;
    if tg_op <> 'INSERT' and (tg_op = 'DELETE' or old.event_id <> new.event_id) then
      perform private.assert_valid_catalog_event_lineup(old.event_id);
    end if;
  end if;
  return null;
end;
$$;

create constraint trigger catalog_events_require_valid_lineup
after insert or update on public.catalog_events
deferrable initially deferred
for each row execute function private.enforce_catalog_event_lineup();

create constraint trigger catalog_event_artists_require_valid_lineup
after insert or update or delete on public.catalog_event_artists
deferrable initially deferred
for each row execute function private.enforce_catalog_event_lineup();

create function private.resolve_catalog_event_entity_as(
  p_user_id uuid,
  p_entity_id uuid,
  p_kind public.catalog_entity_kind,
  p_event_id uuid default null
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entity public.catalog_entities%rowtype;
  v_current_id uuid := p_entity_id;
  v_seen uuid[] := '{}'::uuid[];
  v_depth integer := 0;
begin
  if p_user_id is null or p_entity_id is null then
    return null;
  end if;

  select entity.* into v_entity
  from public.catalog_entities as entity
  where entity.id = p_entity_id and entity.kind = p_kind;

  if not found or not (
    v_entity.origin = 'musicbrainz'
    or exists (
      select 1
      from private.catalog_entity_provenance as provenance
      where provenance.entity_id = p_entity_id
        and provenance.creator_id = p_user_id
    )
    or private.can_use_catalog_entity_as(p_user_id, p_entity_id, p_kind, p_event_id)
  ) then
    return null;
  end if;

  loop
    v_depth := v_depth + 1;
    if v_depth > 10 or v_current_id = any(v_seen) then
      return null;
    end if;
    v_seen := array_append(v_seen, v_current_id);

    select entity.* into v_entity
    from public.catalog_entities as entity
    where entity.id = v_current_id and entity.kind = p_kind;

    if not found then
      return null;
    elsif v_entity.status in ('active', 'needs_review') then
      return v_current_id;
    elsif v_entity.status = 'merged' and v_entity.merged_into_id is not null then
      v_current_id := v_entity.merged_into_id;
    else
      return null;
    end if;
  end loop;
  return null;
end;
$$;

create function private.resolve_catalog_event_id(p_event_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_id uuid := p_event_id;
  v_target_id uuid;
  v_state public.catalog_event_row_state;
  v_seen uuid[] := '{}'::uuid[];
  v_depth integer := 0;
begin
  loop
    v_depth := v_depth + 1;
    if v_current_id is null or v_depth > 10 or v_current_id = any(v_seen) then
      return null;
    end if;
    v_seen := array_append(v_seen, v_current_id);

    select event.row_state, event.merged_into_event_id
    into v_state, v_target_id
    from public.catalog_events as event
    where event.id = v_current_id;

    if not found or v_state = 'tombstoned' then
      return null;
    elsif v_state = 'active' then
      return v_current_id;
    end if;
    v_current_id := v_target_id;
  end loop;
  return null;
end;
$$;

create function private.can_read_catalog_event_as(p_user_id uuid, p_event_id uuid)
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
        and (event.listing = 'listed' or event.created_by = p_user_id)
    )
$$;

create function private.assert_catalog_event_creation_quota(p_creator_id uuid)
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
    pg_catalog.hashtextextended('catalog-event-quota:' || p_creator_id::text, 0)
  );

  select quota.rolling_hour_limit, quota.rolling_day_limit
  into v_hour_limit, v_day_limit
  from private.catalog_event_creation_quota as quota
  where quota.singleton;

  select
    count(*) filter (where event.created_at >= clock_timestamp() - interval '1 hour'),
    count(*)
  into v_hour_count, v_day_count
  from public.catalog_events as event
  where event.created_by = p_creator_id
    and event.created_at >= clock_timestamp() - interval '24 hours';

  if v_hour_count >= v_hour_limit or v_day_count >= v_day_limit then
    raise exception 'You have reached the community event creation limit. Try again later.'
      using errcode = 'P0001';
  end if;
end;
$$;

create function private.prepare_catalog_event_payload(
  p_actor_id uuid,
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_catalog_tour_id uuid,
  p_event_date date,
  p_starts_at timestamptz,
  p_time_zone_identifier text,
  p_listing public.catalog_event_listing,
  p_event_id uuid default null
)
returns table (
  artists jsonb,
  catalog_place_id uuid,
  catalog_area_id uuid,
  catalog_tour_id uuid,
  headliner_catalog_artist_id uuid,
  venue_name text,
  area_name text,
  tour_name text,
  headliner_name text,
  memory_unlock_at timestamptz,
  exact_duplicate_key text,
  search_text text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_artist jsonb;
  v_artist_id uuid;
  v_resolved_artist_id uuid;
  v_resolved_place_id uuid;
  v_resolved_tour_id uuid;
  v_normalized_artists jsonb := '[]'::jsonb;
  v_artist_names text[] := '{}'::text[];
  v_primary_count integer := 0;
  v_headliner_id uuid;
  v_headliner_name text;
  v_place_name text;
  v_area_id uuid;
  v_area_name text;
  v_tour_name text;
  v_time_zone text := btrim(coalesce(p_time_zone_identifier, ''));
  v_unlock_at timestamptz;
  v_scope text;
  v_duplicate_key text;
  v_search_text text;
begin
  if p_event_date is null
    or p_event_date < current_date - 36525
    or p_event_date > current_date + 3650
  then
    raise exception 'Choose an event date within the supported range'
      using errcode = '22023';
  end if;

  if not (v_time_zone = 'UTC' or position('/' in v_time_zone) > 0)
    or not exists (
      select 1 from pg_catalog.pg_timezone_names as zone where zone.name = v_time_zone
    )
  then
    raise exception 'Choose a valid IANA venue time zone'
      using errcode = '22023';
  end if;

  if p_starts_at is not null
    and (p_starts_at at time zone v_time_zone)::date <> p_event_date
  then
    raise exception 'The start time must fall on the event date in the venue time zone'
      using errcode = '22023';
  end if;

  if p_artists is null or jsonb_typeof(p_artists) <> 'array'
    or jsonb_array_length(p_artists) not between 1 and 10
  then
    raise exception 'Events require between 1 and 10 catalog artists'
      using errcode = '22023';
  end if;

  for v_artist in select item.value from jsonb_array_elements(p_artists) as item(value)
  loop
    if jsonb_typeof(v_artist) <> 'object'
      or not (v_artist ? 'catalog_artist_id')
      or not (v_artist ? 'is_primary')
      or jsonb_typeof(v_artist -> 'catalog_artist_id') <> 'string'
      or jsonb_typeof(v_artist -> 'is_primary') <> 'boolean'
      or (v_artist - 'catalog_artist_id' - 'is_primary') <> '{}'::jsonb
    then
      raise exception 'Every lineup artist requires only catalog_artist_id and is_primary'
        using errcode = '22023';
    end if;

    begin
      v_artist_id := (v_artist ->> 'catalog_artist_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Every lineup artist requires a valid catalog artist ID'
        using errcode = '22023';
    end;

    v_resolved_artist_id := private.resolve_catalog_event_entity_as(
      p_actor_id, v_artist_id, 'artist', p_event_id
    );
    if v_resolved_artist_id is null then
      raise exception 'Choose only available catalog artists'
        using errcode = '22023';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(v_normalized_artists) as existing(value)
      where (existing.value ->> 'catalog_artist_id')::uuid = v_resolved_artist_id
    ) then
      raise exception 'An event lineup cannot contain the same catalog artist twice'
        using errcode = '22023';
    end if;

    select entity.display_name
    into v_headliner_name
    from public.catalog_entities as entity
    join public.catalog_artists as artist on artist.id = entity.id
    where entity.id = v_resolved_artist_id;

    v_artist_names := array_append(v_artist_names, v_headliner_name);
    if (v_artist ->> 'is_primary')::boolean then
      v_primary_count := v_primary_count + 1;
      v_headliner_id := v_resolved_artist_id;
    end if;
    v_normalized_artists := v_normalized_artists || jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', v_resolved_artist_id,
      'is_primary', (v_artist ->> 'is_primary')::boolean
    ));
  end loop;

  if v_primary_count <> 1 then
    raise exception 'Events require exactly one headliner'
      using errcode = '22023';
  end if;

  select entity.display_name
  into v_headliner_name
  from public.catalog_entities as entity
  where entity.id = v_headliner_id;

  v_resolved_place_id := private.resolve_catalog_event_entity_as(
    p_actor_id, p_catalog_place_id, 'place', p_event_id
  );
  if v_resolved_place_id is null then
    raise exception 'Choose an available catalog place'
      using errcode = '22023';
  end if;

  select place.area_id, entity.display_name
  into v_area_id, v_place_name
  from public.catalog_places as place
  join public.catalog_entities as entity on entity.id = place.id
  where place.id = v_resolved_place_id;

  if not found then
    raise exception 'Choose an available catalog place'
      using errcode = '22023';
  end if;

  if v_area_id is null then
    v_area_name := 'Area not listed';
  else
    select entity.display_name into v_area_name
    from public.catalog_entities as entity
    where entity.id = v_area_id and entity.status in ('active', 'needs_review');
    if not found then
      raise exception 'The catalog place does not have an available area'
        using errcode = '22023';
    end if;
  end if;

  if p_catalog_tour_id is not null then
    v_resolved_tour_id := private.resolve_catalog_event_entity_as(
      p_actor_id, p_catalog_tour_id, 'tour', p_event_id
    );
    if v_resolved_tour_id is null then
      raise exception 'Choose an available catalog tour'
        using errcode = '22023';
    end if;
    select entity.display_name into v_tour_name
    from public.catalog_entities as entity
    join public.catalog_tours as tour on tour.id = entity.id
    where entity.id = v_resolved_tour_id;
  end if;

  v_unlock_at := case
    when p_starts_at is not null then p_starts_at + interval '6 hours'
    else (p_event_date + time '23:59:59') at time zone v_time_zone
  end;
  v_scope := case
    when p_listing = 'listed' then 'listed'
    else 'unlisted:' || p_actor_id::text
  end;
  v_duplicate_key := pg_catalog.md5(
    v_scope || '|' || v_resolved_place_id::text || '|' || p_event_date::text
    || '|' || coalesce(date_trunc('second', p_starts_at)::text, '-')
    || '|' || v_headliner_id::text
  );
  v_search_text := lower(private.normalize_concert_text(
    array_to_string(v_artist_names, ' ') || ' ' || v_place_name || ' ' || v_area_name
    || coalesce(' ' || v_tour_name, '')
  ));

  return query select
    v_normalized_artists,
    v_resolved_place_id,
    v_area_id,
    v_resolved_tour_id,
    v_headliner_id,
    v_place_name,
    v_area_name,
    v_tour_name,
    v_headliner_name,
    v_unlock_at,
    v_duplicate_key,
    v_search_text;
end;
$$;

create view private.catalog_event_projections as
select
  event.id as event_id,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'catalog_artist_id', lineup.catalog_artist_id,
        'display_name', lineup.artist_name_snapshot,
        'position', lineup.lineup_position,
        'is_headliner', lineup.is_headliner
      ) order by lineup.lineup_position
    ) filter (where lineup.event_id is not null),
    '[]'::jsonb
  ) as artists,
  event.catalog_place_id,
  event.catalog_area_id,
  event.catalog_tour_id,
  event.venue_name_snapshot as venue_name,
  event.area_name_snapshot as area_name,
  event.tour_name_snapshot as tour_name,
  event.headliner_name_snapshot as headliner_name,
  event.event_date,
  event.starts_at,
  event.time_zone_identifier,
  event.memory_unlock_at,
  event.lifecycle,
  event.listing,
  event.integrity,
  event.row_state,
  event.version,
  event.search_text,
  event.created_at,
  event.updated_at
from public.catalog_events as event
left join public.catalog_event_artists as lineup on lineup.event_id = event.id
group by event.id;

alter table public.catalog_events enable row level security;
alter table public.catalog_event_artists enable row level security;
alter table public.social_activity_events enable row level security;

create policy "catalog_events_select_allowed"
on public.catalog_events for select to authenticated
using (private.can_read_catalog_event_as(auth.uid(), id));

create policy "catalog_event_artists_select_allowed"
on public.catalog_event_artists for select to authenticated
using (private.can_read_catalog_event_as(auth.uid(), event_id));

create policy "social_activity_events_select_allowed"
on public.social_activity_events for select to authenticated
using (private.can_read_catalog_event_as(auth.uid(), event_id));

revoke all on table
  public.catalog_events,
  public.catalog_event_artists,
  public.social_activity_events
from public, anon, authenticated;

create function public.search_catalog_events(
  p_query text default null,
  p_filters jsonb default '{}'::jsonb,
  p_cursor jsonb default null,
  p_limit integer default 20
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
  v_query text;
  v_start_date date;
  v_end_date date;
  v_area_id uuid;
  v_artist_id uuid;
  v_cursor_bucket integer;
  v_cursor_relevance double precision;
  v_cursor_date_key integer;
  v_cursor_event_id uuid;
begin
  if p_limit not between 1 and 50 then
    raise exception 'Event search limit must be between 1 and 50'
      using errcode = '22023';
  end if;
  if p_query is not null and (
    char_length(p_query) > 160 or private.contains_control_characters(p_query)
  ) then
    raise exception 'Event search text is invalid'
      using errcode = '22023';
  end if;
  v_query := nullif(lower(regexp_replace(btrim(coalesce(p_query, '')), '[[:space:]]+', ' ', 'g')), '');

  if p_filters is null or jsonb_typeof(p_filters) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(p_filters) as key
      where key not in ('start_date', 'end_date', 'area_catalog_id', 'artist_catalog_id')
    )
  then
    raise exception 'Event search filters are invalid'
      using errcode = '22023';
  end if;

  begin
    v_start_date := nullif(p_filters ->> 'start_date', '')::date;
    v_end_date := nullif(p_filters ->> 'end_date', '')::date;
    v_area_id := nullif(p_filters ->> 'area_catalog_id', '')::uuid;
    v_artist_id := nullif(p_filters ->> 'artist_catalog_id', '')::uuid;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception 'Event search filters are invalid'
      using errcode = '22023';
  end;
  if v_start_date is not null and v_end_date is not null and v_start_date > v_end_date then
    raise exception 'Event search start date must not follow its end date'
      using errcode = '22023';
  end if;

  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'bucket' - 'relevance' - 'date_key' - 'event_id') <> '{}'::jsonb
      or not (p_cursor ?& array['bucket', 'relevance', 'date_key', 'event_id'])
    then
      raise exception 'Event search cursor is invalid'
        using errcode = '22023';
    end if;
    begin
      v_cursor_bucket := (p_cursor ->> 'bucket')::integer;
      v_cursor_relevance := (p_cursor ->> 'relevance')::double precision;
      v_cursor_date_key := (p_cursor ->> 'date_key')::integer;
      v_cursor_event_id := (p_cursor ->> 'event_id')::uuid;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Event search cursor is invalid'
        using errcode = '22023';
    end;
  end if;

  return query
  with scored as (
    select
      projection.*,
      case when projection.event_date >= current_date then 0 else 1 end as sort_bucket,
      case
        when v_query is null then 0::double precision
        when lower(projection.headliner_name) = v_query then 3::double precision
        else public.similarity(projection.search_text, v_query)::double precision
          + case when position(v_query in projection.search_text) > 0 then 1 else 0 end
      end as sort_relevance,
      case
        when projection.event_date >= current_date
          then projection.event_date - date '2000-01-01'
        else -(projection.event_date - date '2000-01-01')
      end as sort_date_key
    from private.catalog_event_projections as projection
    where projection.row_state = 'active'
      and private.can_read_catalog_event_as(v_caller_id, projection.event_id)
      and (v_query is null or position(v_query in projection.search_text) > 0
        or public.similarity(projection.search_text, v_query) >= 0.2)
      and (v_start_date is null or projection.event_date >= v_start_date)
      and (v_end_date is null or projection.event_date <= v_end_date)
      and (v_area_id is null or projection.catalog_area_id = v_area_id)
      and (v_artist_id is null or exists (
        select 1 from public.catalog_event_artists as lineup
        where lineup.event_id = projection.event_id
          and lineup.catalog_artist_id = v_artist_id
      ))
  ), page as (
    select scored.*
    from scored
    where p_cursor is null
      or scored.sort_bucket > v_cursor_bucket
      or (scored.sort_bucket = v_cursor_bucket and scored.sort_relevance < v_cursor_relevance)
      or (
        scored.sort_bucket = v_cursor_bucket
        and scored.sort_relevance = v_cursor_relevance
        and scored.sort_date_key > v_cursor_date_key
      )
      or (
        scored.sort_bucket = v_cursor_bucket
        and scored.sort_relevance = v_cursor_relevance
        and scored.sort_date_key = v_cursor_date_key
        and scored.event_id > v_cursor_event_id
      )
    order by scored.sort_bucket, scored.sort_relevance desc, scored.sort_date_key, scored.event_id
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
      'relevance', page.sort_relevance,
      'date_key', page.sort_date_key,
      'event_id', page.event_id
    )
  from page
  order by page.sort_bucket, page.sort_relevance desc, page.sort_date_key, page.event_id;
end;
$$;

create function public.get_catalog_event_detail(p_event_id uuid)
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
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
begin
  if v_event_id is null or not private.can_read_catalog_event_as(v_caller_id, v_event_id) then
    raise exception 'This event is unavailable'
      using errcode = '42501';
  end if;

  return query
  select
    projection.event_id,
    projection.artists,
    projection.catalog_place_id,
    projection.catalog_area_id,
    projection.catalog_tour_id,
    projection.venue_name,
    projection.area_name,
    projection.tour_name,
    projection.event_date,
    projection.starts_at,
    projection.time_zone_identifier,
    projection.memory_unlock_at,
    projection.lifecycle,
    projection.listing,
    projection.integrity,
    projection.row_state,
    'Community added'::text,
    projection.version,
    projection.created_at,
    projection.updated_at,
    null::jsonb
  from private.catalog_event_projections as projection
  where projection.event_id = v_event_id;
end;
$$;

create function public.create_catalog_event(
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_event_date date,
  p_catalog_tour_id uuid default null,
  p_starts_at timestamptz default null,
  p_time_zone_identifier text default 'UTC',
  p_listing public.catalog_event_listing default 'listed'
)
returns table (event_id uuid, was_created boolean, version integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_payload record;
  v_existing public.catalog_events%rowtype;
  v_event_id uuid;
  v_artist jsonb;
  v_position integer;
  v_lifecycle public.catalog_event_lifecycle;
begin
  select * into v_payload
  from private.prepare_catalog_event_payload(
    v_actor_id,
    p_artists,
    p_catalog_place_id,
    p_catalog_tour_id,
    p_event_date,
    p_starts_at,
    btrim(p_time_zone_identifier),
    p_listing,
    null
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-event:' || v_payload.exact_duplicate_key, 0)
  );

  select event.* into v_existing
  from public.catalog_events as event
  where event.exact_duplicate_key = v_payload.exact_duplicate_key
    and event.row_state = 'active'
  limit 1;

  if found then
    return query select v_existing.id, false, v_existing.version;
    return;
  end if;

  perform private.assert_catalog_event_creation_quota(v_actor_id);
  v_lifecycle := case
    when v_payload.memory_unlock_at <= clock_timestamp() then 'completed'::public.catalog_event_lifecycle
    else 'scheduled'::public.catalog_event_lifecycle
  end;

  insert into public.catalog_events (
    created_by,
    catalog_place_id,
    catalog_area_id,
    catalog_tour_id,
    headliner_catalog_artist_id,
    event_date,
    starts_at,
    time_zone_identifier,
    memory_unlock_at,
    lifecycle,
    listing,
    venue_name_snapshot,
    area_name_snapshot,
    tour_name_snapshot,
    headliner_name_snapshot,
    search_text,
    exact_duplicate_key
  ) values (
    v_actor_id,
    v_payload.catalog_place_id,
    v_payload.catalog_area_id,
    v_payload.catalog_tour_id,
    v_payload.headliner_catalog_artist_id,
    p_event_date,
    p_starts_at,
    btrim(p_time_zone_identifier),
    v_payload.memory_unlock_at,
    v_lifecycle,
    p_listing,
    v_payload.venue_name,
    v_payload.area_name,
    v_payload.tour_name,
    v_payload.headliner_name,
    v_payload.search_text,
    v_payload.exact_duplicate_key
  ) returning id into v_event_id;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_payload.artists) with ordinality as item(value, ordinality)
  loop
    insert into public.catalog_event_artists (
      event_id,
      catalog_artist_id,
      lineup_position,
      is_headliner,
      artist_name_snapshot
    )
    select
      v_event_id,
      (v_artist ->> 'catalog_artist_id')::uuid,
      v_position,
      (v_artist ->> 'is_primary')::boolean,
      entity.display_name
    from public.catalog_entities as entity
    where entity.id = (v_artist ->> 'catalog_artist_id')::uuid;
  end loop;

  insert into public.social_activity_events (actor_id, action, event_id)
  values (v_actor_id, 'event_created', v_event_id);

  return query select v_event_id, true, 1;
end;
$$;

create function public.update_catalog_event(
  p_event_id uuid,
  p_expected_version integer,
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_event_date date,
  p_catalog_tour_id uuid default null,
  p_starts_at timestamptz default null,
  p_time_zone_identifier text default 'UTC',
  p_listing public.catalog_event_listing default 'listed',
  p_lifecycle public.catalog_event_lifecycle default 'scheduled'
)
returns table (event_id uuid, version integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_event public.catalog_events%rowtype;
  v_updated public.catalog_events%rowtype;
  v_payload record;
  v_artist jsonb;
  v_position integer;
  v_lifecycle public.catalog_event_lifecycle;
begin
  select event.* into v_event
  from public.catalog_events as event
  where event.id = p_event_id
  for update;

  if not found or v_event.row_state <> 'active' then
    raise exception 'This event is unavailable'
      using errcode = '42501';
  end if;
  if v_event.created_by <> v_actor_id then
    raise exception 'Only the community event creator can propose this correction'
      using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version <> v_event.version then
    raise exception 'This event changed. Refresh before editing it again.'
      using errcode = 'P0001';
  end if;

  select * into v_payload
  from private.prepare_catalog_event_payload(
    v_actor_id,
    p_artists,
    p_catalog_place_id,
    p_catalog_tour_id,
    p_event_date,
    p_starts_at,
    p_time_zone_identifier,
    p_listing,
    p_event_id
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-event:' || v_payload.exact_duplicate_key, 0)
  );
  if exists (
    select 1
    from public.catalog_events as duplicate
    where duplicate.exact_duplicate_key = v_payload.exact_duplicate_key
      and duplicate.row_state = 'active'
      and duplicate.id <> p_event_id
  ) then
    raise exception 'A matching community event already exists'
      using errcode = 'P0001';
  end if;

  if p_lifecycle = 'completed' and v_payload.memory_unlock_at > clock_timestamp() then
    raise exception 'An event cannot be completed before memories unlock'
      using errcode = '22023';
  end if;
  v_lifecycle := case
    when p_lifecycle in ('cancelled', 'postponed') then p_lifecycle
    when v_payload.memory_unlock_at <= clock_timestamp() then 'completed'::public.catalog_event_lifecycle
    else 'scheduled'::public.catalog_event_lifecycle
  end;

  update public.catalog_events
  set
    catalog_place_id = v_payload.catalog_place_id,
    catalog_area_id = v_payload.catalog_area_id,
    catalog_tour_id = v_payload.catalog_tour_id,
    headliner_catalog_artist_id = v_payload.headliner_catalog_artist_id,
    event_date = p_event_date,
    starts_at = p_starts_at,
    time_zone_identifier = btrim(p_time_zone_identifier),
    memory_unlock_at = v_payload.memory_unlock_at,
    lifecycle = v_lifecycle,
    listing = p_listing,
    venue_name_snapshot = v_payload.venue_name,
    area_name_snapshot = v_payload.area_name,
    tour_name_snapshot = v_payload.tour_name,
    headliner_name_snapshot = v_payload.headliner_name,
    search_text = v_payload.search_text,
    exact_duplicate_key = v_payload.exact_duplicate_key,
    version = v_event.version + 1,
    updated_at = clock_timestamp(),
    last_material_activity_at = clock_timestamp()
  where id = p_event_id
  returning * into v_updated;

  delete from public.catalog_event_artists where catalog_event_artists.event_id = p_event_id;
  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_payload.artists) with ordinality as item(value, ordinality)
  loop
    insert into public.catalog_event_artists (
      event_id,
      catalog_artist_id,
      lineup_position,
      is_headliner,
      artist_name_snapshot
    )
    select
      p_event_id,
      (v_artist ->> 'catalog_artist_id')::uuid,
      v_position,
      (v_artist ->> 'is_primary')::boolean,
      entity.display_name
    from public.catalog_entities as entity
    where entity.id = (v_artist ->> 'catalog_artist_id')::uuid;
  end loop;

  insert into private.catalog_event_revisions (
    event_id, changed_by, previous_version, next_version, old_snapshot, new_snapshot
  ) values (
    p_event_id,
    v_actor_id,
    v_event.version,
    v_updated.version,
    to_jsonb(v_event),
    to_jsonb(v_updated)
  );
  insert into public.social_activity_events (actor_id, action, event_id, metadata)
  values (v_actor_id, 'event_updated', p_event_id, jsonb_build_object('version', v_updated.version));

  return query select p_event_id, v_updated.version;
end;
$$;

create function public.report_catalog_event(
  p_event_id uuid,
  p_reason text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_report_id uuid;
  v_note text := private.optional_concert_text(p_note, 500, 'Report note');
begin
  if p_reason not in ('duplicate', 'wrong_date', 'wrong_venue', 'wrong_lineup', 'cancelled', 'other') then
    raise exception 'Choose a valid event report reason'
      using errcode = '22023';
  end if;
  if v_event_id is null or not private.can_read_catalog_event_as(v_actor_id, v_event_id) then
    raise exception 'This event is unavailable'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-event-report:' || v_actor_id::text, 0)
  );
  select report.id into v_report_id
  from private.catalog_event_reports as report
  where report.event_id = v_event_id
    and report.reporter_id = v_actor_id
    and report.status = 'open';
  if found then
    return v_report_id;
  end if;
  if (
    select count(*)
    from private.catalog_event_reports as report
    where report.reporter_id = v_actor_id
      and report.created_at >= clock_timestamp() - interval '24 hours'
  ) >= 20 then
    raise exception 'You have reached the event report limit. Try again later.'
      using errcode = 'P0001';
  end if;

  insert into private.catalog_event_reports (event_id, reporter_id, reason, note)
  values (v_event_id, v_actor_id, p_reason, v_note)
  returning id into v_report_id;
  return v_report_id;
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_concert_owner(uuid) to authenticated;
grant execute on function private.can_view_profile_avatar(uuid) to authenticated;
grant execute on function private.are_accepted_friends(uuid, uuid) to authenticated;
grant execute on function private.has_relationship_block(uuid, uuid) to authenticated;
grant execute on function private.can_view_concert(uuid) to authenticated;
grant execute on function private.is_concert_editor_as(uuid, uuid) to authenticated;
grant execute on function private.can_view_concert_as(uuid, uuid) to authenticated;
grant execute on function private.can_view_concert_event_as(
  uuid, uuid, public.concert_event_type
) to authenticated;
grant execute on function private.can_upload_reserved_album_photo(uuid, text) to authenticated;
grant execute on function private.can_delete_prepared_album_photo(uuid, text) to authenticated;
grant execute on function private.can_read_catalog_entity_as(uuid, uuid) to authenticated;
grant execute on function private.can_read_catalog_event_as(uuid, uuid) to authenticated;

revoke all on function public.search_catalog_events(text, jsonb, jsonb, integer)
  from public, anon;
revoke all on function public.get_catalog_event_detail(uuid)
  from public, anon;
revoke all on function public.create_catalog_event(
  jsonb, uuid, date, uuid, timestamptz, text, public.catalog_event_listing
) from public, anon;
revoke all on function public.update_catalog_event(
  uuid, integer, jsonb, uuid, date, uuid, timestamptz, text,
  public.catalog_event_listing, public.catalog_event_lifecycle
) from public, anon;
revoke all on function public.report_catalog_event(uuid, text, text)
  from public, anon;

grant execute on function public.search_catalog_events(text, jsonb, jsonb, integer)
  to authenticated;
grant execute on function public.get_catalog_event_detail(uuid)
  to authenticated;
grant execute on function public.create_catalog_event(
  jsonb, uuid, date, uuid, timestamptz, text, public.catalog_event_listing
) to authenticated;
grant execute on function public.update_catalog_event(
  uuid, integer, jsonb, uuid, date, uuid, timestamptz, text,
  public.catalog_event_listing, public.catalog_event_lifecycle
) to authenticated;
grant execute on function public.report_catalog_event(uuid, text, text)
  to authenticated;

revoke all on table
  private.catalog_event_reports,
  private.catalog_event_revisions,
  private.catalog_event_creation_quota
from public, anon, authenticated;
