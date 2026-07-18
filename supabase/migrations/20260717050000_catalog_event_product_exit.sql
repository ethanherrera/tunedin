-- Close the remaining community-event product-loop contracts before rollout.
--
-- This migration aligns occurrence identity and memory unlocks with the approved
-- product design, adds warning/report/profile/feed read contracts, and supports
-- an explicit "the cancelled performance happened" confirmation without ever
-- deriving Went automatically.

create or replace function private.prepare_catalog_event_payload(
  p_actor_id uuid,
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_catalog_tour_id uuid,
  p_event_date date,
  p_starts_at timestamptz,
  p_time_zone_identifier text,
  p_listing public.catalog_event_listing,
  p_event_id uuid default null
)
returns table (
  artists jsonb,
  catalog_place_id uuid,
  catalog_area_id uuid,
  catalog_tour_id uuid,
  headliner_catalog_artist_id uuid,
  venue_name text,
  area_name text,
  tour_name text,
  headliner_name text,
  memory_unlock_at timestamptz,
  exact_duplicate_key text,
  search_text text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_artist jsonb;
  v_artist_id uuid;
  v_resolved_artist_id uuid;
  v_resolved_place_id uuid;
  v_resolved_tour_id uuid;
  v_normalized_artists jsonb := '[]'::jsonb;
  v_artist_names text[] := '{}'::text[];
  v_primary_count integer := 0;
  v_headliner_id uuid;
  v_headliner_name text;
  v_place_name text;
  v_area_id uuid;
  v_area_name text;
  v_tour_name text;
  v_time_zone text := btrim(coalesce(p_time_zone_identifier, ''));
  v_unlock_at timestamptz;
  v_scope text;
  v_duplicate_key text;
  v_search_text text;
begin
  if p_event_date is null
    or p_event_date < current_date - 36525
    or p_event_date > current_date + 3650
  then
    raise exception 'Choose an event date within the supported range'
      using errcode = '22023';
  end if;

  if not (v_time_zone = 'UTC' or position('/' in v_time_zone) > 0)
    or not exists (
      select 1 from pg_catalog.pg_timezone_names as zone where zone.name = v_time_zone
    )
  then
    raise exception 'Choose a valid IANA venue time zone'
      using errcode = '22023';
  end if;

  if p_starts_at is not null
    and (p_starts_at at time zone v_time_zone)::date <> p_event_date
  then
    raise exception 'The start time must fall on the event date in the venue time zone'
      using errcode = '22023';
  end if;

  if p_artists is null or jsonb_typeof(p_artists) <> 'array'
    or jsonb_array_length(p_artists) not between 1 and 10
  then
    raise exception 'Events require between 1 and 10 catalog artists'
      using errcode = '22023';
  end if;

  for v_artist in select item.value from jsonb_array_elements(p_artists) as item(value)
  loop
    if jsonb_typeof(v_artist) <> 'object'
      or not (v_artist ? 'catalog_artist_id')
      or not (v_artist ? 'is_primary')
      or jsonb_typeof(v_artist -> 'catalog_artist_id') <> 'string'
      or jsonb_typeof(v_artist -> 'is_primary') <> 'boolean'
      or (v_artist - 'catalog_artist_id' - 'is_primary') <> '{}'::jsonb
    then
      raise exception 'Every lineup artist requires only catalog_artist_id and is_primary'
        using errcode = '22023';
    end if;

    begin
      v_artist_id := (v_artist ->> 'catalog_artist_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Every lineup artist requires a valid catalog artist ID'
        using errcode = '22023';
    end;

    v_resolved_artist_id := private.resolve_catalog_event_entity_as(
      p_actor_id, v_artist_id, 'artist', p_event_id
    );
    if v_resolved_artist_id is null then
      raise exception 'Choose only available catalog artists'
        using errcode = '22023';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(v_normalized_artists) as existing(value)
      where (existing.value ->> 'catalog_artist_id')::uuid = v_resolved_artist_id
    ) then
      raise exception 'An event lineup cannot contain the same catalog artist twice'
        using errcode = '22023';
    end if;

    select entity.display_name
    into v_headliner_name
    from public.catalog_entities as entity
    join public.catalog_artists as artist on artist.id = entity.id
    where entity.id = v_resolved_artist_id;

    v_artist_names := array_append(v_artist_names, v_headliner_name);
    if (v_artist ->> 'is_primary')::boolean then
      v_primary_count := v_primary_count + 1;
      v_headliner_id := v_resolved_artist_id;
    end if;
    v_normalized_artists := v_normalized_artists || jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', v_resolved_artist_id,
      'is_primary', (v_artist ->> 'is_primary')::boolean
    ));
  end loop;

  if v_primary_count <> 1 then
    raise exception 'Events require exactly one headliner'
      using errcode = '22023';
  end if;

  select entity.display_name
  into v_headliner_name
  from public.catalog_entities as entity
  where entity.id = v_headliner_id;

  v_resolved_place_id := private.resolve_catalog_event_entity_as(
    p_actor_id, p_catalog_place_id, 'place', p_event_id
  );
  if v_resolved_place_id is null then
    raise exception 'Choose an available catalog place'
      using errcode = '22023';
  end if;

  select place.area_id, entity.display_name
  into v_area_id, v_place_name
  from public.catalog_places as place
  join public.catalog_entities as entity on entity.id = place.id
  where place.id = v_resolved_place_id;

  if not found then
    raise exception 'Choose an available catalog place'
      using errcode = '22023';
  end if;

  if v_area_id is null then
    v_area_name := 'Area not listed';
  else
    select entity.display_name into v_area_name
    from public.catalog_entities as entity
    where entity.id = v_area_id and entity.status in ('active', 'needs_review');
    if not found then
      raise exception 'The catalog place does not have an available area'
        using errcode = '22023';
    end if;
  end if;

  if p_catalog_tour_id is not null then
    v_resolved_tour_id := private.resolve_catalog_event_entity_as(
      p_actor_id, p_catalog_tour_id, 'tour', p_event_id
    );
    if v_resolved_tour_id is null then
      raise exception 'Choose an available catalog tour'
        using errcode = '22023';
    end if;
    select entity.display_name into v_tour_name
    from public.catalog_entities as entity
    join public.catalog_tours as tour on tour.id = entity.id
    where entity.id = v_resolved_tour_id;
  end if;

  -- The approved lifecycle contract unlocks four hours after a known start,
  -- or at 3:00 a.m. on the following venue-local day when time is unknown.
  v_unlock_at := case
    when p_starts_at is not null then p_starts_at + interval '4 hours'
    else (p_event_date + 1 + time '03:00') at time zone v_time_zone
  end;
  v_scope := case
    when p_listing = 'listed' then 'listed'
    else 'unlisted:' || p_actor_id::text
  end;
  -- Start time is factual detail, not occurrence identity. This prevents two
  -- canonical rows when community contributors disagree only about show time.
  v_duplicate_key := pg_catalog.md5(
    v_scope || '|' || v_resolved_place_id::text || '|' || p_event_date::text
    || '|' || v_headliner_id::text
  );
  v_search_text := lower(private.normalize_concert_text(
    array_to_string(v_artist_names, ' ') || ' ' || v_place_name || ' ' || v_area_name
    || coalesce(' ' || v_tour_name, '')
  ));

  return query select
    v_normalized_artists,
    v_resolved_place_id,
    v_area_id,
    v_resolved_tour_id,
    v_headliner_id,
    v_place_name,
    v_area_name,
    v_tour_name,
    v_headliner_name,
    v_unlock_at,
    v_duplicate_key,
    v_search_text;
