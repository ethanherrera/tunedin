-- Stage 3: friend discovery and relationship-safe profiles.
--
-- Relationships are stored once per canonical user pair. Client roles can read
-- only their own relationship rows and mutate them only through the narrowly
-- scoped RPCs below. Profile discovery deliberately goes through RPCs so a
-- non-friend never receives concert or friend-list data by accident.

create extension if not exists pg_trgm;

create type public.relationship_status as enum ('pending', 'accepted', 'declined', 'blocked');

create table public.relationships (
  user_low_id uuid not null references public.profiles (id) on delete cascade,
  user_high_id uuid not null references public.profiles (id) on delete cascade,
  status public.relationship_status not null,
  initiator_id uuid not null references public.profiles (id) on delete cascade,
  responder_id uuid references public.profiles (id) on delete set null,
  blocker_id uuid references public.profiles (id) on delete set null,
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_low_id, user_high_id),
  constraint relationships_canonical_pair_check check (user_low_id < user_high_id),
  constraint relationships_initiator_is_participant_check check (
    initiator_id in (user_low_id, user_high_id)
  ),
  constraint relationships_responder_is_other_participant_check check (
    responder_id is null
    or (
      responder_id in (user_low_id, user_high_id)
      and responder_id <> initiator_id
    )
  ),
  constraint relationships_blocker_is_participant_check check (
    blocker_id is null or blocker_id in (user_low_id, user_high_id)
  ),
  constraint relationships_state_metadata_check check (
    (status = 'pending' and responder_id is null and blocker_id is null and responded_at is null)
    or (status in ('accepted', 'declined') and responder_id is not null and blocker_id is null and responded_at is not null)
    or (status = 'blocked' and blocker_id is not null and responded_at is not null)
  )
);

create index relationships_user_low_status on public.relationships (user_low_id, status);
create index relationships_user_high_status on public.relationships (user_high_id, status);

create function private.touch_relationship()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_relationship_timestamps
before update on public.relationships
for each row execute function private.touch_relationship();

create function private.are_accepted_friends(p_one uuid, p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.relationships
    where status = 'accepted'
      and (
        (user_low_id = p_one and user_high_id = p_other)
        or (user_low_id = p_other and user_high_id = p_one)
      )
  );
$$;

create function private.has_relationship_block(p_one uuid, p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.relationships
    where status = 'blocked'
      and (
        (user_low_id = p_one and user_high_id = p_other)
        or (user_low_id = p_other and user_high_id = p_one)
      )
  );
$$;

create function private.has_completed_profile(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = p_user_id
      and onboarding_completed_at is not null
  );
$$;

create function private.require_completed_caller()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'Authentication is required'
      using errcode = '42501';
  end if;

  if not private.has_completed_profile(v_caller_id) then
    raise exception 'Complete onboarding before using friends'
      using errcode = '42501';
  end if;

  return v_caller_id;
end;
$$;

create function private.relationship_label(p_viewer_id uuid, p_other_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select case
        when status = 'accepted' then 'friends'
        when status = 'pending' and initiator_id = p_viewer_id then 'outgoing'
        when status = 'pending' then 'incoming'
        when status = 'declined' then 'declined'
        when status = 'blocked' and blocker_id = p_viewer_id then 'blocked'
        when status = 'blocked' then 'unavailable'
      end
      from public.relationships
      where (user_low_id = p_viewer_id and user_high_id = p_other_id)
        or (user_low_id = p_other_id and user_high_id = p_viewer_id)
    ),
    'none'
  );
$$;

create function private.can_view_concert(p_concert_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.concerts
    where id = p_concert_id
      and (
        owner_id = auth.uid()
        or (
          visibility = 'friends'
          and private.are_accepted_friends(owner_id, auth.uid())
        )
      )
  );
$$;

alter table public.relationships enable row level security;

create policy "relationships_select_participant"
on public.relationships
for select
to authenticated
using ((select auth.uid()) in (user_low_id, user_high_id));

create policy "concerts_select_accepted_friend"
on public.concerts
for select
to authenticated
using (
  visibility = 'friends'
  and (select private.are_accepted_friends(owner_id, auth.uid()))
);

create policy "concert_artists_select_visible_concert"
on public.concert_artists
for select
to authenticated
using ((select private.can_view_concert(concert_id)));

create policy "setlist_items_select_visible_concert"
on public.setlist_items
for select
to authenticated
using ((select private.can_view_concert(concert_id)));

create policy "concert_events_select_visible_concert"
on public.concert_events
for select
to authenticated
using ((select private.can_view_concert(concert_id)));

create index concerts_profile_search_venue on public.concerts using gin (venue_name gin_trgm_ops);
create index concerts_profile_search_city on public.concerts using gin (city gin_trgm_ops) where city is not null;
create index concerts_profile_search_tour on public.concerts using gin (tour gin_trgm_ops) where tour is not null;
create index concert_artists_profile_search_name on public.concert_artists using gin (artist_name gin_trgm_ops);

