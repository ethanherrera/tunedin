-- Let a concert owner return a shared concert to Private in one transaction.
--
-- The owner-only transition removes every tagged collaborator before the
-- function returns, so it cannot leave a private concert with stale editor
-- access. Friends lose read/comment access through the existing visibility
-- checks as soon as the concert row is updated.

create or replace function public.update_concert(
  p_concert_id uuid,
  p_expected_version bigint,
  p_artists jsonb,
  p_venue_name text,
  p_concert_date date,
  p_city text default null,
  p_tour text default null,
  p_starts_at timestamptz default null,
  p_venue_time_zone text default null,
  p_setlist jsonb default '[]'::jsonb,
  p_visibility public.concert_visibility default 'private'
)
returns public.concerts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_concert_editor(p_concert_id);
  v_concert public.concerts%rowtype;
  v_venue_name text;
  v_city text;
  v_tour text;
  v_time_zone text;
  v_artists jsonb;
  v_setlist jsonb;
  v_current_artists jsonb;
  v_current_setlist jsonb;
  v_changed_fields text[] := '{}';
  v_event_type public.concert_event_type;
  v_artist jsonb;
  v_song_title jsonb;
  v_position integer;
  v_reprivatizing boolean := false;
  v_revoked_collaborator_id uuid;
begin
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

  if p_concert_date is null then
    raise exception 'Concert date is required'
      using errcode = '22023';
  end if;

  if (p_starts_at is null) <> (p_venue_time_zone is null) then
    raise exception 'Start time and venue time zone must be provided together'
      using errcode = '22023';
  end if;

  v_venue_name := private.require_concert_text(p_venue_name, 160, 'Venue name');
  v_city := private.optional_concert_text(p_city, 100, 'City');
  v_tour := private.optional_concert_text(p_tour, 160, 'Tour');
  v_time_zone := p_venue_time_zone;

  if v_time_zone is not null and (
    private.contains_control_characters(v_time_zone)
    or v_time_zone <> btrim(v_time_zone)
    or not private.is_iana_time_zone(v_time_zone)
  ) then
    raise exception 'Venue time zone must be a valid IANA time-zone identifier'
      using errcode = '22023';
  end if;

  select artists, setlist
  into v_artists, v_setlist
  from private.validate_concert_payload(p_artists, p_setlist);

  select coalesce(
    jsonb_agg(
      jsonb_build_object('name', artist_name, 'is_primary', is_primary)
      order by lineup_position
    ),
    '[]'::jsonb
  )
  into v_current_artists
  from public.concert_artists
  where concert_id = p_concert_id;

  select coalesce(jsonb_agg(song_title order by set_position), '[]'::jsonb)
  into v_current_setlist
  from public.setlist_items
  where concert_id = p_concert_id;

  if v_concert.venue_name is distinct from v_venue_name then
    v_changed_fields := array_append(v_changed_fields, 'venue');
  end if;
  if v_concert.city is distinct from v_city then
    v_changed_fields := array_append(v_changed_fields, 'city');
  end if;
  if v_concert.concert_date is distinct from p_concert_date then
    v_changed_fields := array_append(v_changed_fields, 'date');
  end if;
  if v_concert.starts_at is distinct from p_starts_at then
    v_changed_fields := array_append(v_changed_fields, 'start_time');
  end if;
  if v_concert.venue_time_zone is distinct from v_time_zone then
    v_changed_fields := array_append(v_changed_fields, 'time_zone');
  end if;
  if v_concert.tour is distinct from v_tour then
    v_changed_fields := array_append(v_changed_fields, 'tour');
  end if;
  if v_concert.visibility is distinct from p_visibility then
    v_changed_fields := array_append(v_changed_fields, 'visibility');
  end if;
  if v_current_artists is distinct from v_artists then
    v_changed_fields := array_append(v_changed_fields, 'lineup');
  end if;
  if v_current_setlist is distinct from v_setlist then
    v_changed_fields := array_append(v_changed_fields, 'setlist');
  end if;

  if cardinality(v_changed_fields) = 0 then
    return v_concert;
  end if;

  if v_concert.visibility <> 'private' and p_visibility = 'private' then
    if v_concert.owner_id <> v_actor_id then
      raise exception 'Only the concert owner can make this concert private'
        using errcode = '42501';
    end if;
    v_reprivatizing := true;
  end if;

  update public.concerts
  set
    venue_name = v_venue_name,
    city = v_city,
    concert_date = p_concert_date,
    starts_at = p_starts_at,
    venue_time_zone = v_time_zone,
    tour = v_tour,
    visibility = p_visibility,
    updated_at = clock_timestamp()
  where id = p_concert_id
  returning * into v_concert;

  if v_reprivatizing then
    for v_revoked_collaborator_id in
      delete from public.concert_collaborators
      where concert_id = p_concert_id
      returning profile_id
    loop
      perform private.record_concert_event(
        p_concert_id,
        v_actor_id,
        'collaborator_removed',
        v_revoked_collaborator_id,
        jsonb_build_object('reason', 'owner_made_private')
      );
    end loop;
  end if;

  if 'lineup' = any(v_changed_fields) then
    delete from public.concert_artists where concert_id = p_concert_id;
    for v_artist, v_position in
      select item.value, item.ordinality::integer
      from jsonb_array_elements(v_artists) with ordinality as item(value, ordinality)
    loop
      insert into public.concert_artists (concert_id, lineup_position, artist_name, is_primary)
      values (
        p_concert_id,
        v_position,
        v_artist ->> 'name',
        (v_artist ->> 'is_primary')::boolean
      );
    end loop;
  end if;

  if 'setlist' = any(v_changed_fields) then
    delete from public.setlist_items where concert_id = p_concert_id;
    for v_song_title, v_position in
      select item.value, item.ordinality::integer
      from jsonb_array_elements(v_setlist) with ordinality as item(value, ordinality)
    loop
      insert into public.setlist_items (concert_id, set_position, song_title)
      values (p_concert_id, v_position, v_song_title #>> '{}');
    end loop;
  end if;

  v_event_type := case
    when v_changed_fields = array['setlist'] then 'setlist_updated'::public.concert_event_type
    when v_changed_fields = array['visibility'] then 'visibility_changed'::public.concert_event_type
    else 'concert_updated'::public.concert_event_type
  end;

  perform private.record_concert_event(
    p_concert_id,
    v_actor_id,
    v_event_type,
    null,
    jsonb_build_object('changed_fields', to_jsonb(v_changed_fields))
  );
  perform private.notify_concert_editors(p_concert_id, v_actor_id, 'concert_updated');

  return v_concert;
end;
$$;
