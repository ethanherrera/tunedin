-- Artwork imported for MusicBrainz events is durable, provider-neutral event
-- cover data. The private resolution state prevents a search from repeatedly
-- calling upstream artwork APIs when an event has no artwork yet.

create table private.catalog_event_artwork_imports (
  event_id uuid primary key references public.catalog_events (id) on delete cascade,
  resolution_state text not null check (
    resolution_state in ('resolving', 'resolved', 'unavailable', 'retryable')
  ),
  selected_priority smallint check (selected_priority between 1 and 4),
  last_attempt_at timestamptz not null default clock_timestamp(),
  retry_after timestamptz not null
);

create index catalog_event_artwork_imports_retry_after
  on private.catalog_event_artwork_imports (retry_after);

create function public.claim_musicbrainz_event_artwork(p_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claimed boolean := false;
begin
  if p_event_id is null then
    raise exception 'Concert ID is required' using errcode = '22023';
  end if;

  -- Community-provided art is always authoritative and must not be replaced
  -- by an import, even if this event acquired a MusicBrainz source later.
  if exists (
    select 1
    from public.catalog_events as event
    where event.id = p_event_id and event.cover_source = 'community'
  ) then
    return false;
  end if;

  if not exists (
    select 1
    from private.catalog_event_sources as source
    where source.event_id = p_event_id and source.provider_key = 'musicbrainz'
  ) then
    return false;
  end if;

  insert into private.catalog_event_artwork_imports (
    event_id, resolution_state, selected_priority, last_attempt_at, retry_after
  ) values (
    p_event_id, 'resolving', null, clock_timestamp(), clock_timestamp() + interval '10 minutes'
  ) on conflict (event_id) do update
  set resolution_state = 'resolving',
      last_attempt_at = excluded.last_attempt_at,
      retry_after = excluded.retry_after
  where private.catalog_event_artwork_imports.retry_after <= clock_timestamp()
  returning true into v_claimed;

  return coalesce(v_claimed, false);
end;
$$;

create function public.complete_musicbrainz_event_artwork(
  p_event_id uuid,
  p_cover jsonb,
  p_priority smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text;
  v_remote_url text;
  v_provider_name text;
  v_attribution text;
  v_source_page_url text;
  v_license_name text;
  v_license_url text;
  v_previous_priority smallint;
  v_updated_rows integer := 0;
  v_cover_written boolean := false;
begin
  if p_event_id is null then
    raise exception 'Concert ID is required' using errcode = '22023';
  end if;
  if (p_cover is null and p_priority is not null)
    or (p_cover is not null and (p_priority is null or p_priority not between 1 and 4))
  then
    raise exception 'Concert artwork resolution is invalid' using errcode = '22023';
  end if;
  if p_cover is not null and (
    jsonb_typeof(p_cover) <> 'object'
    or (p_cover - array[
      'source', 'remote_url', 'provider_name', 'attribution', 'source_page_url',
      'license_name', 'license_url'
    ]) <> '{}'::jsonb
  ) then
    raise exception 'Concert artwork payload is invalid' using errcode = '22023';
  end if;

  if p_cover is not null then
    v_source := p_cover ->> 'source';
    v_remote_url := p_cover ->> 'remote_url';
    v_provider_name := private.optional_catalog_text(
      nullif(p_cover ->> 'provider_name', ''), 120, 'Artwork provider'
    );
    v_attribution := private.optional_catalog_text(
      nullif(p_cover ->> 'attribution', ''), 500, 'Artwork attribution'
    );
    v_source_page_url := nullif(p_cover ->> 'source_page_url', '');
    v_license_name := private.optional_catalog_text(
      nullif(p_cover ->> 'license_name', ''), 120, 'Artwork license'
    );
    v_license_url := nullif(p_cover ->> 'license_url', '');
    if v_source is null or v_source not in ('provider', 'wikimedia')
      or v_remote_url is null or char_length(v_remote_url) > 2048
      or v_remote_url !~ '^https://'
      or (v_source_page_url is not null and (
        char_length(v_source_page_url) > 2048 or v_source_page_url !~ '^https://'
      ))
      or (v_license_url is not null and (
        char_length(v_license_url) > 2048 or v_license_url !~ '^https://'
      ))
      or (v_source = 'provider' and v_provider_name is null)
      or (v_source = 'wikimedia' and (
        v_attribution is null or v_source_page_url is null
        or v_license_name is null or v_license_url is null
      ))
    then
      raise exception 'Concert artwork payload is invalid' using errcode = '22023';
    end if;
  end if;

  select selected_priority into v_previous_priority
  from private.catalog_event_artwork_imports
  where event_id = p_event_id
  for update;
  if not found then
    raise exception 'Concert artwork was not claimed' using errcode = 'P0001';
  end if;

  if p_cover is not null then
    update public.catalog_events as event
    set cover_source = v_source,
        cover_object_path = null,
        cover_remote_url = v_remote_url,
        cover_provider_name = v_provider_name,
        cover_attribution = v_attribution,
        cover_source_page_url = v_source_page_url,
        cover_license_name = v_license_name,
        cover_license_url = v_license_url,
        cover_version = event.cover_version + 1,
        version = event.version + 1,
        updated_at = clock_timestamp()
    where event.id = p_event_id
      and event.cover_source is distinct from 'community'
      and (
        event.cover_source is null
        or v_previous_priority is null
        or p_priority < v_previous_priority
      );
    get diagnostics v_updated_rows = row_count;
    v_cover_written := v_updated_rows > 0;
  end if;

  update private.catalog_event_artwork_imports
  set resolution_state = case when p_cover is null then 'unavailable' else 'resolved' end,
      selected_priority = case
        when p_cover is null then v_previous_priority
        when v_cover_written then p_priority
        else v_previous_priority
      end,
      retry_after = clock_timestamp() + interval '30 days'
  where event_id = p_event_id;
end;
$$;

create function public.fail_musicbrainz_event_artwork(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.catalog_event_artwork_imports
  set resolution_state = 'retryable',
      selected_priority = null,
      retry_after = clock_timestamp() + interval '1 hour'
  where event_id = p_event_id;
end;
$$;

revoke all on table private.catalog_event_artwork_imports from public, anon, authenticated;
revoke all on function public.claim_musicbrainz_event_artwork(uuid) from public, anon, authenticated;
revoke all on function public.complete_musicbrainz_event_artwork(uuid, jsonb, smallint)
  from public, anon, authenticated;
revoke all on function public.fail_musicbrainz_event_artwork(uuid)
  from public, anon, authenticated;
grant execute on function public.claim_musicbrainz_event_artwork(uuid) to service_role;
grant execute on function public.complete_musicbrainz_event_artwork(uuid, jsonb, smallint)
  to service_role;
grant execute on function public.fail_musicbrainz_event_artwork(uuid) to service_role;
