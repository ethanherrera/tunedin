-- Phase 5: reviewed event integrity operations.
--
-- Shared occurrences can be merged or hidden without deleting attendance,
-- diaries, reviews, media, comments, or immutable activity. High-impact
-- operations require a completed authenticated profile carrying the protected
-- app_metadata.catalog_event_operator claim and always append a private audit.

alter table public.catalog_event_attendance
  add column superseded_by_attendance_id uuid
    references public.catalog_event_attendance (id) on delete restrict,
  add column superseded_at timestamptz,
  add constraint catalog_event_attendance_superseded_shape_check check (
    (
      superseded_by_attendance_id is null
      and superseded_at is null
    )
    or (
      superseded_by_attendance_id is not null
      and superseded_by_attendance_id <> id
      and superseded_at is not null
    )
  );

create index catalog_event_attendance_effective_event
  on public.catalog_event_attendance (event_id, profile_id)
  where superseded_by_attendance_id is null;

create table private.catalog_event_integrity_operations (
  id uuid primary key default gen_random_uuid(),
  operation text not null check (
    operation in ('merge', 'tombstone', 'diary_detach', 'diary_relink')
  ),
  operator_id uuid not null references public.profiles (id) on delete restrict,
  source_event_id uuid references public.catalog_events (id) on delete restrict,
  target_event_id uuid references public.catalog_events (id) on delete restrict,
  diary_id uuid,
  reason_code text not null check (
    reason_code in (
      'duplicate_event',
      'invalid_event',
      'legal_request',
      'safety',
      'privacy_request',
      'incorrect_association',
      'recovery'
    )
  ),
  record_snapshot jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint catalog_event_integrity_operation_shape_check check (
    jsonb_typeof(record_snapshot) = 'object'
    and pg_column_size(record_snapshot) <= 65536
    and (
      (
        operation = 'merge'
        and source_event_id is not null
        and target_event_id is not null
        and source_event_id <> target_event_id
        and diary_id is null
        and reason_code = 'duplicate_event'
      )
      or (
        operation = 'tombstone'
        and source_event_id is not null
        and target_event_id is null
        and diary_id is null
        and reason_code in ('invalid_event', 'legal_request', 'safety')
      )
      or (
        operation = 'diary_detach'
        and source_event_id is not null
        and target_event_id is null
        and diary_id is not null
        and reason_code in ('legal_request', 'safety', 'privacy_request')
      )
      or (
        operation = 'diary_relink'
        and source_event_id is not null
        and target_event_id is not null
        and diary_id is not null
        and reason_code in ('incorrect_association', 'recovery')
      )
    )
  )
);

create index catalog_event_integrity_operations_event_time
  on private.catalog_event_integrity_operations (
    source_event_id, created_at desc, id desc
  );
create index catalog_event_integrity_operations_diary_time
  on private.catalog_event_integrity_operations (
    diary_id, created_at desc, id desc
  ) where diary_id is not null;

create function private.prevent_catalog_event_integrity_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Catalog event integrity audits are immutable'
    using errcode = '42501';
end;
$$;

create trigger catalog_event_integrity_operations_are_immutable
before update or delete on private.catalog_event_integrity_operations
for each row execute function private.prevent_catalog_event_integrity_audit_mutation();

create function private.is_catalog_event_operator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and coalesce(
      auth.jwt() -> 'app_metadata' ->> 'catalog_event_operator',
      'false'
    ) = 'true'
$$;

create function private.require_catalog_event_operator()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_operator_id uuid := private.require_completed_caller();
begin
  if not private.is_catalog_event_operator() then
    raise exception 'Catalog event operator access is required'
      using errcode = '42501';
  end if;
  return v_operator_id;
end;
$$;

create function private.catalog_event_integrity_bypass_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_catalog_event_operator()
    and current_setting('app.catalog_event_integrity_operator', true) = auth.uid()::text
$$;

-- The operator RPCs need to move both sides of the diary/attendance invariant
-- in one transaction. Ordinary sessions cannot activate this bypass because
-- the trigger also verifies the protected JWT claim.
create or replace function private.enforce_personal_diary_integrity()
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

  if private.catalog_event_integrity_bypass_allowed() then
    return new;
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

