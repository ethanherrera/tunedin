-- Phase 4: event-linked personal diaries.
--
-- The shared catalog event remains the occurrence source of truth. A diary is
-- an owner-only `concerts` record so existing photos and comments remain on the
-- durable personal object, while attendance and diary audience stay independent.

create type public.concert_record_model as enum ('legacy_shared', 'personal_diary');

alter table public.catalog_event_attendance
  add column id uuid not null default gen_random_uuid(),
  add constraint catalog_event_attendance_id_unique unique (id);

alter table public.concerts
  add column catalog_event_id uuid references public.catalog_events (id) on delete set null,
  add column attendance_id uuid references public.catalog_event_attendance (id) on delete restrict,
  add column record_model public.concert_record_model not null default 'legacy_shared',
  add column diary_audience public.catalog_event_audience,
  add column published_at timestamptz,
  add column detached_event_reason text,
  add constraint concerts_record_model_shape_check check (
    (
      record_model = 'legacy_shared'
      and catalog_event_id is null
      and attendance_id is null
      and diary_audience is null
      and published_at is null
      and detached_event_reason is null
    )
    or (
      record_model = 'personal_diary'
      and attendance_id is not null
      and diary_audience is not null
      and visibility = 'private'
      and (
        (catalog_event_id is not null and detached_event_reason is null)
        or (catalog_event_id is null and detached_event_reason is not null)
      )
    )
  ),
  add constraint concerts_detached_event_reason_check check (
    detached_event_reason is null
    or private.is_normalized_concert_text(detached_event_reason, 120)
  );

create unique index concerts_one_personal_diary_per_event
  on public.concerts (owner_id, catalog_event_id)
  where record_model = 'personal_diary'
    and catalog_event_id is not null
    and deletion_status = 'active';
create index concerts_personal_diary_event_visibility
  on public.concerts (catalog_event_id, diary_audience, published_at desc, id)
  where record_model = 'personal_diary' and deletion_status = 'active';
create index concerts_personal_diary_owner_history
  on public.concerts (owner_id, published_at desc, id)
  where record_model = 'personal_diary' and deletion_status = 'active';

create table public.diary_reviews (
  concert_id uuid primary key references public.concerts (id) on delete cascade,
  overall_score_points smallint,
  performance_score_points smallint,
  review_body text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint diary_reviews_overall_score_check check (
    overall_score_points is null
    or (overall_score_points between 5 and 100 and overall_score_points % 5 = 0)
  ),
  constraint diary_reviews_performance_score_check check (
    performance_score_points is null
    or (performance_score_points between 5 and 100 and performance_score_points % 5 = 0)
  ),
  constraint diary_reviews_body_check check (
    review_body is null or private.is_normalized_concert_text(review_body, 4000)
  )
);

create table private.catalog_event_diary_mutations (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  event_id uuid not null references public.catalog_events (id) on delete cascade,
  created_at timestamptz not null default clock_timestamp()
);

create index catalog_event_diary_mutations_actor_window
  on private.catalog_event_diary_mutations (profile_id, created_at desc);

create function private.touch_diary_review()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.created_at := old.created_at;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger set_diary_review_updated_at
before update on public.diary_reviews
for each row execute function private.touch_diary_review();

create function private.enforce_personal_diary_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attendance public.catalog_event_attendance%rowtype;
  v_event public.catalog_events%rowtype;
begin
  if new.record_model = 'legacy_shared' then
    if tg_op = 'UPDATE' and old.record_model <> 'legacy_shared' then
      raise exception 'A personal diary cannot become a legacy concert'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' and old.record_model <> 'personal_diary' then
    raise exception 'Legacy concerts cannot be converted into personal diaries'
      using errcode = '23514';
  end if;

  select attendance.* into v_attendance
  from public.catalog_event_attendance as attendance
  where attendance.id = new.attendance_id;

  if v_attendance.id is null
    or v_attendance.profile_id <> new.owner_id
    or v_attendance.status <> 'went'
    or (
      new.catalog_event_id is not null
      and v_attendance.event_id <> new.catalog_event_id
    )
  then
    raise exception 'A personal diary must match its owner, event, and Went record'
      using errcode = '23514';
  end if;

  if new.catalog_event_id is not null then
    select event.* into v_event
    from public.catalog_events as event
    where event.id = new.catalog_event_id;

    if v_event.id is null
      or new.catalog_place_id <> v_event.catalog_place_id
      or new.catalog_area_id is distinct from v_event.catalog_area_id
      or new.catalog_tour_id is distinct from v_event.catalog_tour_id
      or new.concert_date <> v_event.event_date
      or new.starts_at is distinct from v_event.starts_at
      or new.venue_time_zone is distinct from (
        case when v_event.starts_at is null then null else v_event.time_zone_identifier end
      )
    then
      raise exception 'A personal diary must preserve its shared event snapshot'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger enforce_personal_diary_integrity
