-- Replace the transitional diary/shared-concert storage model with the product's
-- permanent vocabulary and authorization boundary:
--   catalog events -> event comments and personal posts
--   personal posts -> media and comments
-- This is intentionally destructive. The prior event-content rows were local/
-- staging fixtures and cannot be represented as supported product state.

drop policy if exists "images_delete_editable_concert_photo" on storage.objects;
drop policy if exists "images_delete_moderated_album_photo" on storage.objects;
drop policy if exists "images_insert_editable_concert_photo" on storage.objects;
drop policy if exists "images_insert_reserved_album_photo" on storage.objects;
drop policy if exists "images_select_ready_album_photo" on storage.objects;
drop policy if exists "images_select_visible_concert_photo" on storage.objects;
drop policy if exists "images_update_editable_concert_photo" on storage.objects;
drop policy if exists "images_update_reserved_album_photo" on storage.objects;

do $drop_obsolete_functions$
declare
  target record;
begin
  for target in
    select function.oid::regprocedure as signature
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as namespace on namespace.oid = function.pronamespace
    where function.prokind = 'f'
      and namespace.nspname in ('public', 'private')
      and (
        pg_catalog.pg_get_functiondef(function.oid) ~
          '(public[.]concerts|public[.]concert_artists|public[.]concert_photos|public[.]comments|public[.]diary_reviews|public[.]catalog_event_posts|personal_diary|catalog_event_diary|event_posted|event_replied|diary_published|diary_media_added)'
        or function.proname in (
          'assert_catalog_event_diary_rate_limit',
          'assert_catalog_event_post_rate_limit',
          'assert_comment_rate_limit',
          'can_delete_prepared_album_photo',
          'can_read_catalog_event_post_as',
          'can_read_personal_diary_as',
          'can_upload_reserved_album_photo',
          'enforce_personal_diary_integrity',
          'enqueue_catalog_event_diary_notifications',
          'protect_personal_diary_attendance',
          'record_personal_diary_media_activity',
          'touch_comment',
          'touch_concert',
          'touch_concert_activity',
          'touch_concert_child',
          'touch_diary_review'
        )
      )
  loop
    execute pg_catalog.format('drop function if exists %s cascade', target.signature);
  end loop;
end
$drop_obsolete_functions$;

drop table if exists public.diary_reviews cascade;
drop table if exists public.comments cascade;
drop table if exists public.concert_photos cascade;
drop table if exists public.concert_artists cascade;
drop table if exists public.concerts cascade;
drop table if exists public.catalog_event_posts cascade;
drop table if exists private.catalog_event_diary_mutations cascade;
drop table if exists private.catalog_event_integrity_operations cascade;

drop type if exists public.concert_record_model cascade;
drop type if exists public.concert_visibility cascade;
drop type if exists public.concert_photo_status cascade;

alter type public.social_activity_action rename value 'diary_published' to 'post_published';
alter type public.social_activity_action rename value 'diary_media_added' to 'post_media_added';
alter type public.social_activity_action rename value 'event_posted' to 'event_commented';
alter type public.social_activity_action rename value 'event_replied' to 'event_comment_replied';

alter table private.catalog_event_notification_outbox
  drop constraint catalog_event_notification_action_check,
  add constraint catalog_event_notification_action_check check (
    action in (
      'event_invited',
      'invitation_accepted',
      'event_comment_replied',
      'post_published',
      'post_media_added',
      'event_cancelled',
      'event_schedule_changed'
    )
  );

create function private.enqueue_catalog_event_notification(
  p_recipient_id uuid,
  p_actor_id uuid,
  p_event_id uuid,
  p_action text,
  p_subject_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_action not in (
    'event_invited',
    'invitation_accepted',
    'event_comment_replied',
    'post_published',
    'post_media_added',
    'event_cancelled',
    'event_schedule_changed'
  ) then
    raise exception 'Notification action is invalid' using errcode = '22023';
  end if;
  if p_recipient_id = p_actor_id
    or private.has_relationship_block(p_recipient_id, p_actor_id)
  then
    return;
  end if;
  insert into private.catalog_event_notification_outbox (
    recipient_id, actor_id, event_id, action, subject_id
  ) values (
    p_recipient_id, p_actor_id, p_event_id, p_action, p_subject_id
  );
end;
$$;

create type public.post_media_status as enum ('pending', 'ready', 'deleting');

create table public.event_comments (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.catalog_events (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  parent_comment_id uuid references public.event_comments (id) on delete restrict,
  body text not null,
  audience public.catalog_event_audience not null default 'friends',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint event_comments_body_check check (
    char_length(body) between 1 and 500
    and body = btrim(body)
    and body !~ '[[:cntrl:]]'
  ),
  constraint event_comments_audience_check check (audience in ('friends', 'community'))
);

create table public.event_posts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.catalog_events (id) on delete set null,
  author_id uuid not null references public.profiles (id) on delete cascade,
  attendance_id uuid references public.catalog_event_attendance (id) on delete set null,
  event_snapshot jsonb not null,
  audience public.catalog_event_audience not null default 'friends',
  overall_score_points smallint,
  performance_score_points smallint,
  note text,
  published_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint event_posts_overall_score_check check (
    overall_score_points is null
    or (overall_score_points between 5 and 100 and mod(overall_score_points, 5) = 0)
  ),
  constraint event_posts_performance_score_check check (
    performance_score_points is null
    or (performance_score_points between 5 and 100 and mod(performance_score_points, 5) = 0)
  ),
  constraint event_posts_note_check check (
    note is null
    or (
      char_length(note) between 1 and 4000
      and note = btrim(note)
      and note !~ '[[:cntrl:]]'
    )
  ),
  constraint event_posts_snapshot_check check (
    jsonb_typeof(event_snapshot) = 'object'
    and event_snapshot ? 'event_id'
  )
);

create unique index event_posts_one_active_post_per_event
  on public.event_posts (author_id, event_id)
  where event_id is not null and deleted_at is null;
create index event_posts_event_published
  on public.event_posts (event_id, published_at desc, id)
  where deleted_at is null and published_at is not null;
create index event_posts_author_history
  on public.event_posts (author_id, published_at desc, id)
  where deleted_at is null and published_at is not null;

create table public.post_media (
  id uuid primary key,
  post_id uuid not null references public.event_posts (id) on delete cascade,
  uploader_id uuid not null references public.profiles (id) on delete cascade,
  object_path text not null unique,
  caption text,
  version bigint not null default 1,
  status public.post_media_status not null default 'pending',
  created_at timestamptz not null default clock_timestamp(),
  attached_at timestamptz,
  expires_at timestamptz not null,
  deletion_requested_at timestamptz,
  deleted_at timestamptz,
  constraint post_media_object_path_check check (
    object_path = 'posts/' || post_id::text || '/media/' || id::text || '.jpg'
  ),
  constraint post_media_caption_check check (
    caption is null
    or (
      char_length(caption) between 1 and 500
      and caption = btrim(caption)
      and caption !~ '[[:cntrl:]]'
    )
  ),
  constraint post_media_lifecycle_check check (
    (status = 'pending' and attached_at is null and deleted_at is null)
    or (status = 'ready' and attached_at is not null and deleted_at is null)
    or (status = 'deleting' and deletion_requested_at is not null)
  )
);

create index post_media_post_cursor
  on public.post_media (post_id, attached_at desc, id desc)
  where status = 'ready';
create index post_media_uploader_rate_limit
  on public.post_media (uploader_id, created_at desc);

create table public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.event_posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint post_comments_body_check check (
    char_length(body) between 1 and 1000
    and body = btrim(body)
    and body !~ '[[:cntrl:]]'
  )
);