create or replace function private.protect_personal_diary_attendance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.catalog_event_integrity_bypass_allowed() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

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

create function public.review_catalog_event_merge(
  p_source_event_id uuid,
  p_target_event_id uuid
)
returns table (
  source_version integer,
  target_version integer,
  source_attendance_count bigint,
  target_attendance_count bigint,
  duplicate_attendance_count bigint,
  source_diary_count bigint,
  duplicate_diary_count bigint,
  source_post_count bigint,
  source_invitation_count bigint,
  can_merge boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.catalog_events%rowtype;
  v_target public.catalog_events%rowtype;
begin
  perform private.require_catalog_event_operator();
  select event.* into v_source
  from public.catalog_events as event
  where event.id = p_source_event_id and event.row_state = 'active';
  select event.* into v_target
  from public.catalog_events as event
  where event.id = p_target_event_id and event.row_state = 'active';

  if v_source.id is null or v_target.id is null or v_source.id = v_target.id then
    raise exception 'Merge review requires two different active events'
      using errcode = '22023';
  end if;

  return query
  select
    v_source.version,
    v_target.version,
    (select count(*) from public.catalog_event_attendance where event_id = v_source.id),
    (select count(*) from public.catalog_event_attendance where event_id = v_target.id),
    (
      select count(*)
      from public.catalog_event_attendance as source_attendance
      join public.catalog_event_attendance as target_attendance
        on target_attendance.event_id = v_target.id
        and target_attendance.profile_id = source_attendance.profile_id
      where source_attendance.event_id = v_source.id
    ),
    (
      select count(*) from public.concerts
      where catalog_event_id = v_source.id
        and record_model = 'personal_diary'
        and deletion_status = 'active'
    ),
    (
      select count(*)
      from public.concerts as source_diary
      join public.concerts as target_diary
        on target_diary.owner_id = source_diary.owner_id
        and target_diary.catalog_event_id = v_target.id
        and target_diary.record_model = 'personal_diary'
        and target_diary.deletion_status = 'active'
      where source_diary.catalog_event_id = v_source.id
        and source_diary.record_model = 'personal_diary'
        and source_diary.deletion_status = 'active'
    ),
    (select count(*) from public.catalog_event_posts where event_id = v_source.id),
    (select count(*) from public.catalog_event_invitations where event_id = v_source.id),
    not exists (
      select 1
      from public.concerts as source_diary
      join public.concerts as target_diary
        on target_diary.owner_id = source_diary.owner_id
        and target_diary.catalog_event_id = v_target.id
        and target_diary.record_model = 'personal_diary'
        and target_diary.deletion_status = 'active'
      where source_diary.catalog_event_id = v_source.id
        and source_diary.record_model = 'personal_diary'
        and source_diary.deletion_status = 'active'
    );
end;
$$;

create function public.merge_catalog_events(
  p_source_event_id uuid,
  p_target_event_id uuid,
  p_expected_source_version integer,
  p_expected_target_version integer,
  p_reason_code text default 'duplicate_event'
)
returns table (
  source_event_id uuid,
  target_event_id uuid,
  source_version integer,
  target_version integer,
  attendance_moved integer,
  attendance_superseded integer,
  diaries_moved integer,
  posts_moved integer,
  invitations_moved integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_operator_id uuid := private.require_catalog_event_operator();
  v_source public.catalog_events%rowtype;
  v_target public.catalog_events%rowtype;
  v_updated_source public.catalog_events%rowtype;
  v_updated_target public.catalog_events%rowtype;
  v_diary_ids uuid[];
  v_diaries_moved integer := 0;
  v_attendance_moved integer := 0;
  v_attendance_superseded integer := 0;
  v_posts_moved integer := 0;
  v_invitations_moved integer := 0;
  v_invitation_conflicts integer := 0;
begin
  if p_reason_code <> 'duplicate_event' then
    raise exception 'Event merges require the duplicate_event reason'
      using errcode = '22023';
  end if;
  if p_source_event_id is null
    or p_target_event_id is null
    or p_source_event_id = p_target_event_id
  then
    raise exception 'Merge requires two different events'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'catalog-event-integrity:' || least(p_source_event_id, p_target_event_id)::text,
      0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'catalog-event-integrity:' || greatest(p_source_event_id, p_target_event_id)::text,
      0
    )
  );

  select event.* into v_source
  from public.catalog_events as event
  where event.id = p_source_event_id
  for update;
  select event.* into v_target
  from public.catalog_events as event
  where event.id = p_target_event_id
  for update;

  if v_source.id is null or v_target.id is null
    or v_source.row_state <> 'active'
    or v_target.row_state <> 'active'
  then
    raise exception 'Merge requires two active events'
      using errcode = '22023';
  end if;
  if v_source.version <> p_expected_source_version
    or v_target.version <> p_expected_target_version
  then
    raise exception 'An event changed after review. Review the merge again.'
      using errcode = 'P0001';
  end if;
  if exists (
    select 1
    from public.concerts as source_diary
    join public.concerts as target_diary
      on target_diary.owner_id = source_diary.owner_id
      and target_diary.catalog_event_id = v_target.id
      and target_diary.record_model = 'personal_diary'
      and target_diary.deletion_status = 'active'
    where source_diary.catalog_event_id = v_source.id
      and source_diary.record_model = 'personal_diary'
      and source_diary.deletion_status = 'active'
  ) then
    raise exception 'Resolve duplicate personal diaries before merging these events'
      using errcode = 'P0001';
  end if;

  perform set_config('app.catalog_event_integrity_operator', v_operator_id::text, true);

  select coalesce(array_agg(diary.id), '{}'::uuid[])
  into v_diary_ids
  from public.concerts as diary
  where diary.catalog_event_id = v_source.id
    and diary.record_model = 'personal_diary'
    and diary.deletion_status = 'active';

  -- If both duplicate events contain attendance for a diary owner, Went wins
  -- and the least permissive audience is retained on the canonical row.
  update public.catalog_event_attendance as target_attendance
  set status = 'went',
      audience = case
        when target_attendance.audience = 'private'
          or source_attendance.audience = 'private' then 'private'::public.catalog_event_audience
        when target_attendance.audience = 'friends'
          or source_attendance.audience = 'friends' then 'friends'::public.catalog_event_audience
        else 'community'::public.catalog_event_audience
      end
  from public.catalog_event_attendance as source_attendance
  join public.concerts as source_diary
    on source_diary.attendance_id = source_attendance.id
    and source_diary.record_model = 'personal_diary'
    and source_diary.deletion_status = 'active'
  where source_attendance.event_id = v_source.id
    and target_attendance.event_id = v_target.id
    and target_attendance.profile_id = source_attendance.profile_id;

  update public.concerts as diary
  set catalog_event_id = v_target.id,
      attendance_id = coalesce(target_attendance.id, source_attendance.id),
      catalog_place_id = v_target.catalog_place_id,
      catalog_area_id = v_target.catalog_area_id,
      catalog_tour_id = v_target.catalog_tour_id,
      concert_date = v_target.event_date,
      starts_at = v_target.starts_at,
      venue_time_zone = case
        when v_target.starts_at is null then null else v_target.time_zone_identifier
      end,
      updated_at = clock_timestamp()
  from public.catalog_event_attendance as source_attendance
  left join public.catalog_event_attendance as target_attendance
    on target_attendance.event_id = v_target.id
    and target_attendance.profile_id = source_attendance.profile_id
  where diary.attendance_id = source_attendance.id
    and diary.id = any(v_diary_ids);
  get diagnostics v_diaries_moved = row_count;

  if cardinality(v_diary_ids) > 0 then
    delete from public.concert_artists as artist
    where artist.concert_id = any(v_diary_ids);

    insert into public.concert_artists (
      concert_id,
      lineup_position,
      artist_name,
      catalog_artist_id,
      is_primary
    )
    select
      diary_id,
      lineup.lineup_position,
      '',
      lineup.catalog_artist_id,
      lineup.is_headliner
    from unnest(v_diary_ids) as moved(diary_id)
    cross join public.catalog_event_artists as lineup
    where lineup.event_id = v_target.id;
  end if;

  update public.catalog_event_attendance as source_attendance
  set event_id = v_target.id
  where source_attendance.event_id = v_source.id
    and not exists (
      select 1
      from public.catalog_event_attendance as target_attendance
      where target_attendance.event_id = v_target.id
        and target_attendance.profile_id = source_attendance.profile_id
    );
  get diagnostics v_attendance_moved = row_count;

  update public.catalog_event_attendance as source_attendance
  set superseded_by_attendance_id = target_attendance.id,
      superseded_at = clock_timestamp()
  from public.catalog_event_attendance as target_attendance
  where source_attendance.event_id = v_source.id
    and target_attendance.event_id = v_target.id
    and target_attendance.profile_id = source_attendance.profile_id;
  get diagnostics v_attendance_superseded = row_count;

  update public.catalog_event_posts
  set event_id = v_target.id
  where event_id = v_source.id;
  get diagnostics v_posts_moved = row_count;

  update public.catalog_event_invitations as source_invitation
  set event_id = v_target.id
  where source_invitation.event_id = v_source.id
    and not exists (
      select 1
      from public.catalog_event_invitations as target_invitation
      where target_invitation.event_id = v_target.id
        and target_invitation.sender_id = source_invitation.sender_id
        and target_invitation.recipient_id = source_invitation.recipient_id
    );
  get diagnostics v_invitations_moved = row_count;

  update public.catalog_event_invitations as source_invitation
  set status = 'withdrawn',
      responded_at = coalesce(source_invitation.responded_at, clock_timestamp())
  where source_invitation.event_id = v_source.id
    and source_invitation.status = 'pending'
    and exists (
      select 1
      from public.catalog_event_invitations as target_invitation
      where target_invitation.event_id = v_target.id
        and target_invitation.sender_id = source_invitation.sender_id
        and target_invitation.recipient_id = source_invitation.recipient_id
    );
  get diagnostics v_invitation_conflicts = row_count;

  update private.catalog_event_notification_outbox
  set event_id = v_target.id
  where event_id = v_source.id;

  update public.catalog_events as event
  set row_state = 'merged',
      merged_into_event_id = v_target.id,
      version = event.version + 1,
      updated_at = clock_timestamp(),
      last_material_activity_at = clock_timestamp()
  where event.id = v_source.id
  returning event.* into v_updated_source;

  update public.catalog_events as event
  set integrity = case
        when event.integrity = 'disputed' then event.integrity
        else 'corroborated'::public.catalog_event_integrity
      end,
      version = event.version + 1,
      updated_at = clock_timestamp(),
      last_material_activity_at = clock_timestamp()
  where event.id = v_target.id
  returning event.* into v_updated_target;

  insert into private.catalog_event_revisions (
    event_id, changed_by, previous_version, next_version, old_snapshot, new_snapshot
  ) values
    (
      v_source.id, v_operator_id, v_source.version, v_updated_source.version,
      to_jsonb(v_source), to_jsonb(v_updated_source)
    ),
    (
      v_target.id, v_operator_id, v_target.version, v_updated_target.version,
      to_jsonb(v_target), to_jsonb(v_updated_target)
    );

  insert into private.catalog_event_integrity_operations (
    operation,
    operator_id,
    source_event_id,
    target_event_id,
    reason_code,
    record_snapshot
  ) values (
    'merge',
    v_operator_id,
    v_source.id,
    v_target.id,
    p_reason_code,
    jsonb_build_object(
      'source_before', to_jsonb(v_source),
      'target_before', to_jsonb(v_target),
      'attendance_moved', v_attendance_moved,
      'attendance_superseded', v_attendance_superseded,
      'diaries_moved', v_diaries_moved,
      'posts_moved', v_posts_moved,
      'invitations_moved', v_invitations_moved,
      'invitation_conflicts_withdrawn', v_invitation_conflicts
    )
  );

  return query select
    v_source.id,
    v_target.id,
    v_updated_source.version,
    v_updated_target.version,
    v_attendance_moved,
    v_attendance_superseded,
    v_diaries_moved,
    v_posts_moved,
    v_invitations_moved;