before insert or update of
  owner_id,
  catalog_event_id,
  attendance_id,
  record_model,
  diary_audience,
  visibility,
  catalog_place_id,
  catalog_area_id,
  catalog_tour_id,
  concert_date,
  starts_at,
  venue_time_zone
on public.concerts
for each row execute function private.enforce_personal_diary_integrity();

create function private.reject_personal_diary_collaborator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.concerts as concert
    where concert.id = new.concert_id
      and concert.record_model = 'personal_diary'
  ) then
    raise exception 'Personal diaries have one owner and cannot add editors'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger reject_personal_diary_collaborator
before insert or update on public.concert_collaborators
for each row execute function private.reject_personal_diary_collaborator();

create function private.protect_personal_diary_attendance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.concerts as concert
    where concert.record_model = 'personal_diary'
      and concert.attendance_id = old.id
      and (
        tg_op = 'DELETE'
        or new.id <> old.id
        or new.event_id <> old.event_id
        or new.profile_id <> old.profile_id
        or new.status <> 'went'
      )
  ) then
    raise exception 'Delete the personal diary before changing its Went record'
      using errcode = '23503';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger protect_personal_diary_attendance
before update or delete on public.catalog_event_attendance
for each row execute function private.protect_personal_diary_attendance();

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
      and (
        concert.owner_id = p_user_id
        or (
          concert.record_model = 'legacy_shared'
          and not private.has_relationship_block(concert.owner_id, p_user_id)
          and exists (
            select 1
            from public.concert_collaborators as collaborator
            where collaborator.concert_id = concert.id
              and collaborator.profile_id = p_user_id
          )
        )
      )
  );
$$;

create function private.can_read_personal_diary_as(
  p_user_id uuid,
  p_concert_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_completed_profile(p_user_id)
    and exists (
      select 1
      from public.concerts as concert
      where concert.id = p_concert_id
        and concert.record_model = 'personal_diary'
        and (
          concert.owner_id = p_user_id
          or (
            concert.deletion_status = 'active'
            and concert.published_at is not null
            and not private.has_relationship_block(concert.owner_id, p_user_id)
            and (
              concert.diary_audience = 'community'
              or (
                concert.diary_audience = 'friends'
                and private.are_accepted_friends(concert.owner_id, p_user_id)
              )
            )
          )
        )
    );
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
  select exists (
    select 1
    from public.concerts as concert
    where concert.id = p_concert_id
      and (
        (
          concert.record_model = 'personal_diary'
          and private.can_read_personal_diary_as(p_user_id, concert.id)
        )
        or (
          concert.record_model = 'legacy_shared'
          and (
            private.is_concert_editor_as(p_user_id, concert.id)
            or (
              concert.visibility = 'friends'
              and private.are_accepted_friends(concert.owner_id, p_user_id)
            )
          )
        )
      )
  );
$$;

create function private.assert_catalog_event_diary_rate_limit(
  p_profile_id uuid,
  p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hour_count integer;
  v_day_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-event-diary:' || p_profile_id::text, 0)
  );

  delete from private.catalog_event_diary_mutations as mutation
  where mutation.profile_id = p_profile_id
    and mutation.created_at < clock_timestamp() - interval '24 hours';

  select
    count(*) filter (where mutation.created_at >= clock_timestamp() - interval '1 hour'),
    count(*)
  into v_hour_count, v_day_count
  from private.catalog_event_diary_mutations as mutation
  where mutation.profile_id = p_profile_id
    and mutation.created_at >= clock_timestamp() - interval '24 hours';

  if v_hour_count >= 60 or v_day_count >= 300 then
    raise exception 'You are updating concert diaries too quickly. Try again later.'
      using errcode = 'P0001';
  end if;

  insert into private.catalog_event_diary_mutations (profile_id, event_id)
  values (p_profile_id, p_event_id);
end;
$$;

-- Convert the notification action to a checked text contract so later product
-- actions can be added without unsafe same-transaction enum alterations.
drop function private.enqueue_catalog_event_notification(
  uuid,
  uuid,
  uuid,
  private.catalog_event_notification_action,
  uuid
);

alter table private.catalog_event_notification_outbox
  alter column action type text using action::text,
  add constraint catalog_event_notification_action_check check (
    action in (
      'event_invited',
      'invitation_accepted',
      'event_replied',
      'diary_published',
      'diary_media_added'
    )
  );

drop type private.catalog_event_notification_action;

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
    'event_replied',
    'diary_published',
    'diary_media_added'
  ) then
    raise exception 'Notification action is invalid' using errcode = '22023';
  end if;

  if p_recipient_id = p_actor_id
    or private.has_relationship_block(p_recipient_id, p_actor_id)
  then
    return;
  end if;

  insert into private.catalog_event_notification_outbox (
    recipient_id,
    actor_id,
    event_id,
    action,
    subject_id
  ) values (
    p_recipient_id,
    p_actor_id,
    p_event_id,
    p_action,
    p_subject_id
  );
