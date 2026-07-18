-- Remove the retired shared-concert product. The remaining `concerts` rows are
-- implementation storage for event Posts until the post-vocabulary migration
-- renames that public contract. Existing Development/Staging concert and Post
-- data is intentionally discarded so no legacy object can leak into the new UI.

delete from public.concerts;

delete from public.catalog_entities
where origin in ('legacy_import', 'legacy_client');

-- Event Posts are owner-authored objects. Collaboration, transfer, setlists,
-- legacy timelines, and shared-log notifications no longer exist.
create or replace function private.is_concert_editor_as(
  p_user_id uuid,
  p_concert_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.concerts as concert
    where concert.id = p_concert_id
      and concert.owner_id = p_user_id
      and concert.record_model = 'personal_diary'
  )
$$;

create or replace function private.can_view_concert_as(
  p_user_id uuid,
  p_concert_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_read_personal_diary_as(p_user_id, p_concert_id)
$$;

create or replace function private.can_use_catalog_entity_as(
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
      )
  )
$$;

create or replace function private.can_read_catalog_entity_as(
  p_user_id uuid,
  p_entity_id uuid
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
          from public.catalog_events as event
          where private.can_read_catalog_event_as(p_user_id, event.id)
            and entity.id in (
              event.catalog_place_id,
              event.catalog_area_id,
              event.catalog_tour_id
            )
        )
        or exists (
          select 1
          from public.catalog_event_artists as artist
          where artist.catalog_artist_id = entity.id
            and private.can_read_catalog_event_as(p_user_id, artist.event_id)
        )
      )
  )
$$;

-- Relationship mutations used to remove shared-concert collaborators. With
-- that product deleted, the hook is deliberately inert until the callers are
-- simplified in the vocabulary migration.
create or replace function private.revoke_relationship_collaboration(
  p_actor_id uuid,
  p_other_id uuid,
  p_reason text
)
returns void
language sql
security definer
set search_path = ''
as $$
  select
$$;

-- Photo operations now authorize only against the owning/visible personal
-- Post. They no longer write a legacy concert timeline or collaboration alert.
create or replace function public.reserve_concert_photo(
  p_concert_id uuid,
  p_photo_id uuid default gen_random_uuid()
)
returns public.concert_photos
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.require_concert_editor(p_concert_id);
  v_photo public.concert_photos%rowtype;
  v_policy record;
begin
  select * into strict v_policy from private.concert_album_policy_limits();
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 1));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_concert_id::text, 0));

  if not exists (
    select 1 from public.concerts
    where id = p_concert_id
      and owner_id = v_actor
      and record_model = 'personal_diary'
      and deletion_status = 'active'
  ) then
    raise exception 'This Post is unavailable' using errcode = '55000';
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
    raise exception 'You have reached the photo upload limit for today' using errcode = '42900';
  end if;

  if (
    select count(*) from public.concert_photos
    where concert_id = p_concert_id
      and status in ('ready', 'pending')
      and (status = 'ready' or expires_at > clock_timestamp())
  ) >= v_policy.concert_photo_limit then
    raise exception 'This Post has reached its photo limit' using errcode = '54000';
  end if;

  insert into public.concert_photos (id, concert_id, uploader_id, object_path, expires_at)
  values (
    p_photo_id,
    p_concert_id,
    v_actor,
    'concerts/' || p_concert_id::text || '/album/' || p_photo_id::text || '.jpg',
    clock_timestamp() + pg_catalog.make_interval(
      secs => v_policy.pending_reservation_lifetime_seconds
    )
  )
  returning * into v_photo;
  return v_photo;
end;
$$;

create or replace function public.attach_concert_photo(p_photo_id uuid)
returns public.concert_photos
language plpgsql
security definer
set search_path = ''
as $$
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

  select * into v_object
  from storage.objects
  where bucket_id = 'images' and name = v_photo.object_path;
  if not found then
    raise exception 'Uploaded photo was not found' using errcode = 'P0001';
  end if;
  if coalesce(v_object.metadata ->> 'mimetype', '') <> 'image/jpeg' then
    raise exception 'Post photos must be JPEG images' using errcode = '22023';
  end if;
  begin
    v_size := (v_object.metadata ->> 'size')::bigint;
  exception when others then
    v_size := 0;
  end;
  if v_size <= 0 or v_size > v_policy.attached_file_byte_limit then
    raise exception 'Post photo size is invalid' using errcode = '22023';
  end if;

  update public.concert_photos
  set status = 'ready', attached_at = clock_timestamp()
  where id = p_photo_id
  returning * into v_photo;
  perform private.touch_concert_activity(v_photo.concert_id);
  return v_photo;
end;
$$;

