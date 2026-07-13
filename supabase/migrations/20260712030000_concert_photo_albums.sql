-- Private concert photo albums. Postgres owns reservations, permissions, and
-- quotas; Storage only accepts the exact object path reserved here.

alter type public.concert_event_type add value if not exists 'album_photo_added';

alter table public.direct_collaboration_notifications
  drop constraint direct_collaboration_notifications_kind_check,
  add constraint direct_collaboration_notifications_kind_check check (
    kind in ('collaborator_tagged', 'concert_updated', 'comment_added',
      'ownership_transferred', 'album_photo_added')
  );

alter table public.concerts
  add column deletion_status text not null default 'active',
  add column deletion_requested_at timestamptz,
  add constraint concerts_deletion_status_check check (deletion_status in ('active', 'deleting')),
  add constraint concerts_deletion_timestamp_check check (
    (deletion_status = 'active' and deletion_requested_at is null)
    or (deletion_status = 'deleting' and deletion_requested_at is not null)
  );

create type public.concert_photo_status as enum ('pending', 'ready', 'deleting');

create table public.concert_photos (
  id uuid primary key default gen_random_uuid(),
  concert_id uuid not null references public.concerts (id) on delete cascade,
  uploader_id uuid not null references public.profiles (id) on delete restrict,
  object_path text not null unique,
  caption text,
  version bigint not null default 1,
  status public.concert_photo_status not null default 'pending',
  created_at timestamptz not null default now(),
  attached_at timestamptz,
  expires_at timestamptz not null default (now() + interval '1 hour'),
  deletion_requested_at timestamptz,
  deleted_at timestamptz,
  constraint concert_photos_fixed_path check (
    object_path = 'concerts/' || concert_id::text || '/album/' || id::text || '.jpg'
  ),
  constraint concert_photos_caption_check check (
    caption is null or (
      char_length(caption) between 1 and 300
      and not private.contains_control_characters(caption)
      and caption = private.normalize_concert_text(caption)
    )
  ),
  constraint concert_photos_lifecycle_check check (
    (status = 'pending' and attached_at is null and deletion_requested_at is null and deleted_at is null)
    or (status = 'ready' and attached_at is not null and deletion_requested_at is null and deleted_at is null)
    or (status = 'deleting' and attached_at is not null and deletion_requested_at is not null and deleted_at is null)
  )
);

create index concert_photos_album_cursor
  on public.concert_photos (concert_id, attached_at desc, id desc)
  where status = 'ready';
create index concert_photos_contributor_quota
  on public.concert_photos (concert_id, uploader_id, created_at desc);

create function public.concert_album_policy()
returns table (
  policy_version integer,
  concert_photo_limit integer,
  contributor_photo_limit integer,
  reservation_limit_24_hours integer,
  picker_batch_limit integer,
  caption_character_limit integer,
  attached_file_byte_limit bigint,
  pending_reservation_lifetime_seconds integer
)
language sql stable security definer set search_path = ''
as $$
  select 1, 100, 30, 10, 10, 300, 2097152::bigint, 3600;
$$;

create function public.reserve_concert_photo(p_concert_id uuid, p_photo_id uuid default gen_random_uuid())
returns public.concert_photos
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.require_concert_editor(p_concert_id);
  v_photo public.concert_photos%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_concert_id::text, 0));

  if not exists (select 1 from public.concerts where id = p_concert_id and deletion_status = 'active') then
    raise exception 'This concert is being deleted' using errcode = '55000';
  end if;

  select * into v_photo from public.concert_photos where id = p_photo_id;
  if found then
    if v_photo.concert_id <> p_concert_id or v_photo.uploader_id <> v_actor then
      raise exception 'That reservation belongs to another upload' using errcode = '42501';
    end if;
    return v_photo;
  end if;

  if (select count(*) from public.concert_photos
      where uploader_id = v_actor and created_at > clock_timestamp() - interval '24 hours') >= 10 then
    raise exception 'You have reached the album upload limit for today' using errcode = '42900';
  end if;
  if (select count(*) from public.concert_photos
      where concert_id = p_concert_id and status in ('ready', 'pending')
        and (status = 'ready' or expires_at > clock_timestamp())) >= 100 then
    raise exception 'This album already has 100 photos' using errcode = '54000';
  end if;
  if (select count(*) from public.concert_photos
      where concert_id = p_concert_id and uploader_id = v_actor and status in ('ready', 'pending')
        and (status = 'ready' or expires_at > clock_timestamp())) >= 30 then
    raise exception 'You already have 30 photos in this album' using errcode = '54000';
  end if;

  insert into public.concert_photos (id, concert_id, uploader_id, object_path)
  values (p_photo_id, p_concert_id, v_actor,
    'concerts/' || p_concert_id::text || '/album/' || p_photo_id::text || '.jpg')
  returning * into v_photo;
  return v_photo;
end;
$$;

create function public.attach_concert_photo(p_photo_id uuid)
returns public.concert_photos
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.require_completed_caller();
  v_photo public.concert_photos%rowtype;
  v_object storage.objects%rowtype;
  v_size bigint;