end;
$$;

create function private.enqueue_catalog_event_diary_notifications(
  p_actor_id uuid,
  p_event_id uuid,
  p_diary_id uuid,
  p_audience public.catalog_event_audience,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient_id uuid;
begin
  if p_audience = 'private' then
    return;
  end if;

  for v_recipient_id in
    select case
      when relationship.user_low_id = p_actor_id then relationship.user_high_id
      else relationship.user_low_id
    end
    from public.relationships as relationship
    where relationship.status = 'accepted'
      and p_actor_id in (relationship.user_low_id, relationship.user_high_id)
  loop
    perform private.enqueue_catalog_event_notification(
      v_recipient_id,
      p_actor_id,
      p_event_id,
      p_action,
      p_diary_id
    );
  end loop;
end;
$$;

create function public.upsert_catalog_event_diary(
  p_event_id uuid,
  p_overall_score numeric default null,
  p_performance_score numeric default null,
  p_review_body text default null,
  p_audience public.catalog_event_audience default 'friends',
  p_publish boolean default true
)
returns table (
  diary_id uuid,
  event_id uuid,
  published_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_event public.catalog_events%rowtype;
  v_attendance public.catalog_event_attendance%rowtype;
  v_diary public.concerts%rowtype;
  v_review_body text := private.optional_concert_text(p_review_body, 4000, 'Diary note');
  v_overall_points smallint;
  v_performance_points smallint;
  v_was_published boolean := false;
  v_will_be_published boolean;
begin
  if v_event_id is null
    or not private.can_read_catalog_event_as(v_actor_id, v_event_id)
  then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;

  select event.* into v_event
  from public.catalog_events as event
  where event.id = v_event_id
  for update;

  if v_event.lifecycle = 'cancelled'
    or (
      v_event.lifecycle <> 'completed'
      and v_event.memory_unlock_at > clock_timestamp()
    )
  then
    raise exception 'Diaries unlock after the concert' using errcode = '22023';
  end if;

  select attendance.* into v_attendance
  from public.catalog_event_attendance as attendance
  where attendance.event_id = v_event_id
    and attendance.profile_id = v_actor_id
  for update;

  if v_attendance.id is null or v_attendance.status <> 'went' then
    raise exception 'Mark that you went before creating a diary' using errcode = '22023';
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
    v_overall_points := (p_overall_score * 10)::smallint;
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
    v_performance_points := (p_performance_score * 10)::smallint;
  end if;

  perform private.assert_catalog_event_diary_rate_limit(v_actor_id, v_event_id);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'catalog-event-personal-diary:' || v_actor_id::text || ':' || v_event_id::text,
      0
    )
  );

  select concert.* into v_diary
  from public.concerts as concert
  where concert.owner_id = v_actor_id
    and concert.catalog_event_id = v_event_id
    and concert.record_model = 'personal_diary'
    and concert.deletion_status = 'active'
  for update;

  if v_diary.id is null then
    insert into public.concerts (
      owner_id,
      venue_name,
      concert_date,
      starts_at,
      venue_time_zone,
      visibility,
      catalog_place_id,
      catalog_area_id,
      catalog_tour_id,
      catalog_event_id,
      attendance_id,
      record_model,
      diary_audience
    ) values (
      v_actor_id,
      '',
      v_event.event_date,
      v_event.starts_at,
      case when v_event.starts_at is null then null else v_event.time_zone_identifier end,
      'private',
      v_event.catalog_place_id,
      v_event.catalog_area_id,
      v_event.catalog_tour_id,
      v_event_id,
      v_attendance.id,
      'personal_diary',
      p_audience
    )
    returning * into v_diary;

    insert into public.concert_artists (
      concert_id,
      lineup_position,
      artist_name,
      catalog_artist_id,
      is_primary
    )
    select
      v_diary.id,
      lineup.lineup_position,
      '',
      lineup.catalog_artist_id,
      lineup.is_headliner
    from public.catalog_event_artists as lineup
    where lineup.event_id = v_event_id
    order by lineup.lineup_position;
  else
    v_was_published := v_diary.published_at is not null;
  end if;

  insert into public.diary_reviews as review (
    concert_id,
    overall_score_points,
    performance_score_points,
    review_body
  ) values (
    v_diary.id,
    v_overall_points,
    v_performance_points,
    v_review_body
  )
  on conflict on constraint diary_reviews_pkey do update
  set overall_score_points = excluded.overall_score_points,
      performance_score_points = excluded.performance_score_points,
      review_body = excluded.review_body;

  v_will_be_published := p_publish or v_was_published;
  if v_will_be_published
    and v_overall_points is null
    and v_performance_points is null
    and v_review_body is null
    and not exists (
      select 1
      from public.concert_photos as photo
      where photo.concert_id = v_diary.id
        and photo.status = 'ready'
    )
  then
    raise exception 'A published diary needs a score, note, or photo'
      using errcode = '22023';
  end if;

  update public.concerts as concert
  set diary_audience = p_audience,
      published_at = case
        when v_will_be_published then coalesce(concert.published_at, clock_timestamp())
        else null
      end,
      updated_at = clock_timestamp()
  where concert.id = v_diary.id
  returning concert.* into v_diary;

  update public.catalog_events as event
  set last_material_activity_at = clock_timestamp()
  where event.id = v_event_id;

  if p_publish and not v_was_published then
    insert into public.social_activity_events (
      actor_id,
      action,
      event_id,
      subject_id,
      metadata
    ) values (
      v_actor_id,
      'diary_published',
      v_event_id,
      v_diary.id,
      '{}'::jsonb
    );

    perform private.enqueue_catalog_event_diary_notifications(
      v_actor_id,
      v_event_id,
      v_diary.id,
      p_audience,
      'diary_published'
    );
  end if;

  return query select v_diary.id, v_event_id, v_diary.published_at;
