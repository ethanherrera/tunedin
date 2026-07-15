-- MusicBrainz-backed catalog identities for every structured concert value.
--
-- This is an expand/migrate/contract-compatible migration. Existing diary text
-- is preserved as a snapshot and receives owner-scoped legacy_import identities;
-- supported older clients continue through the legacy string RPCs, which now
-- resolve legacy_client identities before delegating to the ID-only v2 RPCs.

create type public.catalog_entity_kind as enum ('artist', 'area', 'place', 'song', 'tour');
create type public.catalog_entity_origin as enum (
  'musicbrainz',
  'tunedin_custom',
  'legacy_import',
  'legacy_client'
);
create type public.catalog_entity_status as enum ('active', 'needs_review', 'merged', 'retired');

create table public.catalog_entities (
  id uuid primary key default gen_random_uuid(),
  kind public.catalog_entity_kind not null,
  origin public.catalog_entity_origin not null,
  status public.catalog_entity_status not null default 'active',
  display_name text not null,
  sort_name text not null,
  disambiguation text,
  musicbrainz_mbid uuid,
  merged_into_id uuid references public.catalog_entities (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint catalog_entities_id_kind_unique unique (id, kind),
  constraint catalog_entities_display_name_check check (
    private.is_normalized_concert_text(display_name, 160)
  ),
  constraint catalog_entities_sort_name_check check (
    private.is_normalized_concert_text(sort_name, 160)
  ),
  constraint catalog_entities_disambiguation_check check (
    disambiguation is null or private.is_normalized_concert_text(disambiguation, 240)
  ),
  constraint catalog_entities_musicbrainz_origin_check check (
    (origin = 'musicbrainz' and musicbrainz_mbid is not null)
    or (origin <> 'musicbrainz' and musicbrainz_mbid is null)
  ),
  constraint catalog_entities_merge_state_check check (
    (status = 'merged' and merged_into_id is not null and merged_into_id <> id)
    or (status <> 'merged' and merged_into_id is null)
  )
);

create unique index catalog_entities_musicbrainz_identity
  on public.catalog_entities (kind, musicbrainz_mbid)
  where musicbrainz_mbid is not null;
create index catalog_entities_name_search
  on public.catalog_entities using gin (display_name gin_trgm_ops);
create index catalog_entities_sort_search
  on public.catalog_entities using gin (sort_name gin_trgm_ops);

create table public.catalog_areas (
  id uuid primary key,
  kind public.catalog_entity_kind not null default 'area'
    check (kind = 'area'),
  area_type text,
  country_code text,
  subdivision_code text,
  parent_area_id uuid references public.catalog_areas (id) on delete restrict,
  constraint catalog_areas_entity_fk foreign key (id, kind)
    references public.catalog_entities (id, kind) on delete cascade,
  constraint catalog_areas_type_check check (
    area_type is null or private.is_normalized_concert_text(area_type, 80)
  ),
  constraint catalog_areas_country_code_check check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  constraint catalog_areas_subdivision_code_check check (
    subdivision_code is null or subdivision_code ~ '^[A-Z0-9]{1,3}(-[A-Z0-9]{1,4})?$'
  ),
  constraint catalog_areas_parent_check check (parent_area_id is null or parent_area_id <> id)
);

create table public.catalog_artists (
  id uuid primary key,
  kind public.catalog_entity_kind not null default 'artist'
    check (kind = 'artist'),
  artist_type text,
  country_code text,
  area_id uuid references public.catalog_areas (id) on delete restrict,
  area_name text,
  life_span_begin text,
  life_span_end text,
  ended boolean,
  constraint catalog_artists_entity_fk foreign key (id, kind)
    references public.catalog_entities (id, kind) on delete cascade,
  constraint catalog_artists_type_check check (
    artist_type is null or private.is_normalized_concert_text(artist_type, 80)
  ),
  constraint catalog_artists_country_code_check check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  constraint catalog_artists_area_name_check check (
    area_name is null or private.is_normalized_concert_text(area_name, 160)
  ),
  constraint catalog_artists_life_span_begin_check check (
    life_span_begin is null or life_span_begin ~ '^([0-9]{4}|[0-9]{4}-(0[1-9]|1[0-2])|[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1]))$'
  ),
  constraint catalog_artists_life_span_end_check check (
    life_span_end is null or life_span_end ~ '^([0-9]{4}|[0-9]{4}-(0[1-9]|1[0-2])|[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1]))$'
  )
);

create table public.catalog_places (
  id uuid primary key,
  kind public.catalog_entity_kind not null default 'place'
    check (kind = 'place'),
  area_id uuid references public.catalog_areas (id) on delete restrict,
  place_type text,
  address text,
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  ended boolean,
  constraint catalog_places_entity_fk foreign key (id, kind)
    references public.catalog_entities (id, kind) on delete cascade,
  constraint catalog_places_type_check check (
    place_type is null or private.is_normalized_concert_text(place_type, 80)
  ),
  constraint catalog_places_address_check check (
    address is null or private.is_normalized_concert_text(address, 240)
  ),
  constraint catalog_places_latitude_check check (
    latitude is null or latitude between -90 and 90
  ),
  constraint catalog_places_longitude_check check (
    longitude is null or longitude between -180 and 180
  )
);

create table public.catalog_songs (
  id uuid primary key,
  kind public.catalog_entity_kind not null default 'song'
    check (kind = 'song'),
  work_mbid uuid,
  duration_ms integer,
  first_release_date text,
  artist_credit text,
  constraint catalog_songs_entity_fk foreign key (id, kind)
    references public.catalog_entities (id, kind) on delete cascade,
  constraint catalog_songs_duration_check check (duration_ms is null or duration_ms >= 0),
  constraint catalog_songs_first_release_date_check check (
    first_release_date is null or first_release_date ~ '^([0-9]{4}|[0-9]{4}-(0[1-9]|1[0-2])|[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[0-1]))$'
  ),
  constraint catalog_songs_artist_credit_check check (
    artist_credit is null or private.is_normalized_concert_text(artist_credit, 320)
  )
);

create table public.catalog_song_artists (
  song_id uuid not null references public.catalog_songs (id) on delete cascade,
  artist_id uuid not null references public.catalog_artists (id) on delete restrict,
  credit_position smallint not null,
  credit_name text,
  join_phrase text not null default '',
  primary key (song_id, credit_position),
  constraint catalog_song_artists_artist_unique unique (song_id, artist_id),
  constraint catalog_song_artists_position_check check (credit_position between 1 and 50),
  constraint catalog_song_artists_credit_name_check check (
    credit_name is null or private.is_normalized_concert_text(credit_name, 160)
  ),
  constraint catalog_song_artists_join_phrase_check check (
    char_length(join_phrase) <= 40 and not private.contains_control_characters(join_phrase)
  )
);

create table public.catalog_tours (
  id uuid primary key,
  kind public.catalog_entity_kind not null default 'tour'
    check (kind = 'tour'),
  series_type text not null default 'Tour',
  constraint catalog_tours_entity_fk foreign key (id, kind)
    references public.catalog_entities (id, kind) on delete cascade,
  constraint catalog_tours_series_type_check check (
    private.is_normalized_concert_text(series_type, 80)
  )
);

create table public.catalog_tour_artists (
  tour_id uuid not null references public.catalog_tours (id) on delete cascade,
  artist_id uuid not null references public.catalog_artists (id) on delete restrict,
  credit_position smallint not null,
  primary key (tour_id, credit_position),
  constraint catalog_tour_artists_artist_unique unique (tour_id, artist_id),
  constraint catalog_tour_artists_position_check check (credit_position between 1 and 50)
);

create index catalog_places_area on public.catalog_places (area_id);
create index catalog_artists_area on public.catalog_artists (area_id);
create index catalog_song_artists_artist on public.catalog_song_artists (artist_id, song_id);
create index catalog_tour_artists_artist on public.catalog_tour_artists (artist_id, tour_id);

-- Creator and ingestion provenance is deliberately private. Catalog projections
-- never expose creator identity.
create table private.catalog_entity_provenance (
  entity_id uuid primary key,
  kind public.catalog_entity_kind not null,
  creator_id uuid references public.profiles (id) on delete set null,
  ingested_by uuid references public.profiles (id) on delete set null,
  dedupe_key text,
  source_updated_at timestamptz,
  refreshed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint catalog_entity_provenance_entity_fk foreign key (entity_id, kind)
    references public.catalog_entities (id, kind) on delete cascade,
  constraint catalog_entity_provenance_dedupe_check check (
    dedupe_key is null or (char_length(dedupe_key) between 1 and 1000 and dedupe_key !~ '[[:cntrl:]]')
  )
);

create unique index catalog_entity_provenance_creator_dedupe
  on private.catalog_entity_provenance (creator_id, kind, dedupe_key)
  where creator_id is not null and dedupe_key is not null;
create index catalog_entity_provenance_creator
  on private.catalog_entity_provenance (creator_id, kind, created_at desc);

create table private.catalog_creation_quota_config (
  kind public.catalog_entity_kind primary key,
  rolling_hour_limit integer not null check (rolling_hour_limit > 0),
  rolling_day_limit integer not null check (rolling_day_limit >= rolling_hour_limit)
);

insert into private.catalog_creation_quota_config (kind, rolling_hour_limit, rolling_day_limit)
values
  ('artist', 30, 100),
  ('area', 20, 50),
  ('place', 30, 100),
  ('song', 60, 200),
  ('tour', 30, 100);

-- Rate limiting and upstream coordination store only opaque UUIDs and request
-- hashes; raw search terms, result names, URLs, and response bodies are never
-- written to audit/log tables.
create table private.catalog_search_requests (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  requested_at timestamptz not null default clock_timestamp()
);
create index catalog_search_requests_window
  on private.catalog_search_requests (profile_id, requested_at desc);

create table private.musicbrainz_cache (
  cache_key text primary key,
  kind public.catalog_entity_kind not null,
  request_type text not null check (request_type in ('search', 'lookup')),
  payload jsonb not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint musicbrainz_cache_key_check check (cache_key ~ '^v1:[a-f0-9]{64}$'),
  constraint musicbrainz_cache_payload_check check (jsonb_typeof(payload) in ('object', 'array'))
);
create index musicbrainz_cache_expiry on private.musicbrainz_cache (expires_at);

create table private.musicbrainz_request_leases (
  cache_key text primary key,
  lease_id uuid not null,
  lease_expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint musicbrainz_request_leases_key_check check (cache_key ~ '^v1:[a-f0-9]{64}$')
);
create index musicbrainz_request_leases_expiry
  on private.musicbrainz_request_leases (lease_expires_at);

create table private.musicbrainz_request_gate (
  singleton boolean primary key default true check (singleton),
  next_available_at timestamptz not null default '-infinity'::timestamptz
);
insert into private.musicbrainz_request_gate (singleton) values (true);

alter table public.concerts
  add column catalog_place_id uuid references public.catalog_places (id) on delete restrict,
  add column catalog_area_id uuid references public.catalog_areas (id) on delete restrict,
  add column catalog_tour_id uuid references public.catalog_tours (id) on delete restrict;

alter table public.concert_artists
  add column catalog_artist_id uuid references public.catalog_artists (id) on delete restrict;

alter table public.setlist_items
  add column catalog_song_id uuid references public.catalog_songs (id) on delete restrict;

create index concerts_catalog_place on public.concerts (catalog_place_id);
create index concerts_catalog_area on public.concerts (catalog_area_id);
create index concerts_catalog_tour on public.concerts (catalog_tour_id);
create index concert_artists_catalog_artist on public.concert_artists (catalog_artist_id);
create index setlist_items_catalog_song on public.setlist_items (catalog_song_id);

create function private.touch_catalog_entity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger set_catalog_entity_updated_at
before update on public.catalog_entities
for each row execute function private.touch_catalog_entity();

create function private.assert_catalog_merge_target()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_target_kind public.catalog_entity_kind;
  v_target_status public.catalog_entity_status;
begin
  if new.merged_into_id is null then
    return new;
  end if;

  select kind, status into v_target_kind, v_target_status
  from public.catalog_entities
  where id = new.merged_into_id;

  if not found or v_target_kind <> new.kind or v_target_status not in ('active', 'needs_review') then
    raise exception 'A merged catalog entity must target a usable entity of the same kind'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger catalog_entities_validate_merge_target
before insert or update of status, merged_into_id on public.catalog_entities
for each row execute function private.assert_catalog_merge_target();

create function private.normalize_catalog_key(p_value text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select lower(private.normalize_concert_text(p_value))
$$;

create function private.optional_catalog_text(
  p_value text,
  p_maximum_length integer,
  p_field_name text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select private.optional_concert_text(p_value, p_maximum_length, p_field_name)
$$;

-- MusicBrainz artist-credit join phrases are presentation data whose leading
-- and trailing spaces are significant (for example, " feat. "). Preserve the
-- source value exactly while still enforcing a small safe storage boundary.
create function private.musicbrainz_join_phrase(p_value text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null then
    return '';
  end if;
  if pg_catalog.char_length(p_value) > 40
    or private.contains_control_characters(p_value)
  then
    raise exception 'MusicBrainz join phrase is invalid'
      using errcode = '22023';
  end if;
  return p_value;
end;
$$;

create function private.can_use_catalog_entity_as(
  p_user_id uuid,
  p_entity_id uuid,
  p_kind public.catalog_entity_kind,
  p_concert_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.catalog_entities as entity
    where entity.id = p_entity_id
      and entity.kind = p_kind
      and entity.status in ('active', 'needs_review')
      and (
        entity.origin = 'musicbrainz'
        or exists (
          select 1
          from private.catalog_entity_provenance as provenance
          where provenance.entity_id = entity.id
            and provenance.creator_id = p_user_id
        )
        or (
          p_concert_id is not null
          and private.is_concert_editor_as(p_user_id, p_concert_id)
          and (
            (p_kind = 'place' and exists (
              select 1 from public.concerts
              where id = p_concert_id and catalog_place_id = p_entity_id
            ))
            or (p_kind = 'area' and exists (
              select 1 from public.concerts
              where id = p_concert_id and catalog_area_id = p_entity_id
            ))
            or (p_kind = 'tour' and exists (
              select 1 from public.concerts
              where id = p_concert_id and catalog_tour_id = p_entity_id
            ))
            or (p_kind = 'artist' and exists (
              select 1 from public.concert_artists
              where concert_id = p_concert_id and catalog_artist_id = p_entity_id
            ))
            or (p_kind = 'song' and exists (
              select 1 from public.setlist_items
              where concert_id = p_concert_id and catalog_song_id = p_entity_id
            ))
          )
        )
      )
  )
$$;

create function private.assert_catalog_creation_quota(
  p_creator_id uuid,
  p_kind public.catalog_entity_kind
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
    pg_catalog.hashtextextended('catalog-quota:' || p_creator_id::text || ':' || p_kind::text, 0)
  );

  select rolling_hour_limit, rolling_day_limit
  into v_hour_limit, v_day_limit
  from private.catalog_creation_quota_config
  where kind = p_kind;

  if not found then
    raise exception 'Catalog creation is not configured for this entity type'
      using errcode = 'P0001';
  end if;

  select
    count(*) filter (where provenance.created_at >= clock_timestamp() - interval '1 hour'),
    count(*)
  into v_hour_count, v_day_count
  from private.catalog_entity_provenance as provenance
  join public.catalog_entities as entity on entity.id = provenance.entity_id
  where provenance.creator_id = p_creator_id
    and provenance.kind = p_kind
    and provenance.created_at >= clock_timestamp() - interval '24 hours'
    and entity.origin in ('tunedin_custom', 'legacy_client');

  if v_hour_count >= v_hour_limit or v_day_count >= v_day_limit then
    raise exception 'You have reached the custom % limit. Try again later.', p_kind::text
      using errcode = 'P0001';
  end if;
end;
$$;

create function private.get_or_create_local_catalog_entity(
  p_creator_id uuid,
  p_kind public.catalog_entity_kind,
  p_origin public.catalog_entity_origin,
  p_display_name text,
  p_sort_name text,
  p_disambiguation text,
  p_dedupe_key text,
  p_enforce_quota boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity_id uuid;
  v_display_name text;
  v_sort_name text;
  v_disambiguation text;
begin
  if p_creator_id is null or not private.has_completed_profile(p_creator_id) then
    raise exception 'Complete onboarding before creating catalog entries'
      using errcode = '42501';
  end if;

  if p_origin not in ('tunedin_custom', 'legacy_import', 'legacy_client') then
    raise exception 'Local catalog entries require local provenance'
      using errcode = '22023';
  end if;

  v_display_name := private.require_concert_text(p_display_name, 160, 'Catalog name');
  v_sort_name := private.require_concert_text(coalesce(p_sort_name, v_display_name), 160, 'Catalog sort name');
  v_disambiguation := private.optional_catalog_text(p_disambiguation, 240, 'Catalog disambiguation');

  if p_dedupe_key is null or char_length(p_dedupe_key) not between 1 and 1000
    or private.contains_control_characters(p_dedupe_key)
  then
    raise exception 'A valid catalog duplicate key is required'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'catalog-entity:' || p_creator_id::text || ':' || p_kind::text || ':' || p_dedupe_key,
      0
    )
  );

  select entity.id
  into v_entity_id
  from private.catalog_entity_provenance as provenance
  join public.catalog_entities as entity on entity.id = provenance.entity_id
  where provenance.creator_id = p_creator_id
    and provenance.kind = p_kind
    and provenance.dedupe_key = p_dedupe_key
    and entity.status in ('active', 'needs_review')
  limit 1;

  if found then
    return v_entity_id;
  end if;

  if p_enforce_quota then
    perform private.assert_catalog_creation_quota(p_creator_id, p_kind);
  end if;

  insert into public.catalog_entities (
    kind,
    origin,
    status,
    display_name,
    sort_name,
    disambiguation
  )
  values (
    p_kind,
    p_origin,
    case when p_origin in ('legacy_import', 'legacy_client')
      then 'needs_review'::public.catalog_entity_status
      else 'active'::public.catalog_entity_status
    end,
    v_display_name,
    v_sort_name,
    v_disambiguation
  )
  returning id into v_entity_id;

  insert into private.catalog_entity_provenance (
    entity_id,
    kind,
    creator_id,
    ingested_by,
    dedupe_key
  )
  values (v_entity_id, p_kind, p_creator_id, p_creator_id, p_dedupe_key);

  return v_entity_id;
end;
$$;

create function private.resolve_local_artist(
  p_creator_id uuid,
  p_name text,
  p_origin public.catalog_entity_origin,
  p_artist_type text default null,
  p_disambiguation text default null,
  p_area_id uuid default null,
  p_enforce_quota boolean default true,
  p_concert_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := private.require_concert_text(p_name, 160, 'Artist name');
  v_artist_type text := private.optional_catalog_text(p_artist_type, 80, 'Artist type');
  v_disambiguation text := private.optional_catalog_text(p_disambiguation, 240, 'Artist disambiguation');
  v_area_name text;
  v_entity_id uuid;
  v_key text;
begin
  if p_area_id is not null then
    select entity.display_name into v_area_name
    from public.catalog_areas as area
    join public.catalog_entities as entity on entity.id = area.id
    where area.id = p_area_id
      and entity.status in ('active', 'needs_review');
    if not found or not private.can_use_catalog_entity_as(
      p_creator_id, p_area_id, 'area', p_concert_id
    ) then
      raise exception 'Choose an available catalog area'
        using errcode = '22023';
    end if;
  end if;

  v_key := 'artist|' || private.normalize_catalog_key(v_name)
    || '|type:' || coalesce(lower(v_artist_type), '-')
    || '|area:' || coalesce(p_area_id::text, '-')
    || '|disambiguation:' || coalesce(lower(v_disambiguation), '-');

  v_entity_id := private.get_or_create_local_catalog_entity(
    p_creator_id,
    'artist',
    p_origin,
    v_name,
    v_name,
    v_disambiguation,
    v_key,
    p_enforce_quota
  );

  insert into public.catalog_artists (id, artist_type, area_id, area_name)
  values (v_entity_id, v_artist_type, p_area_id, v_area_name)
  on conflict (id) do nothing;

  return v_entity_id;
end;
$$;

create function private.resolve_local_area(
  p_creator_id uuid,
  p_name text,
  p_origin public.catalog_entity_origin,
  p_country_code text default null,
  p_parent_area_id uuid default null,
  p_enforce_quota boolean default true,
  p_concert_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := private.require_concert_text(p_name, 160, 'Area name');
  v_country_code text := nullif(upper(btrim(coalesce(p_country_code, ''))), '');
  v_entity_id uuid;
  v_key text;
begin
  if v_country_code is not null and v_country_code !~ '^[A-Z]{2}$' then
    raise exception 'Country code must contain two letters'
      using errcode = '22023';
  end if;

  if p_parent_area_id is not null and (
    not private.can_use_catalog_entity_as(
      p_creator_id, p_parent_area_id, 'area', p_concert_id
    )
    or not exists (
    select 1
    from public.catalog_areas as area
    join public.catalog_entities as entity on entity.id = area.id
    where area.id = p_parent_area_id
      and entity.status in ('active', 'needs_review')
    )
  ) then
    raise exception 'Choose an available parent area'
      using errcode = '22023';
  end if;

  v_key := 'area|' || private.normalize_catalog_key(v_name)
    || '|country:' || coalesce(v_country_code, '-')
    || '|parent:' || coalesce(p_parent_area_id::text, '-');

  v_entity_id := private.get_or_create_local_catalog_entity(
    p_creator_id,
    'area',
    p_origin,
    v_name,
    v_name,
    null,
    v_key,
    p_enforce_quota
  );

  insert into public.catalog_areas (id, country_code, parent_area_id)
  values (v_entity_id, v_country_code, p_parent_area_id)
  on conflict (id) do nothing;

  return v_entity_id;
end;
$$;

create function private.resolve_local_place(
  p_creator_id uuid,
  p_name text,
  p_origin public.catalog_entity_origin,
  p_area_id uuid default null,
  p_place_type text default null,
  p_address text default null,
  p_disambiguation text default null,
  p_enforce_quota boolean default true,
  p_concert_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := private.require_concert_text(p_name, 160, 'Venue name');
  v_place_type text := private.optional_catalog_text(p_place_type, 80, 'Place type');
  v_address text := private.optional_catalog_text(p_address, 240, 'Address');
  v_disambiguation text := private.optional_catalog_text(p_disambiguation, 240, 'Place disambiguation');
  v_entity_id uuid;
  v_key text;
begin
  if p_area_id is not null and (
    not private.can_use_catalog_entity_as(
      p_creator_id, p_area_id, 'area', p_concert_id
    )
    or not exists (
    select 1
    from public.catalog_areas as area
    join public.catalog_entities as entity on entity.id = area.id
    where area.id = p_area_id
      and entity.status in ('active', 'needs_review')
    )
  ) then
    raise exception 'Choose an available catalog area'
      using errcode = '22023';
  end if;

  v_key := 'place|' || private.normalize_catalog_key(v_name)
    || '|area:' || coalesce(p_area_id::text, '-');

  v_entity_id := private.get_or_create_local_catalog_entity(
    p_creator_id,
    'place',
    p_origin,
    v_name,
    v_name,
    v_disambiguation,
    v_key,
    p_enforce_quota
  );

  insert into public.catalog_places (id, area_id, place_type, address)
  values (v_entity_id, p_area_id, v_place_type, v_address)
  on conflict (id) do nothing;

  return v_entity_id;
end;
$$;

create function private.resolve_local_song(
  p_creator_id uuid,
  p_title text,
  p_origin public.catalog_entity_origin,
  p_artist_ids uuid[],
  p_disambiguation text default null,
  p_enforce_quota boolean default true,
  p_concert_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text := private.require_concert_text(p_title, 160, 'Song title');
  v_disambiguation text := private.optional_catalog_text(p_disambiguation, 240, 'Song disambiguation');
  v_artist_id uuid;
  v_artist_name text;
  v_artist_names text[] := '{}';
  v_position integer := 0;
  v_entity_id uuid;
  v_key text;
begin
  if p_artist_ids is null or cardinality(p_artist_ids) not between 1 and 50
    or cardinality(p_artist_ids) <> cardinality(array(select distinct item from unnest(p_artist_ids) as item))
  then
    raise exception 'Songs require between 1 and 50 distinct catalog artists'
      using errcode = '22023';
  end if;

  foreach v_artist_id in array p_artist_ids loop
    if not private.can_use_catalog_entity_as(
      p_creator_id, v_artist_id, 'artist', p_concert_id
    ) then
      raise no_data_found;
    end if;
    select entity.display_name
    into strict v_artist_name
    from public.catalog_artists as artist
    join public.catalog_entities as entity on entity.id = artist.id
    where artist.id = v_artist_id
      and entity.status in ('active', 'needs_review');
    v_artist_names := array_append(v_artist_names, v_artist_name);
  end loop;

  v_key := 'song|' || private.normalize_catalog_key(v_title)
    || '|artists:' || array_to_string(p_artist_ids, ',')
    || '|disambiguation:' || coalesce(lower(v_disambiguation), '-');

  v_entity_id := private.get_or_create_local_catalog_entity(
    p_creator_id,
    'song',
    p_origin,
    v_title,
    v_title,
    v_disambiguation,
    v_key,
    p_enforce_quota
  );

  insert into public.catalog_songs (id, artist_credit)
  values (v_entity_id, left(array_to_string(v_artist_names, ', '), 320))
  on conflict (id) do nothing;

  foreach v_artist_id in array p_artist_ids loop
    v_position := v_position + 1;
    insert into public.catalog_song_artists (song_id, artist_id, credit_position)
    values (v_entity_id, v_artist_id, v_position)
    on conflict do nothing;
  end loop;

  return v_entity_id;
exception
  when no_data_found then
    raise exception 'Choose only available catalog artists for the song'
      using errcode = '22023';
end;
$$;

create function private.resolve_local_tour(
  p_creator_id uuid,
  p_name text,
  p_origin public.catalog_entity_origin,
  p_artist_ids uuid[],
  p_disambiguation text default null,
  p_enforce_quota boolean default true,
  p_concert_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := private.require_concert_text(p_name, 160, 'Tour');
  v_disambiguation text := private.optional_catalog_text(p_disambiguation, 240, 'Tour disambiguation');
  v_artist_id uuid;
  v_position integer := 0;
  v_entity_id uuid;
  v_key text;
begin
  if p_artist_ids is null or cardinality(p_artist_ids) not between 1 and 50
    or cardinality(p_artist_ids) <> cardinality(array(select distinct item from unnest(p_artist_ids) as item))
  then
    raise exception 'Tours require between 1 and 50 distinct catalog artists'
      using errcode = '22023';
  end if;

  foreach v_artist_id in array p_artist_ids loop
    if not private.can_use_catalog_entity_as(
      p_creator_id, v_artist_id, 'artist', p_concert_id
    )
      or not exists (
      select 1
      from public.catalog_artists as artist
      join public.catalog_entities as entity on entity.id = artist.id
      where artist.id = v_artist_id
        and entity.status in ('active', 'needs_review')
    ) then
      raise exception 'Choose only available catalog artists for the tour'
        using errcode = '22023';
    end if;
  end loop;

  v_key := 'tour|' || private.normalize_catalog_key(v_name)
    || '|artists:' || array_to_string(p_artist_ids, ',');

  v_entity_id := private.get_or_create_local_catalog_entity(
    p_creator_id,
    'tour',
    p_origin,
    v_name,
    v_name,
    v_disambiguation,
    v_key,
    p_enforce_quota
  );

  insert into public.catalog_tours (id)
  values (v_entity_id)
  on conflict (id) do nothing;

  foreach v_artist_id in array p_artist_ids loop
    v_position := v_position + 1;
    insert into public.catalog_tour_artists (tour_id, artist_id, credit_position)
    values (v_entity_id, v_artist_id, v_position)
    on conflict do nothing;
  end loop;

  return v_entity_id;
end;
$$;

-- Exact, owner-scoped legacy backfill. No fuzzy matching or MusicBrainz
-- assignment occurs in this migration.
do $$
declare
  v_row record;
  v_entity_id uuid;
begin
  for v_row in
    select distinct concert.owner_id, artist.artist_name
    from public.concert_artists as artist
    join public.concerts as concert on concert.id = artist.concert_id
  loop
    v_entity_id := private.resolve_local_artist(
      v_row.owner_id,
      v_row.artist_name,
      'legacy_import',
      p_enforce_quota => false
    );
    update public.concert_artists as artist
    set catalog_artist_id = v_entity_id
    from public.concerts as concert
    where concert.id = artist.concert_id
      and concert.owner_id = v_row.owner_id
      and artist.artist_name = v_row.artist_name;
  end loop;

  for v_row in
    select distinct owner_id, city
    from public.concerts
    where city is not null
  loop
    perform private.resolve_local_area(
      v_row.owner_id,
      v_row.city,
      'legacy_import',
      p_enforce_quota => false
    );
  end loop;

  for v_row in
    select distinct owner_id, venue_name, city
    from public.concerts
  loop
    v_entity_id := private.resolve_local_place(
      v_row.owner_id,
      v_row.venue_name,
      'legacy_import',
      case when v_row.city is null then null else private.resolve_local_area(
        v_row.owner_id,
        v_row.city,
        'legacy_import',
        p_enforce_quota => false
      ) end,
      p_enforce_quota => false
    );
    update public.concerts
    set
      catalog_place_id = v_entity_id,
      catalog_area_id = (select area_id from public.catalog_places where id = v_entity_id)
    where owner_id = v_row.owner_id
      and venue_name = v_row.venue_name
      and city is not distinct from v_row.city;
  end loop;

  for v_row in
    select distinct
      concert.owner_id,
      concert.tour,
      artist.catalog_artist_id
    from public.concerts as concert
    join public.concert_artists as artist
      on artist.concert_id = concert.id and artist.is_primary
    where concert.tour is not null
  loop
    v_entity_id := private.resolve_local_tour(
      v_row.owner_id,
      v_row.tour,
      'legacy_import',
      array[v_row.catalog_artist_id],
      p_enforce_quota => false
    );
    update public.concerts as concert
    set catalog_tour_id = v_entity_id
    where concert.owner_id = v_row.owner_id
      and concert.tour = v_row.tour
      and exists (
        select 1
        from public.concert_artists as artist
        where artist.concert_id = concert.id
          and artist.is_primary
          and artist.catalog_artist_id = v_row.catalog_artist_id
      );
  end loop;

  for v_row in
    select distinct
      concert.owner_id,
      item.song_title,
      artist.catalog_artist_id
    from public.setlist_items as item
    join public.concerts as concert on concert.id = item.concert_id
    join public.concert_artists as artist
      on artist.concert_id = concert.id and artist.is_primary
  loop
    v_entity_id := private.resolve_local_song(
      v_row.owner_id,
      v_row.song_title,
      'legacy_import',
      array[v_row.catalog_artist_id],
      p_enforce_quota => false
    );
    update public.setlist_items as item
    set catalog_song_id = v_entity_id
    from public.concerts as concert
    where concert.id = item.concert_id
      and concert.owner_id = v_row.owner_id
      and item.song_title = v_row.song_title
      and exists (
        select 1
        from public.concert_artists as artist
        where artist.concert_id = concert.id
          and artist.is_primary
          and artist.catalog_artist_id = v_row.catalog_artist_id
      );
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from public.concerts where catalog_place_id is null)
    or exists (select 1 from public.concert_artists where catalog_artist_id is null)
    or exists (select 1 from public.setlist_items where catalog_song_id is null)
  then
    raise exception 'Catalog backfill left required concert references unresolved';
  end if;
end;
$$;

-- Backfill updates queue the pre-existing deferred lineup checks. Execute them
-- before ALTER TABLE, which rejects relations with pending trigger events.
do $$
begin
  execute 'set constraints public.concerts_require_valid_lineup, '
    || 'public.concert_artists_require_valid_lineup immediate';
end;
$$;

alter table public.concerts
  alter column catalog_place_id set not null;
alter table public.concert_artists
  alter column catalog_artist_id set not null;
alter table public.setlist_items
  alter column catalog_song_id set not null;

create function private.catalog_metadata(p_entity_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case entity.kind
    when 'artist' then (
      select jsonb_build_object(
        'artistType', artist.artist_type,
        'countryCode', artist.country_code,
        'areaCatalogId', artist.area_id,
        'areaMusicBrainzId', area_entity.musicbrainz_mbid,
        'areaName', artist.area_name,
        'lifeSpanBegin', artist.life_span_begin,
        'lifeSpanEnd', artist.life_span_end,
        'ended', artist.ended
      )
      from public.catalog_artists as artist
      left join public.catalog_entities as area_entity on area_entity.id = artist.area_id
      where artist.id = entity.id
    )
    when 'area' then (
      select jsonb_build_object(
        'areaType', area.area_type,
        'countryCode', area.country_code,
        'subdivisionCode', area.subdivision_code,
        'parentAreaCatalogId', area.parent_area_id,
        'parentMusicBrainzId', parent_entity.musicbrainz_mbid,
        'parentName', parent_entity.display_name
      )
      from public.catalog_areas as area
      left join public.catalog_entities as parent_entity on parent_entity.id = area.parent_area_id
      where area.id = entity.id
    )
    when 'place' then (
      select jsonb_build_object(
        'placeType', place.place_type,
        'address', place.address,
        'latitude', place.latitude,
        'longitude', place.longitude,
        'ended', place.ended,
        'areaCatalogId', place.area_id,
        'areaMusicBrainzId', area_entity.musicbrainz_mbid,
        'areaName', area_entity.display_name
      )
      from public.catalog_places as place
      left join public.catalog_entities as area_entity on area_entity.id = place.area_id
      where place.id = entity.id
    )
    when 'song' then (
      select jsonb_build_object(
        'workMusicBrainzId', song.work_mbid,
        'durationMs', song.duration_ms,
        'firstReleaseDate', song.first_release_date,
        'artistCredit', coalesce((
          select jsonb_agg(jsonb_build_object(
            'artistCatalogId', credit.artist_id,
            'artistMusicBrainzId', artist_entity.musicbrainz_mbid,
            'name', coalesce(credit.credit_name, artist_entity.display_name),
            'canonicalName', artist_entity.display_name,
            'joinPhrase', credit.join_phrase
          ) order by credit.credit_position)
          from public.catalog_song_artists as credit
          join public.catalog_entities as artist_entity on artist_entity.id = credit.artist_id
          where credit.song_id = song.id
        ), '[]'::jsonb)
      )
      from public.catalog_songs as song
      where song.id = entity.id
    )
    when 'tour' then (
      select jsonb_build_object(
        'seriesType', tour.series_type,
        'disambiguation', entity.disambiguation,
        'artistCredit', coalesce((
          select jsonb_agg(jsonb_build_object(
            'artistCatalogId', credit.artist_id,
            'artistMusicBrainzId', artist_entity.musicbrainz_mbid,
            'name', artist_entity.display_name,
            'canonicalName', artist_entity.display_name,
            'joinPhrase', ''
          ) order by credit.credit_position)
          from public.catalog_tour_artists as credit
          join public.catalog_entities as artist_entity on artist_entity.id = credit.artist_id
          where credit.tour_id = tour.id
        ), '[]'::jsonb)
      )
      from public.catalog_tours as tour
      where tour.id = entity.id
    )
  end
  from public.catalog_entities as entity
  where entity.id = p_entity_id
$$;

create function private.catalog_subtitle(p_entity_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select left(case entity.kind
    when 'artist' then (
      select nullif(concat_ws(' • ', artist.artist_type, artist.area_name), '')
      from public.catalog_artists as artist where artist.id = entity.id
    )
    when 'area' then (
      select nullif(concat_ws(' • ', area.area_type, parent.display_name, area.country_code), '')
      from public.catalog_areas as area
      left join public.catalog_entities as parent on parent.id = area.parent_area_id
      where area.id = entity.id
    )
    when 'place' then (
      select nullif(concat_ws(' • ', place.place_type, area.display_name, place.address), '')
      from public.catalog_places as place
      left join public.catalog_entities as area on area.id = place.area_id
      where place.id = entity.id
    )
    when 'song' then (
      select nullif(concat_ws(' • ', song.artist_credit, song.first_release_date), '')
      from public.catalog_songs as song where song.id = entity.id
    )
    when 'tour' then (
      select nullif(concat_ws(' • ', tour.series_type, (
        select string_agg(artist.display_name, ', ' order by credit.credit_position)
        from public.catalog_tour_artists as credit
        join public.catalog_entities as artist on artist.id = credit.artist_id
        where credit.tour_id = tour.id
      ), entity.disambiguation), '')
      from public.catalog_tours as tour where tour.id = entity.id
    )
  end, 500)
  from public.catalog_entities as entity
  where entity.id = p_entity_id
$$;

create function private.catalog_selection(p_entity_id uuid)
returns table (
  id uuid,
  kind public.catalog_entity_kind,
  origin public.catalog_entity_origin,
  display_name text,
  sort_name text,
  disambiguation text,
  musicbrainz_mbid uuid,
  subtitle text,
  metadata jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    entity.id,
    entity.kind,
    entity.origin,
    entity.display_name,
    entity.sort_name,
    entity.disambiguation,
    entity.musicbrainz_mbid,
    private.catalog_subtitle(entity.id),
    private.catalog_metadata(entity.id)
  from public.catalog_entities as entity
  where entity.id = p_entity_id
$$;

create function private.can_read_catalog_entity_as(p_user_id uuid, p_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.catalog_entities as entity
    where entity.id = p_entity_id
      and (
        (entity.origin = 'musicbrainz' and entity.status in ('active', 'needs_review'))
        or exists (
          select 1
          from private.catalog_entity_provenance as provenance
          where provenance.entity_id = entity.id
            and provenance.creator_id = p_user_id
        )
        or exists (
          select 1
          from public.concerts as concert
          where private.can_view_concert_as(p_user_id, concert.id)
            and entity.id in (concert.catalog_place_id, concert.catalog_area_id, concert.catalog_tour_id)
        )
        or exists (
          select 1
          from public.concert_artists as artist
          where artist.catalog_artist_id = entity.id
            and private.can_view_concert_as(p_user_id, artist.concert_id)
        )
        or exists (
          select 1
          from public.setlist_items as item
          where item.catalog_song_id = entity.id
            and private.can_view_concert_as(p_user_id, item.concert_id)
        )
        or (
          entity.kind = 'area'
          and exists (
            select 1
            from public.catalog_places as place
            join public.concerts as concert on concert.catalog_place_id = place.id
            where place.area_id = entity.id
              and private.can_view_concert_as(p_user_id, concert.id)
          )
        )
        or (
          entity.kind = 'artist'
          and (
            exists (
              select 1
              from public.catalog_song_artists as credit
              join public.setlist_items as item on item.catalog_song_id = credit.song_id
              where credit.artist_id = entity.id
                and private.can_view_concert_as(p_user_id, item.concert_id)
            )
            or exists (
              select 1
              from public.catalog_tour_artists as credit
              join public.concerts as concert on concert.catalog_tour_id = credit.tour_id
              where credit.artist_id = entity.id
                and private.can_view_concert_as(p_user_id, concert.id)
            )
          )
        )
      )
  )
$$;

alter table public.catalog_entities enable row level security;
alter table public.catalog_areas enable row level security;
alter table public.catalog_artists enable row level security;
alter table public.catalog_places enable row level security;
alter table public.catalog_songs enable row level security;
alter table public.catalog_song_artists enable row level security;
alter table public.catalog_tours enable row level security;
alter table public.catalog_tour_artists enable row level security;

create policy "catalog_entities_select_allowed"
on public.catalog_entities for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), id)));
create policy "catalog_areas_select_allowed"
on public.catalog_areas for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), id)));
create policy "catalog_artists_select_allowed"
on public.catalog_artists for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), id)));
create policy "catalog_places_select_allowed"
on public.catalog_places for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), id)));
create policy "catalog_songs_select_allowed"
on public.catalog_songs for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), id)));
create policy "catalog_song_artists_select_allowed"
on public.catalog_song_artists for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), song_id)));
create policy "catalog_tours_select_allowed"
on public.catalog_tours for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), id)));
create policy "catalog_tour_artists_select_allowed"
on public.catalog_tour_artists for select to authenticated
using ((select private.can_read_catalog_entity_as(auth.uid(), tour_id)));

