drop function public.profile_concert_history(
  uuid,
  text,
  integer,
  public.concert_visibility,
  date,
  uuid,
  integer
);

create function public.profile_concert_history(
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
  where (
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
      or (
        p_sort = 'newest'
        and (concert.concert_date, concert.id) < (p_cursor_date, p_cursor_id)
      )
      or (
        p_sort = 'oldest'
        and (concert.concert_date, concert.id) > (p_cursor_date, p_cursor_id)
      )
      or (
        p_sort = 'recently_updated'
        and (concert.updated_at, concert.id) < (p_cursor_updated_at, p_cursor_id)
      )
      or (
        p_sort = 'artist'
        and (lower(artist.artist_name), concert.id) > (p_cursor_text, p_cursor_id)
      )
      or (
        p_sort = 'venue'
        and (lower(concert.venue_name), concert.id) > (p_cursor_text, p_cursor_id)
      )
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

revoke all on function public.profile_concert_history(
  uuid,
  text,
  integer,
  public.concert_visibility,
  text,
  date,
  timestamptz,
  text,
  uuid,
  integer
) from public, anon;

grant execute on function public.profile_concert_history(
  uuid,
  text,
  integer,
  public.concert_visibility,
  text,
  date,
  timestamptz,
  text,
  uuid,
  integer
) to authenticated;
