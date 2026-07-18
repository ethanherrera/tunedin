-- Remove the final private-concert context from catalog search and custom
-- MusicBrainz fallback creation. Catalog identities are authorized by origin or
-- creator provenance; event creation consumes those identities separately.

create function private.is_normalized_user_text(p_value text, p_maximum_length integer)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_value is not null
    and p_value = private.normalize_user_text(p_value)
    and char_length(p_value) between 1 and p_maximum_length
    and p_value !~ '[[:cntrl:]]'
$$;

-- Rewrite the remaining event/catalog routines to the neutral text helpers
-- before removing the old helper names.
do $rewrite_text_helpers$
declare
  target record;
  definition text;
begin
  for target in
    select function.oid
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace on namespace.oid = function.pronamespace
    where function.prokind = 'f'
      and namespace.nspname in ('public', 'private')
      and function.proname not in (
        'normalize_concert_text',
        'require_concert_text',
        'optional_concert_text',
        'is_normalized_concert_text'
      )
      and pg_catalog.pg_get_functiondef(function.oid) ~
        '(normalize_concert_text|require_concert_text|optional_concert_text|is_normalized_concert_text)'
  loop
    definition := pg_catalog.pg_get_functiondef(target.oid);
    definition := replace(definition, 'private.normalize_concert_text', 'private.normalize_user_text');
    definition := replace(definition, 'private.require_concert_text', 'private.require_user_text');
    definition := replace(definition, 'private.optional_concert_text', 'private.optional_user_text');
    definition := replace(definition, 'private.is_normalized_concert_text', 'private.is_normalized_user_text');
    execute definition;
  end loop;
end
$rewrite_text_helpers$;

-- Custom catalog creation now has one supported local provenance. The retired
-- enum labels are removed after all dependent functions are rebound below.
create or replace function private.assert_catalog_creation_quota(
  p_creator_id uuid,
  p_kind public.catalog_entity_kind
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  hour_limit integer;
  day_limit integer;
  hour_count integer;
  day_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-quota:' || p_creator_id::text || ':' || p_kind::text, 0)
  );
  select rolling_hour_limit, rolling_day_limit
  into hour_limit, day_limit
  from private.catalog_creation_quota_config
  where kind = p_kind;
  if not found then
    raise exception 'Catalog creation is not configured for this entity type'
      using errcode = 'P0001';
  end if;
  select
    count(*) filter (where provenance.created_at >= clock_timestamp() - interval '1 hour'),
    count(*)
  into hour_count, day_count
  from private.catalog_entity_provenance as provenance
  join public.catalog_entities as entity on entity.id = provenance.entity_id
  where provenance.creator_id = p_creator_id
    and provenance.kind = p_kind
    and provenance.created_at >= clock_timestamp() - interval '24 hours'
    and entity.origin = 'tunedin_custom';
  if hour_count >= hour_limit or day_count >= day_limit then
    raise exception 'You have reached the custom % limit. Try again later.', p_kind::text
      using errcode = 'P0001';
  end if;
end;
$$;

