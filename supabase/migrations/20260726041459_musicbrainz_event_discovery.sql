-- MusicBrainz Events are provider-managed concert occurrences. They remain
-- separate from community-created rows: the only provider identity is the
-- provider key plus the external Event ID, never a heuristic match.

-- The original base upsert was defined before the legacy concert helpers were
-- retired. Keep its service-only behavior while moving it to catalog text
-- validation so event ingestion does not restore a removed legacy helper.
create or replace function private.upsert_musicbrainz_base(
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
  v_display_name text := private.optional_catalog_text(p_display_name, 160, 'MusicBrainz name');
  v_sort_name text := private.optional_catalog_text(
    coalesce(p_sort_name, p_display_name), 160, 'MusicBrainz sort name'
  );
  v_disambiguation text := private.optional_catalog_text(
    p_disambiguation, 240, 'MusicBrainz disambiguation'
  );
begin
  if p_mbid is null or v_display_name is null or v_sort_name is null then
    raise exception 'MusicBrainz ID, name, and sort name are required' using errcode = '22023';
  end if;
  insert into public.catalog_entities (
    kind, origin, status, display_name, sort_name, disambiguation, musicbrainz_mbid
  ) values (
    p_kind, 'musicbrainz', 'active', v_display_name, v_sort_name, v_disambiguation, p_mbid
  ) on conflict (kind, musicbrainz_mbid) where musicbrainz_mbid is not null do update
  set display_name = case when p_is_authoritative then excluded.display_name else public.catalog_entities.display_name end,
      sort_name = case when p_is_authoritative then excluded.sort_name else public.catalog_entities.sort_name end,
      disambiguation = case when p_is_authoritative then excluded.disambiguation else public.catalog_entities.disambiguation end
  returning id into v_entity_id;
  insert into private.catalog_entity_provenance (entity_id, kind, source_updated_at, refreshed_at)
  values (v_entity_id, p_kind, clock_timestamp(), clock_timestamp())
  on conflict (entity_id) do update
  set source_updated_at = excluded.source_updated_at, refreshed_at = excluded.refreshed_at;
  return v_entity_id;
end;
$$;

alter table public.catalog_events
  add column origin text not null default 'community'
    check (origin in ('community', 'musicbrainz')),
  add column source_local_start_time time without time zone;

alter table public.catalog_events
  alter column created_by drop not null,
  add constraint catalog_events_origin_owner_check check (
    (origin = 'community' and created_by is not null and source_local_start_time is null)
    or (origin = 'musicbrainz' and created_by is null)
  );

create table private.catalog_event_sources (
  event_id uuid not null references public.catalog_events (id) on delete cascade,
  provider_key text not null check (
    provider_key in ('musicbrainz')
  ),
  external_event_id text not null check (
    char_length(external_event_id) between 1 and 200
    and not private.contains_control_characters(external_event_id)
  ),
  external_url text not null check (
    char_length(external_url) <= 2048
    and external_url ~ '^https://musicbrainz[.]org/event/[0-9a-f-]{36}$'
  ),
  source_updated_at timestamptz,
  last_refreshed_at timestamptz not null default clock_timestamp(),
  source_status text not null default 'active' check (
    source_status in ('active', 'cancelled')
  ),
  primary key (provider_key, external_event_id),
  unique (event_id, provider_key)
);

create index catalog_event_sources_event_id
  on private.catalog_event_sources (event_id);

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
    else 'tunedIn community'
  end as source_label,
  source.external_url as source_url
from public.catalog_events as event
left join public.catalog_event_artists as lineup on lineup.event_id = event.id
left join private.catalog_event_sources as source
  on source.event_id = event.id and source.provider_key = 'musicbrainz'
group by event.id, source.external_url;

create or replace function private.catalog_event_projection_json(p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'event_id', projection.event_id,
    'artists', projection.artists,
    'catalog_place_id', projection.catalog_place_id,
    'catalog_area_id', projection.catalog_area_id,
    'catalog_tour_id', projection.catalog_tour_id,
    'tour_name', projection.tour_name,
    'venue_name', projection.venue_name,
    'area_name', projection.area_name,
    'event_date', projection.event_date,
    'starts_at', projection.starts_at,
    'time_zone_identifier', projection.time_zone_identifier,
    'source_local_start_time', projection.source_local_start_time,
    'memory_unlock_at', projection.memory_unlock_at,
    'lifecycle', projection.lifecycle,
    'listing', projection.listing,
    'integrity', projection.integrity,
    'row_state', projection.row_state,
    'source_label', projection.source_label,
    'source_url', projection.source_url
  ))
  from private.catalog_event_projections as projection
  where projection.event_id = private.resolve_catalog_event_id(p_event_id)
