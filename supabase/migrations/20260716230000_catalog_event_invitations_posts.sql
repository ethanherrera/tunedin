-- Phase 3: private invitations, upcoming conversation, direct notification
-- outbox events, and viewer-specific event activity projections.

create type public.catalog_event_invitation_status as enum (
  'pending',
  'accepted',
  'declined',
  'withdrawn'
);

create type private.catalog_event_notification_action as enum (
  'event_invited',
  'invitation_accepted',
  'event_replied'
);

create table public.catalog_event_invitations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.catalog_events (id) on delete restrict,
  sender_id uuid not null references public.profiles (id) on delete restrict,
  recipient_id uuid not null references public.profiles (id) on delete restrict,
  status public.catalog_event_invitation_status not null default 'pending',
  created_at timestamptz not null default clock_timestamp(),
  responded_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint catalog_event_invitations_distinct_people check (sender_id <> recipient_id),
  constraint catalog_event_invitations_response_time check (
    (status = 'pending' and responded_at is null)
    or (status <> 'pending' and responded_at is not null)
  ),
  constraint catalog_event_invitations_identity unique (event_id, sender_id, recipient_id)
);

create index catalog_event_invitations_recipient_inbox
  on public.catalog_event_invitations (recipient_id, status, created_at desc, id desc);
create index catalog_event_invitations_sender_event
  on public.catalog_event_invitations (sender_id, event_id, status, created_at desc);

create table public.catalog_event_posts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.catalog_events (id) on delete restrict,
  author_id uuid not null references public.profiles (id) on delete restrict,
  parent_post_id uuid references public.catalog_event_posts (id) on delete restrict,
  body text not null,
  audience public.catalog_event_audience not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint catalog_event_posts_audience_check check (audience in ('friends', 'community')),
  constraint catalog_event_posts_body_check check (
    private.is_normalized_concert_text(body, 500)
  )
);

create index catalog_event_posts_event_time
  on public.catalog_event_posts (event_id, created_at, id);
create index catalog_event_posts_author_rate_limit
  on public.catalog_event_posts (author_id, created_at desc);
create index catalog_event_posts_parent
  on public.catalog_event_posts (parent_post_id, created_at, id)
  where parent_post_id is not null;

create table private.catalog_event_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete restrict,
  event_id uuid not null references public.catalog_events (id) on delete restrict,
  action private.catalog_event_notification_action not null,
  subject_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  delivered_at timestamptz,
  constraint catalog_event_notification_distinct_people check (recipient_id <> actor_id)
);

create index catalog_event_notification_outbox_delivery
  on private.catalog_event_notification_outbox (delivered_at, created_at, id);
create index catalog_event_notification_outbox_recipient
  on private.catalog_event_notification_outbox (recipient_id, created_at desc, id desc);

create function private.touch_catalog_event_social_row()
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

create trigger set_catalog_event_invitation_updated_at
before update on public.catalog_event_invitations
for each row execute function private.touch_catalog_event_social_row();

create trigger set_catalog_event_post_updated_at
before update on public.catalog_event_posts
for each row execute function private.touch_catalog_event_social_row();