create index post_comments_post_cursor
  on public.post_comments (post_id, created_at desc, id desc);

-- A hard source-event removal discards event-level coordination but preserves
-- personal Posts, their media, comments, and immutable event snapshots.
alter table public.catalog_event_attendance
  drop constraint catalog_event_attendance_event_id_fkey,
  add constraint catalog_event_attendance_event_id_fkey
    foreign key (event_id) references public.catalog_events (id) on delete cascade;
alter table public.catalog_event_invitations
  drop constraint catalog_event_invitations_event_id_fkey,
  add constraint catalog_event_invitations_event_id_fkey
    foreign key (event_id) references public.catalog_events (id) on delete cascade;
alter table private.catalog_event_notification_outbox
  drop constraint catalog_event_notification_outbox_event_id_fkey,
  add constraint catalog_event_notification_outbox_event_id_fkey
    foreign key (event_id) references public.catalog_events (id) on delete cascade;
alter table private.catalog_event_reports
  drop constraint catalog_event_reports_event_id_fkey,
  add constraint catalog_event_reports_event_id_fkey
    foreign key (event_id) references public.catalog_events (id) on delete cascade;
alter table private.catalog_event_revisions
  drop constraint catalog_event_revisions_event_id_fkey,
  add constraint catalog_event_revisions_event_id_fkey
    foreign key (event_id) references public.catalog_events (id) on delete cascade;
alter table public.social_activity_events
  drop constraint social_activity_events_event_id_fkey,
  add constraint social_activity_events_event_id_fkey
    foreign key (event_id) references public.catalog_events (id) on delete cascade;
alter table public.catalog_events
  drop constraint catalog_events_merged_into_event_id_fkey,
  add constraint catalog_events_merged_into_event_id_fkey
    foreign key (merged_into_event_id) references public.catalog_events (id) on delete set null;

create table private.product_write_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  action text not null,
  occurred_at timestamptz not null default clock_timestamp()
);
create index product_write_events_rate_limit
  on private.product_write_events (actor_id, action, occurred_at desc);

create function private.normalize_user_text(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(btrim(coalesce(p_value, '')), '[[:space:]]+', ' ', 'g'), '')
$$;

