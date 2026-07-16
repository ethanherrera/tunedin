-- Durable, provider-neutral concert covers.
--
-- A cover describes one dated concert occurrence. It deliberately does not
-- live on catalog_artists: a tour/date may have its own artwork, and imported
-- media must retain its provider/license provenance independently of artist
-- identity. Community clients write only the fixed private Storage path via
-- the bounded RPC below. Future importers may populate the remote/provenance
-- columns from a trusted server-side ingestion path.

alter table public.catalog_events
  add column cover_source text,
  add column cover_object_path text,
  add column cover_remote_url text,
  add column cover_provider_name text,
  add column cover_attribution text,
  add column cover_source_page_url text,
  add column cover_license_name text,
  add column cover_license_url text,
  add column cover_version bigint not null default 0,
  add constraint catalog_events_cover_version_check check (cover_version >= 0),
  add constraint catalog_events_cover_object_path_fixed check (
    cover_object_path is null
    or cover_object_path = 'event-covers/' || id::text || '/cover.jpg'
  ),
  add constraint catalog_events_cover_urls_check check (
    (cover_remote_url is null or (char_length(cover_remote_url) <= 2048 and cover_remote_url ~ '^https://'))
    and (cover_source_page_url is null or (char_length(cover_source_page_url) <= 2048 and cover_source_page_url ~ '^https://'))
    and (cover_license_url is null or (char_length(cover_license_url) <= 2048 and cover_license_url ~ '^https://'))
  ),
  add constraint catalog_events_cover_text_check check (
    (cover_provider_name is null or (
      char_length(cover_provider_name) between 1 and 120
      and not private.contains_control_characters(cover_provider_name)
    ))
    and (cover_attribution is null or (
      char_length(cover_attribution) between 1 and 500
      and not private.contains_control_characters(cover_attribution)
    ))
    and (cover_license_name is null or (
      char_length(cover_license_name) between 1 and 120
      and not private.contains_control_characters(cover_license_name)
    ))
  ),
  add constraint catalog_events_cover_shape_check check (
    (
      cover_source is null
      and cover_object_path is null
      and cover_remote_url is null
      and cover_provider_name is null
      and cover_attribution is null
      and cover_source_page_url is null
      and cover_license_name is null
      and cover_license_url is null
    )
    or (
      cover_source = 'community'
      and cover_object_path is not null
      and cover_remote_url is null
      and cover_provider_name is null
      and cover_source_page_url is null
      and cover_license_name is null
      and cover_license_url is null
    )
    or (
      cover_source = 'provider'
      and cover_object_path is null
      and cover_remote_url is not null
      and cover_provider_name is not null
    )
    or (
      cover_source = 'wikimedia'
      and cover_object_path is null
      and cover_remote_url is not null
      and cover_attribution is not null
      and cover_source_page_url is not null
      and cover_license_name is not null
      and cover_license_url is not null
    )
  );

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
  event.updated_at
from public.catalog_events as event
left join public.catalog_event_artists as lineup on lineup.event_id = event.id
group by event.id;

create function private.can_manage_catalog_event_cover(p_user_id uuid, p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_user_id is null
      or p_path !~ '^event-covers/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/cover[.]jpg$'
      then false
    else exists (
      select 1
      from public.catalog_events as event
      where event.id = split_part(p_path, '/', 2)::uuid
        and event.created_by = p_user_id
        and event.row_state = 'active'
    )
  end;
$$;

create function private.can_read_catalog_event_cover(p_user_id uuid, p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_user_id is null
      or p_path !~ '^event-covers/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/cover[.]jpg$'
      then false
    else private.can_read_catalog_event_as(p_user_id, split_part(p_path, '/', 2)::uuid)
  end;
$$;

create policy "images_insert_owned_catalog_event_cover"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'images'
  and private.can_manage_catalog_event_cover(auth.uid(), name)
);

create policy "images_update_owned_catalog_event_cover"
on storage.objects for update to authenticated
using (
  bucket_id = 'images'
  and private.can_manage_catalog_event_cover(auth.uid(), name)
)
with check (
  bucket_id = 'images'
  and private.can_manage_catalog_event_cover(auth.uid(), name)
);

create policy "images_delete_owned_catalog_event_cover"
on storage.objects for delete to authenticated
using (
  bucket_id = 'images'
  and private.can_manage_catalog_event_cover(auth.uid(), name)
);

create policy "images_select_visible_catalog_event_cover"
on storage.objects for select to authenticated
using (
  bucket_id = 'images'
  and private.can_read_catalog_event_cover(auth.uid(), name)
);

create function public.set_catalog_event_cover(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.require_completed_caller();
  v_path text := 'event-covers/' || p_event_id::text || '/cover.jpg';
  v_event public.catalog_events%rowtype;
  v_object storage.objects%rowtype;
begin
  select * into v_event
  from public.catalog_events as event
  where event.id = p_event_id
  for update;

  if not found or v_event.row_state <> 'active' then
    raise exception 'Concert is unavailable' using errcode = 'P0002';
  end if;
  if v_event.created_by <> v_actor then
    raise exception 'Only the concert creator can change its cover' using errcode = '42501';
  end if;

  select * into v_object
  from storage.objects as object
  where object.bucket_id = 'images' and object.name = v_path;
  if not found then
    raise exception 'Uploaded concert cover was not found' using errcode = 'P0001';
  end if;
  if coalesce(v_object.metadata ->> 'mimetype', '') <> 'image/jpeg' then
    raise exception 'Concert covers must be JPEG images' using errcode = '22023';
  end if;
  if coalesce((v_object.metadata ->> 'size')::bigint, 0) <= 0
    or (v_object.metadata ->> 'size')::bigint > 3145728 then
    raise exception 'Concert covers must be no larger than 3 MB' using errcode = '22023';
  end if;

  update public.catalog_events
  set cover_source = 'community',
      cover_object_path = v_path,
      cover_remote_url = null,
      cover_provider_name = null,
      cover_attribution = null,
      cover_source_page_url = null,
      cover_license_name = null,
      cover_license_url = null,
      cover_version = cover_version + 1,
      version = version + 1,
      updated_at = clock_timestamp()
  where id = p_event_id;
end;
$$;

create function public.remove_catalog_event_cover(p_event_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.require_completed_caller();
  v_event public.catalog_events%rowtype;
  v_path text;
begin
  select * into v_event
  from public.catalog_events as event
  where event.id = p_event_id
  for update;
  if not found or v_event.row_state <> 'active' then
    raise exception 'Concert is unavailable' using errcode = 'P0002';
  end if;
  if v_event.created_by <> v_actor then
    raise exception 'Only the concert creator can change its cover' using errcode = '42501';
  end if;

  v_path := v_event.cover_object_path;
  update public.catalog_events
  set cover_source = null,
      cover_object_path = null,
      cover_remote_url = null,
      cover_provider_name = null,
      cover_attribution = null,
      cover_source_page_url = null,
      cover_license_name = null,
      cover_license_url = null,
      cover_version = cover_version + 1,
      version = version + 1,
      updated_at = clock_timestamp()
  where id = p_event_id;
  return v_path;
end;
$$;

revoke all on function
  private.can_manage_catalog_event_cover(uuid, text),
  private.can_read_catalog_event_cover(uuid, text),
  public.set_catalog_event_cover(uuid),
  public.remove_catalog_event_cover(uuid)
from public, anon;

grant execute on function
  private.can_manage_catalog_event_cover(uuid, text),
  private.can_read_catalog_event_cover(uuid, text),
  public.set_catalog_event_cover(uuid),
  public.remove_catalog_event_cover(uuid)
to authenticated;