end;
$$;

-- Re-key existing rows before restoring uniqueness. If a pre-rollout database
-- somehow contains conflicting occurrences, index creation fails closed and an
-- operator must use the reviewed merge workflow; this migration never guesses.
drop index public.catalog_events_active_exact_duplicate;

update public.catalog_events as event
set memory_unlock_at = case
      when event.starts_at is not null then event.starts_at + interval '4 hours'
      else (event.event_date + 1 + time '03:00') at time zone event.time_zone_identifier
    end,
    exact_duplicate_key = pg_catalog.md5(
      case
        when event.listing = 'listed' then 'listed'
        else 'unlisted:' || event.created_by::text
      end
      || '|' || event.catalog_place_id::text
      || '|' || event.event_date::text
      || '|' || event.headliner_catalog_artist_id::text
    ),
    lifecycle = case
      when event.lifecycle in ('cancelled', 'postponed') then event.lifecycle
      when case
        when event.starts_at is not null then event.starts_at + interval '4 hours'
        else (event.event_date + 1 + time '03:00') at time zone event.time_zone_identifier
      end <= clock_timestamp()
      then 'completed'::public.catalog_event_lifecycle
      else 'scheduled'::public.catalog_event_lifecycle
    end
where event.row_state = 'active';

create unique index catalog_events_active_exact_duplicate
  on public.catalog_events (exact_duplicate_key)
  where row_state = 'active';

