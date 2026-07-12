-- Keep the published album policy and every enforced limit on one private,
-- immutable server contract. Reservation locks cover both the contributor and
-- concert so concurrent requests cannot race either quota boundary.

create function private.concert_album_policy_limits()
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
language sql immutable set search_path = '' as $$
  select 1, 100, 30, 10, 10, 300, 2097152::bigint, 3600;
$$;

revoke all on function private.concert_album_policy_limits() from public;

create or replace function public.concert_album_policy()
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
language sql stable security definer set search_path = '' as $$
  select * from private.concert_album_policy_limits();
$$;

create or replace function public.reserve_concert_photo(
  p_concert_id uuid,
  p_photo_id uuid default gen_random_uuid()
)
returns public.concert_photos
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.require_concert_editor(p_concert_id);
  v_photo public.concert_photos%rowtype;
  v_policy record;
begin
  select * into strict v_policy from private.concert_album_policy_limits();
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text, 1));
  perform pg_advisory_xact_lock(hashtextextended(p_concert_id::text, 0));

  if not exists (
    select 1 from public.concerts
    where id = p_concert_id and deletion_status = 'active'
  ) then
    raise exception 'This concert is being deleted' using errcode = '55000';
  end if;

  select * into v_photo from public.concert_photos where id = p_photo_id;
  if found then
    if v_photo.concert_id <> p_concert_id or v_photo.uploader_id <> v_actor then
      raise exception 'That reservation belongs to another upload' using errcode = '42501';
    end if;
    return v_photo;
  end if;

  if (
    select count(*) from public.concert_photos
    where uploader_id = v_actor
      and created_at > clock_timestamp() - interval '24 hours'
  ) >= v_policy.reservation_limit_24_hours then
    raise exception 'You have reached the album upload limit for today' using errcode = '42900';
  end if;

  if (
    select count(*) from public.concert_photos
    where concert_id = p_concert_id
      and status in ('ready', 'pending')
      and (status = 'ready' or expires_at > clock_timestamp())
  ) >= v_policy.concert_photo_limit then
    raise exception 'This album has reached its photo limit' using errcode = '54000';
  end if;

  if (
    select count(*) from public.concert_photos
    where concert_id = p_concert_id
      and uploader_id = v_actor
      and status in ('ready', 'pending')
      and (status = 'ready' or expires_at > clock_timestamp())
  ) >= v_policy.contributor_photo_limit then
    raise exception 'You have reached your photo limit for this album' using errcode = '54000';
  end if;

  insert into public.concert_photos (id, concert_id, uploader_id, object_path, expires_at)
  values (
    p_photo_id,
    p_concert_id,
    v_actor,
    'concerts/' || p_concert_id::text || '/album/' || p_photo_id::text || '.jpg',
    clock_timestamp() + make_interval(secs => v_policy.pending_reservation_lifetime_seconds)
  )
  returning * into v_photo;
  return v_photo;
end;
$$;

create or replace function public.attach_concert_photo(p_photo_id uuid)
returns public.concert_photos
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.require_completed_caller();
  v_photo public.concert_photos%rowtype;
  v_object storage.objects%rowtype;
  v_policy record;
  v_size bigint;
begin
  select * into strict v_policy from private.concert_album_policy_limits();
  select * into v_photo from public.concert_photos where id = p_photo_id for update;
  if not found or v_photo.uploader_id <> v_actor then
    raise exception 'That reservation is not yours' using errcode = '42501';
  end if;
  if v_photo.status = 'ready' then return v_photo; end if;
  if v_photo.status <> 'pending' or v_photo.expires_at <= clock_timestamp() then
    raise exception 'That photo reservation expired' using errcode = '55000';
  end if;
  perform private.require_concert_editor(v_photo.concert_id);
  if not exists (
    select 1 from public.concerts
    where id = v_photo.concert_id and deletion_status = 'active'
  ) then
    raise exception 'This concert is being deleted' using errcode = '55000';
  end if;

  select * into v_object from storage.objects
  where bucket_id = 'images' and name = v_photo.object_path;
  if not found then
    raise exception 'Uploaded album photo was not found' using errcode = 'P0001';
  end if;
  if coalesce(v_object.metadata ->> 'mimetype', '') <> 'image/jpeg' then
    raise exception 'Album photos must be JPEG images' using errcode = '22023';
  end if;
  begin
    v_size := (v_object.metadata ->> 'size')::bigint;
  exception when others then
    v_size := 0;
  end;
  if v_size <= 0 or v_size > v_policy.attached_file_byte_limit then
    raise exception 'Album photo size is invalid' using errcode = '22023';
  end if;

  update public.concert_photos
  set status = 'ready', attached_at = clock_timestamp()
  where id = p_photo_id
  returning * into v_photo;
  perform private.touch_concert_activity(v_photo.concert_id);
  perform private.record_concert_event(
    v_photo.concert_id, v_actor, 'album_photo_added', v_photo.id
  );
  perform private.notify_concert_editors(
    v_photo.concert_id, v_actor, 'album_photo_added'
  );
  return v_photo;
end;
$$;

create or replace function private.reject_concert_event_mutation()
returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' and exists (
      select 1 from public.concerts
      where id = old.concert_id and deletion_status = 'deleting'
    ) then
    return old;
  end if;

  raise exception 'Concert events are immutable' using errcode = '55000';
end;
$$;

create or replace function public.finalize_concert_deletion(p_concert_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_concert_owner(p_concert_id);
  if not exists (
    select 1 from public.concerts
    where id = p_concert_id and deletion_status = 'deleting'
  ) then
    raise exception 'Concert deletion was not prepared' using errcode = '55000';
  end if;
  if exists (
    select 1 from storage.objects object
    where object.bucket_id = 'images'
      and object.name like 'concerts/' || p_concert_id::text || '/%'
  ) then
    raise exception 'Delete stored concert images before finalizing' using errcode = '55000';
  end if;

  -- Delete the immutable audit rows explicitly while the prepared parent is
  -- still visible; the trigger permits this only for a deleting concert.
  delete from public.concert_events where concert_id = p_concert_id;
  delete from public.concerts where id = p_concert_id;
end;
$$;

-- Storage's update endpoint evaluates SELECT as well as UPDATE. Expose only
-- the caller's own live reservation so a retry may replace a partial object;
-- other viewers still receive signed reads only after attachment is ready.
alter policy "images_select_ready_album_photo" on storage.objects
using (
  bucket_id = 'images' and (
    exists (
      select 1 from public.concert_photos photo
      where photo.object_path = name
        and photo.status = 'ready'
        and private.can_view_concert(photo.concert_id)
    )
    or private.can_upload_reserved_album_photo(auth.uid(), name)
    or private.can_delete_prepared_album_photo(auth.uid(), name)
  )
);