-- Pending and accepted invitations grant access to an unlisted event so the
-- recipient can inspect and respond before creating attendance.
create or replace function private.can_read_catalog_event_as(p_user_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_completed_profile(p_user_id)
    and exists (
      select 1
      from public.catalog_events as event
      where event.id = p_event_id
        and event.row_state = 'active'
        and (
          event.listing = 'listed'
          or event.created_by = p_user_id
          or exists (
            select 1
            from public.catalog_event_attendance as attendance
            where attendance.event_id = event.id
              and attendance.profile_id = p_user_id
          )
          or exists (
            select 1
            from public.catalog_event_invitations as invitation
            where invitation.event_id = event.id
              and invitation.status in ('pending', 'accepted')
              and p_user_id in (invitation.sender_id, invitation.recipient_id)
              and private.are_accepted_friends(invitation.sender_id, invitation.recipient_id)
              and not private.has_relationship_block(invitation.sender_id, invitation.recipient_id)
          )
        )
    )
$$;

create function private.can_read_catalog_event_post_as(
  p_viewer_id uuid,
  p_post_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.catalog_event_posts as post
    where post.id = p_post_id
      and private.can_read_catalog_event_as(p_viewer_id, post.event_id)
      and private.has_completed_profile(post.author_id)
      and (
        post.author_id = p_viewer_id
        or (
          not private.has_relationship_block(p_viewer_id, post.author_id)
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

create function private.enqueue_catalog_event_notification(
  p_recipient_id uuid,
  p_actor_id uuid,
  p_event_id uuid,
  p_action private.catalog_event_notification_action,
  p_subject_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
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

create function private.assert_catalog_event_invitation_quota(
  p_sender_id uuid,
  p_additional_count integer
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
    pg_catalog.hashtextextended('catalog-event-invitations:' || p_sender_id::text, 0)
  );

  select
    count(*) filter (where notification.created_at >= clock_timestamp() - interval '1 hour'),
    count(*)
  into v_hour_count, v_day_count
  from private.catalog_event_notification_outbox as notification
  where notification.actor_id = p_sender_id
    and notification.action = 'event_invited'
    and notification.created_at >= clock_timestamp() - interval '24 hours';

  if v_hour_count + p_additional_count > 50 or v_day_count + p_additional_count > 200 then
    raise exception 'You have reached the concert invitation limit. Try again later.'
      using errcode = 'P0001';
  end if;
end;
$$;

create function private.assert_catalog_event_post_rate_limit(p_author_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day_count integer;
  v_latest_at timestamptz;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-event-posts:' || p_author_id::text, 0)
  );

  select count(*), max(post.created_at)
  into v_day_count, v_latest_at
  from public.catalog_event_posts as post
  where post.author_id = p_author_id
    and post.created_at >= clock_timestamp() - interval '24 hours';

  if v_day_count >= 100 then
    raise exception 'You have reached the event conversation limit for today.'
      using errcode = 'P0001';
  end if;
  if v_latest_at is not null and v_latest_at > clock_timestamp() - interval '2 seconds' then
    raise exception 'Wait a moment before posting again.'
      using errcode = 'P0001';
  end if;
end;
$$;

alter table public.catalog_event_invitations enable row level security;
alter table public.catalog_event_posts enable row level security;

create policy "catalog_event_invitations_select_participant"
on public.catalog_event_invitations for select to authenticated
using (
  auth.uid() in (sender_id, recipient_id)
  and not private.has_relationship_block(sender_id, recipient_id)
);

create policy "catalog_event_posts_select_visible"
on public.catalog_event_posts for select to authenticated
using (private.can_read_catalog_event_post_as(auth.uid(), id));

revoke all on table public.catalog_event_invitations, public.catalog_event_posts
  from public, anon, authenticated;
revoke all on table private.catalog_event_notification_outbox
  from public, anon, authenticated;

create function public.list_catalog_event_invite_candidates(p_event_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  relationship text,
  avatar_object_path text,
  avatar_version bigint,
  attendance_status public.catalog_event_attendance_status,
  is_already_invited boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_event public.catalog_events%rowtype;
begin
  if v_event_id is null or not private.can_read_catalog_event_as(v_caller_id, v_event_id) then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;

  select source.* into v_event
  from public.catalog_events as source
  where source.id = v_event_id;

  if v_event.lifecycle in ('cancelled', 'completed')
    or v_event.memory_unlock_at <= clock_timestamp()
  then
    raise exception 'Invitations are available only before the concert'
      using errcode = '22023';
  end if;

  return query
  select
    profile.id,
    profile.username,
    profile.display_name,
    'friends'::text,
    profile.avatar_object_path,
    profile.avatar_version,
    attendance.status,
    coalesce(invitation.status = 'pending', false)
  from public.profiles as profile
  left join public.catalog_event_attendance as attendance
    on attendance.event_id = v_event_id and attendance.profile_id = profile.id
  left join public.catalog_event_invitations as invitation
    on invitation.event_id = v_event_id
    and invitation.sender_id = v_caller_id
    and invitation.recipient_id = profile.id
  where profile.id <> v_caller_id
    and profile.onboarding_completed_at is not null
    and private.are_accepted_friends(v_caller_id, profile.id)
    and not private.has_relationship_block(v_caller_id, profile.id)
  order by profile.display_name, profile.username, profile.id
  limit 200;
end;
$$;

create function public.send_catalog_event_invitations(
  p_event_id uuid,
  p_recipient_ids uuid[]
)
returns table (sent_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_event public.catalog_events%rowtype;
  v_recipient_id uuid;
  v_invitation_id uuid;
  v_sent_count integer := 0;
begin
  if p_recipient_ids is null
    or cardinality(p_recipient_ids) not between 1 and 20
    or array_position(p_recipient_ids, null) is not null
    or cardinality(p_recipient_ids) <> cardinality(array(select distinct unnest(p_recipient_ids)))
  then
    raise exception 'Choose between 1 and 20 different friends' using errcode = '22023';
  end if;
  if v_event_id is null or not private.can_read_catalog_event_as(v_caller_id, v_event_id) then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;

  select source.* into v_event
  from public.catalog_events as source
  where source.id = v_event_id
  for update;

  if v_event.lifecycle in ('cancelled', 'completed')
    or v_event.memory_unlock_at <= clock_timestamp()
  then
    raise exception 'Invitations are available only before the concert'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(p_recipient_ids) as requested(recipient_id)
    left join public.profiles as profile on profile.id = requested.recipient_id
    where requested.recipient_id = v_caller_id
      or profile.onboarding_completed_at is null
      or not private.are_accepted_friends(v_caller_id, requested.recipient_id)
      or private.has_relationship_block(v_caller_id, requested.recipient_id)
  ) then
    raise exception 'Invitations can be sent only to current friends'
      using errcode = '42501';
  end if;

  perform private.assert_catalog_event_invitation_quota(
    v_caller_id,
    cardinality(p_recipient_ids)
  );

  foreach v_recipient_id in array p_recipient_ids loop
    if exists (
      select 1 from public.catalog_event_attendance as attendance
      where attendance.event_id = v_event_id
        and attendance.profile_id = v_recipient_id
        and attendance.status in ('going', 'went')
    ) or exists (
      select 1 from public.catalog_event_invitations as invitation
      where invitation.event_id = v_event_id
        and invitation.sender_id = v_caller_id
        and invitation.recipient_id = v_recipient_id
        and invitation.status = 'pending'
    ) then
      continue;
    end if;

    insert into public.catalog_event_invitations as invitation (
      event_id, sender_id, recipient_id, status, created_at, responded_at
    ) values (
      v_event_id, v_caller_id, v_recipient_id, 'pending', clock_timestamp(), null
    )
    on conflict on constraint catalog_event_invitations_identity do update
    set status = 'pending',
        created_at = clock_timestamp(),
        responded_at = null
    returning invitation.id into v_invitation_id;

    perform private.enqueue_catalog_event_notification(
      v_recipient_id, v_caller_id, v_event_id, 'event_invited', v_invitation_id
    );
    v_sent_count := v_sent_count + 1;
  end loop;

  return query select v_sent_count;
end;
$$;

create function public.list_pending_catalog_event_invitations(
  p_cursor jsonb default null,
  p_limit integer default 20
)
returns table (
  invitation_id uuid,
  event_id uuid,
  event jsonb,
  sender_id uuid,
  sender_username text,
  sender_display_name text,
  sender_relationship text,
  sender_avatar_object_path text,
  sender_avatar_version bigint,
  created_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
begin
  if p_limit not between 1 and 50 then
    raise exception 'Invitation limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'created_at' - 'invitation_id') <> '{}'::jsonb
      or not (p_cursor ?& array['created_at', 'invitation_id'])
    then
      raise exception 'Invitation cursor is invalid' using errcode = '22023';
    end if;
    begin
      v_cursor_created_at := (p_cursor ->> 'created_at')::timestamptz;
      v_cursor_id := (p_cursor ->> 'invitation_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Invitation cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  select
    invitation.id,
    invitation.event_id,
    jsonb_build_object(
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
    ),
    sender.id,
    sender.username,
    sender.display_name,
    private.relationship_label(v_caller_id, sender.id),
    sender.avatar_object_path,
    sender.avatar_version,
    invitation.updated_at,
    jsonb_build_object('created_at', invitation.updated_at, 'invitation_id', invitation.id)
  from public.catalog_event_invitations as invitation
  join public.profiles as sender on sender.id = invitation.sender_id
  join private.catalog_event_projections as projection on projection.event_id = invitation.event_id
  where invitation.recipient_id = v_caller_id
    and invitation.status = 'pending'
    and private.are_accepted_friends(invitation.sender_id, invitation.recipient_id)
    and not private.has_relationship_block(v_caller_id, invitation.sender_id)
    and private.can_read_catalog_event_as(v_caller_id, invitation.event_id)
    and (
      p_cursor is null
      or invitation.updated_at < v_cursor_created_at
      or (invitation.updated_at = v_cursor_created_at and invitation.id > v_cursor_id)
    )
  order by invitation.updated_at desc, invitation.id
  limit p_limit;
end;
$$;

create function public.respond_catalog_event_invitation(
  p_invitation_id uuid,
  p_response public.catalog_event_invitation_status,
  p_audience public.catalog_event_audience default 'friends'
)
returns table (
  invitation_id uuid,
  event_id uuid,
  status public.catalog_event_invitation_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_invitation public.catalog_event_invitations%rowtype;
  v_event public.catalog_events%rowtype;
begin
  if p_response not in ('accepted', 'declined') then
    raise exception 'Invitation response must be accepted or declined'
      using errcode = '22023';
  end if;

  select invitation.* into v_invitation
  from public.catalog_event_invitations as invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null
    or v_invitation.recipient_id <> v_caller_id
    or v_invitation.status <> 'pending'
    or not private.are_accepted_friends(v_invitation.sender_id, v_invitation.recipient_id)
    or private.has_relationship_block(v_caller_id, v_invitation.sender_id)
  then
    raise exception 'That invitation is no longer available' using errcode = '42501';
  end if;

  select source.* into v_event
  from public.catalog_events as source
  where source.id = v_invitation.event_id
  for update;

  if p_response = 'accepted' and (
    v_event.lifecycle in ('cancelled', 'completed')
    or v_event.memory_unlock_at <= clock_timestamp()
  ) then
    raise exception 'This concert can no longer be added to Going'
      using errcode = '22023';
  end if;

  if p_response = 'accepted' then
    perform public.set_catalog_event_attendance(v_invitation.event_id, 'going', p_audience);
  end if;

  update public.catalog_event_invitations as invitation
  set status = p_response,
      responded_at = clock_timestamp()
  where invitation.id = v_invitation.id;

  if p_response = 'accepted' then
    insert into public.social_activity_events (actor_id, action, event_id, subject_id)
    values (v_caller_id, 'invitation_accepted', v_invitation.event_id, v_invitation.id);
    perform private.enqueue_catalog_event_notification(
      v_invitation.sender_id,
      v_caller_id,
      v_invitation.event_id,
      'invitation_accepted',
      v_invitation.id
    );
  end if;

  return query select v_invitation.id, v_invitation.event_id, p_response;
end;
$$;

create function public.list_catalog_event_posts(
  p_event_id uuid,
  p_scope text default 'all',
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  parent_post_id uuid,
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
  v_caller_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
begin
  if v_event_id is null or not private.can_read_catalog_event_as(v_caller_id, v_event_id) then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;
  if p_scope not in ('all', 'friends', 'community') then
    raise exception 'Conversation scope is invalid' using errcode = '22023';
  end if;
  if p_limit not between 1 and 50 then
    raise exception 'Conversation limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'created_at' - 'post_id') <> '{}'::jsonb
      or not (p_cursor ?& array['created_at', 'post_id'])
    then
      raise exception 'Conversation cursor is invalid' using errcode = '22023';
    end if;
    begin
      v_cursor_created_at := (p_cursor ->> 'created_at')::timestamptz;
      v_cursor_id := (p_cursor ->> 'post_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Conversation cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  select
    post.id,
    post.parent_post_id,
    author.id,
    author.username,
    author.display_name,
    private.relationship_label(v_caller_id, author.id),
    author.avatar_object_path,
    author.avatar_version,
    case when post.deleted_at is null then post.body else 'Post deleted'::text end,
    post.audience,
    post.created_at,
    post.deleted_at is not null,
    jsonb_build_object('created_at', post.created_at, 'post_id', post.id)
  from public.catalog_event_posts as post
  join public.profiles as author on author.id = post.author_id
  where post.event_id = v_event_id
    and private.can_read_catalog_event_post_as(v_caller_id, post.id)
    and (
      p_scope = 'all'
      or (p_scope = 'friends' and private.are_accepted_friends(v_caller_id, post.author_id))
      or (
        p_scope = 'community'
        and post.audience = 'community'
        and not private.are_accepted_friends(v_caller_id, post.author_id)
        and post.author_id <> v_caller_id
      )
    )
    and (
      p_cursor is null
      or post.created_at < v_cursor_created_at
      or (post.created_at = v_cursor_created_at and post.id > v_cursor_id)
    )
  order by post.created_at desc, post.id
  limit p_limit;
end;
$$;

create function public.create_catalog_event_post(
  p_event_id uuid,
  p_parent_post_id uuid default null,
  p_body text default null,
  p_audience public.catalog_event_audience default 'friends'
)
returns table (post_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_event public.catalog_events%rowtype;
  v_parent public.catalog_event_posts%rowtype;
  v_body text := private.require_concert_text(p_body, 500, 'Post');
  v_post_id uuid;
begin
  if p_audience = 'private' then
    raise exception 'Event posts must be shared with friends or community'
      using errcode = '22023';
  end if;
  if v_event_id is null or not private.can_read_catalog_event_as(v_caller_id, v_event_id) then
    raise exception 'This event is unavailable' using errcode = '42501';
  end if;

  select source.* into v_event
  from public.catalog_events as source
  where source.id = v_event_id
  for update;
  if v_event.lifecycle in ('cancelled', 'completed')
    or v_event.memory_unlock_at <= clock_timestamp()
  then
    raise exception 'Upcoming conversation closes after the concert'
      using errcode = '22023';
  end if;

  if p_parent_post_id is not null then
    select post.* into v_parent
    from public.catalog_event_posts as post
    where post.id = p_parent_post_id
    for update;
    if v_parent.id is null
      or v_parent.event_id <> v_event_id
      or v_parent.parent_post_id is not null
      or v_parent.deleted_at is not null
      or not private.can_read_catalog_event_post_as(v_caller_id, v_parent.id)
    then
      raise exception 'That post is unavailable for replies' using errcode = '42501';
    end if;
  end if;

  perform private.assert_catalog_event_post_rate_limit(v_caller_id);

  insert into public.catalog_event_posts (
    event_id, author_id, parent_post_id, body, audience
  ) values (
    v_event_id, v_caller_id, p_parent_post_id, v_body, p_audience
  ) returning id into v_post_id;

  insert into public.social_activity_events (actor_id, action, event_id, subject_id)
  values (
    v_caller_id,
    case when p_parent_post_id is null
      then 'event_posted'::public.social_activity_action
      else 'event_replied'::public.social_activity_action
    end,
    v_event_id,
    v_post_id
  );

  if p_parent_post_id is not null and v_parent.author_id <> v_caller_id then
    perform private.enqueue_catalog_event_notification(
      v_parent.author_id, v_caller_id, v_event_id, 'event_replied', v_post_id
    );
  end if;

  update public.catalog_events as event
  set last_material_activity_at = clock_timestamp()
  where event.id = v_event_id;

  return query select v_post_id;
end;
$$;

create function public.update_catalog_event_post(
  p_post_id uuid,
  p_body text,
  p_audience public.catalog_event_audience
)
returns table (post_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_post public.catalog_event_posts%rowtype;
  v_body text := private.require_concert_text(p_body, 500, 'Post');
begin
  if p_audience = 'private' then
    raise exception 'Event posts must be shared with friends or community'
      using errcode = '22023';
  end if;
  select post.* into v_post
  from public.catalog_event_posts as post
  where post.id = p_post_id
  for update;
  if v_post.id is null or v_post.author_id <> v_caller_id or v_post.deleted_at is not null then
    raise exception 'That post is unavailable' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.catalog_events as event
    where event.id = v_post.event_id
      and (event.lifecycle in ('cancelled', 'completed') or event.memory_unlock_at <= clock_timestamp())
  ) then
    raise exception 'Upcoming conversation closes after the concert' using errcode = '22023';
  end if;

  update public.catalog_event_posts as post
  set body = v_body, audience = p_audience
  where post.id = v_post.id;
  return query select v_post.id;
end;
$$;

create function public.delete_catalog_event_post(p_post_id uuid)
returns table (post_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_post public.catalog_event_posts%rowtype;
begin
  select post.* into v_post
  from public.catalog_event_posts as post
  where post.id = p_post_id
  for update;
  if v_post.id is null or v_post.author_id <> v_caller_id then
    raise exception 'That post is unavailable' using errcode = '42501';
  end if;
  update public.catalog_event_posts as post
  set deleted_at = coalesce(post.deleted_at, clock_timestamp())
  where post.id = v_post.id;
  return query select v_post.id;
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
    jsonb_build_object(
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
    ),
    activity.occurred_at,
    jsonb_build_object('occurred_at', activity.occurred_at, 'activity_id', activity.id)
  from public.social_activity_events as activity
  join public.profiles as actor on actor.id = activity.actor_id
  join private.catalog_event_projections as projection on projection.event_id = activity.event_id
  left join public.catalog_event_attendance as attendance
    on attendance.event_id = activity.event_id and attendance.profile_id = activity.actor_id
  left join public.catalog_event_posts as post on post.id = activity.subject_id
  where activity.actor_id <> v_caller_id
    and private.can_read_catalog_event_as(v_caller_id, activity.event_id)
    and not private.has_relationship_block(v_caller_id, activity.actor_id)
    and (
      activity.action in ('event_created', 'event_updated')
      or (
        activity.action in ('marked_going', 'marked_went', 'invitation_accepted')
        and attendance.status in ('going', 'went')
        and private.can_read_catalog_event_attendance_as(
          v_caller_id, activity.event_id, activity.actor_id, attendance.audience
        )
      )
      or (
        activity.action in ('event_posted', 'event_replied')
        and post.deleted_at is null
        and private.can_read_catalog_event_post_as(v_caller_id, post.id)
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

revoke all on function private.touch_catalog_event_social_row()
  from public, anon, authenticated;
revoke all on function private.can_read_catalog_event_post_as(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.enqueue_catalog_event_notification(
  uuid, uuid, uuid, private.catalog_event_notification_action, uuid
) from public, anon, authenticated;
revoke all on function private.assert_catalog_event_invitation_quota(uuid, integer)
  from public, anon, authenticated;
revoke all on function private.assert_catalog_event_post_rate_limit(uuid)
  from public, anon, authenticated;

revoke all on function public.list_catalog_event_invite_candidates(uuid)
  from public, anon;
revoke all on function public.send_catalog_event_invitations(uuid, uuid[])
  from public, anon;
revoke all on function public.list_pending_catalog_event_invitations(jsonb, integer)
  from public, anon;
revoke all on function public.respond_catalog_event_invitation(
  uuid, public.catalog_event_invitation_status, public.catalog_event_audience
) from public, anon;
revoke all on function public.list_catalog_event_posts(uuid, text, jsonb, integer)
  from public, anon;
revoke all on function public.create_catalog_event_post(
  uuid, uuid, text, public.catalog_event_audience
) from public, anon;
revoke all on function public.update_catalog_event_post(
  uuid, text, public.catalog_event_audience
) from public, anon;
revoke all on function public.delete_catalog_event_post(uuid)
  from public, anon;
revoke all on function public.list_catalog_event_activity(jsonb, integer)
  from public, anon;

grant execute on function public.list_catalog_event_invite_candidates(uuid)
  to authenticated;
grant execute on function public.send_catalog_event_invitations(uuid, uuid[])
  to authenticated;
grant execute on function public.list_pending_catalog_event_invitations(jsonb, integer)
  to authenticated;
grant execute on function public.respond_catalog_event_invitation(
  uuid, public.catalog_event_invitation_status, public.catalog_event_audience
) to authenticated;
grant execute on function public.list_catalog_event_posts(uuid, text, jsonb, integer)
  to authenticated;
grant execute on function public.create_catalog_event_post(
  uuid, uuid, text, public.catalog_event_audience
) to authenticated;
grant execute on function public.update_catalog_event_post(
  uuid, text, public.catalog_event_audience
) to authenticated;
grant execute on function public.delete_catalog_event_post(uuid)
  to authenticated;
grant execute on function public.list_catalog_event_activity(jsonb, integer)
  to authenticated;