create function public.find_catalog_event_duplicate_candidates(
  p_artists jsonb,
  p_catalog_place_id uuid,
  p_event_date date,
  p_catalog_tour_id uuid default null,
  p_starts_at timestamptz default null,
  p_time_zone_identifier text default 'UTC',
  p_listing public.catalog_event_listing default 'listed',
  p_limit integer default 5
)
returns table (
  event_id uuid,
  artists jsonb,
  catalog_place_id uuid,
  catalog_area_id uuid,
  catalog_tour_id uuid,
  venue_name text,
  area_name text,
  tour_name text,
  event_date date,
  starts_at timestamptz,
  time_zone_identifier text,
  memory_unlock_at timestamptz,
  lifecycle public.catalog_event_lifecycle,
  listing public.catalog_event_listing,
  integrity public.catalog_event_integrity,
  row_state public.catalog_event_row_state,
  source_label text,
  version integer,
  created_at timestamptz,
  updated_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_payload record;
begin
  if p_limit not between 1 and 10 then
    raise exception 'Duplicate candidate limit must be between 1 and 10'
      using errcode = '22023';
  end if;

  select * into v_payload
  from private.prepare_catalog_event_payload(
    v_caller_id,
    p_artists,
    p_catalog_place_id,
    p_catalog_tour_id,
    p_event_date,
    p_starts_at,
    btrim(p_time_zone_identifier),
    p_listing,
    null
  );

  return query
  select
    projection.event_id,
    projection.artists,
    projection.catalog_place_id,
    projection.catalog_area_id,
    projection.catalog_tour_id,
    projection.venue_name,
    projection.area_name,
    projection.tour_name,
    projection.event_date,
    projection.starts_at,
    projection.time_zone_identifier,
    projection.memory_unlock_at,
    projection.lifecycle,
    projection.listing,
    projection.integrity,
    projection.row_state,
    'Community added'::text,
    projection.version,
    projection.created_at,
    projection.updated_at,
    null::jsonb
  from private.catalog_event_projections as projection
  where projection.row_state = 'active'
    and projection.headliner_name is not null
    and exists (
      select 1
      from public.catalog_event_artists as lineup
      where lineup.event_id = projection.event_id
        and lineup.catalog_artist_id = v_payload.headliner_catalog_artist_id
        and lineup.is_headliner
    )
    and projection.event_date between p_event_date - 2 and p_event_date + 2
    and (
      projection.catalog_place_id = v_payload.catalog_place_id
      or (
        v_payload.catalog_area_id is not null
        and projection.catalog_area_id = v_payload.catalog_area_id
      )
    )
    and private.can_read_catalog_event_as(v_caller_id, projection.event_id)
  order by
    (projection.event_id in (
      select event.id
      from public.catalog_events as event
      where event.exact_duplicate_key = v_payload.exact_duplicate_key
        and event.row_state = 'active'
    )) desc,
    (projection.catalog_place_id = v_payload.catalog_place_id) desc,
    abs(projection.event_date - p_event_date),
    projection.event_date,
    projection.event_id
  limit p_limit;
end;
$$;

alter table private.catalog_event_reports
  drop constraint catalog_event_reports_reason_check,
  add constraint catalog_event_reports_reason_check check (
    reason in (
      'duplicate',
      'wrong_date',
      'wrong_venue',
      'wrong_lineup',
      'cancelled',
      'sensitive_location',
      'other'
    )
  );

create or replace function public.report_catalog_event(
  p_event_id uuid,
  p_reason text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_report_id uuid;
  v_note text := private.optional_concert_text(p_note, 500, 'Report note');
begin
  if p_reason not in (
    'duplicate',
    'wrong_date',
    'wrong_venue',
    'wrong_lineup',
    'cancelled',
    'sensitive_location',
    'other'
  ) then
    raise exception 'Choose a valid event report reason'
      using errcode = '22023';
  end if;
  if v_event_id is null or not private.can_read_catalog_event_as(v_actor_id, v_event_id) then
    raise exception 'This event is unavailable'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-event-report:' || v_actor_id::text, 0)
  );
  select report.id into v_report_id
  from private.catalog_event_reports as report
  where report.event_id = v_event_id
    and report.reporter_id = v_actor_id
    and report.status = 'open';
  if found then
    return v_report_id;
  end if;
  if (
    select count(*)
    from private.catalog_event_reports as report
    where report.reporter_id = v_actor_id
      and report.created_at >= clock_timestamp() - interval '24 hours'
  ) >= 20 then
    raise exception 'You have reached the event report limit. Try again later.'
      using errcode = 'P0001';
  end if;

  insert into private.catalog_event_reports (event_id, reporter_id, reason, note)
  values (v_event_id, v_actor_id, p_reason, v_note)
  returning id into v_report_id;
  return v_report_id;
end;
$$;

alter table public.catalog_event_attendance
  add column cancelled_performance_confirmed_at timestamptz,
  add constraint catalog_event_attendance_cancelled_performance_shape_check check (
    cancelled_performance_confirmed_at is null or status = 'went'
  );

create function public.confirm_cancelled_catalog_event_performance(
  p_event_id uuid,
  p_audience public.catalog_event_audience default 'friends'
)
returns table (
  event_id uuid,
  status public.catalog_event_attendance_status,
  audience public.catalog_event_audience,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := private.require_completed_caller();
  v_event_id uuid := private.resolve_catalog_event_id(p_event_id);
  v_event public.catalog_events%rowtype;
  v_previous public.catalog_event_attendance%rowtype;
  v_attendance public.catalog_event_attendance%rowtype;
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

  if v_event.lifecycle <> 'cancelled'
    or v_event.memory_unlock_at > clock_timestamp()
  then
    raise exception 'Confirm a cancelled performance only after its scheduled show time'
      using errcode = '22023';
  end if;

  select attendance.* into v_previous
  from public.catalog_event_attendance as attendance
  where attendance.event_id = v_event_id
    and attendance.profile_id = v_actor_id
  for update;

  if v_previous.status = 'went'
    and v_previous.audience = p_audience
    and v_previous.cancelled_performance_confirmed_at is not null
  then
    return query select
      v_previous.event_id,
      v_previous.status,
      v_previous.audience,
      v_previous.updated_at;
    return;
  end if;

  perform private.consume_catalog_event_attendance_quota(v_actor_id, v_event_id);

  insert into public.catalog_event_attendance as attendance (
    event_id,
    profile_id,
    status,
    audience,
    cancelled_performance_confirmed_at
  ) values (
    v_event_id,
    v_actor_id,
    'went',
    p_audience,
    clock_timestamp()
  )
  on conflict on constraint catalog_event_attendance_pkey do update
  set status = 'went',
      audience = excluded.audience,
      cancelled_performance_confirmed_at = coalesce(
        attendance.cancelled_performance_confirmed_at,
        excluded.cancelled_performance_confirmed_at
      )
  returning attendance.* into v_attendance;

  update public.catalog_events as event
  set last_material_activity_at = clock_timestamp()
  where event.id = v_event_id;

  if v_previous.status is distinct from 'went'::public.catalog_event_attendance_status then
    insert into public.social_activity_events (actor_id, action, event_id, metadata)
    values (
      v_actor_id,
      'marked_went',
      v_event_id,
      jsonb_build_object(
        'audience', p_audience,
        'cancelled_performance_confirmed', true
      )
    );
  end if;

  return query select
    v_attendance.event_id,
    v_attendance.status,
    v_attendance.audience,
    v_attendance.updated_at;
end;
$$;

create or replace function public.upsert_catalog_event_diary(
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

  select attendance.* into v_attendance
  from public.catalog_event_attendance as attendance
  where attendance.event_id = v_event_id
    and attendance.profile_id = v_actor_id
    and attendance.superseded_by_attendance_id is null
  for update;

  if v_attendance.id is null or v_attendance.status <> 'went' then
    raise exception 'Mark that you went before creating a diary' using errcode = '22023';
  end if;

  if (
      v_event.lifecycle = 'cancelled'
      and v_attendance.cancelled_performance_confirmed_at is null
    )
    or (
      v_event.lifecycle not in ('cancelled', 'completed')
      and v_event.memory_unlock_at > clock_timestamp()
    )
  then
    raise exception 'Diaries unlock after the concert' using errcode = '22023';
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

create function private.can_read_catalog_event_history_attendance_as(
  p_viewer_id uuid,
  p_event_id uuid,
  p_profile_id uuid,
  p_audience public.catalog_event_audience
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_completed_profile(p_viewer_id)
    and private.has_completed_profile(p_profile_id)
    and (
      p_viewer_id = p_profile_id
      or (
        not private.has_relationship_block(p_viewer_id, p_profile_id)
        and (
          p_audience = 'community'
          or (
            p_audience = 'friends'
            and private.are_accepted_friends(p_viewer_id, p_profile_id)
          )
        )
      )
    )
    and (
      private.resolve_catalog_event_id(p_event_id) is null
      or private.can_read_catalog_event_as(
        p_viewer_id,
        private.resolve_catalog_event_id(p_event_id)
      )
    )
$$;

create function public.list_catalog_profile_attendance(
  p_profile_id uuid,
  p_state public.catalog_event_attendance_status default 'going',
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns table (
  attendance_id uuid,
  event jsonb,
  status public.catalog_event_attendance_status,
  audience public.catalog_event_audience,
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
  if p_state not in ('going', 'went') then
    raise exception 'Profile attendance shows only Going or Went'
      using errcode = '22023';
  end if;
  if p_limit not between 1 and 50 then
    raise exception 'Profile attendance limit must be between 1 and 50'
      using errcode = '22023';
  end if;
  if not private.has_completed_profile(p_profile_id) then
    return;
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'occurred_at' - 'attendance_id') <> '{}'::jsonb
      or not (p_cursor ?& array['occurred_at', 'attendance_id'])
    then
      raise exception 'Profile attendance cursor is invalid'
        using errcode = '22023';
    end if;
    begin
      v_cursor_occurred_at := (p_cursor ->> 'occurred_at')::timestamptz;
      v_cursor_id := (p_cursor ->> 'attendance_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Profile attendance cursor is invalid'
        using errcode = '22023';
    end;
  end if;

  return query
  select
    attendance.id,
    private.catalog_event_history_projection_json(attendance.event_id),
    attendance.status,
    attendance.audience,
    attendance.updated_at,
    jsonb_build_object(
      'occurred_at', attendance.updated_at,
      'attendance_id', attendance.id
    )
  from public.catalog_event_attendance as attendance
  where attendance.profile_id = p_profile_id
    and attendance.status = p_state
    and attendance.superseded_by_attendance_id is null
    and private.can_read_catalog_event_history_attendance_as(
      v_caller_id,
      attendance.event_id,
      attendance.profile_id,
      attendance.audience
    )
    and private.catalog_event_history_projection_json(attendance.event_id) is not null
    and (
      p_cursor is null
      or attendance.updated_at < v_cursor_occurred_at
      or (
        attendance.updated_at = v_cursor_occurred_at
        and attendance.id > v_cursor_id
      )
    )
  order by attendance.updated_at desc, attendance.id
  limit p_limit;
end;
$$;

create or replace function public.list_catalog_profile_event_history(
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
      private.catalog_event_history_projection_json(attendance.event_id) as event_snapshot,
      null::uuid as diary_id,
      attendance.updated_at as history_occurred_at,
      attendance.id as subject_id
    from public.catalog_event_attendance as attendance
    where attendance.profile_id = p_profile_id
      and attendance.status = 'went'
      and attendance.superseded_by_attendance_id is null
      and private.can_read_catalog_event_history_attendance_as(
        v_caller_id,
        attendance.event_id,
        attendance.profile_id,
        attendance.audience
      )
    union all
    select
      'diary'::text,
      case
        when diary_record.catalog_event_id is not null
          then private.catalog_event_history_projection_json(diary_record.catalog_event_id)
        else (
          select operation.record_snapshot -> 'event'
          from private.catalog_event_integrity_operations as operation
          where operation.diary_id = diary_record.id
            and operation.operation = 'diary_detach'
          order by operation.created_at desc, operation.id desc
          limit 1
        )
      end,
      diary_record.id,
      diary_record.published_at,
      diary_record.id
    from public.concerts as diary_record
    where diary_record.owner_id = p_profile_id
      and diary_record.record_model = 'personal_diary'
      and diary_record.deletion_status = 'active'
      and diary_record.published_at is not null
      and private.can_read_personal_diary_as(v_caller_id, diary_record.id)
      and (
        diary_record.catalog_event_id is null
        or private.resolve_catalog_event_id(diary_record.catalog_event_id) is null
        or private.can_read_catalog_event_as(
          v_caller_id,
          private.resolve_catalog_event_id(diary_record.catalog_event_id)
        )
      )
  )
  select
    history.history_kind,
    history.event_snapshot,
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
    history.history_occurred_at,
    jsonb_build_object(
      'occurred_at', history.history_occurred_at,
      'history_kind', history.history_kind,
      'subject_id', history.subject_id
    )
  from history
  left join public.concerts as diary_record on diary_record.id = history.diary_id
  left join public.profiles as author on author.id = diary_record.owner_id
  left join public.diary_reviews as review on review.concert_id = diary_record.id
  where history.event_snapshot is not null
    and (
      p_cursor is null
      or history.history_occurred_at < v_cursor_occurred_at
      or (
        history.history_occurred_at = v_cursor_occurred_at
        and (history.history_kind, history.subject_id) > (v_cursor_kind, v_cursor_subject_id)
      )
    )
  order by history.history_occurred_at desc, history.history_kind, history.subject_id
  limit p_limit;
end;
$$;

create function private.catalog_event_diary_preview_json(
  p_viewer_id uuid,
  p_diary_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'diary_id', diary.id,
    'author_id', author.id,
    'author_username', author.username,
    'author_display_name', author.display_name,
    'author_relationship', private.relationship_label(p_viewer_id, author.id),
    'author_avatar_object_path', author.avatar_object_path,
    'author_avatar_version', author.avatar_version,
    'overall_score', review.overall_score_points::numeric / 10,
    'performance_score', review.performance_score_points::numeric / 10,
    'review_body', review.review_body,
    'photo_count', (
      select count(*)
      from public.concert_photos as photo
      where photo.concert_id = diary.id and photo.status = 'ready'
    ),
    'video_count', 0,
    'comment_count', (
      select count(*)
      from public.comments as comment
      where comment.concert_id = diary.id and comment.deleted_at is null
    ),
    'audience', diary.diary_audience,
    'published_at', diary.published_at
  )
  from public.concerts as diary
  join public.profiles as author on author.id = diary.owner_id
  left join public.diary_reviews as review on review.concert_id = diary.id
  where diary.id = p_diary_id
    and diary.record_model = 'personal_diary'
    and diary.deletion_status = 'active'
    and diary.published_at is not null
    and private.can_read_personal_diary_as(p_viewer_id, diary.id)
$$;

drop function public.list_catalog_event_activity(jsonb, integer);

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
  diary jsonb,
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
    activity.subject_id,
    case
      when activity.action in ('diary_published', 'diary_media_added')
        then private.catalog_event_diary_preview_json(v_caller_id, activity.subject_id)
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
  left join public.catalog_event_posts as post on post.id = activity.subject_id
  left join public.concerts as diary_record
    on diary_record.id = activity.subject_id
    and diary_record.record_model = 'personal_diary'
  where activity.actor_id <> v_caller_id
    and private.are_accepted_friends(v_caller_id, activity.actor_id)
    and canonical.event_id is not null
    and private.can_read_catalog_event_as(v_caller_id, canonical.event_id)
    and not private.has_relationship_block(v_caller_id, activity.actor_id)
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
          v_caller_id,
          canonical.event_id,
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
        and diary_record.catalog_event_id = canonical.event_id
        and diary_record.published_at is not null
        and private.can_read_personal_diary_as(v_caller_id, diary_record.id)
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

alter table private.catalog_event_notification_outbox
  drop constraint catalog_event_notification_action_check,
  add constraint catalog_event_notification_action_check check (
    action in (
      'event_invited',
      'invitation_accepted',
      'event_replied',
      'diary_published',
      'diary_media_added',
      'event_cancelled',
      'event_schedule_changed'
    )
  );

create or replace function private.enqueue_catalog_event_notification(
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
    'diary_media_added',
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

create function private.enqueue_catalog_event_correction_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_recipient_id uuid;
begin
  if new.old_snapshot ->> 'lifecycle' is distinct from new.new_snapshot ->> 'lifecycle'
    and new.new_snapshot ->> 'lifecycle' = 'cancelled'
  then
    v_action := 'event_cancelled';
  elsif (new.old_snapshot -> 'event_date') is distinct from (new.new_snapshot -> 'event_date')
    or (new.old_snapshot -> 'starts_at') is distinct from (new.new_snapshot -> 'starts_at')
    or (new.old_snapshot -> 'catalog_place_id')
      is distinct from (new.new_snapshot -> 'catalog_place_id')
    or (new.old_snapshot -> 'time_zone_identifier')
      is distinct from (new.new_snapshot -> 'time_zone_identifier')
  then
    v_action := 'event_schedule_changed';
  else
    return new;
  end if;

  for v_recipient_id in
    select distinct recipient.profile_id
    from (
      select attendance.profile_id
      from public.catalog_event_attendance as attendance
      where attendance.event_id = new.event_id
        and attendance.superseded_by_attendance_id is null
        and attendance.status in ('going', 'went')
      union all
      select invitation.recipient_id
      from public.catalog_event_invitations as invitation
      where invitation.event_id = new.event_id
        and invitation.status in ('pending', 'accepted')
    ) as recipient(profile_id)
  loop
    perform private.enqueue_catalog_event_notification(
      v_recipient_id,
      new.changed_by,
      new.event_id,
      v_action,
      new.id
    );
  end loop;
  return new;
end;
$$;

create trigger enqueue_catalog_event_correction_notifications
after insert on private.catalog_event_revisions
for each row execute function private.enqueue_catalog_event_correction_notifications();

revoke all on function private.prepare_catalog_event_payload(
  uuid, jsonb, uuid, uuid, date, timestamptz, text, public.catalog_event_listing, uuid
) from public, anon, authenticated;
revoke all on function private.can_read_catalog_event_history_attendance_as(
  uuid, uuid, uuid, public.catalog_event_audience
) from public, anon, authenticated;
revoke all on function private.catalog_event_diary_preview_json(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.enqueue_catalog_event_notification(
  uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
revoke all on function private.enqueue_catalog_event_correction_notifications()
  from public, anon, authenticated;

revoke all on function public.find_catalog_event_duplicate_candidates(
  jsonb, uuid, date, uuid, timestamptz, text, public.catalog_event_listing, integer
) from public, anon;
revoke all on function public.confirm_cancelled_catalog_event_performance(
  uuid, public.catalog_event_audience
) from public, anon;
revoke all on function public.list_catalog_profile_attendance(
  uuid, public.catalog_event_attendance_status, jsonb, integer
) from public, anon;
revoke all on function public.list_catalog_event_activity(jsonb, integer)
  from public, anon;

grant execute on function public.find_catalog_event_duplicate_candidates(
  jsonb, uuid, date, uuid, timestamptz, text, public.catalog_event_listing, integer
) to authenticated;
grant execute on function public.confirm_cancelled_catalog_event_performance(
  uuid, public.catalog_event_audience
) to authenticated;
grant execute on function public.list_catalog_profile_attendance(
  uuid, public.catalog_event_attendance_status, jsonb, integer
) to authenticated;
grant execute on function public.list_catalog_event_activity(jsonb, integer)
  to authenticated;
