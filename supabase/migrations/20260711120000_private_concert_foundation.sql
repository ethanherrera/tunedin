-- Stage 2: private concert diary foundation.
--
-- Concert creation is deliberately restricted to create_private_concert. The RPC
-- validates and writes the concert, ordered children, and creation event as one
-- transaction; client roles receive read-only access to their own records.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create type public.concert_visibility as enum ('private', 'collaborators', 'friends');
create type public.concert_event_type as enum ('concert_created');

create function private.contains_control_characters(p_value text)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_value ~ '[[:cntrl:]]'
$$;

create function private.normalize_concert_text(p_value text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select regexp_replace(
    regexp_replace(p_value, '^[[:space:]]+|[[:space:]]+$', '', 'g'),
    '[[:space:]]+',
    ' ',
    'g'
  )
$$;

create function private.is_normalized_concert_text(
  p_value text,
  p_maximum_length integer
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select
    char_length(p_value) between 1 and p_maximum_length
    and not private.contains_control_characters(p_value)
    and p_value = private.normalize_concert_text(p_value)
$$;

create function private.require_concert_text(
  p_value text,
  p_maximum_length integer,
  p_field_name text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_normalized text;
begin
  if p_value is null then
    raise exception '% is required', p_field_name
      using errcode = '22023';
  end if;

  if private.contains_control_characters(p_value) then
    raise exception '% cannot contain control characters', p_field_name
      using errcode = '22023';
  end if;

  v_normalized := private.normalize_concert_text(p_value);

  if char_length(v_normalized) not between 1 and p_maximum_length then
    raise exception '% must contain between 1 and % characters', p_field_name, p_maximum_length
      using errcode = '22023';
  end if;

  return v_normalized;
end;
$$;

create function private.optional_concert_text(
  p_value text,
  p_maximum_length integer,
  p_field_name text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_normalized text;
begin
  if p_value is null then
    return null;
  end if;

  if private.contains_control_characters(p_value) then
    raise exception '% cannot contain control characters', p_field_name
      using errcode = '22023';
  end if;

  v_normalized := private.normalize_concert_text(p_value);

  if v_normalized = '' then
    return null;
  end if;

  if char_length(v_normalized) > p_maximum_length then
    raise exception '% must contain no more than % characters', p_field_name, p_maximum_length
      using errcode = '22023';
  end if;

  return v_normalized;
end;
$$;

create function private.is_iana_time_zone(p_value text)
returns boolean
language sql
stable
strict
set search_path = ''
as $$
  select
    p_value !~ '[[:space:]]'
    and (p_value = 'UTC' or p_value like '%/%')
    and exists (
      select 1
      from pg_catalog.pg_timezone_names
      where name = p_value
    )
$$;

create table public.concerts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  venue_name text not null,
  city text,
  concert_date date not null,
  starts_at timestamptz,
  venue_time_zone text,
  tour text,
  visibility public.concert_visibility not null default 'private',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  constraint concerts_venue_name_normalized_check check (
    private.is_normalized_concert_text(venue_name, 160)
  ),
  constraint concerts_city_normalized_check check (
    city is null or private.is_normalized_concert_text(city, 100)
  ),
  constraint concerts_tour_normalized_check check (
    tour is null or private.is_normalized_concert_text(tour, 160)
  ),
  constraint concerts_time_zone_pair_check check (
    (starts_at is null and venue_time_zone is null)
    or (
      starts_at is not null
      and venue_time_zone is not null
      and private.is_iana_time_zone(venue_time_zone)
    )
  )
);

create table public.concert_artists (
  id uuid primary key default gen_random_uuid(),
  concert_id uuid not null references public.concerts (id) on delete cascade,
  lineup_position smallint not null,
  artist_name text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint concert_artists_position_range_check check (lineup_position between 1 and 10),
  constraint concert_artists_name_normalized_check check (
    private.is_normalized_concert_text(artist_name, 160)
  ),
  constraint concert_artists_concert_position_unique unique (concert_id, lineup_position)
);

create unique index concert_artists_one_primary_per_concert
  on public.concert_artists (concert_id)
  where is_primary;

create table public.setlist_items (
  id uuid primary key default gen_random_uuid(),
  concert_id uuid not null references public.concerts (id) on delete cascade,
  set_position smallint not null,
  song_title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint setlist_items_position_range_check check (set_position between 1 and 50),
  constraint setlist_items_title_normalized_check check (
    private.is_normalized_concert_text(song_title, 160)
  ),
  constraint setlist_items_concert_position_unique unique (concert_id, set_position)
);

create table public.concert_events (
  id uuid primary key default gen_random_uuid(),
  concert_id uuid not null references public.concerts (id) on delete cascade,
  actor_id uuid not null,
  event_type public.concert_event_type not null,
  occurred_at timestamptz not null default now()
);

create index concerts_owner_history_cursor
  on public.concerts (owner_id, concert_date desc, id desc);

create index concert_artists_concert_lineup
  on public.concert_artists (concert_id, lineup_position);

create index setlist_items_concert_order
  on public.setlist_items (concert_id, set_position);

create index concert_events_concert_chronological
  on public.concert_events (concert_id, occurred_at asc, id asc);

create function private.touch_concert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  new.last_activity_at = now();
  return new;
end;
$$;

create function private.touch_concert_child()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_concert_timestamps
before update on public.concerts
for each row execute function private.touch_concert();

create trigger set_concert_artist_timestamps
before update on public.concert_artists
for each row execute function private.touch_concert_child();

create trigger set_setlist_item_timestamps
before update on public.setlist_items
for each row execute function private.touch_concert_child();

create function private.assert_valid_concert_lineup(p_concert_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_artist_count integer;
  v_primary_count integer;
  v_max_position integer;
begin
  select
    count(*),
    count(*) filter (where is_primary),
    coalesce(max(lineup_position), 0)
  into v_artist_count, v_primary_count, v_max_position
  from public.concert_artists
  where concert_id = p_concert_id;

  if v_artist_count < 1 then
    raise exception 'Concerts must have at least one artist'
      using errcode = '23514';
  end if;

  if v_artist_count > 10 then
    raise exception 'Concerts may have no more than 10 artists'
      using errcode = '23514';
  end if;

  if v_primary_count <> 1 then
    raise exception 'Concerts must have exactly one primary artist'
      using errcode = '23514';
  end if;

  if v_max_position <> v_artist_count then
    raise exception 'Concert artist positions must be contiguous from 1'
      using errcode = '23514';
  end if;
end;
$$;

create function private.enforce_concert_lineup()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_new_concert_id uuid;
  v_old_concert_id uuid;
begin
  if tg_table_name = 'concerts' then
    v_new_concert_id := case when tg_op = 'DELETE' then null else new.id end;
    v_old_concert_id := case when tg_op = 'INSERT' then null else old.id end;
  else
    v_new_concert_id := case when tg_op = 'DELETE' then null else new.concert_id end;
    v_old_concert_id := case when tg_op = 'INSERT' then null else old.concert_id end;
  end if;

  if v_new_concert_id is not null
    and exists (select 1 from public.concerts where id = v_new_concert_id) then
    perform private.assert_valid_concert_lineup(v_new_concert_id);
  end if;

  if v_old_concert_id is not null
    and v_old_concert_id is distinct from v_new_concert_id
    and exists (select 1 from public.concerts where id = v_old_concert_id) then
    perform private.assert_valid_concert_lineup(v_old_concert_id);
  end if;

  return null;
end;
$$;

create constraint trigger concerts_require_valid_lineup
after insert or update on public.concerts
deferrable initially deferred
for each row execute function private.enforce_concert_lineup();

create constraint trigger concert_artists_require_valid_lineup
after insert or update or delete on public.concert_artists
deferrable initially deferred
for each row execute function private.enforce_concert_lineup();

create function private.reject_concert_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Concert events are immutable'
    using errcode = '55000';
end;
$$;

create trigger concert_events_are_immutable
before update or delete on public.concert_events
for each row execute function private.reject_concert_event_mutation();

create function private.is_concert_owner(p_concert_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.concerts
    where id = p_concert_id
      and owner_id = auth.uid()
  )
$$;

alter table public.concerts enable row level security;
alter table public.concert_artists enable row level security;
alter table public.setlist_items enable row level security;
alter table public.concert_events enable row level security;

create policy "concerts_select_owner"
on public.concerts
for select
to authenticated
using ((select auth.uid()) = owner_id);

create policy "concert_artists_select_owner"
on public.concert_artists
for select
to authenticated
using ((select private.is_concert_owner(concert_id)));

create policy "setlist_items_select_owner"
on public.setlist_items
for select
to authenticated
using ((select private.is_concert_owner(concert_id)));

create policy "concert_events_select_owner"
on public.concert_events
for select
to authenticated
using ((select private.is_concert_owner(concert_id)));

create function public.create_private_concert(
  p_artists jsonb,
  p_venue_name text,
  p_concert_date date,
  p_city text default null,
  p_tour text default null,
  p_starts_at timestamptz default null,
  p_venue_time_zone text default null,
  p_setlist jsonb default '[]'::jsonb
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_concert public.concerts%rowtype;
  v_artist jsonb;
  v_setlist_item jsonb;
  v_position integer;
  v_primary_count integer := 0;
  v_venue_name text;
  v_city text;
  v_tour text;
  v_time_zone text;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to create a concert'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = v_actor_id
      and onboarding_completed_at is not null
  ) then
    raise exception 'Complete onboarding before creating a concert'
      using errcode = '42501';
  end if;

  if p_artists is null or jsonb_typeof(p_artists) <> 'array' then
    raise exception 'Artists must be a JSON array'
      using errcode = '22023';
  end if;

  if jsonb_array_length(p_artists) not between 1 and 10 then
    raise exception 'Concerts require between 1 and 10 artists'
      using errcode = '22023';
  end if;

  if p_setlist is null or jsonb_typeof(p_setlist) <> 'array' then
    raise exception 'Setlist must be a JSON array'
      using errcode = '22023';
  end if;

  if jsonb_array_length(p_setlist) > 50 then
    raise exception 'Concerts may have no more than 50 setlist entries'
      using errcode = '22023';
  end if;

  v_venue_name := private.require_concert_text(p_venue_name, 160, 'Venue name');
  v_city := private.optional_concert_text(p_city, 100, 'City');
  v_tour := private.optional_concert_text(p_tour, 160, 'Tour');

  if p_concert_date is null then
    raise exception 'Concert date is required'
      using errcode = '22023';
  end if;

  if (p_starts_at is null) <> (p_venue_time_zone is null) then
    raise exception 'Start time and venue time zone must be provided together'
      using errcode = '22023';
  end if;

  if p_venue_time_zone is not null then
    if private.contains_control_characters(p_venue_time_zone)
      or p_venue_time_zone <> btrim(p_venue_time_zone)
      or not private.is_iana_time_zone(p_venue_time_zone) then
      raise exception 'Venue time zone must be a valid IANA time-zone identifier'
        using errcode = '22023';
    end if;
    v_time_zone := p_venue_time_zone;
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
      or (v_artist - 'name' - 'is_primary') <> '{}'::jsonb then
      raise exception 'Every artist must contain only name and is_primary fields'
        using errcode = '22023';
    end if;

    perform private.require_concert_text(v_artist ->> 'name', 160, 'Artist name');

    if (v_artist ->> 'is_primary')::boolean then
      v_primary_count := v_primary_count + 1;
    end if;
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

    perform private.require_concert_text(v_setlist_item #>> '{}', 160, 'Song title');
  end loop;

  insert into public.concerts (
    owner_id,
    venue_name,
    city,
    concert_date,
    starts_at,
    venue_time_zone,
    tour
  )
  values (
    v_actor_id,
    v_venue_name,
    v_city,
    p_concert_date,
    p_starts_at,
    v_time_zone,
    v_tour
  )
  returning * into v_concert;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(p_artists) with ordinality as item(value, ordinality)
  loop
    insert into public.concert_artists (
      concert_id,
      lineup_position,
      artist_name,
      is_primary
    )
    values (
      v_concert.id,
      v_position,
      private.require_concert_text(v_artist ->> 'name', 160, 'Artist name'),
      (v_artist ->> 'is_primary')::boolean
    );
  end loop;

  for v_setlist_item, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(p_setlist) with ordinality as item(value, ordinality)
  loop
    insert into public.setlist_items (concert_id, set_position, song_title)
    values (
      v_concert.id,
      v_position,
      private.require_concert_text(v_setlist_item #>> '{}', 160, 'Song title')
    );
  end loop;

  insert into public.concert_events (concert_id, actor_id, event_type)
  values (v_concert.id, v_actor_id, 'concert_created');

  return v_concert;
end;
$$;

revoke all on table public.concerts, public.concert_artists, public.setlist_items, public.concert_events from anon, authenticated;
grant select on table public.concerts, public.concert_artists, public.setlist_items, public.concert_events to authenticated;

revoke all on function public.create_private_concert(jsonb, text, date, text, text, timestamptz, text, jsonb) from public, anon;
grant execute on function public.create_private_concert(jsonb, text, date, text, text, timestamptz, text, jsonb) to authenticated;

revoke all on all functions in schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_concert_owner(uuid) to authenticated;
