alter table public.profiles
  add column avatar_object_path text,
  add column avatar_version bigint not null default 0,
  add constraint profiles_avatar_object_path_fixed
    check (avatar_object_path is null or avatar_object_path = 'avatars/' || id::text || '/profile.jpg');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('images', 'images', false, 5242880, array['image/jpeg']::text[])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create function private.can_view_profile_avatar(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and private.has_completed_profile(p_profile_id)
    and not private.has_relationship_block(auth.uid(), p_profile_id);
$$;

revoke all on function private.can_view_profile_avatar(uuid) from public, anon;
grant execute on function private.can_view_profile_avatar(uuid) to authenticated;

create policy "images_insert_own_avatar"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'images'
  and name = 'avatars/' || (select auth.uid())::text || '/profile.jpg'
);

create policy "images_update_own_avatar"
on storage.objects for update to authenticated
using (
  bucket_id = 'images'
  and name = 'avatars/' || (select auth.uid())::text || '/profile.jpg'
)
with check (
  bucket_id = 'images'
  and name = 'avatars/' || (select auth.uid())::text || '/profile.jpg'
);

create policy "images_delete_own_avatar"
on storage.objects for delete to authenticated
using (
  bucket_id = 'images'
  and name = 'avatars/' || (select auth.uid())::text || '/profile.jpg'
);

create policy "images_select_visible_avatar"
on storage.objects for select to authenticated
using (
  bucket_id = 'images'
  and (
    name = 'avatars/' || (select auth.uid())::text || '/profile.jpg'
    or case
      when name ~ '^avatars/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/profile[.]jpg$'
      then private.can_view_profile_avatar(split_part(name, '/', 2)::uuid)
      else false
    end
  )
);

create function public.set_profile_avatar()
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_path text := 'avatars/' || v_caller_id::text || '/profile.jpg';
  v_object storage.objects%rowtype;
  v_profile public.profiles%rowtype;
begin
  select object.* into v_object
  from storage.objects object
  where object.bucket_id = 'images' and object.name = v_path;

  if not found then
    raise exception 'Uploaded profile photo was not found' using errcode = 'P0001';
  end if;

  if coalesce(v_object.metadata ->> 'mimetype', '') <> 'image/jpeg' then
    raise exception 'Profile photos must be JPEG images' using errcode = '22023';
  end if;

  if coalesce((v_object.metadata ->> 'size')::bigint, 0) <= 0
    or (v_object.metadata ->> 'size')::bigint > 1048576
  then
    raise exception 'Profile photos must be no larger than 1 MB' using errcode = '22023';
  end if;

  update public.profiles
  set avatar_object_path = v_path,
      avatar_version = avatar_version + 1
  where id = v_caller_id
  returning * into v_profile;
  return v_profile;
end;
$$;

create function public.remove_profile_avatar()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_path text;
begin
  select avatar_object_path into v_path from public.profiles where id = v_caller_id for update;
  update public.profiles
  set avatar_object_path = null,
      avatar_version = avatar_version + 1
  where id = v_caller_id
  returning id into v_caller_id;

  if not found then
    raise exception 'Profile unavailable' using errcode = 'P0001';
  end if;

  return v_path;
end;
$$;

revoke all on function public.set_profile_avatar() from public, anon;
revoke all on function public.remove_profile_avatar() from public, anon;
grant execute on function public.set_profile_avatar() to authenticated;
grant execute on function public.remove_profile_avatar() to authenticated;

drop function public.search_profiles(text);
create function public.search_profiles(p_username_prefix text)
returns table (id uuid, username text, display_name text, relationship text, avatar_object_path text, avatar_version bigint)
language plpgsql security definer set search_path = '' as $$
declare v_caller_id uuid := private.require_completed_caller(); v_prefix text := public.normalize_username(p_username_prefix);
begin
  if v_prefix is null or v_prefix = '' or char_length(v_prefix) > 24 or v_prefix !~ '^[a-z0-9_]+$' then return; end if;
  return query select profile.id, profile.username, profile.display_name,
    private.relationship_label(v_caller_id, profile.id), profile.avatar_object_path, profile.avatar_version
  from public.profiles profile where profile.id <> v_caller_id and profile.onboarding_completed_at is not null
    and profile.username like v_prefix || '%' and not private.has_relationship_block(v_caller_id, profile.id)
  order by profile.username limit 20;
end; $$;

drop function public.profile_by_username(text);
create function public.profile_by_username(p_username text)
returns table (id uuid, username text, display_name text, relationship text, avatar_object_path text, avatar_version bigint)
language plpgsql security definer set search_path = '' as $$
declare v_caller_id uuid := private.require_completed_caller();
begin return query select profile.id, profile.username, profile.display_name,
  private.relationship_label(v_caller_id, profile.id), profile.avatar_object_path, profile.avatar_version
  from public.profiles profile where profile.onboarding_completed_at is not null
    and profile.username = public.normalize_username(p_username)
    and not private.has_relationship_block(v_caller_id, profile.id) limit 1;
end; $$;

drop function public.list_profile_friends(text);
create function public.list_profile_friends(p_username text)
returns table (id uuid, username text, display_name text, relationship text, avatar_object_path text, avatar_version bigint)
language plpgsql security definer set search_path = '' as $$
declare v_caller_id uuid := private.require_completed_caller(); v_target_id uuid;
begin
  select profile.id into v_target_id from public.profiles profile
  where profile.username = public.normalize_username(p_username) and profile.onboarding_completed_at is not null;
  if not found or private.has_relationship_block(v_caller_id, v_target_id) then return; end if;
  if v_target_id <> v_caller_id and not private.are_accepted_friends(v_caller_id, v_target_id) then
    raise exception 'Only friends can view this list' using errcode = '42501'; end if;
  return query select friend.id, friend.username, friend.display_name,
    private.relationship_label(v_caller_id, friend.id), friend.avatar_object_path, friend.avatar_version
  from public.relationships relation join public.profiles friend on friend.id = case
    when relation.user_low_id = v_target_id then relation.user_high_id else relation.user_low_id end
  where relation.status = 'accepted' and v_target_id in (relation.user_low_id, relation.user_high_id)
  order by friend.username;
end; $$;

drop function public.list_incoming_friend_requests();
create function public.list_incoming_friend_requests()
returns table (id uuid, username text, display_name text, relationship text, avatar_object_path text, avatar_version bigint)
language plpgsql security definer set search_path = '' as $$
declare v_caller_id uuid := private.require_completed_caller();
begin return query select requester.id, requester.username, requester.display_name, 'incoming'::text,
  requester.avatar_object_path, requester.avatar_version
  from public.relationships relation join public.profiles requester on requester.id = relation.initiator_id
  where relation.status = 'pending' and v_caller_id in (relation.user_low_id, relation.user_high_id)
    and relation.initiator_id <> v_caller_id order by relation.requested_at desc;
end; $$;

revoke all on function public.search_profiles(text), public.profile_by_username(text),
  public.list_profile_friends(text), public.list_incoming_friend_requests() from public, anon;
grant execute on function public.search_profiles(text), public.profile_by_username(text),
  public.list_profile_friends(text), public.list_incoming_friend_requests() to authenticated;