revoke all on table
  public.catalog_entities,
  public.catalog_areas,
  public.catalog_artists,
  public.catalog_places,
  public.catalog_songs,
  public.catalog_song_artists,
  public.catalog_tours,
  public.catalog_tour_artists
from anon, authenticated;
grant select on table
  public.catalog_entities,
  public.catalog_areas,
  public.catalog_artists,
  public.catalog_places,
  public.catalog_songs,
  public.catalog_song_artists,
  public.catalog_tours,
  public.catalog_tour_artists
to authenticated;

create function private.apply_concert_catalog_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area_id uuid;
begin
  if tg_op = 'UPDATE' and new.catalog_place_id is not distinct from old.catalog_place_id then
    new.catalog_area_id := old.catalog_area_id;
    new.venue_name := old.venue_name;
    new.city := old.city;
  else
  if new.catalog_place_id is null then
    if new.city is not null then
      v_area_id := private.resolve_local_area(
        new.owner_id, new.city, 'legacy_client', p_enforce_quota => false
      );
    end if;
    new.catalog_place_id := private.resolve_local_place(
      new.owner_id,
      new.venue_name,
      'legacy_client',
      v_area_id,
      p_enforce_quota => false
    );
  end if;

  select place.area_id, entity.display_name
  into new.catalog_area_id, new.venue_name
  from public.catalog_places as place
  join public.catalog_entities as entity on entity.id = place.id
  where place.id = new.catalog_place_id;
  if not found then
    raise exception 'Choose an available catalog place'
      using errcode = '22023';
  end if;

  if new.catalog_area_id is null then
    new.city := null;
  else
    select display_name into new.city
    from public.catalog_entities
    where id = new.catalog_area_id and kind = 'area';
  end if;
  end if;

  if tg_op = 'UPDATE' and new.catalog_tour_id is not distinct from old.catalog_tour_id then
    new.tour := old.tour;
  elsif new.catalog_tour_id is null then
    new.tour := null;
  else
    select display_name into new.tour
    from public.catalog_entities
    where id = new.catalog_tour_id and kind = 'tour';
    if not found then
      raise exception 'Choose an available catalog tour'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