begin
  select * into v_photo from public.concert_photos where id = p_photo_id for update;
  if not found or v_photo.uploader_id <> v_actor then
    raise exception 'That reservation is not yours' using errcode = '42501';
  end if;
  if v_photo.status = 'ready' then return v_photo; end if;
  if v_photo.status <> 'pending' or v_photo.expires_at <= clock_timestamp() then
    raise exception 'That photo reservation expired' using errcode = '55000';
  end if;
  perform private.require_concert_editor(v_photo.concert_id);
  if not exists (select 1 from public.concerts where id = v_photo.concert_id and deletion_status = 'active') then
    raise exception 'This concert is being deleted' using errcode = '55000';
  end if;
  select * into v_object from storage.objects
    where bucket_id = 'images' and name = v_photo.object_path;
  if not found then raise exception 'Uploaded album photo was not found' using errcode = 'P0001'; end if;
  if coalesce(v_object.metadata ->> 'mimetype', '') <> 'image/jpeg' then
    raise exception 'Album photos must be JPEG images' using errcode = '22023';
  end if;
  begin v_size := (v_object.metadata ->> 'size')::bigint;
  exception when others then v_size := 0; end;
  if v_size <= 0 or v_size > 2097152 then
    raise exception 'Album photos must be no larger than 2 MB' using errcode = '22023';
  end if;

  update public.concert_photos set status = 'ready', attached_at = clock_timestamp()
    where id = p_photo_id returning * into v_photo;
  perform private.touch_concert_activity(v_photo.concert_id);
  perform private.record_concert_event(v_photo.concert_id, v_actor, 'album_photo_added', v_photo.id);
  perform private.notify_concert_editors(v_photo.concert_id, v_actor, 'album_photo_added');
  return v_photo;
end;
$$;