create function private.require_user_text(
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
  value text := private.normalize_user_text(p_value);
begin
  if value is null
    or char_length(value) > p_maximum_length
    or value ~ '[[:cntrl:]]'
  then
    raise exception '% is invalid', p_field_name using errcode = '22023';
  end if;
  return value;
end;
$$;

create function private.optional_user_text(
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
  value text := private.normalize_user_text(p_value);
begin
  if value is null then
    return null;
  end if;
  if char_length(value) > p_maximum_length or value ~ '[[:cntrl:]]' then
    raise exception '% is invalid', p_field_name using errcode = '22023';
  end if;
  return value;
end;
$$;

create function private.touch_product_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger touch_event_comment
before update on public.event_comments
for each row execute function private.touch_product_row();
create trigger touch_event_post
before update on public.event_posts
for each row execute function private.touch_product_row();
create trigger touch_post_comment
before update on public.post_comments
for each row execute function private.touch_product_row();

create function private.preserve_event_posts_before_event_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.event_posts as post
  set event_id = null,
      attendance_id = null
  where post.event_id = old.id and post.deleted_at is null;
  return old;
end;
$$;

create trigger preserve_event_posts_before_event_delete
before delete on public.catalog_events
for each row execute function private.preserve_event_posts_before_event_delete();

-- Activity rows remain immutable to callers. The only permitted deletion is
-- PostgreSQL's foreign-key cascade after its source event has been removed.
create or replace function private.prevent_social_activity_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    and not exists (
      select 1
      from public.catalog_events as event
      where event.id = old.event_id
    )
  then
    return old;
  end if;

  raise exception 'Social activity events are immutable'
    using errcode = '42501';
end;
$$;

create function private.assert_product_write_limit(
  p_actor_id uuid,
  p_action text,
  p_limit integer,
  p_window interval
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_actor_id::text || ':' || p_action, 0)
  );
  if (
    select count(*)
    from private.product_write_events as event
    where event.actor_id = p_actor_id
      and event.action = p_action
      and event.occurred_at > clock_timestamp() - p_window
  ) >= p_limit then
    raise exception 'Please wait before trying that again' using errcode = '42900';
  end if;
  insert into private.product_write_events (actor_id, action)
  values (p_actor_id, p_action);
end;
$$;

create function private.can_read_event_post_as(p_viewer_id uuid, p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.event_posts as post
    where post.id = p_post_id
      and post.deleted_at is null
      and not private.has_relationship_block(p_viewer_id, post.author_id)
      and (
        post.author_id = p_viewer_id
        or (
          post.published_at is not null
          and (
            post.audience = 'community'
            or (
              post.audience = 'friends'
              and private.are_accepted_friends(p_viewer_id, post.author_id)
            )
          )
        )
      )
  )
$$;

create function private.can_read_event_comment_as(p_viewer_id uuid, p_comment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.event_comments as comment
    where comment.id = p_comment_id
      and private.can_read_catalog_event_as(p_viewer_id, comment.event_id)
      and not private.has_relationship_block(p_viewer_id, comment.author_id)
      and (
        comment.author_id = p_viewer_id
        or comment.audience = 'community'
        or private.are_accepted_friends(p_viewer_id, comment.author_id)
      )
  )
$$;

create function private.can_read_event_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_read_event_post_as(auth.uid(), p_post_id)
$$;

create function private.can_read_event_comment(p_comment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_read_event_comment_as(auth.uid(), p_comment_id)
$$;

create function private.event_post_preview_json(p_viewer_id uuid, p_post_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'post_id', post.id,
    'author_id', author.id,
    'author_username', author.username,
    'author_display_name', author.display_name,
    'author_relationship', private.relationship_label(p_viewer_id, author.id),
    'author_avatar_object_path', author.avatar_object_path,
    'author_avatar_version', author.avatar_version,
    'overall_score', post.overall_score_points::numeric / 10,
    'performance_score', post.performance_score_points::numeric / 10,
    'note', post.note,
    'photo_count', (
      select count(*)
      from public.post_media as media
      where media.post_id = post.id and media.status = 'ready'
    ),
    'video_count', 0,
    'comment_count', (
      select count(*)
      from public.post_comments as comment
      where comment.post_id = post.id and comment.deleted_at is null
    ),
    'audience', post.audience,
    'published_at', post.published_at
  )
  from public.event_posts as post
  join public.profiles as author on author.id = post.author_id
  where post.id = p_post_id
    and post.published_at is not null
    and private.can_read_event_post_as(p_viewer_id, post.id)
$$;

create function private.enqueue_event_post_notifications(
  p_actor_id uuid,
  p_event_id uuid,
  p_post_id uuid,
  p_audience public.catalog_event_audience,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient_id uuid;
begin
  if p_audience = 'private' then
    return;
  end if;
  for recipient_id in
    select case
      when relationship.user_low_id = p_actor_id then relationship.user_high_id
      else relationship.user_low_id
    end
    from public.relationships as relationship
    where relationship.status = 'accepted'
      and p_actor_id in (relationship.user_low_id, relationship.user_high_id)
  loop
    perform private.enqueue_catalog_event_notification(
      recipient_id,
      p_actor_id,
      p_event_id,
      p_action,
      p_post_id
    );
  end loop;
end;
$$;

create function private.can_upload_reserved_post_media(p_user_id uuid, p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.post_media as media
    join public.event_posts as post on post.id = media.post_id
    where media.object_path = p_path
      and media.uploader_id = p_user_id
      and post.author_id = p_user_id
      and post.deleted_at is null
      and media.status = 'pending'
      and media.expires_at > clock_timestamp()
  )
$$;

create function private.can_write_my_post_media_object(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_upload_reserved_post_media(auth.uid(), p_path)
$$;

create function private.can_read_my_post_media_object(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.post_media as media
    where media.object_path = p_path
      and (
        (media.status = 'ready' and private.can_read_event_post_as(auth.uid(), media.post_id))
        or private.can_upload_reserved_post_media(auth.uid(), p_path)
      )
  )
$$;

create function private.protect_event_post_attendance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'went'
    and (
      tg_op = 'DELETE'
      or new.status is distinct from 'went'::public.catalog_event_attendance_status
    )
    and exists (
      select 1
      from public.event_posts as post
      where post.attendance_id = old.id and post.deleted_at is null
    )
  then
    raise exception 'A concert with a post must remain in Went' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger protect_event_post_attendance
before update or delete on public.catalog_event_attendance
for each row execute function private.protect_event_post_attendance();

alter table public.event_comments enable row level security;
alter table public.event_posts enable row level security;
alter table public.post_media enable row level security;
alter table public.post_comments enable row level security;

create policy "event_comments_select_visible"
on public.event_comments for select to authenticated
using (private.can_read_event_comment(id));

create policy "event_posts_select_visible"
on public.event_posts for select to authenticated
using (private.can_read_event_post(id));

create policy "post_media_select_visible"
on public.post_media for select to authenticated
using (
  (status = 'ready' and private.can_read_event_post(post_id))
  or private.can_write_my_post_media_object(object_path)
);

create policy "post_comments_select_visible"
on public.post_comments for select to authenticated
using (private.can_read_event_post(post_id));

create policy "images_insert_reserved_post_media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'images'
  and private.can_write_my_post_media_object(name)
);

create policy "images_update_reserved_post_media"
on storage.objects for update to authenticated
using (
  bucket_id = 'images'
  and private.can_write_my_post_media_object(name)
)
with check (
  bucket_id = 'images'
  and private.can_write_my_post_media_object(name)
);

create policy "images_select_visible_post_media"
on storage.objects for select to authenticated
using (
  bucket_id = 'images'
  and private.can_read_my_post_media_object(name)
);

create function public.list_event_comments(
  p_event_id uuid,
  p_scope text default 'all',
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  parent_comment_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_relationship text,
  author_avatar_object_path text,
  author_avatar_version bigint,
  body text,
  audience public.catalog_event_audience,
  created_at timestamptz,
  is_deleted boolean,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_completed_caller();
  canonical_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  cursor_created_at timestamptz;
  cursor_id uuid;
begin
  if canonical_event_id is null
    or not private.can_read_catalog_event_as(caller_id, canonical_event_id)
  then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;
  if p_scope not in ('all', 'friends', 'community') then
    raise exception 'Comment scope is invalid' using errcode = '22023';
  end if;
  if p_limit not between 1 and 50 then
    raise exception 'Comment limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'created_at' - 'comment_id') <> '{}'::jsonb
      or not (p_cursor ?& array['created_at', 'comment_id'])
    then
      raise exception 'Comment cursor is invalid' using errcode = '22023';
    end if;
    begin
      cursor_created_at := (p_cursor ->> 'created_at')::timestamptz;
      cursor_id := (p_cursor ->> 'comment_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format then
      raise exception 'Comment cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  select
    comment.id,
    comment.parent_comment_id,
    author.id,
    author.username,
    author.display_name,
    private.relationship_label(caller_id, author.id),
    author.avatar_object_path,
    author.avatar_version,
    case when comment.deleted_at is null then comment.body else 'Comment deleted'::text end,
    comment.audience,
    comment.created_at,
    comment.deleted_at is not null,
    jsonb_build_object('created_at', comment.created_at, 'comment_id', comment.id)
  from public.event_comments as comment
  join public.profiles as author on author.id = comment.author_id
  where comment.event_id = canonical_event_id
    and private.can_read_event_comment_as(caller_id, comment.id)
    and (
      p_scope = 'all'
      or (p_scope = 'friends' and private.are_accepted_friends(caller_id, comment.author_id))
      or (
        p_scope = 'community'
        and comment.audience = 'community'
        and not private.are_accepted_friends(caller_id, comment.author_id)
        and comment.author_id <> caller_id
      )
    )
    and (
      p_cursor is null
      or comment.created_at < cursor_created_at
      or (comment.created_at = cursor_created_at and comment.id > cursor_id)
    )
  order by comment.created_at desc, comment.id
  limit p_limit;
end;
$$;

create function public.create_event_comment(
  p_event_id uuid,
  p_parent_comment_id uuid default null,
  p_body text default null,
  p_audience public.catalog_event_audience default 'friends'
)
returns table (comment_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_completed_caller();
  canonical_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  event_record public.catalog_events%rowtype;
  parent_record public.event_comments%rowtype;
  normalized_body text := private.require_user_text(p_body, 500, 'Comment');
  new_comment_id uuid;
begin
  if p_audience = 'private' then
    raise exception 'Event comments must be shared with friends or community'
      using errcode = '22023';
  end if;
  if canonical_event_id is null
    or not private.can_read_catalog_event_as(caller_id, canonical_event_id)
  then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;

  select source.* into event_record
  from public.catalog_events as source
  where source.id = canonical_event_id
  for update;
  if event_record.lifecycle in ('cancelled', 'completed')
    or event_record.memory_unlock_at <= clock_timestamp()
  then
    raise exception 'Event comments close after the concert' using errcode = '22023';
  end if;

  if p_parent_comment_id is not null then
    select comment.* into parent_record
    from public.event_comments as comment
    where comment.id = p_parent_comment_id
    for update;
    if parent_record.id is null
      or parent_record.event_id <> canonical_event_id
      or parent_record.parent_comment_id is not null
      or parent_record.deleted_at is not null
      or not private.can_read_event_comment_as(caller_id, parent_record.id)
    then
      raise exception 'That comment is unavailable for replies' using errcode = '42501';
    end if;
  end if;

  perform private.assert_product_write_limit(caller_id, 'event_comment', 30, interval '10 minutes');
  insert into public.event_comments (event_id, author_id, parent_comment_id, body, audience)
  values (canonical_event_id, caller_id, p_parent_comment_id, normalized_body, p_audience)
  returning id into new_comment_id;

  insert into public.social_activity_events (actor_id, action, event_id, subject_id)
  values (
    caller_id,
    case when p_parent_comment_id is null
      then 'event_commented'::public.social_activity_action
      else 'event_comment_replied'::public.social_activity_action
    end,
    canonical_event_id,
    new_comment_id
  );

  if p_parent_comment_id is not null and parent_record.author_id <> caller_id then
    perform private.enqueue_catalog_event_notification(
      parent_record.author_id,
      caller_id,
      canonical_event_id,
      'event_comment_replied',
      new_comment_id
    );
  end if;

  update public.catalog_events as event
  set last_material_activity_at = clock_timestamp()
  where event.id = canonical_event_id;
  return query select new_comment_id;
end;
$$;

create function public.list_event_posts(
  p_event_id uuid,
  p_scope text default 'all',
  p_cursor jsonb default null,
  p_limit integer default 30
)
returns table (
  post_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_relationship text,
  author_avatar_object_path text,
  author_avatar_version bigint,
  overall_score numeric,
  performance_score numeric,
  note text,
  photo_count bigint,
  video_count bigint,
  comment_count bigint,
  audience public.catalog_event_audience,
  published_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_completed_caller();
  canonical_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  cursor_published_at timestamptz;
  cursor_id uuid;
begin
  if p_scope not in ('all', 'friends', 'community', 'mine') then
    raise exception 'Post scope is invalid' using errcode = '22023';
  end if;
  if p_limit not between 1 and 50 then
    raise exception 'Post limit must be between 1 and 50' using errcode = '22023';
  end if;
  if canonical_event_id is null
    or not private.can_read_catalog_event_as(caller_id, canonical_event_id)
  then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'published_at' - 'post_id') <> '{}'::jsonb
      or not (p_cursor ?& array['published_at', 'post_id'])
    then
      raise exception 'Post cursor is invalid' using errcode = '22023';
    end if;
    begin
      cursor_published_at := (p_cursor ->> 'published_at')::timestamptz;
      cursor_id := (p_cursor ->> 'post_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format then
      raise exception 'Post cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  select
    post.id,
    author.id,
    author.username,
    author.display_name,
    private.relationship_label(caller_id, author.id),
    author.avatar_object_path,
    author.avatar_version,
    post.overall_score_points::numeric / 10,
    post.performance_score_points::numeric / 10,
    post.note,
    (select count(*) from public.post_media as media
      where media.post_id = post.id and media.status = 'ready'),
    0::bigint,
    (select count(*) from public.post_comments as comment
      where comment.post_id = post.id and comment.deleted_at is null),
    post.audience,
    post.published_at,
    jsonb_build_object('published_at', post.published_at, 'post_id', post.id)
  from public.event_posts as post
  join public.profiles as author on author.id = post.author_id
  where post.event_id = canonical_event_id
    and post.deleted_at is null
    and post.published_at is not null
    and private.can_read_event_post_as(caller_id, post.id)
    and (
      p_scope = 'all'
      or (p_scope = 'mine' and post.author_id = caller_id)
      or (p_scope = 'community' and post.audience = 'community')
      or (
        p_scope = 'friends'
        and (
          post.author_id = caller_id
          or private.are_accepted_friends(caller_id, post.author_id)
        )
      )
    )
    and (
      p_cursor is null
      or post.published_at < cursor_published_at
      or (post.published_at = cursor_published_at and post.id > cursor_id)
    )
  order by post.published_at desc, post.id
  limit p_limit;
end;
$$;

create function public.upsert_event_post(
  p_event_id uuid,
  p_overall_score numeric default null,
  p_performance_score numeric default null,
  p_note text default null,
  p_audience public.catalog_event_audience default 'friends',
  p_publish boolean default true
)
returns table (post_id uuid, event_id uuid, published_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.require_completed_caller();
  canonical_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  event_record public.catalog_events%rowtype;
  attendance_record public.catalog_event_attendance%rowtype;
  post_record public.event_posts%rowtype;
  normalized_note text := private.optional_user_text(p_note, 4000, 'Post note');
  overall_points smallint;
  performance_points smallint;
  was_published boolean := false;
  will_be_published boolean;
begin
  if canonical_event_id is null
    or not private.can_read_catalog_event_as(actor_id, canonical_event_id)
  then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;

  select event.* into event_record
  from public.catalog_events as event
  where event.id = canonical_event_id
  for update;

  select attendance.* into attendance_record
  from public.catalog_event_attendance as attendance
  where attendance.event_id = canonical_event_id
    and attendance.profile_id = actor_id
    and attendance.superseded_by_attendance_id is null
  for update;

  if attendance_record.id is null or attendance_record.status <> 'went' then
    raise exception 'Mark that you went before creating a post' using errcode = '22023';
  end if;
  if (
      event_record.lifecycle = 'cancelled'
      and attendance_record.cancelled_performance_confirmed_at is null
    )
    or (
      event_record.lifecycle not in ('cancelled', 'completed')
      and event_record.memory_unlock_at > clock_timestamp()
    )
  then
    raise exception 'Posts unlock after the concert' using errcode = '22023';
  end if;

  if p_overall_score is not null then
    if p_overall_score < 0.5
      or p_overall_score > 10
      or trunc(p_overall_score * 10) <> p_overall_score * 10
      or mod((p_overall_score * 10)::integer, 5) <> 0
    then
      raise exception 'Overall score must be between 0.5 and 10 in half-point steps'
        using errcode = '22023';
    end if;
    overall_points := (p_overall_score * 10)::smallint;
  end if;
  if p_performance_score is not null then
    if p_performance_score < 0.5
      or p_performance_score > 10
      or trunc(p_performance_score * 10) <> p_performance_score * 10
      or mod((p_performance_score * 10)::integer, 5) <> 0
    then
      raise exception 'Performance score must be between 0.5 and 10 in half-point steps'
        using errcode = '22023';
    end if;
    performance_points := (p_performance_score * 10)::smallint;
  end if;

  perform private.assert_product_write_limit(actor_id, 'post_upsert', 60, interval '1 hour');
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'event-post:' || actor_id::text || ':' || canonical_event_id::text,
      0
    )
  );

  select post.* into post_record
  from public.event_posts as post
  where post.author_id = actor_id
    and post.event_id = canonical_event_id
    and post.deleted_at is null
  for update;

  if post_record.id is null then
    insert into public.event_posts (
      event_id,
      author_id,
      attendance_id,
      event_snapshot,
      audience,
      overall_score_points,
      performance_score_points,
      note
    ) values (
      canonical_event_id,
      actor_id,
      attendance_record.id,
      private.catalog_event_history_projection_json(canonical_event_id),
      p_audience,
      overall_points,
      performance_points,
      normalized_note
    )
    returning * into post_record;
  else
    was_published := post_record.published_at is not null;
    update public.event_posts as post
    set attendance_id = attendance_record.id,
        event_snapshot = private.catalog_event_history_projection_json(canonical_event_id),
        audience = p_audience,
        overall_score_points = overall_points,
        performance_score_points = performance_points,
        note = normalized_note
    where post.id = post_record.id
    returning post.* into post_record;
  end if;

  will_be_published := p_publish or was_published;
  if will_be_published
    and overall_points is null
    and performance_points is null
    and normalized_note is null
    and not exists (
      select 1 from public.post_media as media
      where media.post_id = post_record.id and media.status = 'ready'
    )
  then
    raise exception 'A published post needs a score, note, or photo' using errcode = '22023';
  end if;

  update public.event_posts as post
  set published_at = case
    when will_be_published then coalesce(post.published_at, clock_timestamp())
    else null
  end
  where post.id = post_record.id
  returning post.* into post_record;

  update public.catalog_events as event
  set last_material_activity_at = clock_timestamp()
  where event.id = canonical_event_id;

  if p_publish and not was_published then
    insert into public.social_activity_events (actor_id, action, event_id, subject_id)
    values (actor_id, 'post_published', canonical_event_id, post_record.id);
    perform private.enqueue_event_post_notifications(
      actor_id,
      canonical_event_id,
      post_record.id,
      p_audience,
      'post_published'
    );
  end if;

  return query select post_record.id, canonical_event_id, post_record.published_at;
end;
$$;

create function public.get_event_post_summaries(p_event_ids uuid[])
returns table (event_id uuid, post_count bigint, average_score numeric)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_completed_caller();
begin
  if p_event_ids is null
    or cardinality(p_event_ids) not between 1 and 100
    or array_position(p_event_ids, null) is not null
    or cardinality(p_event_ids) <> cardinality(array(
      select distinct requested_id from unnest(p_event_ids) as requested(requested_id)
    ))
  then
    raise exception 'Post summaries require between 1 and 100 distinct event IDs'
      using errcode = '22023';
  end if;

  return query
  select
    requested.requested_id,
    count(post.id),
    round(avg(post.overall_score_points::numeric / 10), 1)
  from unnest(p_event_ids) as requested(requested_id)
  left join public.event_posts as post
    on post.event_id = requested.requested_id
    and post.deleted_at is null
    and post.published_at is not null
    and private.can_read_event_post_as(caller_id, post.id)
  where private.can_read_catalog_event_as(caller_id, requested.requested_id)
  group by requested.requested_id;
end;
$$;

create function public.list_catalog_profile_event_history(
  p_profile_id uuid,
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns table (
  history_kind text,
  event jsonb,
  post jsonb,
  occurred_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_completed_caller();
  cursor_occurred_at timestamptz;
  cursor_kind text;
  cursor_subject_id uuid;
begin
  if p_limit not between 1 and 50 then
    raise exception 'Profile history limit must be between 1 and 50' using errcode = '22023';
  end if;
  if not private.has_completed_profile(p_profile_id) then
    return;
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'occurred_at' - 'history_kind' - 'subject_id') <> '{}'::jsonb
      or not (p_cursor ?& array['occurred_at', 'history_kind', 'subject_id'])
    then
      raise exception 'Profile history cursor is invalid' using errcode = '22023';
    end if;
    begin
      cursor_occurred_at := (p_cursor ->> 'occurred_at')::timestamptz;
      cursor_kind := p_cursor ->> 'history_kind';
      cursor_subject_id := (p_cursor ->> 'subject_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format then
      raise exception 'Profile history cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  with history as (
    select
      'went'::text as history_kind,
      private.catalog_event_history_projection_json(attendance.event_id) as event_snapshot,
      null::uuid as post_id,
      attendance.updated_at as history_occurred_at,
      attendance.id as subject_id
    from public.catalog_event_attendance as attendance
    where attendance.profile_id = p_profile_id
      and attendance.status = 'went'
      and attendance.superseded_by_attendance_id is null
      and private.can_read_catalog_event_history_attendance_as(
        caller_id,
        attendance.event_id,
        attendance.profile_id,
        attendance.audience
      )
    union all
    select
      'post'::text,
      coalesce(
        case when post_record.event_id is not null
          and private.can_read_catalog_event_as(caller_id, post_record.event_id)
          then private.catalog_event_history_projection_json(post_record.event_id)
        end,
        post_record.event_snapshot
      ),
      post_record.id,
      post_record.published_at,
      post_record.id
    from public.event_posts as post_record
    where post_record.author_id = p_profile_id
      and post_record.deleted_at is null
      and post_record.published_at is not null
      and private.can_read_event_post_as(caller_id, post_record.id)
  )
  select
    history.history_kind,
    history.event_snapshot,
    case when history.post_id is null
      then null
      else private.event_post_preview_json(caller_id, history.post_id)
    end,
    history.history_occurred_at,
    jsonb_build_object(
      'occurred_at', history.history_occurred_at,
      'history_kind', history.history_kind,
      'subject_id', history.subject_id
    )
  from history
  where history.event_snapshot is not null
    and (
      p_cursor is null
      or history.history_occurred_at < cursor_occurred_at
      or (
        history.history_occurred_at = cursor_occurred_at
        and (history.history_kind, history.subject_id) > (cursor_kind, cursor_subject_id)
      )
    )
  order by history.history_occurred_at desc, history.history_kind, history.subject_id
  limit p_limit;
end;
$$;

create function public.list_catalog_event_activity(
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns table (
  activity_id uuid,
  action public.social_activity_action,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  actor_relationship text,
  actor_avatar_object_path text,
  actor_avatar_version bigint,
  subject_id uuid,
  post jsonb,
  event jsonb,
  occurred_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_completed_caller();
  cursor_occurred_at timestamptz;
  cursor_id uuid;
begin
  if p_limit not between 1 and 50 then
    raise exception 'Activity limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'occurred_at' - 'activity_id') <> '{}'::jsonb
      or not (p_cursor ?& array['occurred_at', 'activity_id'])
    then
      raise exception 'Activity cursor is invalid' using errcode = '22023';
    end if;
    begin
      cursor_occurred_at := (p_cursor ->> 'occurred_at')::timestamptz;
      cursor_id := (p_cursor ->> 'activity_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format then
      raise exception 'Activity cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  select
    activity.id,
    activity.action,
    actor.id,
    actor.username,
    actor.display_name,
    private.relationship_label(caller_id, actor.id),
    actor.avatar_object_path,
    actor.avatar_version,
    activity.subject_id,
    case when activity.action in ('post_published', 'post_media_added')
      then private.event_post_preview_json(caller_id, activity.subject_id)
      else null::jsonb
    end,
    private.catalog_event_projection_json(canonical.event_id),
    activity.occurred_at,
    jsonb_build_object('occurred_at', activity.occurred_at, 'activity_id', activity.id)
  from public.social_activity_events as activity
  join public.profiles as actor on actor.id = activity.actor_id
  cross join lateral (
    select private.resolve_catalog_event_id(activity.event_id) as event_id
  ) as canonical
  left join lateral (
    select attendance.*
    from public.catalog_event_attendance as attendance
    where attendance.event_id = canonical.event_id
      and attendance.profile_id = activity.actor_id
      and attendance.superseded_by_attendance_id is null
    limit 1
  ) as attendance on true
  left join public.event_comments as event_comment on event_comment.id = activity.subject_id
  left join public.event_posts as event_post on event_post.id = activity.subject_id
  where activity.actor_id <> caller_id
    and private.are_accepted_friends(caller_id, activity.actor_id)
    and canonical.event_id is not null
    and private.can_read_catalog_event_as(caller_id, canonical.event_id)
    and not private.has_relationship_block(caller_id, activity.actor_id)
    and (
      activity.event_id = canonical.event_id
      or activity.action not in ('event_created', 'event_updated')
    )
    and (
      activity.action in ('event_created', 'event_updated')
      or (
        activity.action in ('marked_going', 'marked_went', 'invitation_accepted')
        and attendance.status in ('going', 'went')
        and private.can_read_catalog_event_attendance_as(
          caller_id,
          canonical.event_id,
          activity.actor_id,
          attendance.audience
        )
      )
      or (
        activity.action in ('event_commented', 'event_comment_replied')
        and event_comment.id is not null
        and private.can_read_event_comment_as(caller_id, event_comment.id)
      )
      or (
        activity.action in ('post_published', 'post_media_added')
        and event_post.published_at is not null
        and private.can_read_event_post_as(caller_id, event_post.id)
      )
    )
    and (
      p_cursor is null
      or activity.occurred_at < cursor_occurred_at
      or (activity.occurred_at = cursor_occurred_at and activity.id > cursor_id)
    )
  order by activity.occurred_at desc, activity.id
  limit p_limit;
end;
$$;

create function public.reserve_post_media(
  p_post_id uuid,
  p_media_id uuid default gen_random_uuid()
)
returns public.post_media
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.require_completed_caller();
  media_record public.post_media%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor_id::text, 1));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_post_id::text, 0));
  if not exists (
    select 1 from public.event_posts as post
    where post.id = p_post_id
      and post.author_id = actor_id
      and post.deleted_at is null
  ) then
    raise exception 'This post is unavailable' using errcode = '42501';
  end if;

  select media.* into media_record
  from public.post_media as media
  where media.id = p_media_id;
  if found then
    if media_record.post_id <> p_post_id or media_record.uploader_id <> actor_id then
      raise exception 'That reservation belongs to another upload' using errcode = '42501';
    end if;
    return media_record;
  end if;

  perform private.assert_product_write_limit(actor_id, 'post_media_reserve', 80, interval '24 hours');
  if (
    select count(*) from public.post_media as media
    where media.post_id = p_post_id
      and media.status in ('ready', 'pending')
      and (media.status = 'ready' or media.expires_at > clock_timestamp())
  ) >= 250 then
    raise exception 'This post has reached its photo limit' using errcode = '54000';
  end if;

  insert into public.post_media (id, post_id, uploader_id, object_path, expires_at)
  values (
    p_media_id,
    p_post_id,
    actor_id,
    'posts/' || p_post_id::text || '/media/' || p_media_id::text || '.jpg',
    clock_timestamp() + interval '15 minutes'
  )
  returning * into media_record;
  return media_record;
end;
$$;

create function public.attach_post_media(p_media_id uuid)
returns public.post_media
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.require_completed_caller();
  media_record public.post_media%rowtype;
  post_record public.event_posts%rowtype;
  object_record storage.objects%rowtype;
  object_size bigint;
begin
  select media.* into media_record
  from public.post_media as media
  where media.id = p_media_id
  for update;
  if not found or media_record.uploader_id <> actor_id then
    raise exception 'That reservation is not yours' using errcode = '42501';
  end if;
  if media_record.status = 'ready' then
    return media_record;
  end if;
  if media_record.status <> 'pending' or media_record.expires_at <= clock_timestamp() then
    raise exception 'That media reservation expired' using errcode = '55000';
  end if;

  select post.* into post_record
  from public.event_posts as post
  where post.id = media_record.post_id
  for update;
  if not found or post_record.author_id <> actor_id or post_record.deleted_at is not null then
    raise exception 'This post is unavailable' using errcode = '42501';
  end if;

  select object.* into object_record
  from storage.objects as object
  where object.bucket_id = 'images' and object.name = media_record.object_path;
  if not found then
    raise exception 'Uploaded photo was not found' using errcode = 'P0001';
  end if;
  if coalesce(object_record.metadata ->> 'mimetype', '') <> 'image/jpeg' then
    raise exception 'Post photos must be JPEG images' using errcode = '22023';
  end if;
  begin
    object_size := (object_record.metadata ->> 'size')::bigint;
  exception when others then
    object_size := 0;
  end;
  if object_size <= 0 or object_size > 2097152 then
    raise exception 'Post photo size is invalid' using errcode = '22023';
  end if;

  update public.post_media as media
  set status = 'ready', attached_at = clock_timestamp()
  where media.id = p_media_id
  returning media.* into media_record;
  update public.event_posts as post set updated_at = clock_timestamp()
  where post.id = media_record.post_id;

  if post_record.published_at is not null and post_record.event_id is not null then
    insert into public.social_activity_events (actor_id, action, event_id, subject_id, metadata)
    values (
      actor_id,
      'post_media_added',
      post_record.event_id,
      post_record.id,
      jsonb_build_object('media_id', media_record.id)
    );
  end if;
  return media_record;
end;
$$;

create function public.list_post_media(
  p_post_id uuid,
  p_cursor_attached_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  post_id uuid,
  uploader_id uuid,
  username text,
  display_name text,
  object_path text,
  caption text,
  version bigint,
  attached_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.require_completed_caller();
begin
  if not private.can_read_event_post_as(actor_id, p_post_id) then
    raise exception 'This post is unavailable' using errcode = '42501';
  end if;
  if p_limit not between 1 and 30 then
    raise exception 'Post media limit must be between 1 and 30' using errcode = '22023';
  end if;
  return query
  select
    media.id,
    media.post_id,
    media.uploader_id,
    profile.username,
    profile.display_name,
    media.object_path,
    media.caption,
    media.version,
    media.attached_at
  from public.post_media as media
  join public.profiles as profile on profile.id = media.uploader_id
  where media.post_id = p_post_id
    and media.status = 'ready'
    and (
      p_cursor_attached_at is null
      or media.attached_at < p_cursor_attached_at
      or (media.attached_at = p_cursor_attached_at and media.id < p_cursor_id)
    )
  order by media.attached_at desc, media.id desc
  limit p_limit;
end;
$$;

create function public.list_post_comments(
  p_post_id uuid,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  post_id uuid,
  author_id uuid,
  username text,
  display_name text,
  body text,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_completed_caller();
begin
  if not private.can_read_event_post_as(caller_id, p_post_id) then
    raise exception 'This post is unavailable' using errcode = '42501';
  end if;
  if p_limit not between 1 and 30 then
    raise exception 'Post comment limit must be between 1 and 30' using errcode = '22023';
  end if;
  return query
  select
    comment.id,
    comment.post_id,
    comment.author_id,
    profile.username,
    profile.display_name,
    case when comment.deleted_at is null then comment.body else null end,
    comment.created_at,
    comment.updated_at,
    comment.deleted_at
  from public.post_comments as comment
  join public.profiles as profile on profile.id = comment.author_id
  where comment.post_id = p_post_id
    and (
      p_cursor_created_at is null
      or comment.created_at < p_cursor_created_at
      or (comment.created_at = p_cursor_created_at and comment.id < p_cursor_id)
    )
  order by comment.created_at desc, comment.id desc
  limit p_limit;
end;
$$;

create function public.create_post_comment(p_post_id uuid, p_body text)
returns table (
  id uuid,
  post_id uuid,
  author_id uuid,
  username text,
  display_name text,
  body text,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := private.require_completed_caller();
  post_record public.event_posts%rowtype;
  comment_record public.post_comments%rowtype;
  normalized_body text := private.require_user_text(p_body, 1000, 'Comment');
begin
  select post.* into post_record
  from public.event_posts as post
  where post.id = p_post_id
  for update;
  if not found
    or post_record.published_at is null
    or not private.can_read_event_post_as(actor_id, p_post_id)
  then
    raise exception 'This post is unavailable' using errcode = '42501';
  end if;

  perform private.assert_product_write_limit(actor_id, 'post_comment', 30, interval '10 minutes');
  insert into public.post_comments (post_id, author_id, body)
  values (p_post_id, actor_id, normalized_body)
  returning * into comment_record;

  return query
  select
    comment_record.id,
    comment_record.post_id,
    comment_record.author_id,
    profile.username,
    profile.display_name,
    comment_record.body,
    comment_record.created_at,
    comment_record.updated_at,
    comment_record.deleted_at
  from public.profiles as profile
  where profile.id = actor_id;
end;
$$;

revoke all on table public.event_comments from public, anon, authenticated;
revoke all on table public.event_posts from public, anon, authenticated;
revoke all on table public.post_media from public, anon, authenticated;
revoke all on table public.post_comments from public, anon, authenticated;
grant select on table public.event_comments to authenticated;
grant select on table public.event_posts to authenticated;
grant select on table public.post_media to authenticated;
grant select on table public.post_comments to authenticated;

revoke all on function public.list_event_comments(uuid, text, jsonb, integer)
  from public, anon, authenticated;
revoke all on function public.create_event_comment(uuid, uuid, text, public.catalog_event_audience)
  from public, anon, authenticated;
revoke all on function public.list_event_posts(uuid, text, jsonb, integer)
  from public, anon, authenticated;
revoke all on function public.upsert_event_post(
  uuid, numeric, numeric, text, public.catalog_event_audience, boolean
) from public, anon, authenticated;
revoke all on function public.get_event_post_summaries(uuid[])
  from public, anon, authenticated;
revoke all on function public.list_catalog_profile_event_history(uuid, jsonb, integer)
  from public, anon, authenticated;
revoke all on function public.list_catalog_event_activity(jsonb, integer)
  from public, anon, authenticated;
revoke all on function public.reserve_post_media(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.attach_post_media(uuid)
  from public, anon, authenticated;
revoke all on function public.list_post_media(uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;
revoke all on function public.list_post_comments(uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;
revoke all on function public.create_post_comment(uuid, text)
  from public, anon, authenticated;

grant execute on function public.list_event_comments(uuid, text, jsonb, integer) to authenticated;
grant execute on function public.create_event_comment(
  uuid, uuid, text, public.catalog_event_audience
) to authenticated;
grant execute on function public.list_event_posts(uuid, text, jsonb, integer) to authenticated;
grant execute on function public.upsert_event_post(
  uuid, numeric, numeric, text, public.catalog_event_audience, boolean
) to authenticated;
grant execute on function public.get_event_post_summaries(uuid[]) to authenticated;
grant execute on function public.list_catalog_profile_event_history(uuid, jsonb, integer)
  to authenticated;
grant execute on function public.list_catalog_event_activity(jsonb, integer) to authenticated;
grant execute on function public.reserve_post_media(uuid, uuid) to authenticated;
grant execute on function public.attach_post_media(uuid) to authenticated;
grant execute on function public.list_post_media(uuid, timestamptz, uuid, integer)
  to authenticated;
grant execute on function public.list_post_comments(uuid, timestamptz, uuid, integer)
  to authenticated;
grant execute on function public.create_post_comment(uuid, text) to authenticated;

revoke all on function private.normalize_user_text(text) from public, anon, authenticated;
revoke all on function private.require_user_text(text, integer, text) from public, anon, authenticated;
revoke all on function private.optional_user_text(text, integer, text) from public, anon, authenticated;
revoke all on function private.touch_product_row() from public, anon, authenticated;
revoke all on function private.preserve_event_posts_before_event_delete()
  from public, anon, authenticated;
revoke all on function private.prevent_social_activity_mutation()
  from public, anon, authenticated;
revoke all on function private.assert_product_write_limit(uuid, text, integer, interval)
  from public, anon, authenticated;
revoke all on function private.can_read_event_post_as(uuid, uuid) from public, anon, authenticated;
revoke all on function private.can_read_event_comment_as(uuid, uuid) from public, anon, authenticated;
revoke all on function private.can_read_event_post(uuid) from public, anon, authenticated;
revoke all on function private.can_read_event_comment(uuid) from public, anon, authenticated;
revoke all on function private.event_post_preview_json(uuid, uuid) from public, anon, authenticated;
revoke all on function private.enqueue_catalog_event_notification(uuid, uuid, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function private.enqueue_event_post_notifications(
  uuid, uuid, uuid, public.catalog_event_audience, text
) from public, anon, authenticated;
revoke all on function private.can_upload_reserved_post_media(uuid, text)
  from public, anon, authenticated;
revoke all on function private.can_write_my_post_media_object(text)
  from public, anon, authenticated;
revoke all on function private.can_read_my_post_media_object(text)
  from public, anon, authenticated;
revoke all on function private.protect_event_post_attendance() from public, anon, authenticated;

grant execute on function private.can_read_event_post(uuid) to authenticated;
grant execute on function private.can_read_event_comment(uuid) to authenticated;
grant execute on function private.can_write_my_post_media_object(text) to authenticated;
grant execute on function private.can_read_my_post_media_object(text) to authenticated;

alter table public.event_comments replica identity full;
alter table public.event_posts replica identity full;
alter table public.post_media replica identity full;
alter table public.post_comments replica identity full;

do $publication$
begin
  alter publication supabase_realtime add table public.event_comments;
  alter publication supabase_realtime add table public.event_posts;
  alter publication supabase_realtime add table public.post_media;
  alter publication supabase_realtime add table public.post_comments;
exception when duplicate_object then
  null;
end
$publication$;