create function private.apply_concert_artist_catalog_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  select owner_id into v_owner_id
  from public.concerts where id = new.concert_id;

  if tg_op = 'UPDATE' and new.catalog_artist_id is not distinct from old.catalog_artist_id then
    new.artist_name := old.artist_name;
    return new;
  elsif new.catalog_artist_id is null then
    new.catalog_artist_id := private.resolve_local_artist(
      v_owner_id, new.artist_name, 'legacy_client', p_enforce_quota => false
    );
  end if;

  select display_name into new.artist_name
  from public.catalog_entities
  where id = new.catalog_artist_id and kind = 'artist';
  if not found then
    raise exception 'Choose an available catalog artist'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create function private.apply_setlist_catalog_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_primary_artist_id uuid;
begin
  select concert.owner_id, artist.catalog_artist_id
  into v_owner_id, v_primary_artist_id
  from public.concerts as concert
  left join public.concert_artists as artist
    on artist.concert_id = concert.id and artist.is_primary
  where concert.id = new.concert_id;

  if tg_op = 'UPDATE' and new.catalog_song_id is not distinct from old.catalog_song_id then
    new.song_title := old.song_title;
    return new;
  elsif new.catalog_song_id is null then
    if v_primary_artist_id is null then
      raise exception 'A primary artist is required before adding setlist songs'
        using errcode = '23514';
    end if;
    new.catalog_song_id := private.resolve_local_song(
      v_owner_id,
      new.song_title,
      'legacy_client',
      array[v_primary_artist_id],
      p_enforce_quota => false
    );
  end if;

  select display_name into new.song_title
  from public.catalog_entities
  where id = new.catalog_song_id and kind = 'song';
  if not found then
    raise exception 'Choose an available catalog song'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger derive_concert_catalog_snapshots