create or replace function private.get_or_create_local_catalog_entity(
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
  entity_id uuid;
  display_name text;
  sort_name text;
  disambiguation text;
begin
  if p_creator_id is null or not private.has_completed_profile(p_creator_id) then
    raise exception 'Complete onboarding before creating catalog entries'
      using errcode = '42501';
  end if;
  if p_origin <> 'tunedin_custom' then
    raise exception 'Local catalog entries require tunedIn custom provenance'
      using errcode = '22023';
  end if;
  display_name := private.require_user_text(p_display_name, 160, 'Catalog name');
  sort_name := private.require_user_text(
    coalesce(p_sort_name, display_name), 160, 'Catalog sort name'
  );
  disambiguation := private.optional_catalog_text(
    p_disambiguation, 240, 'Catalog disambiguation'
  );
  if p_dedupe_key is null
    or char_length(p_dedupe_key) not between 1 and 1000
    or private.contains_control_characters(p_dedupe_key)
  then
    raise exception 'A valid catalog duplicate key is required' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'catalog-entity:' || p_creator_id::text || ':' || p_kind::text || ':' || p_dedupe_key,
      0
    )
  );
  select entity.id into entity_id
  from private.catalog_entity_provenance as provenance
  join public.catalog_entities as entity on entity.id = provenance.entity_id
  where provenance.creator_id = p_creator_id
    and provenance.kind = p_kind
    and provenance.dedupe_key = p_dedupe_key
    and entity.status in ('active', 'needs_review')
  limit 1;
  if found then
    return entity_id;
  end if;
  if p_enforce_quota then
    perform private.assert_catalog_creation_quota(p_creator_id, p_kind);
  end if;
  insert into public.catalog_entities (
    kind, origin, status, display_name, sort_name, disambiguation
  ) values (
    p_kind, 'tunedin_custom', 'active', display_name, sort_name, disambiguation
  )
  returning id into entity_id;
  insert into private.catalog_entity_provenance (
    entity_id, kind, creator_id, ingested_by, dedupe_key
  ) values (entity_id, p_kind, p_creator_id, p_creator_id, p_dedupe_key);
  return entity_id;
end;
$$;

CREATE OR REPLACE FUNCTION private.can_use_catalog_entity_as(p_user_id uuid, p_entity_id uuid, p_kind catalog_entity_kind)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      )
  )
$function$;

