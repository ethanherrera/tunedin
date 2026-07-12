-- Close the access-revocation gap in shared concerts.
--
-- Tagging is immediate, but it never creates permanent access that survives a
-- direct unfriend or safety block. These helpers run in the relationship
-- mutation transaction, so the relationship and concert permissions change
-- together.

create function private.lock_relationship_pair(p_one uuid, p_other uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_one is null or p_other is null or p_one = p_other then
    raise exception 'A relationship requires two different profiles'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      least(p_one, p_other)::text || greatest(p_one, p_other)::text,
      0
    )
  );
end;
$$;

create function private.revoke_relationship_collaboration(
  p_actor_id uuid,
  p_other_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_collaborator record;
begin
  for v_collaborator in
    select collaborator.concert_id, collaborator.profile_id
    from public.concert_collaborators as collaborator
    join public.concerts as concert on concert.id = collaborator.concert_id
    where (
      concert.owner_id = p_actor_id
      and collaborator.profile_id = p_other_id
    ) or (
      concert.owner_id = p_other_id
      and collaborator.profile_id = p_actor_id
    ) or (
      collaborator.tagged_by = p_actor_id
      and collaborator.profile_id = p_other_id
    ) or (
      collaborator.tagged_by = p_other_id
      and collaborator.profile_id = p_actor_id
    )
    for update of concert, collaborator
  loop
    delete from public.concert_collaborators
    where concert_id = v_collaborator.concert_id
      and profile_id = v_collaborator.profile_id;

    perform private.bump_concert_version(v_collaborator.concert_id);
    perform private.record_concert_event(
      v_collaborator.concert_id,
      p_actor_id,
      'collaborator_removed',
      v_collaborator.profile_id,
      jsonb_build_object('reason', p_reason)
    );
  end loop;
end;
$$;

create or replace function private.is_concert_editor_as(p_user_id uuid, p_concert_id uuid)
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
          not private.has_relationship_block(concert.owner_id, p_user_id)
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

create or replace function public.remove_friend(p_friend_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  perform private.lock_relationship_pair(v_caller_id, p_friend_id);

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

  perform private.revoke_relationship_collaboration(
    v_caller_id,
    p_friend_id,
    'friendship_ended'
  );
end;
$$;

create or replace function public.block_profile(p_profile_id uuid)
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

  perform private.lock_relationship_pair(v_caller_id, p_profile_id);
  v_low_id := least(v_caller_id, p_profile_id);
  v_high_id := greatest(v_caller_id, p_profile_id);

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

  perform private.revoke_relationship_collaboration(
    v_caller_id,
    p_profile_id,
    'blocked'
  );
end;
$$;

create or replace function public.tag_concert_collaborator(
  p_concert_id uuid,
  p_profile_id uuid,
  p_expected_version bigint
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_concert_editor(p_concert_id);
  v_concert public.concerts%rowtype;
begin
  if p_profile_id is null or p_profile_id = v_actor_id then
    raise exception 'Choose a friend other than yourself'
      using errcode = '22023';
  end if;

  -- Serialize a tag with a concurrent unfriend/block of the same pair, then
  -- re-check the editor role after acquiring that relationship lock.
  perform private.lock_relationship_pair(v_actor_id, p_profile_id);
  v_actor_id := private.require_concert_editor(p_concert_id);

  select *
  into v_concert
  from public.concerts
  where id = p_concert_id
  for update;

  if not found then
    raise exception 'That concert is no longer available'
      using errcode = 'P0001';
  end if;

  perform private.assert_expected_concert_version(v_concert, p_expected_version);

  if v_concert.visibility = 'private' then
    raise exception 'Choose Collaborators or Friends before tagging someone'
      using errcode = '22023';
  end if;

  if p_profile_id = v_concert.owner_id then
    raise exception 'The owner is already part of this concert'
      using errcode = '22023';
  end if;

  if not private.has_completed_profile(p_profile_id)
    or not private.are_accepted_friends(v_actor_id, p_profile_id)
    or private.has_relationship_block(v_concert.owner_id, p_profile_id)
  then
    raise exception 'Only an available friend can be tagged'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.concert_collaborators
    where concert_id = p_concert_id and profile_id = p_profile_id
  ) then
    return v_concert;
  end if;

  insert into public.concert_collaborators (concert_id, profile_id, tagged_by)
  values (p_concert_id, p_profile_id, v_actor_id);
  perform private.bump_concert_version(p_concert_id);

  select * into v_concert from public.concerts where id = p_concert_id;
  perform private.record_concert_event(
    p_concert_id,
    v_actor_id,
    'collaborator_tagged',
    p_profile_id
  );
  perform private.enqueue_collaboration_notification(
    p_profile_id,
    v_actor_id,
    p_concert_id,
    'collaborator_tagged'
  );

  return v_concert;
end;
$$;

create or replace function public.transfer_concert_ownership(
  p_concert_id uuid,
  p_new_owner_id uuid,
  p_expected_version bigint
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_concert_owner(p_concert_id);
  v_concert public.concerts%rowtype;
  v_recent_transfers integer;
begin
  select count(*)
  into v_recent_transfers
  from public.concert_events
  where actor_id = v_actor_id
    and event_type = 'ownership_transferred'
    and occurred_at >= now() - interval '24 hours';

  if v_recent_transfers >= 20 then
    raise exception 'You have reached the ownership-transfer limit for today'
      using errcode = 'P0001';
  end if;

  select *
  into v_concert
  from public.concerts
  where id = p_concert_id
  for update;

  perform private.assert_expected_concert_version(v_concert, p_expected_version);

  if private.has_relationship_block(v_concert.owner_id, p_new_owner_id)
    or not exists (
      select 1
      from public.concert_collaborators
      where concert_id = p_concert_id and profile_id = p_new_owner_id
    )
  then
    raise exception 'Choose an existing tagged collaborator as the new owner'
      using errcode = '22023';
  end if;

  delete from public.concert_collaborators
  where concert_id = p_concert_id and profile_id = p_new_owner_id;

  insert into public.concert_collaborators (concert_id, profile_id, tagged_by)
  values (p_concert_id, v_actor_id, v_actor_id)
  on conflict (concert_id, profile_id) do nothing;

  update public.concerts
  set owner_id = p_new_owner_id, updated_at = clock_timestamp()
  where id = p_concert_id
  returning * into v_concert;

  perform private.record_concert_event(
    p_concert_id,
    v_actor_id,
    'ownership_transferred',
    p_new_owner_id
  );
  perform private.enqueue_collaboration_notification(
    p_new_owner_id,
    v_actor_id,
    p_concert_id,
    'ownership_transferred'
  );

  return v_concert;
end;
$$;

revoke all on function private.lock_relationship_pair(uuid, uuid) from public;
revoke all on function private.revoke_relationship_collaboration(uuid, uuid, text) from public;