before insert or update of catalog_place_id, catalog_area_id, catalog_tour_id, venue_name, city, tour
on public.concerts
for each row execute function private.apply_concert_catalog_snapshot();
create trigger derive_concert_artist_catalog_snapshots
before insert or update of catalog_artist_id, artist_name
on public.concert_artists
for each row execute function private.apply_concert_artist_catalog_snapshot();
create trigger derive_setlist_catalog_snapshots
before insert or update of catalog_song_id, song_title
on public.setlist_items
for each row execute function private.apply_setlist_catalog_snapshot();

alter table public.concerts
  add constraint concerts_tour_catalog_pair_check check (
    (catalog_tour_id is null and tour is null)
    or (catalog_tour_id is not null and tour is not null)
  );

create or replace function private.touch_concert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at is not distinct from old.updated_at
    and new.owner_id is not distinct from old.owner_id
    and new.catalog_place_id is not distinct from old.catalog_place_id
    and new.catalog_area_id is not distinct from old.catalog_area_id
    and new.catalog_tour_id is not distinct from old.catalog_tour_id
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

create function private.require_catalog_caller()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'Authentication is required to use the music catalog'
      using errcode = '42501';
  end if;
  if not private.has_completed_profile(v_caller_id) then
    raise exception 'Complete onboarding before using the music catalog'
      using errcode = '42501';
  end if;
  return v_caller_id;
end;
$$;

create function public.search_catalog(
  p_kind public.catalog_entity_kind,
  p_query text,
  p_artist_ids uuid[] default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_concert_id uuid default null
)
returns table (
  id uuid,
  kind public.catalog_entity_kind,
  origin public.catalog_entity_origin,
  display_name text,
  sort_name text,
  disambiguation text,
  musicbrainz_mbid uuid,
  subtitle text,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_query text;
begin
  if p_concert_id is not null then
    perform private.require_concert_editor(p_concert_id);
  end if;
  if p_query is null or private.contains_control_characters(p_query) then
    raise exception 'Catalog search requires a valid query'
      using errcode = '22023';
  end if;
  v_query := private.normalize_concert_text(p_query);
  if char_length(v_query) not between 2 and 160 then
    raise exception 'Catalog search requires between 2 and 160 characters'
      using errcode = '22023';
  end if;
  if p_limit not between 1 and 50 or p_offset not between 0 and 750 then
    raise exception 'Catalog search page is out of range'
      using errcode = '22023';
  end if;
  if p_artist_ids is not null and (
    cardinality(p_artist_ids) > 50
    or cardinality(p_artist_ids) <> cardinality(array(select distinct item from unnest(p_artist_ids) as item))
  ) then
    raise exception 'Artist context must contain no more than 50 distinct IDs'
      using errcode = '22023';
  end if;

  return query
  select selection.*
  from public.catalog_entities as entity
  cross join lateral private.catalog_selection(entity.id) as selection
  where entity.kind = p_kind
    and entity.status in ('active', 'needs_review')
    and (
      entity.origin = 'musicbrainz'
      or private.can_use_catalog_entity_as(v_caller_id, entity.id, p_kind, p_concert_id)
    )
    and (
      strpos(lower(entity.display_name), lower(v_query)) > 0
      or strpos(lower(entity.sort_name), lower(v_query)) > 0
      or strpos(lower(coalesce(entity.disambiguation, '')), lower(v_query)) > 0
    )
  order by
    case when entity.origin = 'musicbrainz' then 1 else 0 end,
    case
      when p_artist_ids is not null and p_kind = 'song' and exists (
        select 1 from public.catalog_song_artists as credit
        where credit.song_id = entity.id and credit.artist_id = any(p_artist_ids)
      ) then 0
      when p_artist_ids is not null and p_kind = 'tour' and exists (
        select 1 from public.catalog_tour_artists as credit
        where credit.tour_id = entity.id and credit.artist_id = any(p_artist_ids)
      ) then 0
      else 1
    end,
    case when lower(entity.display_name) = lower(v_query) then 0 else 1 end,
    public.similarity(entity.display_name, v_query) desc,
    lower(entity.sort_name),
    entity.id
  limit p_limit offset p_offset;
end;
$$;

create function public.get_catalog_artist_search_context(
  p_profile_id uuid,
  p_artist_ids uuid[],
  p_concert_id uuid default null
)
returns table (
  catalog_id uuid,
  musicbrainz_mbid uuid,
  display_name text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_profile_id is null or not private.has_completed_profile(p_profile_id) then
    raise exception 'A completed profile is required for artist search context'
      using errcode = '42501';
  end if;
  if p_concert_id is not null
    and not private.is_concert_editor_as(p_profile_id, p_concert_id)
  then
    raise exception 'Artist search context concert is not editable by this profile'
      using errcode = '42501';
  end if;
  if p_artist_ids is null or cardinality(p_artist_ids) not between 1 and 10
    or cardinality(p_artist_ids) <>
      cardinality(array(select distinct item from unnest(p_artist_ids) as item))
  then
    raise exception 'Artist search context requires 1 to 10 distinct IDs'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_artist_ids) as requested(id)
    left join public.catalog_entities as entity
      on entity.id = requested.id and entity.kind = 'artist'
        and entity.status in ('active', 'needs_review')
    where entity.id is null
      or not private.can_use_catalog_entity_as(
        p_profile_id, requested.id, 'artist', p_concert_id
      )
  ) then
    raise exception 'Choose only available catalog artists for search context'
      using errcode = '22023';
  end if;

  return query
  select entity.id, entity.musicbrainz_mbid, entity.display_name
  from unnest(p_artist_ids) with ordinality as requested(id, position)
  join public.catalog_entities as entity on entity.id = requested.id
  order by requested.position;