create function public.list_concert_photos(
  p_concert_id uuid, p_cursor_attached_at timestamptz default null,
  p_cursor_id uuid default null, p_limit integer default 30
)
returns table (id uuid, concert_id uuid, uploader_id uuid, username text, display_name text,
  object_path text, caption text, version bigint, attached_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := private.require_completed_caller();
begin
  if not private.can_view_concert_as(v_actor, p_concert_id) then
    raise exception 'You cannot view this concert' using errcode = '42501';
  end if;
  return query
    select photo.id, photo.concert_id, photo.uploader_id, profile.username, profile.display_name,
      photo.object_path, photo.caption, photo.version, photo.attached_at
    from public.concert_photos photo join public.profiles profile on profile.id = photo.uploader_id
    where photo.concert_id = p_concert_id and photo.status = 'ready'
      and (p_cursor_attached_at is null or photo.attached_at < p_cursor_attached_at
        or (photo.attached_at = p_cursor_attached_at and photo.id < p_cursor_id))
    order by photo.attached_at desc, photo.id desc
    limit greatest(1, least(coalesce(p_limit, 30), 30));
end;
$$;

create function public.update_concert_photo_caption(p_photo_id uuid, p_caption text)
returns public.concert_photos
language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.require_completed_caller(); v_photo public.concert_photos%rowtype;
  v_caption text := private.optional_concert_text(p_caption, 300, 'Caption');
begin
  select * into v_photo from public.concert_photos where id = p_photo_id for update;
  if not found or v_photo.status <> 'ready' or v_photo.uploader_id <> v_actor then
    raise exception 'Only the uploader can edit this caption' using errcode = '42501';
  end if;
  perform private.require_concert_editor(v_photo.concert_id);
  update public.concert_photos set caption = v_caption, version = version + 1
    where id = p_photo_id returning * into v_photo;
  return v_photo;
end;
$$;

create function public.prepare_concert_photo_deletion(p_photo_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.require_completed_caller(); v_photo public.concert_photos%rowtype;
begin
  select * into v_photo from public.concert_photos where id = p_photo_id for update;
  if not found or v_photo.status not in ('ready', 'deleting') then
    raise exception 'That photo is no longer available' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.concerts where id = v_photo.concert_id and owner_id = v_actor)
    and not (v_photo.uploader_id = v_actor and private.is_concert_editor_as(v_actor, v_photo.concert_id)) then
    raise exception 'You cannot delete this photo' using errcode = '42501';
  end if;
  update public.concert_photos set status = 'deleting', deletion_requested_at = coalesce(deletion_requested_at, clock_timestamp())
    where id = p_photo_id;
  return v_photo.object_path;
end;
$$;

create function public.finalize_concert_photo_deletion(p_photo_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.require_completed_caller(); v_photo public.concert_photos%rowtype;
begin
  select * into v_photo from public.concert_photos where id = p_photo_id for update;
  if not found or v_photo.status <> 'deleting' then raise exception 'Photo deletion was not prepared' using errcode = '55000'; end if;
  if not exists (select 1 from public.concerts where id = v_photo.concert_id and owner_id = v_actor)
    and not (v_photo.uploader_id = v_actor and private.is_concert_editor_as(v_actor, v_photo.concert_id)) then
    raise exception 'You cannot delete this photo' using errcode = '42501'; end if;
  if exists (select 1 from storage.objects where bucket_id = 'images' and name = v_photo.object_path) then
    raise exception 'Delete the stored photo before finalizing' using errcode = '55000'; end if;
  delete from public.concert_photos where id = p_photo_id;
end;
$$;

create function public.prepare_concert_deletion(p_concert_id uuid)
returns table (object_path text)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_concert_owner(p_concert_id);
  update public.concerts set deletion_status = 'deleting',
    deletion_requested_at = coalesce(deletion_requested_at, clock_timestamp())
    where id = p_concert_id;
  update public.concert_photos set status = 'deleting',
    deletion_requested_at = coalesce(deletion_requested_at, clock_timestamp())
    where concert_id = p_concert_id and status = 'ready';
  return query
    select concert.photo_object_path from public.concerts concert
      where concert.id = p_concert_id and concert.photo_object_path is not null
    union all
    select photo.object_path from public.concert_photos photo
      where photo.concert_id = p_concert_id and photo.status = 'deleting';
end;
$$;

create function public.finalize_concert_deletion(p_concert_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_concert_owner(p_concert_id);
  if not exists (select 1 from public.concerts where id = p_concert_id and deletion_status = 'deleting') then
    raise exception 'Concert deletion was not prepared' using errcode = '55000';
  end if;
  if exists (select 1 from storage.objects object where object.bucket_id = 'images'
    and object.name like 'concerts/' || p_concert_id::text || '/%') then
    raise exception 'Delete stored concert images before finalizing' using errcode = '55000';
  end if;
  delete from public.concerts where id = p_concert_id;
end;
$$;

create function private.can_upload_reserved_album_photo(p_user_id uuid, p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.concert_photos photo
    where photo.object_path = p_path and photo.uploader_id = p_user_id
      and photo.status = 'pending' and photo.expires_at > clock_timestamp()
      and private.is_concert_editor_as(p_user_id, photo.concert_id));
$$;

create function private.can_delete_prepared_album_photo(p_user_id uuid, p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.concert_photos photo
    join public.concerts concert on concert.id = photo.concert_id
    where photo.object_path = p_path and photo.status = 'deleting'
      and (concert.owner_id = p_user_id or (photo.uploader_id = p_user_id
        and private.is_concert_editor_as(p_user_id, photo.concert_id))));
$$;

revoke all on function private.can_upload_reserved_album_photo(uuid, text),
  private.can_delete_prepared_album_photo(uuid, text) from public;
grant execute on function private.can_upload_reserved_album_photo(uuid, text),
  private.can_delete_prepared_album_photo(uuid, text) to authenticated;

-- Album Storage authorization is tied to a live reservation and its immutable path.
create policy "images_insert_reserved_album_photo" on storage.objects for insert to authenticated
with check (bucket_id = 'images' and private.can_upload_reserved_album_photo(auth.uid(), name));
create policy "images_update_reserved_album_photo" on storage.objects for update to authenticated
using (bucket_id = 'images' and private.can_upload_reserved_album_photo(auth.uid(), name))
with check (bucket_id = 'images' and private.can_upload_reserved_album_photo(auth.uid(), name));
create policy "images_select_ready_album_photo" on storage.objects for select to authenticated
using (bucket_id = 'images' and (
  exists (select 1 from public.concert_photos photo
    where photo.object_path = name and photo.status = 'ready' and private.can_view_concert(photo.concert_id))
  or private.can_delete_prepared_album_photo(auth.uid(), name)
));
create policy "images_delete_moderated_album_photo" on storage.objects for delete to authenticated
using (bucket_id = 'images' and private.can_delete_prepared_album_photo(auth.uid(), name));

alter table public.concert_photos enable row level security;
create policy "concert_photos_select_visible" on public.concert_photos for select to authenticated
using (status = 'ready' and private.can_view_concert(concert_id));
revoke all on table public.concert_photos from anon, authenticated;
grant select on table public.concert_photos to authenticated;

revoke all on function public.concert_album_policy(), public.reserve_concert_photo(uuid, uuid),
  public.attach_concert_photo(uuid), public.list_concert_photos(uuid, timestamptz, uuid, integer),
  public.update_concert_photo_caption(uuid, text), public.prepare_concert_photo_deletion(uuid),
  public.finalize_concert_photo_deletion(uuid), public.prepare_concert_deletion(uuid),
  public.finalize_concert_deletion(uuid) from public, anon;
grant execute on function public.concert_album_policy(), public.reserve_concert_photo(uuid, uuid),
  public.attach_concert_photo(uuid), public.list_concert_photos(uuid, timestamptz, uuid, integer),
  public.update_concert_photo_caption(uuid, text), public.prepare_concert_photo_deletion(uuid),
  public.finalize_concert_photo_deletion(uuid), public.prepare_concert_deletion(uuid),
  public.finalize_concert_deletion(uuid) to authenticated;

alter table public.concert_photos replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.concert_photos;
exception when duplicate_object then null; end $$;