create function public.search_profiles(p_username_prefix text)
returns table (
  id uuid,
  username text,
  display_name text,
  relationship text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_prefix text := public.normalize_username(p_username_prefix);
begin
  if v_prefix is null
    or v_prefix = ''
    or char_length(v_prefix) > 24
    or v_prefix !~ '^[a-z0-9_]+$'
  then
    return;
  end if;

  return query
  select
    profile.id,
    profile.username,
    profile.display_name,
    private.relationship_label(v_caller_id, profile.id)
  from public.profiles as profile
  where profile.id <> v_caller_id
    and profile.onboarding_completed_at is not null
    and profile.username like v_prefix || '%'
    and not private.has_relationship_block(v_caller_id, profile.id)
  order by profile.username
  limit 20;
end;
$$;

create function public.profile_by_username(p_username text)
returns table (
  id uuid,
  username text,
  display_name text,
  relationship text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_username text := public.normalize_username(p_username);
begin
  return query
  select
    profile.id,
    profile.username,
    profile.display_name,
    private.relationship_label(v_caller_id, profile.id)
  from public.profiles as profile
  where profile.onboarding_completed_at is not null
    and profile.username = v_username
    and not private.has_relationship_block(v_caller_id, profile.id)
  limit 1;
end;
$$;

create function public.list_profile_friends(p_username text)
returns table (
  id uuid,
  username text,
  display_name text,
  relationship text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_target_id uuid;
begin
  select profile.id
  into v_target_id
  from public.profiles as profile
  where profile.username = public.normalize_username(p_username)
    and profile.onboarding_completed_at is not null;

  if not found
    or private.has_relationship_block(v_caller_id, v_target_id)
  then
    return;
  end if;

  if v_target_id <> v_caller_id
    and not private.are_accepted_friends(v_caller_id, v_target_id)
  then
    raise exception 'Only friends can view this list'
      using errcode = '42501';
  end if;

  return query
  select
    friend.id,
    friend.username,
    friend.display_name,
    private.relationship_label(v_caller_id, friend.id)
  from public.relationships as relation
  join public.profiles as friend
    on friend.id = case
      when relation.user_low_id = v_target_id then relation.user_high_id
      else relation.user_low_id
    end
  where relation.status = 'accepted'
    and v_target_id in (relation.user_low_id, relation.user_high_id)
  order by friend.username;
end;
$$;

create function public.list_incoming_friend_requests()
returns table (
  id uuid,
  username text,
  display_name text,
  relationship text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  return query
  select
    requester.id,
    requester.username,
    requester.display_name,
    'incoming'::text
  from public.relationships as relation
  join public.profiles as requester on requester.id = relation.initiator_id
  where relation.status = 'pending'
    and v_caller_id in (relation.user_low_id, relation.user_high_id)
    and relation.initiator_id <> v_caller_id
  order by relation.requested_at desc;
end;
$$;

create function public.send_friend_request(p_recipient_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_low_id uuid;
  v_high_id uuid;
  v_relation public.relationships%rowtype;
begin
  if p_recipient_id is null or p_recipient_id = v_caller_id then
    raise exception 'Choose another profile to send a friend request'
      using errcode = '22023';
  end if;

  if not private.has_completed_profile(p_recipient_id) then
    raise exception 'That profile is unavailable'
      using errcode = 'P0001';
  end if;

  v_low_id := least(v_caller_id, p_recipient_id);
  v_high_id := greatest(v_caller_id, p_recipient_id);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_low_id::text || v_high_id::text, 0));

  select *
  into v_relation
  from public.relationships
  where user_low_id = v_low_id and user_high_id = v_high_id
  for update;

  if not found then
    insert into public.relationships (
      user_low_id, user_high_id, status, initiator_id, requested_at
    )
    values (v_low_id, v_high_id, 'pending', v_caller_id, now());
    return;
  end if;

  if v_relation.status = 'blocked' then
    raise exception 'This profile is unavailable'
      using errcode = '42501';
  end if;

  if v_relation.status = 'accepted' then
    return;
  end if;

  if v_relation.status = 'pending' then
    if v_relation.initiator_id = v_caller_id then
      return;
    end if;

    raise exception 'This person already sent you a request'
      using errcode = 'P0001';
  end if;

  if v_relation.responded_at > now() - interval '5 minutes' then
    raise exception 'Try again in a few minutes'
      using errcode = 'P0001';
  end if;

  update public.relationships
  set
    status = 'pending',
    initiator_id = v_caller_id,
    responder_id = null,
    blocker_id = null,
    requested_at = now(),
    responded_at = null
  where user_low_id = v_low_id and user_high_id = v_high_id;
end;
$$;

create function public.accept_friend_request(p_requester_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  update public.relationships
  set status = 'accepted', responder_id = v_caller_id, responded_at = now()
  where status = 'pending'
    and initiator_id = p_requester_id
    and v_caller_id in (user_low_id, user_high_id);

  if not found then
    raise exception 'That request is no longer available'
      using errcode = 'P0001';
  end if;
end;
$$;

create function public.decline_friend_request(p_requester_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  update public.relationships
  set status = 'declined', responder_id = v_caller_id, responded_at = now()
  where status = 'pending'
    and initiator_id = p_requester_id
    and v_caller_id in (user_low_id, user_high_id);

  if not found then
    raise exception 'That request is no longer available'
      using errcode = 'P0001';
  end if;
end;
$$;

create function public.withdraw_friend_request(p_recipient_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  delete from public.relationships
  where status = 'pending'
    and initiator_id = v_caller_id
    and (
      (user_low_id = v_caller_id and user_high_id = p_recipient_id)
      or (user_low_id = p_recipient_id and user_high_id = v_caller_id)
    );

  if not found then
    raise exception 'That outgoing request is no longer available'
      using errcode = 'P0001';
  end if;
end;
$$;

create function public.remove_friend(p_friend_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  delete from public.relationships
  where status = 'accepted'
    and (
      (user_low_id = v_caller_id and user_high_id = p_friend_id)
      or (user_low_id = p_friend_id and user_high_id = v_caller_id)
    );

  if not found then
    raise exception 'You are no longer friends'
      using errcode = 'P0001';
  end if;
end;
$$;

create function public.block_profile(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_low_id uuid;
  v_high_id uuid;
begin
  if p_profile_id is null or p_profile_id = v_caller_id then
    raise exception 'Choose another profile to block'
      using errcode = '22023';
  end if;

  if not private.has_completed_profile(p_profile_id) then
    raise exception 'That profile is unavailable'
      using errcode = 'P0001';
  end if;

  v_low_id := least(v_caller_id, p_profile_id);
  v_high_id := greatest(v_caller_id, p_profile_id);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_low_id::text || v_high_id::text, 0));

  insert into public.relationships (
    user_low_id, user_high_id, status, initiator_id, blocker_id, requested_at, responded_at
  )
  values (v_low_id, v_high_id, 'blocked', v_caller_id, v_caller_id, now(), now())
  on conflict (user_low_id, user_high_id) do update
  set
    status = 'blocked',
    blocker_id = v_caller_id,
    responder_id = null,
    responded_at = now();
end;
$$;

create function public.unblock_profile(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  delete from public.relationships
  where status = 'blocked'
    and blocker_id = v_caller_id
    and (
      (user_low_id = v_caller_id and user_high_id = p_profile_id)
      or (user_low_id = p_profile_id and user_high_id = v_caller_id)
    );

  if not found then
    raise exception 'That block is no longer active'
      using errcode = 'P0001';
  end if;
end;
$$;

create function public.profile_concert_history(
  p_profile_id uuid,
  p_search text default null,
  p_year integer default null,
  p_visibility public.concert_visibility default null,
  p_cursor_date date default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  owner_id uuid,
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
  primary_artist text
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
    artist.artist_name
  from public.concerts as concert
  join lateral (
    select artist_name
    from public.concert_artists
    where concert_id = concert.id and is_primary
    limit 1
  ) as artist on true
  where concert.owner_id = p_profile_id
    and (
      p_profile_id = v_caller_id
      or concert.visibility = 'friends'
    )
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
      p_cursor_date is null
      or concert.concert_date < p_cursor_date
      or (concert.concert_date = p_cursor_date and concert.id < p_cursor_id)
    )
  order by concert.concert_date desc, concert.id desc
  limit v_limit;
end;
$$;

revoke all on table public.relationships from anon, authenticated;
grant select on table public.relationships to authenticated;

revoke all on function private.touch_relationship() from public;
revoke all on function private.are_accepted_friends(uuid, uuid) from public;
revoke all on function private.has_relationship_block(uuid, uuid) from public;
revoke all on function private.has_completed_profile(uuid) from public;
revoke all on function private.require_completed_caller() from public;
revoke all on function private.relationship_label(uuid, uuid) from public;
revoke all on function private.can_view_concert(uuid) from public;
revoke all on function public.search_profiles(text) from public, anon;
revoke all on function public.profile_by_username(text) from public, anon;
revoke all on function public.list_profile_friends(text) from public, anon;
revoke all on function public.list_incoming_friend_requests() from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon;
revoke all on function public.accept_friend_request(uuid) from public, anon;
revoke all on function public.decline_friend_request(uuid) from public, anon;
revoke all on function public.withdraw_friend_request(uuid) from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;
revoke all on function public.block_profile(uuid) from public, anon;
revoke all on function public.unblock_profile(uuid) from public, anon;
revoke all on function public.profile_concert_history(uuid, text, integer, public.concert_visibility, date, uuid, integer) from public, anon;

grant execute on function private.are_accepted_friends(uuid, uuid) to authenticated;
grant execute on function private.has_relationship_block(uuid, uuid) to authenticated;
grant execute on function private.can_view_concert(uuid) to authenticated;
grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.profile_by_username(text) to authenticated;
grant execute on function public.list_profile_friends(text) to authenticated;
grant execute on function public.list_incoming_friend_requests() to authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.decline_friend_request(uuid) to authenticated;
grant execute on function public.withdraw_friend_request(uuid) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.block_profile(uuid) to authenticated;
grant execute on function public.unblock_profile(uuid) to authenticated;
grant execute on function public.profile_concert_history(uuid, text, integer, public.concert_visibility, date, uuid, integer) to authenticated;
