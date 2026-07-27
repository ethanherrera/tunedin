-- Ticketmaster Discovery is a read-through feed with write-through-on-open.
-- Its catalog and event identities intentionally remain source-local.

alter table public.catalog_entities
  drop constraint catalog_entities_musicbrainz_origin_check,
  add constraint catalog_entities_provider_origin_check check (
    (origin = 'musicbrainz' and musicbrainz_mbid is not null)
    or (origin <> 'musicbrainz' and musicbrainz_mbid is null)
  );

create table private.ticketmaster_catalog_entities (
  entity_id uuid not null references public.catalog_entities (id) on delete cascade,
  entity_kind public.catalog_entity_kind not null
    check (entity_kind in ('artist', 'area', 'place')),
  external_entity_id text not null check (
    char_length(external_entity_id) between 1 and 200
    and not private.contains_control_characters(external_entity_id)
  ),
  external_url text check (
    external_url is null
    or (
      char_length(external_url) <= 2048
      and external_url ~ '^https://'
      and not private.contains_control_characters(external_url)
    )
  ),
  last_refreshed_at timestamptz not null default clock_timestamp(),
  primary key (entity_kind, external_entity_id),
  unique (entity_id)
);

alter table public.catalog_events
  drop constraint catalog_events_origin_owner_check,
  drop constraint catalog_events_origin_check,
  add constraint catalog_events_origin_check check (
    origin in ('community', 'musicbrainz', 'ticketmaster')
  ),
  add constraint catalog_events_origin_owner_check check (
    (origin = 'community' and created_by is not null and source_local_start_time is null)
    or (origin in ('musicbrainz', 'ticketmaster') and created_by is null)
  );

alter table private.catalog_event_sources
  drop constraint catalog_event_sources_provider_key_check,
  drop constraint catalog_event_sources_external_url_check,
  drop constraint catalog_event_sources_source_status_check,
  add constraint catalog_event_sources_provider_key_check check (
    provider_key in ('musicbrainz', 'ticketmaster')
  ),
  add constraint catalog_event_sources_external_url_check check (
    char_length(external_url) <= 2048
    and not private.contains_control_characters(external_url)
    and (
      (provider_key = 'musicbrainz'
        and external_url ~ '^https://musicbrainz[.]org/event/[0-9a-f-]{36}$')
      or (provider_key = 'ticketmaster' and external_url ~ '^https://')
    )
  ),
  add constraint catalog_event_sources_source_status_check check (
    source_status in ('active', 'cancelled', 'postponed')
  );

create table private.ticketmaster_cache (
  cache_key text primary key check (cache_key ~ '^v1:[a-f0-9]{64}$'),
  request_type text not null check (request_type in ('discover', 'detail')),
  payload jsonb not null check (jsonb_typeof(payload) in ('object', 'array')),
  expires_at timestamptz not null,
  hard_delete_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  constraint ticketmaster_cache_retention_check check (
    expires_at <= hard_delete_at
    and hard_delete_at <= updated_at + interval '24 hours'
  )
);

create index ticketmaster_cache_hard_delete_at
  on private.ticketmaster_cache (hard_delete_at);

create table private.ticketmaster_discovery_requests (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  requested_at timestamptz not null default clock_timestamp()
);

create index ticketmaster_discovery_requests_profile_time
  on private.ticketmaster_discovery_requests (profile_id, requested_at);

create table private.ticketmaster_api_requests (
  requested_at timestamptz primary key
);

create table private.ticketmaster_request_gate (
  singleton boolean primary key default true check (singleton),
  next_available_at timestamptz not null default clock_timestamp()
);

insert into private.ticketmaster_request_gate (singleton) values (true);