create or replace function public.create_concert_comment(
  p_concert_id uuid,
  p_body text
)
returns public.comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_comment public.comments%rowtype;
  v_body text := private.require_concert_text(p_body, 1000, 'Comment');
begin
  if not private.can_read_personal_diary_as(v_actor_id, p_concert_id) then
    raise exception 'You no longer have access to this Post' using errcode = '42501';
  end if;
  perform private.assert_comment_rate_limit(v_actor_id);
  insert into public.comments (concert_id, author_id, body)
  values (p_concert_id, v_actor_id, v_body)
  returning * into v_comment;
  perform private.touch_concert_activity(p_concert_id);
  return v_comment;
end;
$$;

create or replace function public.update_concert_comment(
  p_comment_id uuid,
  p_body text
)
returns public.comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_comment public.comments%rowtype;
  v_body text := private.require_concert_text(p_body, 1000, 'Comment');
begin
  select * into v_comment
  from public.comments
  where id = p_comment_id
  for update;
  if not found or v_comment.author_id <> v_actor_id or v_comment.deleted_at is not null then
    raise exception 'Only the comment author can edit this comment' using errcode = '42501';
  end if;
  if not private.can_read_personal_diary_as(v_actor_id, v_comment.concert_id) then
    raise exception 'You no longer have access to this Post' using errcode = '42501';
  end if;
  update public.comments set body = v_body where id = p_comment_id returning * into v_comment;
  perform private.touch_concert_activity(v_comment.concert_id);
  return v_comment;
end;
$$;

create or replace function public.delete_concert_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_comment public.comments%rowtype;
begin
  select * into v_comment
  from public.comments
  where id = p_comment_id
  for update;
  if not found or v_comment.author_id <> v_actor_id or v_comment.deleted_at is not null then
    raise exception 'Only the comment author can delete this comment' using errcode = '42501';
  end if;
  if not private.can_read_personal_diary_as(v_actor_id, v_comment.concert_id) then
    raise exception 'You no longer have access to this Post' using errcode = '42501';
  end if;
  update public.comments
  set body = null, deleted_at = clock_timestamp()
  where id = p_comment_id;
  perform private.touch_concert_activity(v_comment.concert_id);
end;
$$;

-- Remove every authenticated legacy entry point before dropping its storage.
drop function if exists public.create_private_concert(
  jsonb, text, date, text, text, timestamptz, text, jsonb
);
drop function if exists public.create_private_concert_v2(
  jsonb, uuid, date, uuid, timestamptz, text, jsonb
);
drop function if exists public.update_concert(
  uuid, bigint, jsonb, text, date, text, text, timestamptz, text, jsonb,
  public.concert_visibility
);
drop function if exists public.update_concert_v2(
  uuid, bigint, jsonb, uuid, date, uuid, timestamptz, text, jsonb,
  public.concert_visibility
);
drop function if exists public.list_concert_collaborators(uuid);
drop function if exists public.tag_concert_collaborator(uuid, uuid, bigint);
drop function if exists public.remove_concert_collaborator(uuid, uuid, bigint);
drop function if exists public.transfer_concert_ownership(uuid, uuid, bigint);
drop function if exists public.friends_activity_feed(timestamptz, uuid, integer);
drop function if exists public.profile_concert_history(
  uuid, text, integer, public.concert_visibility, text, date, timestamptz,
  text, uuid, integer
);
drop function if exists public.set_concert_photo(uuid);
drop function if exists public.remove_concert_photo(uuid);
drop function if exists public.prepare_concert_deletion(uuid);
drop function if exists public.finalize_concert_deletion(uuid);
drop function if exists public.delete_concert(uuid);

drop trigger if exists reject_personal_diary_collaborator
  on public.concert_collaborators;

drop table if exists public.direct_collaboration_notifications;
drop table if exists public.concert_events;
drop table if exists public.concert_collaborators;
drop table if exists public.setlist_items;

drop function if exists private.reject_personal_diary_collaborator();
drop function if exists private.reject_concert_event_mutation();
drop function if exists private.can_view_concert_event_as(
  uuid, uuid, public.concert_event_type
);
drop function if exists private.notify_concert_editors(uuid, uuid, text);
drop function if exists private.enqueue_collaboration_notification(uuid, uuid, uuid, text);
drop function if exists private.record_concert_event(
  uuid, uuid, public.concert_event_type, uuid, jsonb
);
drop function if exists private.touch_concert_collaborator();
drop function if exists private.apply_setlist_catalog_snapshot();
drop function if exists private.validate_concert_payload(jsonb, jsonb);

drop type if exists public.concert_event_type;

-- The retired functions no longer exist, while Post media/comments remain the
-- only authenticated surface on the durable personal record.
revoke all on function private.revoke_relationship_collaboration(uuid, uuid, text)
from public, anon, authenticated;