$$;

create or replace function private.catalog_event_history_projection_json(p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'event_id', projection.event_id,
    'artists', projection.artists,
    'catalog_place_id', projection.catalog_place_id,
    'catalog_area_id', projection.catalog_area_id,
    'catalog_tour_id', projection.catalog_tour_id,
    'tour_name', projection.tour_name,
    'venue_name', projection.venue_name,
    'area_name', projection.area_name,
    'event_date', projection.event_date,
    'starts_at', projection.starts_at,
    'time_zone_identifier', projection.time_zone_identifier,
    'source_local_start_time', projection.source_local_start_time,
    'memory_unlock_at', projection.memory_unlock_at,
    'lifecycle', projection.lifecycle,
    'listing', projection.listing,
    'integrity', projection.integrity,
    'row_state', projection.row_state,
    'source_label', projection.source_label,
    'source_url', projection.source_url
  ))
  from private.catalog_event_projections as projection
  where projection.event_id = coalesce(
    private.resolve_catalog_event_id(p_event_id),
    p_event_id
  )
$$;

create function public.upsert_musicbrainz_catalog_event(p_event jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_mbid uuid;
  v_event_date date;
  v_local_start_time time;
  v_title text;
  v_venue jsonb;
  v_artists jsonb;
  v_artist jsonb;
  v_venue_id uuid;
  v_area_id uuid;
  v_artist_id uuid;
  v_headliner_id uuid;
  v_headliner_name text;
  v_venue_name text;
  v_area_name text := 'Area not listed';
  v_event_id uuid;
  v_position integer;
  v_is_headliner boolean;
  v_source_status text;
  v_external_url text;
  v_duplicate_key text;
begin
  if p_event is null or jsonb_typeof(p_event) <> 'object'
    or (p_event - array[
      'event_mbid', 'title', 'event_date', 'local_start_time', 'venue',
      'artists', 'source_status', 'source_updated_at'
    ]) <> '{}'::jsonb
  then
    raise exception 'MusicBrainz event payload is invalid' using errcode = '22023';
  end if;

  begin
    v_event_mbid := (p_event ->> 'event_mbid')::uuid;
    v_event_date := (p_event ->> 'event_date')::date;
    v_local_start_time := nullif(p_event ->> 'local_start_time', '')::time;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception 'MusicBrainz event payload is invalid' using errcode = '22023';
  end;
  if v_event_date not between date '1900-01-01' and date '2200-12-31' then
    raise exception 'MusicBrainz event date is invalid' using errcode = '22023';
  end if;
  v_title := private.optional_catalog_text(p_event ->> 'title', 160, 'MusicBrainz event title');
  if v_title is null then
    raise exception 'MusicBrainz event title is required' using errcode = '22023';
  end if;
  v_venue := p_event -> 'venue';
  v_artists := p_event -> 'artists';
  v_source_status := coalesce(nullif(p_event ->> 'source_status', ''), 'active');
  if v_source_status not in ('active', 'cancelled') then
    raise exception 'MusicBrainz event status is invalid' using errcode = '22023';
  end if;
  if jsonb_typeof(v_venue) <> 'object'
    or (v_venue - array['mbid', 'name', 'area_mbid', 'area_name']) <> '{}'::jsonb
    or jsonb_typeof(v_artists) <> 'array'
    or jsonb_array_length(v_artists) not between 1 and 10
  then
    raise exception 'MusicBrainz event payload is invalid' using errcode = '22023';
  end if;

  select id into v_venue_id
  from public.upsert_musicbrainz_catalog_entity(
    'place',
    (v_venue ->> 'mbid')::uuid,
    v_venue ->> 'name',
    v_venue ->> 'name',
    null,
    jsonb_strip_nulls(jsonb_build_object(
      'area_mbid', nullif(v_venue ->> 'area_mbid', ''),
      'area_name', nullif(v_venue ->> 'area_name', '')
    )),
    '[]'::jsonb
  );

  select entity.display_name, place.area_id
  into v_venue_name, v_area_id
  from public.catalog_entities as entity
  join public.catalog_places as place on place.id = entity.id
  where entity.id = v_venue_id;
  if v_area_id is not null then
    select display_name into v_area_name
    from public.catalog_entities where id = v_area_id;
  end if;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
  loop
    if jsonb_typeof(v_artist) <> 'object'
      or (v_artist - array['mbid', 'name', 'is_headliner']) <> '{}'::jsonb
      or jsonb_typeof(v_artist -> 'is_headliner') <> 'boolean'
    then
      raise exception 'MusicBrainz event artist payload is invalid' using errcode = '22023';
    end if;
    select id into v_artist_id
    from public.upsert_musicbrainz_catalog_entity(
      'artist', (v_artist ->> 'mbid')::uuid, v_artist ->> 'name',
      v_artist ->> 'name', null, '{}'::jsonb, '[]'::jsonb
    );
    v_is_headliner := (v_artist ->> 'is_headliner')::boolean;
    if v_is_headliner and v_headliner_id is null then
      v_headliner_id := v_artist_id;
      v_headliner_name := v_artist ->> 'name';
    end if;
  end loop;
  if v_headliner_id is null then
    raise exception 'MusicBrainz event requires a headliner' using errcode = '22023';
  end if;

  v_duplicate_key := pg_catalog.md5('musicbrainz|' || v_event_mbid::text);
  v_external_url := 'https://musicbrainz.org/event/' || v_event_mbid::text;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('musicbrainz-event:' || v_event_mbid::text, 0)
  );

  select source.event_id into v_event_id
  from private.catalog_event_sources as source
  where source.provider_key = 'musicbrainz'
    and source.external_event_id = v_event_mbid::text
  for update;

  if v_event_id is null then
    insert into public.catalog_events (
      created_by, origin, catalog_place_id, catalog_area_id,
      headliner_catalog_artist_id, event_date, starts_at, time_zone_identifier,
      source_local_start_time, memory_unlock_at, lifecycle, listing, integrity,
      venue_name_snapshot, area_name_snapshot, tour_name_snapshot,
      headliner_name_snapshot, search_text, exact_duplicate_key
    ) values (
      null, 'musicbrainz', v_venue_id, v_area_id,
      v_headliner_id, v_event_date,
      (v_event_date + coalesce(v_local_start_time, time '12:00')) at time zone 'UTC',
      'UTC', v_local_start_time,
      ((v_event_date + coalesce(v_local_start_time, time '12:00')) at time zone 'UTC') + interval '4 hours',
      case when v_source_status = 'cancelled' then 'cancelled'::public.catalog_event_lifecycle else 'scheduled'::public.catalog_event_lifecycle end,
      'listed', 'corroborated', v_venue_name, v_area_name, v_title,
      v_headliner_name,
      lower(regexp_replace(
        btrim(v_title || ' ' || v_headliner_name || ' ' || v_venue_name || ' ' || v_area_name),
        '[[:space:]]+', ' ', 'g'
      )),
      v_duplicate_key
    ) returning id into v_event_id;
  else
    update public.catalog_events
    set catalog_place_id = v_venue_id,
        catalog_area_id = v_area_id,
        headliner_catalog_artist_id = v_headliner_id,
        event_date = v_event_date,
        starts_at = (v_event_date + coalesce(v_local_start_time, time '12:00')) at time zone 'UTC',
        time_zone_identifier = 'UTC',
        source_local_start_time = v_local_start_time,
        memory_unlock_at = ((v_event_date + coalesce(v_local_start_time, time '12:00')) at time zone 'UTC') + interval '4 hours',
        lifecycle = case when v_source_status = 'cancelled' then 'cancelled'::public.catalog_event_lifecycle else 'scheduled'::public.catalog_event_lifecycle end,
        listing = 'listed', integrity = 'corroborated',
        venue_name_snapshot = v_venue_name, area_name_snapshot = v_area_name,
        tour_name_snapshot = v_title, headliner_name_snapshot = v_headliner_name,
        search_text = lower(regexp_replace(
          btrim(v_title || ' ' || v_headliner_name || ' ' || v_venue_name || ' ' || v_area_name),
          '[[:space:]]+', ' ', 'g'
        )),
        exact_duplicate_key = v_duplicate_key,
        version = version + 1, updated_at = clock_timestamp(), last_material_activity_at = clock_timestamp()
    where id = v_event_id;
    delete from public.catalog_event_artists where event_id = v_event_id;
  end if;

  for v_artist, v_position in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
  loop
    select entity.id into v_artist_id
    from public.catalog_entities as entity
    where entity.kind = 'artist' and entity.musicbrainz_mbid = (v_artist ->> 'mbid')::uuid;
    insert into public.catalog_event_artists (
      event_id, catalog_artist_id, lineup_position, is_headliner, artist_name_snapshot
    ) values (
      v_event_id, v_artist_id, v_position,
      (v_artist ->> 'is_headliner')::boolean,
      coalesce(
        private.optional_catalog_text(v_artist ->> 'name', 160, 'MusicBrainz artist name'),
        ''
      )
    );
  end loop;

  insert into private.catalog_event_sources (
    event_id, provider_key, external_event_id, external_url, source_updated_at,
    last_refreshed_at, source_status
  ) values (
    v_event_id, 'musicbrainz', v_event_mbid::text, v_external_url,
    nullif(p_event ->> 'source_updated_at', '')::timestamptz,
    clock_timestamp(), v_source_status
  ) on conflict (provider_key, external_event_id) do update
  set event_id = excluded.event_id,
      external_url = excluded.external_url,
      source_updated_at = excluded.source_updated_at,
      last_refreshed_at = excluded.last_refreshed_at,
      source_status = excluded.source_status;

  return v_event_id;
end;
$$;

create function public.search_discoverable_catalog_events(p_query text)
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
  where projection.row_state = 'active'
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

create function public.get_discoverable_catalog_event_detail(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_event jsonb;
begin
  if v_event_id is null or not private.can_read_catalog_event_as(v_caller_id, v_event_id) then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;
  select private.catalog_event_projection_json(v_event_id) into v_event;
  return v_event;
end;
$$;

revoke all on table private.catalog_event_sources from public, anon, authenticated;
revoke all on function public.upsert_musicbrainz_catalog_event(jsonb)
  from public, anon, authenticated;
grant execute on function public.upsert_musicbrainz_catalog_event(jsonb) to service_role;
revoke all on function public.search_discoverable_catalog_events(text) from public, anon;
revoke all on function public.get_discoverable_catalog_event_detail(uuid) from public, anon;
grant execute on function public.search_discoverable_catalog_events(text) to authenticated;
grant execute on function public.get_discoverable_catalog_event_detail(uuid) to authenticated;