create function private.upsert_ticketmaster_catalog_entity(
  p_kind public.catalog_entity_kind,
  p_external_id text,
  p_display_name text,
  p_external_url text default null,
  p_area_id uuid default null,
  p_country_code text default null,
  p_subdivision_code text default null,
  p_address text default null,
  p_latitude numeric default null,
  p_longitude numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity_id uuid;
  v_name text := private.optional_catalog_text(p_display_name, 160, 'Ticketmaster name');
  v_external_id text := btrim(p_external_id);
begin
  if p_kind not in ('artist', 'area', 'place')
    or v_external_id is null
    or char_length(v_external_id) not between 1 and 200
    or private.contains_control_characters(v_external_id)
    or v_name is null
  then
    raise exception 'Ticketmaster catalog identity is invalid' using errcode = '22023';
  end if;

  select link.entity_id into v_entity_id
  from private.ticketmaster_catalog_entities as link
  where link.entity_kind = p_kind and link.external_entity_id = v_external_id
  for update;

  if v_entity_id is null then
    insert into public.catalog_entities (
      kind, origin, status, display_name, sort_name
    ) values (
      p_kind, 'ticketmaster', 'active', v_name, v_name
    ) returning id into v_entity_id;

    insert into private.ticketmaster_catalog_entities (
      entity_id, entity_kind, external_entity_id, external_url
    ) values (
      v_entity_id, p_kind, v_external_id, p_external_url
    );
  else
    update public.catalog_entities
    set display_name = v_name, sort_name = v_name, updated_at = clock_timestamp()
    where id = v_entity_id and origin = 'ticketmaster' and kind = p_kind;
    if not found then
      raise exception 'Ticketmaster catalog identity is inconsistent' using errcode = '23514';
    end if;
    update private.ticketmaster_catalog_entities
    set external_url = p_external_url, last_refreshed_at = clock_timestamp()
    where entity_id = v_entity_id;
  end if;

  if p_kind = 'artist' then
    insert into public.catalog_artists (id, kind, country_code, area_id)
    values (v_entity_id, 'artist', p_country_code, p_area_id)
    on conflict (id) do update
    set country_code = excluded.country_code, area_id = excluded.area_id;
  elsif p_kind = 'area' then
    insert into public.catalog_areas (
      id, kind, area_type, country_code, subdivision_code
    ) values (
      v_entity_id, 'area', 'City', p_country_code, p_subdivision_code
    ) on conflict (id) do update
    set country_code = excluded.country_code,
        subdivision_code = excluded.subdivision_code;
  else
    insert into public.catalog_places (
      id, kind, area_id, place_type, address, latitude, longitude
    ) values (
      v_entity_id, 'place', p_area_id, 'Venue', p_address, p_latitude, p_longitude
    ) on conflict (id) do update
    set area_id = excluded.area_id,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude;
  end if;
  return v_entity_id;
end;
$$;

create function public.upsert_ticketmaster_catalog_event(p_event jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_external_id text;
  v_title text;
  v_event_date date;
  v_local_start_time time;
  v_starts_at timestamptz;
  v_time_zone text;
  v_source_status text;
  v_source_url text;
  v_image_url text;
  v_source_updated_at timestamptz;
  v_venue jsonb;
  v_area jsonb;
  v_artists jsonb;
  v_artist jsonb;
  v_area_external_id text;
  v_area_id uuid;
  v_venue_id uuid;
  v_artist_id uuid;
  v_headliner_id uuid;
  v_headliner_name text;
  v_event_id uuid;
  v_position integer;
  v_duplicate_key text;
  v_venue_name text;
  v_area_name text;
  v_address text;
begin
  if p_event is null or jsonb_typeof(p_event) <> 'object'
    or (p_event - array[
      'event_id', 'title', 'event_date', 'local_start_time', 'starts_at',
      'time_zone', 'status', 'source_url', 'image_url', 'source_updated_at',
      'venue', 'artists'
    ]) <> '{}'::jsonb
  then
    raise exception 'Ticketmaster event payload is invalid' using errcode = '22023';
  end if;

  v_event_external_id := btrim(p_event ->> 'event_id');
  v_title := private.optional_catalog_text(p_event ->> 'title', 160, 'Ticketmaster event title');
  v_time_zone := coalesce(nullif(btrim(p_event ->> 'time_zone'), ''), 'UTC');
  v_source_status := coalesce(nullif(p_event ->> 'status', ''), 'active');
  v_source_url := p_event ->> 'source_url';
  v_image_url := nullif(p_event ->> 'image_url', '');
  begin
    v_event_date := (p_event ->> 'event_date')::date;
    v_local_start_time := nullif(p_event ->> 'local_start_time', '')::time;
    v_starts_at := nullif(p_event ->> 'starts_at', '')::timestamptz;
    v_source_updated_at := nullif(p_event ->> 'source_updated_at', '')::timestamptz;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception 'Ticketmaster event date is invalid' using errcode = '22023';
  end;

  if v_event_external_id is null
    or char_length(v_event_external_id) not between 1 and 200
    or private.contains_control_characters(v_event_external_id)
    or v_title is null
    or v_event_date not between date '1900-01-01' and date '2200-12-31'
    or v_source_status not in ('active', 'cancelled', 'postponed')
    or v_source_url is null
    or char_length(v_source_url) > 2048
    or v_source_url !~ '^https://'
    or (v_image_url is not null and (char_length(v_image_url) > 2048 or v_image_url !~ '^https://'))
    or not exists (select 1 from pg_catalog.pg_timezone_names where name = v_time_zone)
  then
    raise exception 'Ticketmaster event payload is invalid' using errcode = '22023';
  end if;
  if v_starts_at is null then
    v_starts_at := (v_event_date + coalesce(v_local_start_time, time '12:00')) at time zone v_time_zone;
  end if;

  v_venue := p_event -> 'venue';
  v_artists := p_event -> 'artists';
  if jsonb_typeof(v_venue) <> 'object'
    or (v_venue - array[
      'id', 'name', 'url', 'address', 'latitude', 'longitude', 'area'
    ]) <> '{}'::jsonb
    or jsonb_typeof(v_venue -> 'area') <> 'object'
    or jsonb_typeof(v_artists) <> 'array'
    or jsonb_array_length(v_artists) not between 1 and 10
  then
    raise exception 'Ticketmaster event venue or lineup is invalid' using errcode = '22023';
  end if;

  v_area := v_venue -> 'area';
  if (v_area - array['city', 'state_code', 'country_code']) <> '{}'::jsonb then
    raise exception 'Ticketmaster event area is invalid' using errcode = '22023';
  end if;
  v_area_name := private.optional_catalog_text(v_area ->> 'city', 160, 'Ticketmaster city');
  v_area_external_id := lower(concat_ws(
    ':', 'area', nullif(v_area ->> 'country_code', ''),
    nullif(v_area ->> 'state_code', ''), v_area_name
  ));
  v_area_id := private.upsert_ticketmaster_catalog_entity(
    'area', v_area_external_id, v_area_name, null, null,
    nullif(v_area ->> 'country_code', ''), nullif(v_area ->> 'state_code', '')
  );

  v_address := private.optional_catalog_text(v_venue ->> 'address', 240, 'Ticketmaster venue address');
  v_venue_id := private.upsert_ticketmaster_catalog_entity(
    'place', v_venue ->> 'id', v_venue ->> 'name', nullif(v_venue ->> 'url', ''),
    v_area_id, null, null, v_address,
    nullif(v_venue ->> 'latitude', '')::numeric,
    nullif(v_venue ->> 'longitude', '')::numeric
  );
  select display_name into v_venue_name from public.catalog_entities where id = v_venue_id;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
  loop
    if jsonb_typeof(v_artist) <> 'object'
      or (v_artist - array['id', 'name', 'url', 'is_headliner']) <> '{}'::jsonb
      or jsonb_typeof(v_artist -> 'is_headliner') <> 'boolean'
    then
      raise exception 'Ticketmaster event artist is invalid' using errcode = '22023';
    end if;
    v_artist_id := private.upsert_ticketmaster_catalog_entity(
      'artist', v_artist ->> 'id', v_artist ->> 'name', nullif(v_artist ->> 'url', '')
    );
    if (v_artist ->> 'is_headliner')::boolean and v_headliner_id is null then
      v_headliner_id := v_artist_id;
      select display_name into v_headliner_name from public.catalog_entities where id = v_artist_id;
    end if;
  end loop;
  if v_headliner_id is null then
    raise exception 'Ticketmaster event requires a headliner' using errcode = '22023';
  end if;

  v_duplicate_key := pg_catalog.md5('ticketmaster|' || v_event_external_id);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('ticketmaster-event:' || v_event_external_id, 0)
  );
  select source.event_id into v_event_id
  from private.catalog_event_sources as source
  where source.provider_key = 'ticketmaster'
    and source.external_event_id = v_event_external_id
  for update;

  if v_event_id is null then
    insert into public.catalog_events (
      created_by, origin, catalog_place_id, catalog_area_id,
      headliner_catalog_artist_id, event_date, starts_at, time_zone_identifier,
      source_local_start_time, memory_unlock_at, lifecycle, listing, integrity,
      venue_name_snapshot, area_name_snapshot, tour_name_snapshot,
      headliner_name_snapshot, search_text, exact_duplicate_key,
      cover_source, cover_remote_url, cover_provider_name, cover_version
    ) values (
      null, 'ticketmaster', v_venue_id, v_area_id, v_headliner_id,
      v_event_date, v_starts_at, v_time_zone, v_local_start_time,
      v_starts_at + interval '4 hours',
      case v_source_status
        when 'cancelled' then 'cancelled'::public.catalog_event_lifecycle
        when 'postponed' then 'postponed'::public.catalog_event_lifecycle
        else 'scheduled'::public.catalog_event_lifecycle
      end,
      'listed', 'corroborated', v_venue_name, v_area_name, v_title,
      v_headliner_name,
      lower(regexp_replace(
        btrim(v_title || ' ' || v_headliner_name || ' ' || v_venue_name || ' ' || v_area_name),
        '[[:space:]]+', ' ', 'g'
      )),
      v_duplicate_key,
      case when v_image_url is null then null else 'provider' end,
      v_image_url, case when v_image_url is null then null else 'Ticketmaster' end,
      case when v_image_url is null then 0 else 1 end
    ) returning id into v_event_id;
  else
    update public.catalog_events
    set catalog_place_id = v_venue_id,
        catalog_area_id = v_area_id,
        headliner_catalog_artist_id = v_headliner_id,
        event_date = v_event_date,
        starts_at = v_starts_at,
        time_zone_identifier = v_time_zone,
        source_local_start_time = v_local_start_time,
        memory_unlock_at = v_starts_at + interval '4 hours',
        lifecycle = case v_source_status
          when 'cancelled' then 'cancelled'::public.catalog_event_lifecycle
          when 'postponed' then 'postponed'::public.catalog_event_lifecycle
          else 'scheduled'::public.catalog_event_lifecycle
        end,
        listing = 'listed',
        integrity = 'corroborated',
        venue_name_snapshot = v_venue_name,
        area_name_snapshot = v_area_name,
        tour_name_snapshot = v_title,
        headliner_name_snapshot = v_headliner_name,
        search_text = lower(regexp_replace(
          btrim(v_title || ' ' || v_headliner_name || ' ' || v_venue_name || ' ' || v_area_name),
          '[[:space:]]+', ' ', 'g'
        )),
        exact_duplicate_key = v_duplicate_key,
        cover_source = case when v_image_url is null then null else 'provider' end,
        cover_remote_url = v_image_url,
        cover_provider_name = case when v_image_url is null then null else 'Ticketmaster' end,
        cover_version = cover_version + 1,
        version = version + 1,
        updated_at = clock_timestamp(),
        last_material_activity_at = clock_timestamp()
    where id = v_event_id and origin = 'ticketmaster';
    delete from public.catalog_event_artists where event_id = v_event_id;
  end if;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
  loop
    select link.entity_id into v_artist_id
    from private.ticketmaster_catalog_entities as link
    where link.entity_kind = 'artist'
      and link.external_entity_id = v_artist ->> 'id';
    insert into public.catalog_event_artists (
      event_id, catalog_artist_id, lineup_position, is_headliner, artist_name_snapshot
    ) values (
      v_event_id, v_artist_id, v_position,
      (v_artist ->> 'is_headliner')::boolean,
      private.optional_catalog_text(v_artist ->> 'name', 160, 'Ticketmaster artist name')
    );
  end loop;

  insert into private.catalog_event_sources (
    event_id, provider_key, external_event_id, external_url, source_updated_at,
    last_refreshed_at, source_status
  ) values (
    v_event_id, 'ticketmaster', v_event_external_id, v_source_url,
    v_source_updated_at, clock_timestamp(), v_source_status
  ) on conflict (provider_key, external_event_id) do update
  set event_id = excluded.event_id,
      external_url = excluded.external_url,
      source_updated_at = excluded.source_updated_at,
      last_refreshed_at = excluded.last_refreshed_at,
      source_status = excluded.source_status;

  return v_event_id;
end;
$$;

create or replace view private.catalog_event_projections as
select
  event.id as event_id,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'catalog_artist_id', lineup.catalog_artist_id,
        'display_name', lineup.artist_name_snapshot,
        'position', lineup.lineup_position,
        'is_headliner', lineup.is_headliner,
        'event_cover', case
          when lineup.is_headliner and event.cover_source is not null then jsonb_build_object(
            'source', event.cover_source,
            'object_path', event.cover_object_path,
            'remote_url', event.cover_remote_url,
            'provider_name', event.cover_provider_name,
            'attribution', event.cover_attribution,
            'source_page_url', event.cover_source_page_url,
            'license_name', event.cover_license_name,
            'license_url', event.cover_license_url,
            'version', event.cover_version
          )
          else null
        end
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
  event.updated_at,
  event.source_local_start_time,
  case event.origin
    when 'musicbrainz' then 'MusicBrainz'
    when 'ticketmaster' then 'Ticketmaster'
    else 'tunedIn community'
  end as source_label,
  source.external_url as source_url
from public.catalog_events as event
left join public.catalog_event_artists as lineup on lineup.event_id = event.id
left join private.catalog_event_sources as source on source.event_id = event.id
group by event.id, source.external_url;

-- Global concert search remains MusicBrainz/community-only for this release.
-- Imported Ticketmaster rows are reachable from Discover, plans, feeds, and
-- direct detail, but never leak into the search surface through local fallback.
create or replace function public.search_discoverable_catalog_events(p_query text)
returns table (event jsonb)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_query text;
begin
  if p_query is null or char_length(p_query) not between 1 and 160
    or private.contains_control_characters(p_query)
  then
    raise exception 'Event search text is invalid' using errcode = '22023';
  end if;
  v_query := lower(regexp_replace(btrim(p_query), '[[:space:]]+', ' ', 'g'));

  return query
  select private.catalog_event_projection_json(projection.event_id)
  from private.catalog_event_projections as projection
  join public.catalog_events as stored_event on stored_event.id = projection.event_id
  where projection.row_state = 'active'
    and stored_event.origin <> 'ticketmaster'
    and private.can_read_catalog_event_as(v_caller_id, projection.event_id)
    and (
      position(v_query in projection.search_text) > 0
      or public.similarity(projection.search_text, v_query) >= 0.2
    )
  order by
    case when projection.event_date >= current_date then 0 else 1 end,
    case when projection.event_date >= current_date
      then projection.event_date - date '2000-01-01'
      else -(projection.event_date - date '2000-01-01')
    end,
    projection.event_id
  limit 50;
end;
$$;

create function public.consume_ticketmaster_discovery_quota(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_profile_id is null or not private.has_completed_profile(p_profile_id) then
    raise exception 'A completed profile is required for event discovery' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('ticketmaster-discovery:' || p_profile_id::text, 0)
  );
  delete from private.ticketmaster_discovery_requests
  where requested_at < clock_timestamp() - interval '1 hour';
  select count(*) into v_count
  from private.ticketmaster_discovery_requests
  where profile_id = p_profile_id
    and requested_at >= clock_timestamp() - interval '1 hour';
  if v_count >= 120 then
    raise exception 'Ticketmaster discovery limit reached. Try again later.' using errcode = 'P0001';
  end if;
  insert into private.ticketmaster_discovery_requests (profile_id) values (p_profile_id);
end;
$$;

create function public.get_ticketmaster_cache(p_cache_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  if p_cache_key is null or p_cache_key !~ '^v1:[a-f0-9]{64}$' then
    raise exception 'Invalid Ticketmaster cache key' using errcode = '22023';
  end if;
  delete from private.ticketmaster_cache
  where ctid in (
    select ctid from private.ticketmaster_cache
    where hard_delete_at <= clock_timestamp()
    order by hard_delete_at limit 100
  );
  select payload into v_payload
  from private.ticketmaster_cache
  where cache_key = p_cache_key and expires_at > clock_timestamp()
    and hard_delete_at > clock_timestamp();
  return v_payload;
end;
$$;

create function public.put_ticketmaster_cache(
  p_cache_key text,
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
  if p_cache_key is null or p_cache_key !~ '^v1:[a-f0-9]{64}$'
    or p_request_type not in ('discover', 'detail')
    or p_payload is null or jsonb_typeof(p_payload) not in ('object', 'array')
    or p_ttl_seconds not between 1 and 3600
  then
    raise exception 'Invalid Ticketmaster cache write' using errcode = '22023';
  end if;
  insert into private.ticketmaster_cache (
    cache_key, request_type, payload, expires_at, hard_delete_at
  ) values (
    p_cache_key, p_request_type, p_payload,
    clock_timestamp() + make_interval(secs => p_ttl_seconds),
    clock_timestamp() + interval '24 hours'
  ) on conflict (cache_key) do update
  set request_type = excluded.request_type,
      payload = excluded.payload,
      expires_at = excluded.expires_at,
      hard_delete_at = excluded.hard_delete_at,
      updated_at = clock_timestamp();
end;
$$;

create function public.reserve_ticketmaster_request_slot()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_reserved_at timestamptz;
  v_daily_count integer;
begin
  delete from private.ticketmaster_api_requests
  where requested_at < v_now - interval '24 hours';
  select count(*) into v_daily_count from private.ticketmaster_api_requests;
  if v_daily_count >= 4500 then
    raise exception 'Ticketmaster daily request budget reached.' using errcode = 'P0001';
  end if;
  select greatest(next_available_at, v_now) into v_reserved_at
  from private.ticketmaster_request_gate where singleton for update;
  if v_reserved_at > v_now + interval '5 seconds' then
    raise exception 'Ticketmaster is busy. Try again shortly.' using errcode = 'P0001';
  end if;
  update private.ticketmaster_request_gate
  set next_available_at = v_reserved_at + interval '500 milliseconds'
  where singleton;
  insert into private.ticketmaster_api_requests (requested_at) values (v_reserved_at);
  return v_reserved_at;
end;
$$;

revoke all on table private.ticketmaster_catalog_entities,
  private.ticketmaster_cache,
  private.ticketmaster_discovery_requests,
  private.ticketmaster_api_requests,
  private.ticketmaster_request_gate
  from public, anon, authenticated;

revoke all on function private.upsert_ticketmaster_catalog_entity(
  public.catalog_entity_kind, text, text, text, uuid, text, text, text, numeric, numeric
) from public, anon, authenticated;
revoke all on function public.upsert_ticketmaster_catalog_event(jsonb)
  from public, anon, authenticated;
revoke all on function public.consume_ticketmaster_discovery_quota(uuid)
  from public, anon, authenticated;
revoke all on function public.get_ticketmaster_cache(text)
  from public, anon, authenticated;
revoke all on function public.put_ticketmaster_cache(text, text, jsonb, integer)
  from public, anon, authenticated;
revoke all on function public.reserve_ticketmaster_request_slot()
  from public, anon, authenticated;

grant execute on function public.upsert_ticketmaster_catalog_event(jsonb) to service_role;
grant execute on function public.consume_ticketmaster_discovery_quota(uuid) to service_role;
grant execute on function public.get_ticketmaster_cache(text) to service_role;
grant execute on function public.put_ticketmaster_cache(text, text, jsonb, integer) to service_role;
grant execute on function public.reserve_ticketmaster_request_slot() to service_role;
