alter table public.concerts
  add column photo_object_path text,
  add column photo_version bigint not null default 0,
  add constraint concerts_photo_object_path_fixed check (
    photo_object_path is null or photo_object_path = 'concerts/' || id::text || '/main.jpg'
  );

create policy "images_insert_editable_concert_photo"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'images'
  and name ~ '^concerts/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/main[.]jpg$'
  and private.is_concert_editor_as(auth.uid(), split_part(name, '/', 2)::uuid)
);

create policy "images_update_editable_concert_photo"
on storage.objects for update to authenticated
using (bucket_id = 'images' and name like 'concerts/%/main.jpg'
  and private.is_concert_editor_as(auth.uid(), split_part(name, '/', 2)::uuid))
with check (bucket_id = 'images' and name like 'concerts/%/main.jpg'
  and private.is_concert_editor_as(auth.uid(), split_part(name, '/', 2)::uuid));

create policy "images_delete_editable_concert_photo"
on storage.objects for delete to authenticated
using (bucket_id = 'images' and name like 'concerts/%/main.jpg'
  and private.is_concert_editor_as(auth.uid(), split_part(name, '/', 2)::uuid));

create policy "images_select_visible_concert_photo"
on storage.objects for select to authenticated
using (bucket_id = 'images' and name like 'concerts/%/main.jpg'
  and private.can_view_concert(split_part(name, '/', 2)::uuid));

create function public.set_concert_photo(p_concert_id uuid)
returns public.concerts language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.require_concert_editor(p_concert_id);
  v_path text := 'concerts/' || p_concert_id::text || '/main.jpg';
  v_object storage.objects%rowtype;
  v_concert public.concerts%rowtype;
begin
  select * into v_object from storage.objects where bucket_id = 'images' and name = v_path;
  if not found then raise exception 'Uploaded concert photo was not found' using errcode = 'P0001'; end if;
  if coalesce(v_object.metadata ->> 'mimetype', '') <> 'image/jpeg' then
    raise exception 'Concert photos must be JPEG images' using errcode = '22023'; end if;
  if coalesce((v_object.metadata ->> 'size')::bigint, 0) <= 0 or (v_object.metadata ->> 'size')::bigint > 3145728 then
    raise exception 'Concert photos must be no larger than 3 MB' using errcode = '22023'; end if;
  update public.concerts set photo_object_path = v_path, photo_version = photo_version + 1
  where id = p_concert_id returning * into v_concert;
  return v_concert;
end; $$;

create function public.remove_concert_photo(p_concert_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.require_concert_editor(p_concert_id); v_path text;
begin
  select photo_object_path into v_path from public.concerts where id = p_concert_id for update;
  update public.concerts set photo_object_path = null, photo_version = photo_version + 1 where id = p_concert_id;
  return v_path;
end; $$;

revoke all on function public.set_concert_photo(uuid), public.remove_concert_photo(uuid) from public, anon;
grant execute on function public.set_concert_photo(uuid), public.remove_concert_photo(uuid) to authenticated;

drop function public.profile_concert_history(uuid, text, integer, public.concert_visibility, date, uuid, integer);
create function public.profile_concert_history(
  p_profile_id uuid, p_search text default null, p_year integer default null,
  p_visibility public.concert_visibility default null, p_cursor_date date default null,
  p_cursor_id uuid default null, p_limit integer default 30
)
returns table (id uuid, owner_id uuid, venue_name text, city text, concert_date date,
  starts_at timestamptz, venue_time_zone text, tour text, visibility text, created_at timestamptz,
  updated_at timestamptz, last_activity_at timestamptz, primary_artist text,
  photo_object_path text, photo_version bigint)
language plpgsql security definer set search_path = '' as $$
declare v_caller_id uuid := private.require_completed_caller(); v_limit integer := greatest(1, least(coalesce(p_limit, 30), 30));
  v_search text := nullif(private.normalize_concert_text(coalesce(p_search, '')), '');
begin
  if not private.has_completed_profile(p_profile_id) then return; end if;
  if p_profile_id <> v_caller_id and not private.are_accepted_friends(v_caller_id, p_profile_id) then
    raise exception 'Only friends can view this concert history' using errcode = '42501'; end if;
  return query select concert.id, concert.owner_id, concert.venue_name, concert.city, concert.concert_date,
    concert.starts_at, concert.venue_time_zone, concert.tour, concert.visibility::text, concert.created_at,
    concert.updated_at, concert.last_activity_at, artist.artist_name, concert.photo_object_path, concert.photo_version
  from public.concerts concert join lateral (select artist_name from public.concert_artists
    where concert_id = concert.id and is_primary limit 1) artist on true
  where (concert.owner_id = p_profile_id or exists (
      select 1 from public.concert_collaborators collaborator
      where collaborator.concert_id = concert.id and collaborator.profile_id = p_profile_id
    ))
    and private.can_view_concert_as(v_caller_id, concert.id)
    and (p_year is null or extract(year from concert.concert_date)::integer = p_year)
    and (p_visibility is null or concert.visibility = p_visibility)
    and (v_search is null or concert.venue_name ilike '%' || v_search || '%' or coalesce(concert.city, '') ilike '%' || v_search || '%'
      or coalesce(concert.tour, '') ilike '%' || v_search || '%' or artist.artist_name ilike '%' || v_search || '%')
    and (p_cursor_date is null or concert.concert_date < p_cursor_date or (concert.concert_date = p_cursor_date and concert.id < p_cursor_id))
  order by concert.concert_date desc, concert.id desc limit v_limit;
end; $$;
revoke all on function public.profile_concert_history(uuid, text, integer, public.concert_visibility, date, uuid, integer) from public, anon;
grant execute on function public.profile_concert_history(uuid, text, integer, public.concert_visibility, date, uuid, integer) to authenticated;