end;
$$;

create function public.tombstone_catalog_event(
  p_event_id uuid,
  p_expected_version integer,
  p_reason_code text
)
returns table (event_id uuid, version integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_operator_id uuid := private.require_catalog_event_operator();
  v_event public.catalog_events%rowtype;
  v_updated public.catalog_events%rowtype;
begin
  if p_reason_code not in ('invalid_event', 'legal_request', 'safety') then
    raise exception 'Choose a valid event tombstone reason'
      using errcode = '22023';
  end if;

  select event.* into v_event
  from public.catalog_events as event
  where event.id = p_event_id
  for update;
  if v_event.id is null or v_event.row_state <> 'active' then
    raise exception 'Only an active event can be tombstoned'
      using errcode = '22023';
  end if;
  if v_event.version <> p_expected_version then
    raise exception 'This event changed. Review the tombstone again.'
      using errcode = 'P0001';
  end if;

  update public.catalog_events as event
  set row_state = 'tombstoned',
      merged_into_event_id = null,
      version = event.version + 1,
      updated_at = clock_timestamp(),
      last_material_activity_at = clock_timestamp()
  where event.id = v_event.id
  returning event.* into v_updated;

  insert into private.catalog_event_revisions (
    event_id, changed_by, previous_version, next_version, old_snapshot, new_snapshot
  ) values (
    v_event.id,
    v_operator_id,
    v_event.version,
    v_updated.version,
    to_jsonb(v_event),
    to_jsonb(v_updated)
  );

  insert into private.catalog_event_integrity_operations (
    operation, operator_id, source_event_id, reason_code, record_snapshot
  ) values (
    'tombstone',
    v_operator_id,
    v_event.id,
    p_reason_code,
    jsonb_build_object(
      'event_before', private.catalog_event_history_projection_json(v_event.id),
      'attendance_count', (
        select count(*) from public.catalog_event_attendance as attendance
        where attendance.event_id = v_event.id
      ),
      'diary_count', (
        select count(*) from public.concerts as diary
        where diary.catalog_event_id = v_event.id
          and diary.record_model = 'personal_diary'
      )
    )
  );

  return query select v_event.id, v_updated.version;
end;
$$;

create function public.detach_personal_diary(
  p_diary_id uuid,
  p_reason_code text
)
returns table (diary_id uuid, detached_from_event_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_operator_id uuid := private.require_catalog_event_operator();
  v_diary public.concerts%rowtype;
  v_event_snapshot jsonb;
begin
  if p_reason_code not in ('legal_request', 'safety', 'privacy_request') then
    raise exception 'Choose a valid diary detachment reason'
      using errcode = '22023';
  end if;

  select diary.* into v_diary
  from public.concerts as diary
  where diary.id = p_diary_id
  for update;
  if v_diary.id is null
    or v_diary.record_model <> 'personal_diary'
    or v_diary.deletion_status <> 'active'
    or v_diary.catalog_event_id is null
  then
    raise exception 'Only an active linked personal diary can be detached'
      using errcode = '22023';
  end if;

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
  ) into v_event_snapshot
  from private.catalog_event_projections as projection
  where projection.event_id = v_diary.catalog_event_id;

  v_event_snapshot := coalesce(v_event_snapshot, '{}'::jsonb);

  update public.concerts as diary
  set catalog_event_id = null,
      detached_event_reason = p_reason_code,
      diary_audience = 'private',
      updated_at = clock_timestamp()
  where diary.id = v_diary.id;

  insert into private.catalog_event_integrity_operations (
    operation,
    operator_id,
    source_event_id,
    diary_id,
    reason_code,
    record_snapshot
  ) values (
    'diary_detach',
    v_operator_id,
    v_diary.catalog_event_id,
    v_diary.id,
    p_reason_code,
    jsonb_build_object(
      'event', v_event_snapshot,
      'attendance_id', v_diary.attendance_id,
      'owner_id', v_diary.owner_id,
      'previous_audience', v_diary.diary_audience,
      'published_at', v_diary.published_at
    )
  );

  return query select v_diary.id, v_diary.catalog_event_id;
end;
$$;

create function public.relink_personal_diary(
  p_diary_id uuid,
  p_target_event_id uuid,
  p_reason_code text default 'recovery'
)
returns table (diary_id uuid, event_id uuid, attendance_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_operator_id uuid := private.require_catalog_event_operator();
  v_diary public.concerts%rowtype;
  v_event public.catalog_events%rowtype;
  v_old_attendance public.catalog_event_attendance%rowtype;
  v_target_attendance public.catalog_event_attendance%rowtype;
  v_detachment private.catalog_event_integrity_operations%rowtype;
begin
  if p_reason_code not in ('incorrect_association', 'recovery') then
    raise exception 'Choose a valid diary relink reason'
      using errcode = '22023';
  end if;

  select diary.* into v_diary
  from public.concerts as diary
  where diary.id = p_diary_id
  for update;
  if v_diary.id is null
    or v_diary.record_model <> 'personal_diary'
    or v_diary.deletion_status <> 'active'
    or v_diary.catalog_event_id is not null
    or v_diary.detached_event_reason is null
  then
    raise exception 'Only a detached personal diary can be relinked'
      using errcode = '22023';
  end if;

  select operation.* into v_detachment
  from private.catalog_event_integrity_operations as operation
  where operation.diary_id = v_diary.id
    and operation.operation = 'diary_detach'
  order by operation.created_at desc, operation.id desc
  limit 1;
  if v_detachment.id is null then
    raise exception 'The diary detachment audit is missing'
      using errcode = 'P0001';
  end if;

  select event.* into v_event
  from public.catalog_events as event
  where event.id = private.resolve_catalog_event_id(p_target_event_id)
  for update;
  if v_event.id is null or v_event.row_state <> 'active' then
    raise exception 'Relink requires an active target event'
      using errcode = '22023';
  end if;
  if v_event.lifecycle = 'cancelled'
    or (
      v_event.lifecycle <> 'completed'
      and v_event.memory_unlock_at > clock_timestamp()
    )
  then
    raise exception 'Relink requires a completed occurrence'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.concerts as existing
    where existing.owner_id = v_diary.owner_id
      and existing.catalog_event_id = v_event.id
      and existing.record_model = 'personal_diary'
      and existing.deletion_status = 'active'
      and existing.id <> v_diary.id
  ) then
    raise exception 'The diary owner already has a diary for the target event'
      using errcode = 'P0001';
  end if;

  select attendance.* into v_old_attendance
  from public.catalog_event_attendance as attendance
  where attendance.id = v_diary.attendance_id
  for update;
  select attendance.* into v_target_attendance
  from public.catalog_event_attendance as attendance
  where attendance.event_id = v_event.id
    and attendance.profile_id = v_diary.owner_id
  for update;

  perform set_config('app.catalog_event_integrity_operator', v_operator_id::text, true);

  if v_target_attendance.id is null then
    update public.catalog_event_attendance as attendance
    set event_id = v_event.id,
        superseded_by_attendance_id = null,
        superseded_at = null
    where attendance.id = v_old_attendance.id
    returning attendance.* into v_target_attendance;
  else
    if v_target_attendance.status <> 'went' then
      update public.catalog_event_attendance as attendance
      set status = 'went',
          audience = case
            when attendance.audience = 'private'
              or v_old_attendance.audience = 'private' then 'private'::public.catalog_event_audience
            when attendance.audience = 'friends'
              or v_old_attendance.audience = 'friends' then 'friends'::public.catalog_event_audience
            else 'community'::public.catalog_event_audience
          end
      where attendance.id = v_target_attendance.id
      returning attendance.* into v_target_attendance;
    end if;

    if v_old_attendance.id <> v_target_attendance.id then
      update public.catalog_event_attendance
      set superseded_by_attendance_id = v_target_attendance.id,
          superseded_at = clock_timestamp()
      where id = v_old_attendance.id;
    end if;
  end if;

  update public.concerts as diary
  set catalog_event_id = v_event.id,
      attendance_id = v_target_attendance.id,
      detached_event_reason = null,
      catalog_place_id = v_event.catalog_place_id,
      catalog_area_id = v_event.catalog_area_id,
      catalog_tour_id = v_event.catalog_tour_id,
      concert_date = v_event.event_date,
      starts_at = v_event.starts_at,
      venue_time_zone = case
        when v_event.starts_at is null then null else v_event.time_zone_identifier
      end,
      updated_at = clock_timestamp()
  where diary.id = v_diary.id;

  delete from public.concert_artists as artist
  where artist.concert_id = v_diary.id;
  insert into public.concert_artists (
    concert_id, lineup_position, artist_name, catalog_artist_id, is_primary
  )
  select
    v_diary.id,
    lineup.lineup_position,
    '',
    lineup.catalog_artist_id,
    lineup.is_headliner
  from public.catalog_event_artists as lineup
  where lineup.event_id = v_event.id;

  update public.catalog_events
  set last_material_activity_at = clock_timestamp()
  where id = v_event.id;

  insert into private.catalog_event_integrity_operations (
    operation,
    operator_id,
    source_event_id,
    target_event_id,
    diary_id,
    reason_code,
    record_snapshot
  ) values (
    'diary_relink',
    v_operator_id,
    v_detachment.source_event_id,
    v_event.id,
    v_diary.id,
    p_reason_code,
    jsonb_build_object(
      'detachment_operation_id', v_detachment.id,
      'previous_attendance_id', v_old_attendance.id,
      'target_attendance_id', v_target_attendance.id,
      'target_event', private.catalog_event_projection_json(v_event.id)
    )
  );

  return query select v_diary.id, v_event.id, v_target_attendance.id;
end;
$$;

-- Event cards used by activity and profile history resolve merged IDs while a
-- separate history helper falls back to an exact tombstoned snapshot.
create or replace function private.catalog_event_projection_json(p_event_id uuid)
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
  where projection.event_id = private.resolve_catalog_event_id(p_event_id)
$$;

create function private.catalog_event_history_projection_json(p_event_id uuid)
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
  where projection.event_id = coalesce(
    private.resolve_catalog_event_id(p_event_id),
    p_event_id
  )
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
      and (
        v_caller_id = attendance.profile_id
        or (
          not private.has_relationship_block(v_caller_id, attendance.profile_id)
          and (
            attendance.audience = 'community'
            or (
              attendance.audience = 'friends'
              and private.are_accepted_friends(v_caller_id, attendance.profile_id)
            )
          )
        )
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
  left join public.concerts as diary
    on diary.id = activity.subject_id
    and diary.record_model = 'personal_diary'
  where activity.actor_id <> v_caller_id
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
        and diary.catalog_event_id = canonical.event_id
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

revoke all on table private.catalog_event_integrity_operations
  from public, anon, authenticated;
revoke all on function private.prevent_catalog_event_integrity_audit_mutation()
  from public, anon, authenticated;
revoke all on function private.is_catalog_event_operator()
  from public, anon, authenticated;
revoke all on function private.require_catalog_event_operator()
  from public, anon, authenticated;
revoke all on function private.catalog_event_integrity_bypass_allowed()
  from public, anon, authenticated;
revoke all on function private.catalog_event_history_projection_json(uuid)
  from public, anon, authenticated;

revoke all on function public.review_catalog_event_merge(uuid, uuid)
  from public, anon;
revoke all on function public.merge_catalog_events(uuid, uuid, integer, integer, text)
  from public, anon;
revoke all on function public.tombstone_catalog_event(uuid, integer, text)
  from public, anon;
revoke all on function public.detach_personal_diary(uuid, text)
  from public, anon;
revoke all on function public.relink_personal_diary(uuid, uuid, text)
  from public, anon;

grant execute on function public.review_catalog_event_merge(uuid, uuid)
  to authenticated;
grant execute on function public.merge_catalog_events(uuid, uuid, integer, integer, text)
  to authenticated;
grant execute on function public.tombstone_catalog_event(uuid, integer, text)
  to authenticated;
grant execute on function public.detach_personal_diary(uuid, text)
  to authenticated;
grant execute on function public.relink_personal_diary(uuid, uuid, text)
  to authenticated;

revoke all on function private.enforce_personal_diary_integrity()
  from public, anon, authenticated;
revoke all on function private.protect_personal_diary_attendance()
  from public, anon, authenticated;
revoke all on function private.catalog_event_projection_json(uuid)
  from public, anon, authenticated;

-- Authenticated read RPCs call the volatile completed-caller guard and must not
-- advertise a stronger volatility contract to the planner.
alter function public.get_catalog_event_diary_summaries(uuid[]) volatile;
alter function public.list_catalog_event_diaries(uuid, text, jsonb, integer) volatile;