end;
$$;

create function public.create_custom_catalog_artist(
  p_name text,
  p_artist_type text default null,
  p_disambiguation text default null,
  p_area_id uuid default null,
  p_concert_id uuid default null
)
returns table (
  catalog_id uuid,
  musicbrainz_id uuid,
  display_name text,
  sort_name text,
  disambiguation text,
  subtitle text,
  origin public.catalog_entity_origin,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  if p_concert_id is not null then
    perform private.require_concert_editor(p_concert_id);
  end if;
  v_entity_id := private.resolve_local_artist(
    p_creator_id => v_caller_id,
    p_name => p_name,
    p_origin => 'tunedin_custom',
    p_artist_type => p_artist_type,
    p_disambiguation => p_disambiguation,
    p_area_id => p_area_id,
    p_concert_id => p_concert_id
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$$;

create function public.create_custom_catalog_area(
  p_name text,
  p_country_code text default null,
  p_parent_area_id uuid default null,
  p_concert_id uuid default null
)
returns table (
  catalog_id uuid,
  musicbrainz_id uuid,
  display_name text,
  sort_name text,
  disambiguation text,
  subtitle text,
  origin public.catalog_entity_origin,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  if p_concert_id is not null then
    perform private.require_concert_editor(p_concert_id);
  end if;
  v_entity_id := private.resolve_local_area(
    p_creator_id => v_caller_id,
    p_name => p_name,
    p_origin => 'tunedin_custom',
    p_country_code => p_country_code,
    p_parent_area_id => p_parent_area_id,
    p_concert_id => p_concert_id
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$$;

create function public.create_custom_catalog_place(
  p_name text,
  p_area_id uuid,
  p_place_type text default null,
  p_address text default null,
  p_concert_id uuid default null
)
returns table (
  catalog_id uuid,
  musicbrainz_id uuid,
  display_name text,
  sort_name text,
  disambiguation text,
  subtitle text,
  origin public.catalog_entity_origin,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  if p_concert_id is not null then
    perform private.require_concert_editor(p_concert_id);
  end if;
  if p_area_id is null then
    raise exception 'Custom places require a catalog area'
      using errcode = '22023';
  end if;
  v_entity_id := private.resolve_local_place(
    p_creator_id => v_caller_id,
    p_name => p_name,
    p_origin => 'tunedin_custom',
    p_area_id => p_area_id,
    p_place_type => p_place_type,
    p_address => p_address,
    p_concert_id => p_concert_id
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$$;

create function public.create_custom_catalog_song(
  p_title text,
  p_artist_ids uuid[],
  p_concert_id uuid default null
)
returns table (
  catalog_id uuid,
  musicbrainz_id uuid,
  display_name text,
  sort_name text,
  disambiguation text,
  subtitle text,
  origin public.catalog_entity_origin,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  if p_concert_id is not null then
    perform private.require_concert_editor(p_concert_id);
  end if;
  v_entity_id := private.resolve_local_song(
    p_creator_id => v_caller_id,
    p_title => p_title,
    p_origin => 'tunedin_custom',
    p_artist_ids => p_artist_ids,
    p_concert_id => p_concert_id
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$$;

create function public.create_custom_catalog_tour(
  p_name text,
  p_artist_ids uuid[],
  p_concert_id uuid default null
)
returns table (
  catalog_id uuid,
  musicbrainz_id uuid,
  display_name text,
  sort_name text,
  disambiguation text,
  subtitle text,
  origin public.catalog_entity_origin,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  if p_concert_id is not null then
    perform private.require_concert_editor(p_concert_id);
  end if;
  v_entity_id := private.resolve_local_tour(
    p_creator_id => v_caller_id,
    p_name => p_name,
    p_origin => 'tunedin_custom',
    p_artist_ids => p_artist_ids,
    p_concert_id => p_concert_id
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$$;

create function public.consume_catalog_search_quota(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_profile_id is null or not private.has_completed_profile(p_profile_id) then
    raise exception 'A completed profile is required for catalog search'
      using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-search:' || p_profile_id::text, 0)
  );
  delete from private.catalog_search_requests
  where profile_id = p_profile_id
    and requested_at < clock_timestamp() - interval '1 hour';
  select count(*) into v_count
  from private.catalog_search_requests
  where profile_id = p_profile_id
    and requested_at >= clock_timestamp() - interval '1 hour';
  if v_count >= 120 then
    raise exception 'Catalog search limit reached. Try again later.'
      using errcode = 'P0001';
  end if;
  insert into private.catalog_search_requests (profile_id) values (p_profile_id);
end;
$$;

create function public.get_musicbrainz_cache(p_cache_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  if p_cache_key is null or p_cache_key !~ '^v1:[a-f0-9]{64}$' then
    raise exception 'Invalid MusicBrainz cache key'
      using errcode = '22023';
  end if;
  delete from private.musicbrainz_cache
  where ctid in (
    select ctid
    from private.musicbrainz_cache
    where expires_at <= clock_timestamp()
    order by expires_at
    limit 100
  );
  delete from private.musicbrainz_cache
  where cache_key = p_cache_key and expires_at <= clock_timestamp();
  select payload into v_payload
  from private.musicbrainz_cache
  where cache_key = p_cache_key and expires_at > clock_timestamp();
  return v_payload;
end;
$$;

create function public.put_musicbrainz_cache(
  p_cache_key text,
  p_kind public.catalog_entity_kind,
  p_request_type text,
  p_payload jsonb,
  p_ttl_seconds integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_cache_key is null or p_cache_key !~ '^v1:[a-f0-9]{64}$' then
    raise exception 'Invalid MusicBrainz cache key'
      using errcode = '22023';
  end if;
  if p_request_type not in ('search', 'lookup') then
    raise exception 'Unsupported MusicBrainz request type'
      using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) not in ('object', 'array') then
    raise exception 'MusicBrainz cache payload must be an object or array'
      using errcode = '22023';
  end if;
  if p_ttl_seconds not between 1 and 2592000 then
    raise exception 'MusicBrainz cache TTL is out of range'
      using errcode = '22023';
  end if;
  insert into private.musicbrainz_cache (
    cache_key, kind, request_type, payload, expires_at
  )
  values (
    p_cache_key,
    p_kind,
    p_request_type,
    p_payload,
    clock_timestamp() + make_interval(secs => p_ttl_seconds)
  )
  on conflict (cache_key) do update
  set
    kind = excluded.kind,
    request_type = excluded.request_type,
    payload = excluded.payload,
    expires_at = excluded.expires_at,
    updated_at = clock_timestamp();
end;
$$;

create function public.claim_musicbrainz_request(
  p_cache_key text,
  p_lease_id uuid,
  p_lease_seconds integer default 15
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claimed boolean;
begin
  if p_cache_key is null or p_cache_key !~ '^v1:[a-f0-9]{64}$'
    or p_lease_id is null or p_lease_seconds not between 1 and 60
  then
    raise exception 'Invalid MusicBrainz request lease'
      using errcode = '22023';
  end if;
  delete from private.musicbrainz_request_leases
  where ctid in (
    select ctid
    from private.musicbrainz_request_leases
    where lease_expires_at <= clock_timestamp()
    order by lease_expires_at
    limit 100
  );
  insert into private.musicbrainz_request_leases (
    cache_key, lease_id, lease_expires_at
  )
  values (
    p_cache_key,
    p_lease_id,
    clock_timestamp() + make_interval(secs => p_lease_seconds)
  )
  on conflict (cache_key) do update
  set
    lease_id = excluded.lease_id,
    lease_expires_at = excluded.lease_expires_at,
    created_at = clock_timestamp()
  where private.musicbrainz_request_leases.lease_expires_at <= clock_timestamp()
    or private.musicbrainz_request_leases.lease_id = excluded.lease_id;
  select lease_id = p_lease_id into v_claimed
  from private.musicbrainz_request_leases
  where cache_key = p_cache_key;
  return coalesce(v_claimed, false);
end;
$$;

create function public.release_musicbrainz_request(
  p_cache_key text,
  p_lease_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_cache_key is null or p_cache_key !~ '^v1:[a-f0-9]{64}$' or p_lease_id is null then
    raise exception 'Invalid MusicBrainz request lease'
      using errcode = '22023';
  end if;
  delete from private.musicbrainz_request_leases
  where cache_key = p_cache_key and lease_id = p_lease_id;
end;
$$;

create function public.reserve_musicbrainz_request_slot(p_max_wait_ms integer default 5000)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_reserved_at timestamptz;
begin
  if p_max_wait_ms not between 0 and 30000 then
    raise exception 'MusicBrainz queue wait is out of range'
      using errcode = '22023';
  end if;
  select greatest(next_available_at, v_now)
  into v_reserved_at
  from private.musicbrainz_request_gate
  where singleton
  for update;
  if v_reserved_at > v_now + make_interval(secs => p_max_wait_ms::double precision / 1000.0) then
    raise exception 'MusicBrainz is busy. Try again shortly.'
      using errcode = 'P0001';
  end if;
  update private.musicbrainz_request_gate
  set next_available_at = v_reserved_at + interval '1 second'
  where singleton;
  return v_reserved_at;
end;
$$;

create function private.upsert_musicbrainz_base(
  p_kind public.catalog_entity_kind,
  p_mbid uuid,
  p_display_name text,
  p_sort_name text,
  p_disambiguation text,
  p_is_authoritative boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity_id uuid;
  v_display_name text := private.require_concert_text(p_display_name, 160, 'MusicBrainz name');
  v_sort_name text := private.require_concert_text(coalesce(p_sort_name, p_display_name), 160, 'MusicBrainz sort name');
  v_disambiguation text := private.optional_catalog_text(p_disambiguation, 240, 'MusicBrainz disambiguation');
begin
  if p_mbid is null then
    raise exception 'MusicBrainz ID is required'
      using errcode = '22023';
  end if;
  insert into public.catalog_entities (
    kind, origin, status, display_name, sort_name, disambiguation, musicbrainz_mbid
  )
  values (
    p_kind, 'musicbrainz', 'active', v_display_name, v_sort_name, v_disambiguation, p_mbid
  )
  on conflict (kind, musicbrainz_mbid) where musicbrainz_mbid is not null do update
  set
    display_name = case
      when p_is_authoritative then excluded.display_name
      else public.catalog_entities.display_name
    end,
    sort_name = case
      when p_is_authoritative then excluded.sort_name
      else public.catalog_entities.sort_name
    end,
    disambiguation = case
      when p_is_authoritative then excluded.disambiguation
      else public.catalog_entities.disambiguation
    end
  returning id into v_entity_id;

  insert into private.catalog_entity_provenance (
    entity_id, kind, source_updated_at, refreshed_at
  )
  values (v_entity_id, p_kind, clock_timestamp(), clock_timestamp())
  on conflict (entity_id) do update
  set source_updated_at = excluded.source_updated_at,
      refreshed_at = excluded.refreshed_at;
  return v_entity_id;
end;
$$;

create function public.upsert_musicbrainz_catalog_entity(
  p_kind public.catalog_entity_kind,
  p_mbid uuid,
  p_display_name text,
  p_sort_name text default null,
  p_disambiguation text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_artist_credits jsonb default '[]'::jsonb
)
returns table (
  id uuid,
  kind public.catalog_entity_kind,
  origin public.catalog_entity_origin,
  display_name text,
  sort_name text,
  disambiguation text,
  musicbrainz_mbid uuid,
  subtitle text,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity_id uuid;
  v_related_id uuid;
  v_credit jsonb;
  v_credit_artist_id uuid;
  v_position integer := 0;
  v_credit_names text[] := '{}';
begin
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object'
    or p_artist_credits is null or jsonb_typeof(p_artist_credits) <> 'array'
  then
    raise exception 'MusicBrainz metadata and artist credits have invalid shapes'
      using errcode = '22023';
  end if;
  if p_kind in ('artist', 'area', 'place') and jsonb_array_length(p_artist_credits) <> 0 then
    raise exception 'Artist credits are supported only for songs and tours'
      using errcode = '22023';
  end if;
  if p_kind = 'song' and jsonb_array_length(p_artist_credits) not between 1 and 50 then
    raise exception 'MusicBrainz songs require between 1 and 50 artist credits'
      using errcode = '22023';
  end if;
  if p_kind = 'tour' and jsonb_array_length(p_artist_credits) > 50 then
    raise exception 'MusicBrainz tours may have no more than 50 artist credits'
      using errcode = '22023';
  end if;

  v_entity_id := private.upsert_musicbrainz_base(
    p_kind, p_mbid, p_display_name, p_sort_name, p_disambiguation
  );

  if p_kind = 'artist' then
    if (p_metadata - array[
      'artist_type','country_code','area_name','area_mbid','life_span_begin','life_span_end','ended'
    ]) <> '{}'::jsonb then
      raise exception 'Unsupported MusicBrainz artist metadata'
        using errcode = '22023';
    end if;
    v_related_id := null;
    if nullif(p_metadata ->> 'area_mbid', '') is not null then
      if nullif(p_metadata ->> 'area_name', '') is null then
        raise exception 'MusicBrainz artist area name is required with area ID'
          using errcode = '22023';
      end if;
      v_related_id := private.upsert_musicbrainz_base(
        'area', (p_metadata ->> 'area_mbid')::uuid,
        p_metadata ->> 'area_name', p_metadata ->> 'area_name', null, false
      );
      insert into public.catalog_areas (id) values (v_related_id)
      on conflict on constraint catalog_areas_pkey do nothing;
    end if;
    insert into public.catalog_artists (
      id, artist_type, country_code, area_id, area_name,
      life_span_begin, life_span_end, ended
    ) values (
      v_entity_id,
      private.optional_catalog_text(p_metadata ->> 'artist_type', 80, 'Artist type'),
      nullif(upper(p_metadata ->> 'country_code'), ''),
      v_related_id,
      private.optional_catalog_text(p_metadata ->> 'area_name', 160, 'Artist area'),
      nullif(p_metadata ->> 'life_span_begin', ''),
      nullif(p_metadata ->> 'life_span_end', ''),
      case when p_metadata ? 'ended' and p_metadata -> 'ended' <> 'null'::jsonb
        then (p_metadata ->> 'ended')::boolean else null end
    )
    on conflict on constraint catalog_artists_pkey do update set
      artist_type = excluded.artist_type,
      country_code = excluded.country_code,
      area_id = excluded.area_id,
      area_name = excluded.area_name,
      life_span_begin = excluded.life_span_begin,
      life_span_end = excluded.life_span_end,
      ended = excluded.ended;
  elsif p_kind = 'area' then
    if (p_metadata - array[
      'area_type','country_code','subdivision_code','parent_mbid','parent_name'
    ]) <> '{}'::jsonb then
      raise exception 'Unsupported MusicBrainz area metadata'
        using errcode = '22023';
    end if;
    v_related_id := null;
    if nullif(p_metadata ->> 'parent_mbid', '') is not null then
      if nullif(p_metadata ->> 'parent_name', '') is null then
        raise exception 'MusicBrainz parent area name is required with parent ID'
          using errcode = '22023';
      end if;
      v_related_id := private.upsert_musicbrainz_base(
        'area', (p_metadata ->> 'parent_mbid')::uuid,
        p_metadata ->> 'parent_name', p_metadata ->> 'parent_name', null, false
      );
      insert into public.catalog_areas (id) values (v_related_id)
      on conflict on constraint catalog_areas_pkey do nothing;
    end if;
    insert into public.catalog_areas (
      id, area_type, country_code, subdivision_code, parent_area_id
    ) values (
      v_entity_id,
      private.optional_catalog_text(p_metadata ->> 'area_type', 80, 'Area type'),
      nullif(upper(p_metadata ->> 'country_code'), ''),
      nullif(upper(p_metadata ->> 'subdivision_code'), ''),
      v_related_id
    )
    on conflict on constraint catalog_areas_pkey do update set
      area_type = excluded.area_type,
      country_code = excluded.country_code,
      subdivision_code = excluded.subdivision_code,
      parent_area_id = excluded.parent_area_id;
  elsif p_kind = 'place' then
    if (p_metadata - array[
      'place_type','address','latitude','longitude','ended','area_mbid','area_name'
    ]) <> '{}'::jsonb then
      raise exception 'Unsupported MusicBrainz place metadata'
        using errcode = '22023';
    end if;
    v_related_id := null;
    if nullif(p_metadata ->> 'area_mbid', '') is not null then
      if nullif(p_metadata ->> 'area_name', '') is null then
        raise exception 'MusicBrainz place area name is required with area ID'
          using errcode = '22023';
      end if;
      v_related_id := private.upsert_musicbrainz_base(
        'area', (p_metadata ->> 'area_mbid')::uuid,
        p_metadata ->> 'area_name', p_metadata ->> 'area_name', null, false
      );
      insert into public.catalog_areas (id) values (v_related_id)
      on conflict on constraint catalog_areas_pkey do nothing;
    elsif nullif(p_metadata ->> 'area_name', '') is not null then
      raise exception 'MusicBrainz place area name cannot be stored without its ID'
        using errcode = '22023';
    end if;
    insert into public.catalog_places (
      id, area_id, place_type, address, latitude, longitude, ended
    ) values (
      v_entity_id,
      v_related_id,
      private.optional_catalog_text(p_metadata ->> 'place_type', 80, 'Place type'),
      private.optional_catalog_text(p_metadata ->> 'address', 240, 'Place address'),
      nullif(p_metadata ->> 'latitude', '')::numeric,
      nullif(p_metadata ->> 'longitude', '')::numeric,
      case when p_metadata ? 'ended' and p_metadata -> 'ended' <> 'null'::jsonb
        then (p_metadata ->> 'ended')::boolean else null end
    )
    on conflict on constraint catalog_places_pkey do update set
      area_id = excluded.area_id,
      place_type = excluded.place_type,
      address = excluded.address,
      latitude = excluded.latitude,
      longitude = excluded.longitude,
      ended = excluded.ended;
  elsif p_kind in ('song', 'tour') then
    if p_kind = 'song' and (p_metadata - array[
      'work_mbid','duration_ms','first_release_date','artist_credit'
    ]) <> '{}'::jsonb then
      raise exception 'Unsupported MusicBrainz song metadata'
        using errcode = '22023';
    end if;
    if p_kind = 'tour' and (p_metadata - array['series_type','disambiguation']) <> '{}'::jsonb then
      raise exception 'Unsupported MusicBrainz tour metadata'
        using errcode = '22023';
    end if;

    if p_kind = 'song' then
      insert into public.catalog_songs (id) values (v_entity_id)
      on conflict on constraint catalog_songs_pkey do nothing;
      delete from public.catalog_song_artists where song_id = v_entity_id;
    else
      insert into public.catalog_tours (id) values (v_entity_id)
      on conflict on constraint catalog_tours_pkey do nothing;
      delete from public.catalog_tour_artists where tour_id = v_entity_id;
    end if;

    for v_credit, v_position in
      select item.value, item.ordinality::integer
      from jsonb_array_elements(p_artist_credits) with ordinality as item(value, ordinality)
    loop
      if jsonb_typeof(v_credit) <> 'object'
        or (v_credit - array['artist_mbid','name','credit_name','join_phrase']) <> '{}'::jsonb
        or nullif(v_credit ->> 'artist_mbid', '') is null
        or nullif(v_credit ->> 'name', '') is null
      then
        raise exception 'Every MusicBrainz artist credit requires only artist_mbid, name, credit_name, and join_phrase'
          using errcode = '22023';
      end if;
      v_credit_artist_id := private.upsert_musicbrainz_base(
        'artist', (v_credit ->> 'artist_mbid')::uuid,
        v_credit ->> 'name', v_credit ->> 'name', null, false
      );
      insert into public.catalog_artists (id) values (v_credit_artist_id)
      on conflict on constraint catalog_artists_pkey do nothing;
      v_credit_names := array_append(
        v_credit_names,
        private.require_concert_text(
          coalesce(nullif(v_credit ->> 'credit_name', ''), v_credit ->> 'name'),
          160,
          'Artist credit'
        )
      );
      if p_kind = 'song' then
        insert into public.catalog_song_artists (
          song_id, artist_id, credit_position, credit_name, join_phrase
        )
        values (
          v_entity_id,
          v_credit_artist_id,
          v_position,
          private.optional_catalog_text(v_credit ->> 'credit_name', 160, 'Artist credit name'),
          private.musicbrainz_join_phrase(v_credit ->> 'join_phrase')
        );
      else
        insert into public.catalog_tour_artists (tour_id, artist_id, credit_position)
        values (v_entity_id, v_credit_artist_id, v_position);
      end if;
    end loop;

    if p_kind = 'song' then
      insert into public.catalog_songs (
        id, work_mbid, duration_ms, first_release_date, artist_credit
      ) values (
        v_entity_id,
        nullif(p_metadata ->> 'work_mbid', '')::uuid,
        nullif(p_metadata ->> 'duration_ms', '')::integer,
        nullif(p_metadata ->> 'first_release_date', ''),
        coalesce(
          private.optional_catalog_text(p_metadata ->> 'artist_credit', 320, 'Artist credit'),
          left(array_to_string(v_credit_names, ', '), 320)
        )
      )
      on conflict on constraint catalog_songs_pkey do update set
        work_mbid = excluded.work_mbid,
        duration_ms = excluded.duration_ms,
        first_release_date = excluded.first_release_date,
        artist_credit = excluded.artist_credit;
    else
      insert into public.catalog_tours (id, series_type)
      values (
        v_entity_id,
        coalesce(private.optional_catalog_text(p_metadata ->> 'series_type', 80, 'Series type'), 'Tour')
      )
      on conflict on constraint catalog_tours_pkey do update set
        series_type = excluded.series_type;
    end if;
  end if;

  return query select * from private.catalog_selection(v_entity_id);
end;
$$;

create function private.validate_catalog_concert_payload(
  p_actor_id uuid,
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_catalog_tour_id uuid,
  p_setlist jsonb,
  p_concert_id uuid default null
)
returns table (
  artists jsonb,
  setlist jsonb,
  catalog_area_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_artist jsonb;
  v_item jsonb;
  v_artist_id uuid;
  v_song_id uuid;
  v_artist_ids uuid[] := '{}';
  v_position integer;
  v_primary_count integer := 0;
  v_artists jsonb := '[]'::jsonb;
  v_setlist jsonb := '[]'::jsonb;
  v_area_id uuid;
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
  if p_catalog_place_id is null
    or not private.can_use_catalog_entity_as(
      p_actor_id, p_catalog_place_id, 'place', p_concert_id
    )
  then
    raise exception 'Choose an available catalog place'
      using errcode = '22023';
  end if;
  select area_id into v_area_id
  from public.catalog_places
  where id = p_catalog_place_id;

  if p_catalog_tour_id is not null and not private.can_use_catalog_entity_as(
    p_actor_id, p_catalog_tour_id, 'tour', p_concert_id
  ) then
    raise exception 'Choose an available catalog tour'
      using errcode = '22023';
  end if;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(p_artists) with ordinality as item(value, ordinality)
  loop
    if jsonb_typeof(v_artist) <> 'object'
      or not (v_artist ? 'catalog_artist_id')
      or not (v_artist ? 'is_primary')
      or jsonb_typeof(v_artist -> 'catalog_artist_id') <> 'string'
      or jsonb_typeof(v_artist -> 'is_primary') <> 'boolean'
      or (v_artist - 'catalog_artist_id' - 'is_primary') <> '{}'::jsonb
    then
      raise exception 'Every artist must contain only catalog_artist_id and is_primary fields'
        using errcode = '22023';
    end if;
    begin
      v_artist_id := (v_artist ->> 'catalog_artist_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Every artist requires a valid catalog artist ID'
        using errcode = '22023';
    end;
    if v_artist_id = any(v_artist_ids) then
      raise exception 'A concert lineup cannot contain the same catalog artist twice'
        using errcode = '22023';
    end if;
    if not private.can_use_catalog_entity_as(
      p_actor_id, v_artist_id, 'artist', p_concert_id
    ) then
      raise exception 'Choose only available catalog artists'
        using errcode = '22023';
    end if;
    v_artist_ids := array_append(v_artist_ids, v_artist_id);
    v_primary_count := v_primary_count
      + case when (v_artist ->> 'is_primary')::boolean then 1 else 0 end;
    v_artists := v_artists || jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', v_artist_id,
      'is_primary', (v_artist ->> 'is_primary')::boolean
    ));
  end loop;
  if v_primary_count <> 1 then
    raise exception 'Concerts require exactly one primary artist'
      using errcode = '22023';
  end if;

  for v_item, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(p_setlist) with ordinality as item(value, ordinality)
  loop
    if jsonb_typeof(v_item) <> 'object'
      or not (v_item ? 'catalog_song_id')
      or jsonb_typeof(v_item -> 'catalog_song_id') <> 'string'
      or (v_item - 'catalog_song_id') <> '{}'::jsonb
    then
      raise exception 'Every setlist entry must contain only catalog_song_id'
        using errcode = '22023';
    end if;
    begin
      v_song_id := (v_item ->> 'catalog_song_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Every setlist entry requires a valid catalog song ID'
        using errcode = '22023';
    end;
    if not private.can_use_catalog_entity_as(
      p_actor_id, v_song_id, 'song', p_concert_id
    ) then
      raise exception 'Choose only available catalog songs'
        using errcode = '22023';
    end if;
    v_setlist := v_setlist || jsonb_build_array(jsonb_build_object(
      'catalog_song_id', v_song_id
    ));
  end loop;

  return query select v_artists, v_setlist, v_area_id;
end;
$$;

create function public.create_private_concert_v2(
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_concert_date date,
  p_catalog_tour_id uuid default null,
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
  v_actor_id uuid := private.require_catalog_caller();
  v_concert public.concerts%rowtype;
  v_artists jsonb;
  v_setlist jsonb;
  v_area_id uuid;
  v_artist jsonb;
  v_item jsonb;
  v_position integer;
  v_time_zone text := p_venue_time_zone;
begin
  if p_concert_date is null then
    raise exception 'Concert date is required'
      using errcode = '22023';
  end if;
  if (p_starts_at is null) <> (p_venue_time_zone is null) then
    raise exception 'Start time and venue time zone must be provided together'
      using errcode = '22023';
  end if;
  if v_time_zone is not null and (
    private.contains_control_characters(v_time_zone)
    or v_time_zone <> btrim(v_time_zone)
    or not private.is_iana_time_zone(v_time_zone)
  ) then
    raise exception 'Venue time zone must be a valid IANA time-zone identifier'
      using errcode = '22023';
  end if;

  select payload.artists, payload.setlist, payload.catalog_area_id
  into v_artists, v_setlist, v_area_id
  from private.validate_catalog_concert_payload(
    v_actor_id,
    p_artists,
    p_catalog_place_id,
    p_catalog_tour_id,
    p_setlist
  ) as payload;

  insert into public.concerts (
    owner_id,
    venue_name,
    concert_date,
    starts_at,
    venue_time_zone,
    catalog_place_id,
    catalog_area_id,
    catalog_tour_id
  ) values (
    v_actor_id,
    '',
    p_concert_date,
    p_starts_at,
    v_time_zone,
    p_catalog_place_id,
    v_area_id,
    p_catalog_tour_id
  )
  returning * into v_concert;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
  loop
    insert into public.concert_artists (
      concert_id, lineup_position, artist_name, catalog_artist_id, is_primary
    ) values (
      v_concert.id,
      v_position,
      '',
      (v_artist ->> 'catalog_artist_id')::uuid,
      (v_artist ->> 'is_primary')::boolean
    );
  end loop;

  for v_item, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_setlist) with ordinality as item(value, ordinality)
  loop
    insert into public.setlist_items (
      concert_id, set_position, song_title, catalog_song_id
    ) values (
      v_concert.id,
      v_position,
      '',
      (v_item ->> 'catalog_song_id')::uuid
    );
  end loop;

  perform private.record_concert_event(
    v_concert.id, v_actor_id, 'concert_created'
  );
  return v_concert;
end;
$$;

create function public.update_concert_v2(
  p_concert_id uuid,
  p_expected_version bigint,
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_concert_date date,
  p_catalog_tour_id uuid default null,
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
  v_artists jsonb;
  v_setlist jsonb;
  v_catalog_area_id uuid;
  v_current_artists jsonb;
  v_current_setlist jsonb;
  v_changed_fields text[] := '{}';
  v_event_type public.concert_event_type;
  v_artist jsonb;
  v_item jsonb;
  v_position integer;
  v_time_zone text := p_venue_time_zone;
  v_reprivatizing boolean := false;
  v_revoked_collaborator_id uuid;
begin
  select * into v_concert
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
  if p_visibility is null then
    raise exception 'Concert visibility is required'
      using errcode = '22023';
  end if;
  if (p_starts_at is null) <> (p_venue_time_zone is null) then
    raise exception 'Start time and venue time zone must be provided together'
      using errcode = '22023';
  end if;
  if v_time_zone is not null and (
    private.contains_control_characters(v_time_zone)
    or v_time_zone <> btrim(v_time_zone)
    or not private.is_iana_time_zone(v_time_zone)
  ) then
    raise exception 'Venue time zone must be a valid IANA time-zone identifier'
      using errcode = '22023';
  end if;

  select payload.artists, payload.setlist, payload.catalog_area_id
  into v_artists, v_setlist, v_catalog_area_id
  from private.validate_catalog_concert_payload(
    v_actor_id,
    p_artists,
    p_catalog_place_id,
    p_catalog_tour_id,
    p_setlist,
    p_concert_id
  ) as payload;

  select coalesce(jsonb_agg(jsonb_build_object(
    'catalog_artist_id', artist.catalog_artist_id,
    'is_primary', artist.is_primary
  ) order by artist.lineup_position), '[]'::jsonb)
  into v_current_artists
  from public.concert_artists as artist
  where artist.concert_id = p_concert_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'catalog_song_id', item.catalog_song_id
  ) order by item.set_position), '[]'::jsonb)
  into v_current_setlist
  from public.setlist_items as item
  where item.concert_id = p_concert_id;

  if v_concert.catalog_place_id is distinct from p_catalog_place_id then
    v_changed_fields := array_append(v_changed_fields, 'venue');
    if v_concert.catalog_area_id is distinct from v_catalog_area_id then
      v_changed_fields := array_append(v_changed_fields, 'city');
    end if;
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
  if v_concert.catalog_tour_id is distinct from p_catalog_tour_id then
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
    if v_concert.owner_id <> v_actor_id then
      raise exception 'Only the concert owner can make this concert private'
        using errcode = '42501';
    end if;
    v_reprivatizing := true;
  end if;

  update public.concerts
  set
    catalog_place_id = p_catalog_place_id,
    catalog_area_id = v_catalog_area_id,
    catalog_tour_id = p_catalog_tour_id,
    concert_date = p_concert_date,
    starts_at = p_starts_at,
    venue_time_zone = v_time_zone,
    visibility = p_visibility,
    updated_at = clock_timestamp()
  where id = p_concert_id
  returning * into v_concert;

  if v_reprivatizing then
    for v_revoked_collaborator_id in
      delete from public.concert_collaborators
      where concert_id = p_concert_id
      returning profile_id
    loop
      perform private.record_concert_event(
        p_concert_id,
        v_actor_id,
        'collaborator_removed',
        v_revoked_collaborator_id,
        jsonb_build_object('reason', 'owner_made_private')
      );
    end loop;
  end if;

  if 'lineup' = any(v_changed_fields) then
    delete from public.concert_artists where concert_id = p_concert_id;
    for v_artist, v_position in
      select item.value, item.ordinality::integer
      from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
    loop
      insert into public.concert_artists (
        concert_id, lineup_position, artist_name, catalog_artist_id, is_primary
      ) values (
        p_concert_id,
        v_position,
        '',
        (v_artist ->> 'catalog_artist_id')::uuid,
        (v_artist ->> 'is_primary')::boolean
      );
    end loop;
  end if;

  if 'setlist' = any(v_changed_fields) then
    delete from public.setlist_items where concert_id = p_concert_id;
    for v_item, v_position in
      select item.value, item.ordinality::integer
      from jsonb_array_elements(v_setlist) with ordinality as item(value, ordinality)
    loop
      insert into public.setlist_items (
        concert_id, set_position, song_title, catalog_song_id
      ) values (
        p_concert_id,
        v_position,
        '',
        (v_item ->> 'catalog_song_id')::uuid
      );
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

create or replace function public.create_private_concert(
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
  v_artists jsonb;
  v_setlist jsonb;
  v_catalog_artists jsonb := '[]'::jsonb;
  v_catalog_setlist jsonb := '[]'::jsonb;
  v_artist jsonb;
  v_song jsonb;
  v_artist_id uuid;
  v_primary_artist_id uuid;
  v_area_id uuid;
  v_place_id uuid;
  v_tour_id uuid;
  v_position integer;
  v_venue_name text;
  v_city text;
  v_tour text;
begin
  -- Keep the established compatibility-RPC authorization errors stable for
  -- older clients while the v2/catalog endpoints use catalog-specific copy.
  if v_actor_id is null then
    raise exception 'Authentication is required to create a concert'
      using errcode = '42501';
  end if;
  if not private.has_completed_profile(v_actor_id) then
    raise exception 'Complete onboarding before creating a concert'
      using errcode = '42501';
  end if;

  select payload.artists, payload.setlist
  into v_artists, v_setlist
  from private.validate_concert_payload(p_artists, p_setlist) as payload;

  v_venue_name := private.require_concert_text(p_venue_name, 160, 'Venue name');
  v_city := private.optional_concert_text(p_city, 100, 'City');
  v_tour := private.optional_concert_text(p_tour, 160, 'Tour');

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
  loop
    v_artist_id := private.resolve_local_artist(
      v_actor_id, v_artist ->> 'name', 'legacy_client'
    );
    if (v_artist ->> 'is_primary')::boolean then
      v_primary_artist_id := v_artist_id;
    end if;
    v_catalog_artists := v_catalog_artists || jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', v_artist_id,
      'is_primary', (v_artist ->> 'is_primary')::boolean
    ));
  end loop;

  if v_city is not null then
    v_area_id := private.resolve_local_area(
      v_actor_id, v_city, 'legacy_client'
    );
  end if;
  v_place_id := private.resolve_local_place(
    v_actor_id, v_venue_name, 'legacy_client', v_area_id
  );
  if v_tour is not null then
    v_tour_id := private.resolve_local_tour(
      v_actor_id,
      v_tour,
      'legacy_client',
      array[v_primary_artist_id]
    );
  end if;

  for v_song, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_setlist) with ordinality as item(value, ordinality)
  loop
    v_catalog_setlist := v_catalog_setlist || jsonb_build_array(jsonb_build_object(
      'catalog_song_id', private.resolve_local_song(
        v_actor_id,
        v_song #>> '{}',
        'legacy_client',
        array[v_primary_artist_id]
      )
    ));
  end loop;

  return public.create_private_concert_v2(
    p_artists => v_catalog_artists,
    p_catalog_place_id => v_place_id,
    p_concert_date => p_concert_date,
    p_catalog_tour_id => v_tour_id,
    p_starts_at => p_starts_at,
    p_venue_time_zone => p_venue_time_zone,
    p_setlist => v_catalog_setlist
  );
end;
$$;

create or replace function public.update_concert(
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
  v_current public.concerts%rowtype;
  v_artists jsonb;
  v_setlist jsonb;
  v_catalog_artists jsonb := '[]'::jsonb;
  v_catalog_setlist jsonb := '[]'::jsonb;
  v_artist jsonb;
  v_song jsonb;
  v_artist_id uuid;
  v_primary_artist_id uuid;
  v_song_id uuid;
  v_area_id uuid;
  v_place_id uuid;
  v_tour_id uuid;
  v_position integer;
  v_venue_name text;
  v_city text;
  v_tour text;
begin
  select * into v_current
  from public.concerts
  where id = p_concert_id;
  if not found then
    raise exception 'That concert is no longer available'
      using errcode = 'P0001';
  end if;

  select payload.artists, payload.setlist
  into v_artists, v_setlist
  from private.validate_concert_payload(p_artists, p_setlist) as payload;
  v_venue_name := private.require_concert_text(p_venue_name, 160, 'Venue name');
  v_city := private.optional_concert_text(p_city, 100, 'City');
  v_tour := private.optional_concert_text(p_tour, 160, 'Tour');

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
  loop
    select catalog_artist_id into v_artist_id
    from public.concert_artists
    where concert_id = p_concert_id
      and artist_name = v_artist ->> 'name'
    order by lineup_position
    limit 1;
    if not found then
      v_artist_id := private.resolve_local_artist(
        v_actor_id, v_artist ->> 'name', 'legacy_client'
      );
    end if;
    if (v_artist ->> 'is_primary')::boolean then
      v_primary_artist_id := v_artist_id;
    end if;
    v_catalog_artists := v_catalog_artists || jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', v_artist_id,
      'is_primary', (v_artist ->> 'is_primary')::boolean
    ));
  end loop;

  if v_current.venue_name = v_venue_name and v_current.city is not distinct from v_city then
    v_place_id := v_current.catalog_place_id;
  else
    if v_city is not null then
      v_area_id := private.resolve_local_area(v_actor_id, v_city, 'legacy_client');
    end if;
    v_place_id := private.resolve_local_place(
      v_actor_id, v_venue_name, 'legacy_client', v_area_id
    );
  end if;

  if v_tour is null then
    v_tour_id := null;
  elsif v_current.tour = v_tour then
    v_tour_id := v_current.catalog_tour_id;
  else
    v_tour_id := private.resolve_local_tour(
      p_creator_id => v_actor_id,
      p_name => v_tour,
      p_origin => 'legacy_client',
      p_artist_ids => array[v_primary_artist_id],
      p_concert_id => p_concert_id
    );
  end if;

  for v_song, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_setlist) with ordinality as item(value, ordinality)
  loop
    if (
      select count(distinct item.catalog_song_id)
      from public.setlist_items as item
      where item.concert_id = p_concert_id
        and item.song_title = v_song #>> '{}'
    ) > 1 then
      raise exception 'This older app cannot safely edit duplicate song titles. Update tunedIn and try again.'
        using errcode = 'P0001';
    end if;
    select catalog_song_id into v_song_id
    from public.setlist_items
    where concert_id = p_concert_id
      and song_title = v_song #>> '{}'
    order by set_position
    limit 1;
    if not found then
      v_song_id := private.resolve_local_song(
        p_creator_id => v_actor_id,
        p_title => v_song #>> '{}',
        p_origin => 'legacy_client',
        p_artist_ids => array[v_primary_artist_id],
        p_concert_id => p_concert_id
      );
    end if;
    v_catalog_setlist := v_catalog_setlist || jsonb_build_array(jsonb_build_object(
      'catalog_song_id', v_song_id
    ));
  end loop;

  return public.update_concert_v2(
    p_concert_id => p_concert_id,
    p_expected_version => p_expected_version,
    p_artists => v_catalog_artists,
    p_catalog_place_id => v_place_id,
    p_concert_date => p_concert_date,
    p_catalog_tour_id => v_tour_id,
    p_starts_at => p_starts_at,
    p_venue_time_zone => p_venue_time_zone,
    p_setlist => v_catalog_setlist,
    p_visibility => p_visibility
  );
end;
$$;

drop function public.profile_concert_history(
  uuid,
  text,
  integer,
  public.concert_visibility,
  text,
  date,
  timestamptz,
  text,
  uuid,
  integer
);

create function public.profile_concert_history(
  p_profile_id uuid,
  p_search text default null,
  p_year integer default null,
  p_visibility public.concert_visibility default null,
  p_sort text default 'newest',
  p_cursor_date date default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_text text default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  owner_id uuid,
  catalog_place_id uuid,
  catalog_area_id uuid,
  catalog_tour_id uuid,
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
  primary_artist text,
  photo_object_path text,
  photo_version bigint
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
  if p_sort not in ('newest', 'oldest', 'recently_updated', 'artist', 'venue') then
    raise exception 'Unsupported concert-history sort'
      using errcode = '22023';
  end if;
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
    concert.catalog_place_id,
    concert.catalog_area_id,
    concert.catalog_tour_id,
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
    artist.artist_name,
    concert.photo_object_path,
    concert.photo_version
  from public.concerts as concert
  join lateral (
    select concert_artist.artist_name
    from public.concert_artists as concert_artist
    where concert_artist.concert_id = concert.id
      and concert_artist.is_primary
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
      p_cursor_id is null
      or (p_sort = 'newest' and (concert.concert_date, concert.id) < (p_cursor_date, p_cursor_id))
      or (p_sort = 'oldest' and (concert.concert_date, concert.id) > (p_cursor_date, p_cursor_id))
      or (p_sort = 'recently_updated' and (concert.updated_at, concert.id) < (p_cursor_updated_at, p_cursor_id))
      or (p_sort = 'artist' and (lower(artist.artist_name), concert.id) > (p_cursor_text, p_cursor_id))
      or (p_sort = 'venue' and (lower(concert.venue_name), concert.id) > (p_cursor_text, p_cursor_id))
    )
  order by
    case when p_sort = 'newest' then concert.concert_date end desc,
    case when p_sort = 'oldest' then concert.concert_date end asc,
    case when p_sort = 'recently_updated' then concert.updated_at end desc,
    case when p_sort = 'artist' then lower(artist.artist_name) end asc,
    case when p_sort = 'venue' then lower(concert.venue_name) end asc,
    case when p_sort in ('newest', 'recently_updated') then concert.id end desc,
    case when p_sort in ('oldest', 'artist', 'venue') then concert.id end asc
  limit v_limit;
end;
$$;

-- New private helpers are never callable by client roles except for the small
-- policy predicates PostgreSQL evaluates from existing and catalog RLS rules.
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

revoke all on function public.search_catalog(
  public.catalog_entity_kind, text, uuid[], integer, integer, uuid
) from public, anon;
revoke all on function public.create_custom_catalog_artist(
  text, text, text, uuid, uuid
) from public, anon;
revoke all on function public.create_custom_catalog_area(
  text, text, uuid, uuid
) from public, anon;
revoke all on function public.create_custom_catalog_place(
  text, uuid, text, text, uuid
) from public, anon;
revoke all on function public.create_custom_catalog_song(text, uuid[], uuid) from public, anon;
revoke all on function public.create_custom_catalog_tour(text, uuid[], uuid) from public, anon;
revoke all on function public.create_private_concert_v2(
  jsonb, uuid, date, uuid, timestamptz, text, jsonb
) from public, anon;
revoke all on function public.update_concert_v2(
  uuid, bigint, jsonb, uuid, date, uuid, timestamptz, text, jsonb,
  public.concert_visibility
) from public, anon;
revoke all on function public.profile_concert_history(
  uuid, text, integer, public.concert_visibility, text, date, timestamptz,
  text, uuid, integer
) from public, anon;

grant execute on function public.search_catalog(
  public.catalog_entity_kind, text, uuid[], integer, integer, uuid
) to authenticated;
grant execute on function public.create_custom_catalog_artist(
  text, text, text, uuid, uuid
) to authenticated;
grant execute on function public.create_custom_catalog_area(
  text, text, uuid, uuid
) to authenticated;
grant execute on function public.create_custom_catalog_place(
  text, uuid, text, text, uuid
) to authenticated;
grant execute on function public.create_custom_catalog_song(text, uuid[], uuid) to authenticated;
grant execute on function public.create_custom_catalog_tour(text, uuid[], uuid) to authenticated;
grant execute on function public.create_private_concert_v2(
  jsonb, uuid, date, uuid, timestamptz, text, jsonb
) to authenticated;
grant execute on function public.update_concert_v2(
  uuid, bigint, jsonb, uuid, date, uuid, timestamptz, text, jsonb,
  public.concert_visibility
) to authenticated;
grant execute on function public.profile_concert_history(
  uuid, text, integer, public.concert_visibility, text, date, timestamptz,
  text, uuid, integer
) to authenticated;

revoke all on function public.consume_catalog_search_quota(uuid)
  from public, anon, authenticated;
revoke all on function public.get_catalog_artist_search_context(uuid, uuid[], uuid)
  from public, anon, authenticated;
revoke all on function public.get_musicbrainz_cache(text)
  from public, anon, authenticated;
revoke all on function public.put_musicbrainz_cache(
  text, public.catalog_entity_kind, text, jsonb, integer
) from public, anon, authenticated;
revoke all on function public.claim_musicbrainz_request(text, uuid, integer)
  from public, anon, authenticated;
revoke all on function public.release_musicbrainz_request(text, uuid)
  from public, anon, authenticated;
revoke all on function public.reserve_musicbrainz_request_slot(integer)
  from public, anon, authenticated;
revoke all on function public.upsert_musicbrainz_catalog_entity(
  public.catalog_entity_kind, uuid, text, text, text, jsonb, jsonb
) from public, anon, authenticated;

grant execute on function public.consume_catalog_search_quota(uuid) to service_role;
grant execute on function public.get_catalog_artist_search_context(uuid, uuid[], uuid) to service_role;
grant execute on function public.get_musicbrainz_cache(text) to service_role;
grant execute on function public.put_musicbrainz_cache(
  text, public.catalog_entity_kind, text, jsonb, integer
) to service_role;
grant execute on function public.claim_musicbrainz_request(text, uuid, integer) to service_role;
grant execute on function public.release_musicbrainz_request(text, uuid) to service_role;
grant execute on function public.reserve_musicbrainz_request_slot(integer) to service_role;
grant execute on function public.upsert_musicbrainz_catalog_entity(
  public.catalog_entity_kind, uuid, text, text, text, jsonb, jsonb
) to service_role;