CREATE OR REPLACE FUNCTION private.resolve_local_area(p_creator_id uuid, p_name text, p_origin catalog_entity_origin, p_country_code text DEFAULT NULL::text, p_parent_area_id uuid DEFAULT NULL::uuid, p_enforce_quota boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_name text := private.require_user_text(p_name, 160, 'Area name');
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
      p_creator_id, p_parent_area_id, 'area'
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
$function$;

CREATE OR REPLACE FUNCTION private.resolve_local_artist(p_creator_id uuid, p_name text, p_origin catalog_entity_origin, p_artist_type text DEFAULT NULL::text, p_disambiguation text DEFAULT NULL::text, p_area_id uuid DEFAULT NULL::uuid, p_enforce_quota boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_name text := private.require_user_text(p_name, 160, 'Artist name');
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
      p_creator_id, p_area_id, 'area'
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
$function$;

CREATE OR REPLACE FUNCTION private.resolve_local_place(p_creator_id uuid, p_name text, p_origin catalog_entity_origin, p_area_id uuid DEFAULT NULL::uuid, p_place_type text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_disambiguation text DEFAULT NULL::text, p_enforce_quota boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_name text := private.require_user_text(p_name, 160, 'Venue name');
  v_place_type text := private.optional_catalog_text(p_place_type, 80, 'Place type');
  v_address text := private.optional_catalog_text(p_address, 240, 'Address');
  v_disambiguation text := private.optional_catalog_text(p_disambiguation, 240, 'Place disambiguation');
  v_entity_id uuid;
  v_key text;
begin
  if p_area_id is not null and (
    not private.can_use_catalog_entity_as(
      p_creator_id, p_area_id, 'area'
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
$function$;

CREATE OR REPLACE FUNCTION private.resolve_local_song(p_creator_id uuid, p_title text, p_origin catalog_entity_origin, p_artist_ids uuid[], p_disambiguation text DEFAULT NULL::text, p_enforce_quota boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_title text := private.require_user_text(p_title, 160, 'Song title');
  v_disambiguation text := private.optional_catalog_text(p_disambiguation, 240, 'Song disambiguation');
  v_artist_id uuid;
  v_artist_name text;
  v_artist_names text[] := '{}'::text[];
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
      p_creator_id, v_artist_id, 'artist'
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
$function$;

CREATE OR REPLACE FUNCTION private.resolve_local_tour(p_creator_id uuid, p_name text, p_origin catalog_entity_origin, p_artist_ids uuid[], p_disambiguation text DEFAULT NULL::text, p_enforce_quota boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_name text := private.require_user_text(p_name, 160, 'Tour');
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
      p_creator_id, v_artist_id, 'artist'
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
$function$;

CREATE FUNCTION private.resolve_catalog_event_entity_as(
  p_user_id uuid,
  p_entity_id uuid,
  p_kind catalog_entity_kind
)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    or private.can_use_catalog_entity_as(p_user_id, p_entity_id, p_kind)
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
$function$;

-- Rebind the existing event payload validator to the context-free resolver,
-- then remove the old four-argument private overload.
do $rewrite_event_entity_resolver$
declare
  definition text;
begin
  select pg_catalog.pg_get_functiondef(function.oid)
  into definition
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'private'
    and function.proname = 'prepare_catalog_event_payload';

  definition := replace(
    definition,
    'p_actor_id, v_artist_id, ''artist'', p_event_id',
    'p_actor_id, v_artist_id, ''artist'''
  );
  definition := replace(
    definition,
    'p_actor_id, p_catalog_place_id, ''place'', p_event_id',
    'p_actor_id, p_catalog_place_id, ''place'''
  );
  definition := replace(
    definition,
    'p_actor_id, p_catalog_tour_id, ''tour'', p_event_id',
    'p_actor_id, p_catalog_tour_id, ''tour'''
  );
  execute definition;
end
$rewrite_event_entity_resolver$;

drop function private.resolve_catalog_event_entity_as(
  uuid, uuid, public.catalog_entity_kind, uuid
);

do $remove_event_payload_context$
declare
  target record;
  definition text;
begin
  select pg_catalog.pg_get_functiondef(function.oid)
  into definition
  from pg_catalog.pg_proc as function
  join pg_catalog.pg_namespace as namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'private'
    and function.proname = 'prepare_catalog_event_payload';

  definition := replace(
    definition,
    ', p_event_id uuid DEFAULT NULL::uuid)',
    ')'
  );
  execute definition;

  for target in
    select function.oid
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace on namespace.oid = function.pronamespace
    where function.prokind = 'f'
      and namespace.nspname = 'public'
      and pg_catalog.pg_get_functiondef(function.oid) like
        '%private.prepare_catalog_event_payload%'
  loop
    definition := pg_catalog.pg_get_functiondef(target.oid);
    definition := replace(
      definition,
      E'p_listing,\n    null\n  );',
      E'p_listing\n  );'
    );
    definition := replace(
      definition,
      E'p_listing,\n    p_event_id\n  );',
      E'p_listing\n  );'
    );
    execute definition;
  end loop;
end
$remove_event_payload_context$;

drop function private.prepare_catalog_event_payload(
  uuid, jsonb, uuid, uuid, date, timestamptz, text,
  public.catalog_event_listing, uuid
);

CREATE OR REPLACE FUNCTION public.create_custom_catalog_area(p_name text, p_country_code text DEFAULT NULL::text, p_parent_area_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(catalog_id uuid, musicbrainz_id uuid, display_name text, sort_name text, disambiguation text, subtitle text, origin catalog_entity_origin, metadata jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  v_entity_id := private.resolve_local_area(
    p_creator_id => v_caller_id,
    p_name => p_name,
    p_origin => 'tunedin_custom',
    p_country_code => p_country_code,
    p_parent_area_id => p_parent_area_id
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_custom_catalog_artist(p_name text, p_artist_type text DEFAULT NULL::text, p_disambiguation text DEFAULT NULL::text, p_area_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(catalog_id uuid, musicbrainz_id uuid, display_name text, sort_name text, disambiguation text, subtitle text, origin catalog_entity_origin, metadata jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  v_entity_id := private.resolve_local_artist(
    p_creator_id => v_caller_id,
    p_name => p_name,
    p_origin => 'tunedin_custom',
    p_artist_type => p_artist_type,
    p_disambiguation => p_disambiguation,
    p_area_id => p_area_id
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_custom_catalog_place(p_name text, p_area_id uuid, p_place_type text DEFAULT NULL::text, p_address text DEFAULT NULL::text)
 RETURNS TABLE(catalog_id uuid, musicbrainz_id uuid, display_name text, sort_name text, disambiguation text, subtitle text, origin catalog_entity_origin, metadata jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
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
    p_address => p_address
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_custom_catalog_song(p_title text, p_artist_ids uuid[])
 RETURNS TABLE(catalog_id uuid, musicbrainz_id uuid, display_name text, sort_name text, disambiguation text, subtitle text, origin catalog_entity_origin, metadata jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  v_entity_id := private.resolve_local_song(
    p_creator_id => v_caller_id,
    p_title => p_title,
    p_origin => 'tunedin_custom',
    p_artist_ids => p_artist_ids
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_custom_catalog_tour(p_name text, p_artist_ids uuid[])
 RETURNS TABLE(catalog_id uuid, musicbrainz_id uuid, display_name text, sort_name text, disambiguation text, subtitle text, origin catalog_entity_origin, metadata jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_entity_id uuid;
begin
  v_entity_id := private.resolve_local_tour(
    p_creator_id => v_caller_id,
    p_name => p_name,
    p_origin => 'tunedin_custom',
    p_artist_ids => p_artist_ids
  );
  return query
  select selection.id, selection.musicbrainz_mbid, selection.display_name,
    selection.sort_name, selection.disambiguation, selection.subtitle,
    selection.origin, selection.metadata
  from private.catalog_selection(v_entity_id) as selection;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_catalog_artist_search_context(p_profile_id uuid, p_artist_ids uuid[])
 RETURNS TABLE(catalog_id uuid, musicbrainz_mbid uuid, display_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_profile_id is null or not private.has_completed_profile(p_profile_id) then
    raise exception 'A completed profile is required for artist search context'
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
        p_profile_id, requested.id, 'artist'
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
$function$;

CREATE OR REPLACE FUNCTION public.search_catalog(p_kind catalog_entity_kind, p_query text, p_artist_ids uuid[] DEFAULT NULL::uuid[], p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, kind catalog_entity_kind, origin catalog_entity_origin, display_name text, sort_name text, disambiguation text, musicbrainz_mbid uuid, subtitle text, metadata jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller_id uuid := private.require_catalog_caller();
  v_query text;
begin
  if p_query is null or private.contains_control_characters(p_query) then
    raise exception 'Catalog search requires a valid query'
      using errcode = '22023';
  end if;
  v_query := private.normalize_user_text(p_query);
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
      or private.can_use_catalog_entity_as(v_caller_id, entity.id, p_kind)
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
$function$;

-- Remove the old overloads only after their clean replacements exist.
drop function private.can_use_catalog_entity_as(uuid, uuid, public.catalog_entity_kind, uuid);
drop function private.resolve_local_area(uuid, text, public.catalog_entity_origin, text, uuid, boolean, uuid);
drop function private.resolve_local_artist(uuid, text, public.catalog_entity_origin, text, text, uuid, boolean, uuid);
drop function private.resolve_local_place(uuid, text, public.catalog_entity_origin, uuid, text, text, text, boolean, uuid);
drop function private.resolve_local_song(uuid, text, public.catalog_entity_origin, uuid[], text, boolean, uuid);
drop function private.resolve_local_tour(uuid, text, public.catalog_entity_origin, uuid[], text, boolean, uuid);
drop function public.create_custom_catalog_area(text, text, uuid, uuid);
drop function public.create_custom_catalog_artist(text, text, text, uuid, uuid);
drop function public.create_custom_catalog_place(text, uuid, text, text, uuid);
drop function public.create_custom_catalog_song(text, uuid[], uuid);
drop function public.create_custom_catalog_tour(text, uuid[], uuid);
drop function public.get_catalog_artist_search_context(uuid, uuid[], uuid);
drop function public.search_catalog(public.catalog_entity_kind, text, uuid[], integer, integer, uuid);

-- Rebuild the provenance enum so generated clients cannot represent retired
-- import modes. Function definitions are preserved and rebound to the new type.
create temporary table catalog_origin_function_definitions (
  priority integer not null,
  definition text not null
) on commit drop;

insert into catalog_origin_function_definitions (priority, definition)
select
  case
    when function.proname = 'get_or_create_local_catalog_entity' then 10
    when function.proname like 'resolve_local_%' then 20
    when function.proname = 'catalog_selection' then 30
    else 40
  end,
  pg_catalog.pg_get_functiondef(function.oid)
from pg_catalog.pg_proc as function
where function.prokind = 'f'
  and exists (
    select 1
    from pg_catalog.pg_depend as dependency
    where dependency.classid = 'pg_proc'::regclass
      and dependency.objid = function.oid
      and dependency.refobjid = 'public.catalog_entity_origin'::regtype
  );

do $drop_catalog_origin_functions$
declare
  target record;
begin
  for target in
    select function.oid::regprocedure as signature
    from pg_catalog.pg_proc as function
    where function.prokind = 'f'
      and exists (
        select 1
        from pg_catalog.pg_depend as dependency
        where dependency.classid = 'pg_proc'::regclass
          and dependency.objid = function.oid
          and dependency.refobjid = 'public.catalog_entity_origin'::regtype
      )
  loop
    execute pg_catalog.format('drop function if exists %s cascade', target.signature);
  end loop;
end
$drop_catalog_origin_functions$;

alter table public.catalog_entities
  drop constraint catalog_entities_musicbrainz_origin_check;
alter type public.catalog_entity_origin rename to catalog_entity_origin_retired;
create type public.catalog_entity_origin as enum ('musicbrainz', 'tunedin_custom');
alter table public.catalog_entities
  alter column origin type public.catalog_entity_origin
  using origin::text::public.catalog_entity_origin;
alter table public.catalog_entities
  add constraint catalog_entities_musicbrainz_origin_check check (
    (origin = 'musicbrainz' and musicbrainz_mbid is not null)
    or (origin <> 'musicbrainz' and musicbrainz_mbid is null)
  );
drop type public.catalog_entity_origin_retired;

do $restore_catalog_origin_functions$
declare
  target record;
begin
  for target in
    select definition
    from catalog_origin_function_definitions
    order by priority, definition
  loop
    execute target.definition;
  end loop;
end
$restore_catalog_origin_functions$;

-- Bind empty array literals to their declared type so catalog ingestion does
-- not depend on an implicit text-to-array assignment.
do $type_catalog_array_initializers$
declare
  target record;
  definition text;
begin
  for target in
    select function.oid
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace on namespace.oid = function.pronamespace
    where function.prokind = 'f'
      and (
        (namespace.nspname = 'private' and function.proname = 'resolve_local_song')
        or (namespace.nspname = 'public' and function.proname = 'upsert_musicbrainz_catalog_entity')
      )
  loop
    definition := pg_catalog.pg_get_functiondef(target.oid);
    definition := replace(
      definition,
      ' text[] := ''{}'';',
      ' text[] := ''{}''::text[];'
    );
    execute definition;
  end loop;
end
$type_catalog_array_initializers$;

revoke all on function private.catalog_selection(uuid) from public, anon, authenticated;
revoke all on function private.get_or_create_local_catalog_entity(
  uuid, public.catalog_entity_kind, public.catalog_entity_origin,
  text, text, text, text, boolean
) from public, anon, authenticated;
revoke all on function public.upsert_musicbrainz_catalog_entity(
  public.catalog_entity_kind, uuid, text, text, text, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.upsert_musicbrainz_catalog_entity(
  public.catalog_entity_kind, uuid, text, text, text, jsonb, jsonb
) to service_role;

drop function if exists private.apply_concert_catalog_snapshot() cascade;
drop function if exists private.can_view_concert(uuid) cascade;
drop function if exists private.concert_album_policy_limits() cascade;
drop function if exists private.require_concert_editor(uuid) cascade;
drop function if exists private.validate_catalog_concert_payload(uuid, jsonb, uuid, uuid, jsonb, uuid) cascade;
drop function if exists public.concert_album_policy() cascade;

do $rewrite_text_constraints$
declare
  target record;
  definition text;
begin
  for target in
    select
      constraint_record.conrelid::regclass as relation_name,
      constraint_record.conname,
      pg_catalog.pg_get_constraintdef(constraint_record.oid, true) as constraint_definition
    from pg_catalog.pg_constraint as constraint_record
    where pg_catalog.pg_get_constraintdef(constraint_record.oid, true)
      like '%private.is_normalized_concert_text%'
  loop
    definition := replace(
      target.constraint_definition,
      'private.is_normalized_concert_text',
      'private.is_normalized_user_text'
    );
    execute pg_catalog.format(
      'alter table %s drop constraint %I',
      target.relation_name,
      target.conname
    );
    execute pg_catalog.format(
      'alter table %s add constraint %I %s',
      target.relation_name,
      target.conname,
      definition
    );
  end loop;
end
$rewrite_text_constraints$;

drop function private.normalize_concert_text(text);
drop function private.require_concert_text(text, integer, text);
drop function private.optional_concert_text(text, integer, text);
drop function private.is_normalized_concert_text(text, integer);

revoke all on function private.is_normalized_user_text(text, integer) from public, anon, authenticated;
revoke all on function private.can_use_catalog_entity_as(uuid, uuid, public.catalog_entity_kind) from public, anon, authenticated;
revoke all on function private.resolve_catalog_event_entity_as(
  uuid, uuid, public.catalog_entity_kind
) from public, anon, authenticated;
revoke all on function private.prepare_catalog_event_payload(
  uuid, jsonb, uuid, uuid, date, timestamptz, text,
  public.catalog_event_listing
) from public, anon, authenticated;
revoke all on function private.resolve_local_area(uuid, text, public.catalog_entity_origin, text, uuid, boolean) from public, anon, authenticated;
revoke all on function private.resolve_local_artist(uuid, text, public.catalog_entity_origin, text, text, uuid, boolean) from public, anon, authenticated;
revoke all on function private.resolve_local_place(uuid, text, public.catalog_entity_origin, uuid, text, text, text, boolean) from public, anon, authenticated;
revoke all on function private.resolve_local_song(uuid, text, public.catalog_entity_origin, uuid[], text, boolean) from public, anon, authenticated;
revoke all on function private.resolve_local_tour(uuid, text, public.catalog_entity_origin, uuid[], text, boolean) from public, anon, authenticated;

revoke all on function public.create_custom_catalog_area(text, text, uuid) from public, anon, authenticated;
revoke all on function public.create_custom_catalog_artist(text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.create_custom_catalog_place(text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.create_custom_catalog_song(text, uuid[]) from public, anon, authenticated;
revoke all on function public.create_custom_catalog_tour(text, uuid[]) from public, anon, authenticated;
revoke all on function public.get_catalog_artist_search_context(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.search_catalog(public.catalog_entity_kind, text, uuid[], integer, integer) from public, anon, authenticated;

grant execute on function public.create_custom_catalog_area(text, text, uuid) to authenticated;
grant execute on function public.create_custom_catalog_artist(text, text, text, uuid) to authenticated;
grant execute on function public.create_custom_catalog_place(text, uuid, text, text) to authenticated;
grant execute on function public.create_custom_catalog_song(text, uuid[]) to authenticated;
grant execute on function public.create_custom_catalog_tour(text, uuid[]) to authenticated;
grant execute on function public.get_catalog_artist_search_context(uuid, uuid[]) to service_role;
grant execute on function public.search_catalog(public.catalog_entity_kind, text, uuid[], integer, integer) to authenticated;