end;
$$;

create function private.catalog_event_projection_json(p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'event_id', projection.event_id,
    'artists', projection.artists,
    'catalog_place_id', projection.catalog_place_id,
    'catalog_area_id', projection.catalog_area_id,
    'catalog_tour_id', projection.catalog_tour_id,
    'venue_name', projection.venue_name,
    'area_name', projection.area_name,
    'event_date', projection.event_date,
    'starts_at', projection.starts_at,
    'time_zone_identifier', projection.time_zone_identifier,
    'memory_unlock_at', projection.memory_unlock_at,
    'lifecycle', projection.lifecycle,
    'listing', projection.listing,
    'integrity', projection.integrity,
    'row_state', projection.row_state,
    'source_label', 'Community made'
  )
  from private.catalog_event_projections as projection
  where projection.event_id = p_event_id
$$;

create function public.get_catalog_event_diary_summaries(p_event_ids uuid[])
returns table (
  event_id uuid,
  diary_count bigint,
  average_score numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  if p_event_ids is null
    or cardinality(p_event_ids) not between 1 and 100
    or cardinality(p_event_ids) <> cardinality(array(
      select distinct requested_id from unnest(p_event_ids) as requested(requested_id)
    ))
  then
    raise exception 'Diary summaries require between 1 and 100 distinct event IDs'
      using errcode = '22023';
  end if;

  return query
  select
    requested.requested_id,
    count(diary.id),
    round(avg(review.overall_score_points::numeric / 10), 1)
  from unnest(p_event_ids) as requested(requested_id)
  left join public.concerts as diary
    on diary.catalog_event_id = requested.requested_id
    and diary.record_model = 'personal_diary'
    and diary.deletion_status = 'active'
    and diary.published_at is not null
    and private.can_read_personal_diary_as(v_caller_id, diary.id)
  left join public.diary_reviews as review on review.concert_id = diary.id
  where private.can_read_catalog_event_as(v_caller_id, requested.requested_id)
  group by requested.requested_id;
end;
$$;

create function public.list_catalog_event_diaries(
  p_event_id uuid,
  p_scope text default 'all',
  p_cursor jsonb default null,
  p_limit integer default 30
)
returns table (
  diary_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_relationship text,
  author_avatar_object_path text,
  author_avatar_version bigint,
  overall_score numeric,
  performance_score numeric,
  review_body text,
  photo_count bigint,
  video_count bigint,
  comment_count bigint,
  audience public.catalog_event_audience,
  published_at timestamptz,
  next_cursor jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_cursor_published_at timestamptz;
  v_cursor_id uuid;
begin
  if p_scope not in ('all', 'friends', 'community', 'mine') then
    raise exception 'Diary scope is invalid' using errcode = '22023';
  end if;
  if p_limit not between 1 and 50 then
    raise exception 'Diary limit must be between 1 and 50' using errcode = '22023';
  end if;
  if v_event_id is null
    or not private.can_read_catalog_event_as(v_caller_id, v_event_id)
  then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'published_at' - 'diary_id') <> '{}'::jsonb
      or not (p_cursor ?& array['published_at', 'diary_id'])
    then
      raise exception 'Diary cursor is invalid' using errcode = '22023';
    end if;
    begin
      v_cursor_published_at := (p_cursor ->> 'published_at')::timestamptz;
      v_cursor_id := (p_cursor ->> 'diary_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Diary cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  select
    diary.id,
    author.id,
    author.username,
    author.display_name,
    private.relationship_label(v_caller_id, author.id),
    author.avatar_object_path,
    author.avatar_version,
    review.overall_score_points::numeric / 10,
    review.performance_score_points::numeric / 10,
    review.review_body,
    (
      select count(*)
      from public.concert_photos as photo
      where photo.concert_id = diary.id and photo.status = 'ready'
    ),
    0::bigint,
    (
      select count(*)
      from public.comments as comment
      where comment.concert_id = diary.id and comment.deleted_at is null
    ),
    diary.diary_audience,
    diary.published_at,
    jsonb_build_object('published_at', diary.published_at, 'diary_id', diary.id)
  from public.concerts as diary
  join public.profiles as author on author.id = diary.owner_id
  left join public.diary_reviews as review on review.concert_id = diary.id
  where diary.catalog_event_id = v_event_id
    and diary.record_model = 'personal_diary'
    and diary.deletion_status = 'active'
    and diary.published_at is not null
    and private.can_read_personal_diary_as(v_caller_id, diary.id)
    and (
      p_scope = 'all'
      or (p_scope = 'mine' and diary.owner_id = v_caller_id)
      or (p_scope = 'community' and diary.diary_audience = 'community')
      or (
        p_scope = 'friends'
        and (
          diary.owner_id = v_caller_id
          or private.are_accepted_friends(v_caller_id, diary.owner_id)
        )
      )
    )
    and (
      p_cursor is null
      or diary.published_at < v_cursor_published_at
      or (diary.published_at = v_cursor_published_at and diary.id > v_cursor_id)
    )
  order by diary.published_at desc, diary.id
  limit p_limit;
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
  diary jsonb,
  occurred_at timestamptz,
  next_cursor jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_cursor_occurred_at timestamptz;
  v_cursor_kind text;
  v_cursor_subject_id uuid;
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
      v_cursor_occurred_at := (p_cursor ->> 'occurred_at')::timestamptz;
      v_cursor_kind := p_cursor ->> 'history_kind';
      v_cursor_subject_id := (p_cursor ->> 'subject_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Profile history cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  with history as (
    select
      'went'::text as history_kind,
      attendance.event_id,
      null::uuid as diary_id,
      attendance.updated_at as occurred_at,
      attendance.event_id as subject_id
    from public.catalog_event_attendance as attendance
    where attendance.profile_id = p_profile_id
      and attendance.status = 'went'
      and private.can_read_catalog_event_as(v_caller_id, attendance.event_id)
      and private.can_read_catalog_event_attendance_as(
        v_caller_id,
        attendance.event_id,
        attendance.profile_id,
        attendance.audience
      )
    union all
    select
      'diary'::text,
      diary_record.catalog_event_id,
      diary_record.id,
      diary_record.published_at,
      diary_record.id
    from public.concerts as diary_record
    where diary_record.owner_id = p_profile_id
      and diary_record.record_model = 'personal_diary'
      and diary_record.deletion_status = 'active'
      and diary_record.catalog_event_id is not null
      and diary_record.published_at is not null
      and private.can_read_catalog_event_as(v_caller_id, diary_record.catalog_event_id)
      and private.can_read_personal_diary_as(v_caller_id, diary_record.id)
  )
  select
    history.history_kind,
    private.catalog_event_projection_json(history.event_id),
    case when history.diary_id is null then null else jsonb_build_object(
      'diary_id', diary_record.id,
      'author_id', author.id,
      'author_username', author.username,
      'author_display_name', author.display_name,
      'author_relationship', private.relationship_label(v_caller_id, author.id),
      'author_avatar_object_path', author.avatar_object_path,
      'author_avatar_version', author.avatar_version,
      'overall_score', review.overall_score_points::numeric / 10,
      'performance_score', review.performance_score_points::numeric / 10,
      'review_body', review.review_body,
      'photo_count', (
        select count(*) from public.concert_photos as photo
        where photo.concert_id = diary_record.id and photo.status = 'ready'
      ),
      'video_count', 0,
      'comment_count', (
        select count(*) from public.comments as comment
        where comment.concert_id = diary_record.id and comment.deleted_at is null
      ),
      'audience', diary_record.diary_audience,
      'published_at', diary_record.published_at
    ) end,
    history.occurred_at,
    jsonb_build_object(
      'occurred_at', history.occurred_at,
      'history_kind', history.history_kind,
      'subject_id', history.subject_id
    )
  from history
  left join public.concerts as diary_record on diary_record.id = history.diary_id
  left join public.profiles as author on author.id = diary_record.owner_id
  left join public.diary_reviews as review on review.concert_id = diary_record.id
  where p_cursor is null
    or history.occurred_at < v_cursor_occurred_at
    or (
      history.occurred_at = v_cursor_occurred_at
      and (history.history_kind, history.subject_id) > (v_cursor_kind, v_cursor_subject_id)
    )
  order by history.occurred_at desc, history.history_kind, history.subject_id
  limit p_limit;
end;
$$;

create function private.record_personal_diary_media_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_diary public.concerts%rowtype;
begin
  if old.status = 'ready' or new.status <> 'ready' then
    return new;
  end if;

  select concert.* into v_diary
  from public.concerts as concert
  where concert.id = new.concert_id;

  if v_diary.record_model = 'personal_diary'
    and v_diary.catalog_event_id is not null
    and v_diary.published_at is not null
  then
    insert into public.social_activity_events (
      actor_id,
      action,
      event_id,
      subject_id,
      metadata
    ) values (
      v_diary.owner_id,
      'diary_media_added',
      v_diary.catalog_event_id,
      v_diary.id,
      '{}'::jsonb
    );

    perform private.enqueue_catalog_event_diary_notifications(
      v_diary.owner_id,
      v_diary.catalog_event_id,
      v_diary.id,
      v_diary.diary_audience,
      'diary_media_added'
    );
  end if;
  return new;
end;
$$;

create trigger record_personal_diary_media_activity
after update of status on public.concert_photos
for each row execute function private.record_personal_diary_media_activity();

create or replace function public.prepare_concert_photo_deletion(p_photo_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.require_completed_caller();
  v_photo public.concert_photos%rowtype;
begin
  select * into v_photo
  from public.concert_photos
  where id = p_photo_id
  for update;

  if not found or v_photo.status not in ('ready', 'deleting') then
    raise exception 'That photo is no longer available' using errcode = 'P0001';
  end if;
  if not exists (
      select 1 from public.concerts
      where id = v_photo.concert_id and owner_id = v_actor
    )
    and not (
      v_photo.uploader_id = v_actor
      and private.is_concert_editor_as(v_actor, v_photo.concert_id)
    )
  then
    raise exception 'You cannot delete this photo' using errcode = '42501';
  end if;

  if v_photo.status = 'ready'
    and exists (
      select 1
      from public.concerts as diary
      left join public.diary_reviews as review on review.concert_id = diary.id
      where diary.id = v_photo.concert_id
        and diary.record_model = 'personal_diary'
        and diary.published_at is not null
        and review.overall_score_points is null
        and review.performance_score_points is null
        and review.review_body is null
        and (
          select count(*)
          from public.concert_photos as ready_photo
          where ready_photo.concert_id = diary.id
            and ready_photo.status = 'ready'
        ) <= 1
    )
  then
    raise exception 'Add a score or note before removing the diary''s only photo'
      using errcode = '23514';
  end if;

  update public.concert_photos
  set status = 'deleting',
      deletion_requested_at = coalesce(deletion_requested_at, clock_timestamp())
  where id = p_photo_id;
  return v_photo.object_path;
end;
$$;

create or replace function public.list_catalog_event_activity(
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
  event jsonb,
  occurred_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_cursor_occurred_at timestamptz;
  v_cursor_id uuid;
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
      v_cursor_occurred_at := (p_cursor ->> 'occurred_at')::timestamptz;
      v_cursor_id := (p_cursor ->> 'activity_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
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
    private.relationship_label(v_caller_id, actor.id),
    actor.avatar_object_path,
    actor.avatar_version,
    private.catalog_event_projection_json(activity.event_id),
    activity.occurred_at,
    jsonb_build_object('occurred_at', activity.occurred_at, 'activity_id', activity.id)
  from public.social_activity_events as activity
  join public.profiles as actor on actor.id = activity.actor_id
  left join public.catalog_event_attendance as attendance
    on attendance.event_id = activity.event_id
    and attendance.profile_id = activity.actor_id
  left join public.catalog_event_posts as post on post.id = activity.subject_id
  left join public.concerts as diary
    on diary.id = activity.subject_id
    and diary.record_model = 'personal_diary'
  where activity.actor_id <> v_caller_id
    and private.can_read_catalog_event_as(v_caller_id, activity.event_id)
    and not private.has_relationship_block(v_caller_id, activity.actor_id)
    and (
      activity.action in ('event_created', 'event_updated')
      or (
        activity.action in ('marked_going', 'marked_went', 'invitation_accepted')
        and attendance.status in ('going', 'went')
        and private.can_read_catalog_event_attendance_as(
          v_caller_id,
          activity.event_id,
          activity.actor_id,
          attendance.audience
        )
      )
      or (
        activity.action in ('event_posted', 'event_replied')
        and post.deleted_at is null
        and private.can_read_catalog_event_post_as(v_caller_id, post.id)
      )
      or (
        activity.action in ('diary_published', 'diary_media_added')
        and diary.catalog_event_id = activity.event_id
        and diary.published_at is not null
        and private.can_read_personal_diary_as(v_caller_id, diary.id)
      )
    )
    and (
      p_cursor is null
      or activity.occurred_at < v_cursor_occurred_at
      or (activity.occurred_at = v_cursor_occurred_at and activity.id > v_cursor_id)
    )
  order by activity.occurred_at desc, activity.id
  limit p_limit;
end;
$$;

create or replace function public.friends_activity_feed(
  p_cursor_occurred_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  concert_id uuid,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  event_type text,
  occurred_at timestamptz,
  primary_artist text,
  venue_name text,
  concert_date date,
  changed_fields text[],
  setlist_preview text[],
  setlist_count integer,
  photo_id uuid,
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
begin
  return query
  select
    legacy_event.id,
    legacy_event.concert_id,
    legacy_event.actor_id,
    actor.username,
    actor.display_name,
    legacy_event.event_type::text,
    legacy_event.occurred_at,
    primary_artist.artist_name,
    concert.venue_name,
    concert.concert_date,
    coalesce(array(
      select jsonb_array_elements_text(legacy_event.metadata -> 'changed_fields')
    ), array[]::text[]),
    coalesce(setlist.preview, array[]::text[]),
    coalesce(setlist.total, 0),
    photo.id,
    photo.object_path,
    coalesce(photo.version, 0)
  from public.concert_events as legacy_event
  join public.concerts as concert on concert.id = legacy_event.concert_id
  join public.profiles as actor on actor.id = legacy_event.actor_id
  join lateral (
    select lineup.artist_name
    from public.concert_artists as lineup
    where lineup.concert_id = concert.id and lineup.is_primary
    limit 1
  ) as primary_artist on true
  left join lateral (
    select
      array_agg(item.song_title order by item.set_position)
        filter (where item.set_position <= 3) as preview,
      count(*)::integer as total
    from public.setlist_items as item
    where item.concert_id = concert.id
  ) as setlist on true
  left join public.concert_photos as photo
    on legacy_event.event_type = 'album_photo_added'
    and photo.id = legacy_event.subject_id
    and photo.status = 'ready'
  where concert.record_model = 'legacy_shared'
    and private.are_accepted_friends(v_caller_id, legacy_event.actor_id)
    and private.can_view_concert_as(v_caller_id, concert.id)
    and private.can_view_concert_event_as(
      v_caller_id,
      concert.id,
      legacy_event.event_type
    )
    and (
      p_cursor_occurred_at is null
      or legacy_event.occurred_at < p_cursor_occurred_at
      or (
        legacy_event.occurred_at = p_cursor_occurred_at
        and legacy_event.id < p_cursor_id
      )
    )
  order by legacy_event.occurred_at desc, legacy_event.id desc
  limit v_limit;
end;
$$;

-- Keep the established shared-concert archive as a separate compatibility
-- surface. Personal diaries appear through list_catalog_profile_event_history
-- instead, so profiles never render the same memory in both sections.
create or replace function public.profile_concert_history(
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
  where concert.record_model = 'legacy_shared'
    and (
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

alter table public.diary_reviews enable row level security;

create policy "diary_reviews_select_visible_personal_diary"
on public.diary_reviews for select to authenticated
using (private.can_read_personal_diary_as(auth.uid(), concert_id));

revoke all on table public.diary_reviews from public, anon, authenticated;

revoke all on function private.touch_diary_review()
  from public, anon, authenticated;
revoke all on function private.enforce_personal_diary_integrity()
  from public, anon, authenticated;
revoke all on function private.reject_personal_diary_collaborator()
  from public, anon, authenticated;
revoke all on function private.protect_personal_diary_attendance()
  from public, anon, authenticated;
revoke all on function private.can_read_personal_diary_as(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.assert_catalog_event_diary_rate_limit(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.enqueue_catalog_event_notification(
  uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
revoke all on function private.enqueue_catalog_event_diary_notifications(
  uuid, uuid, uuid, public.catalog_event_audience, text
) from public, anon, authenticated;
revoke all on function private.catalog_event_projection_json(uuid)
  from public, anon, authenticated;
revoke all on function private.record_personal_diary_media_activity()
  from public, anon, authenticated;

revoke all on function public.upsert_catalog_event_diary(
  uuid, numeric, numeric, text, public.catalog_event_audience, boolean
) from public, anon;
revoke all on function public.get_catalog_event_diary_summaries(uuid[])
  from public, anon;
revoke all on function public.list_catalog_event_diaries(uuid, text, jsonb, integer)
  from public, anon;
revoke all on function public.list_catalog_profile_event_history(uuid, jsonb, integer)
  from public, anon;

grant execute on function public.upsert_catalog_event_diary(
  uuid, numeric, numeric, text, public.catalog_event_audience, boolean
) to authenticated;
grant execute on function public.get_catalog_event_diary_summaries(uuid[])
  to authenticated;
grant execute on function public.list_catalog_event_diaries(uuid, text, jsonb, integer)
  to authenticated;
grant execute on function public.list_catalog_profile_event_history(uuid, jsonb, integer)
  to authenticated;
