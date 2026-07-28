-- Ticketmaster ingestion is deliberately backend-only in this release.
-- Development and Staging install the production schedules inactive and use
-- the protected manual workflow until the catalog output has been verified.

create extension if not exists pgmq;
create extension if not exists pg_net with schema extensions;

select pgmq.create('ticketmaster_ingestion');
select pgmq.create('ticketmaster_ingestion_dead_letter');

create table private.ticketmaster_ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'queued' check (
    status in (
      'queued',
      'running',
      'completed',
      'completed_with_rejections',
      'failed'
    )
  ),
  city text not null default 'San Francisco' check (city = 'San Francisco'),
  state_code text not null default 'CA' check (state_code = 'CA'),
  country_code text not null default 'US' check (country_code = 'US'),
  time_zone_identifier text not null default 'America/Los_Angeles' check (
    time_zone_identifier = 'America/Los_Angeles'
  ),
  coverage_starts_at timestamptz not null,
  coverage_ends_at timestamptz not null,
  upstream_total_elements integer check (
    upstream_total_elements is null or upstream_total_elements >= 0
  ),
  upstream_total_pages integer check (
    upstream_total_pages is null or upstream_total_pages between 0 and 50
  ),
  pages_completed integer not null default 0 check (pages_completed >= 0),
  raw_events_received integer not null default 0 check (raw_events_received >= 0),
  valid_events_received integer not null default 0 check (valid_events_received >= 0),
  rejected_events integer not null default 0 check (rejected_events >= 0),
  unique_events_seen integer not null default 0 check (unique_events_seen >= 0),
  events_inserted integer not null default 0 check (events_inserted >= 0),
  events_updated integer not null default 0 check (events_updated >= 0),
  events_unchanged integer not null default 0 check (events_unchanged >= 0),
  events_unlisted integer not null default 0 check (events_unlisted >= 0),
  last_error_code text check (
    last_error_code is null or last_error_code ~ '^[a-z][a-z0-9_]{0,63}$'
  ),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  constraint ticketmaster_ingestion_run_window_check check (
    (coverage_starts_at at time zone 'America/Los_Angeles')::time = time '00:00'
    and (coverage_ends_at at time zone 'America/Los_Angeles')::time = time '00:00'
    and (coverage_ends_at at time zone 'America/Los_Angeles')::date
      = (coverage_starts_at at time zone 'America/Los_Angeles')::date + 14
  ),
  constraint ticketmaster_ingestion_run_timestamps_check check (
    (status = 'queued' and started_at is null and completed_at is null)
    or (status = 'running' and started_at is not null and completed_at is null)
    or (
      status in ('completed', 'completed_with_rejections', 'failed')
      and started_at is not null
      and completed_at is not null
      and completed_at >= started_at
    )
  )
);

create unique index ticketmaster_ingestion_one_active_window
  on private.ticketmaster_ingestion_runs (
    city,
    state_code,
    country_code,
    coverage_starts_at,
    coverage_ends_at
  )
  where status in ('queued', 'running');

create index ticketmaster_ingestion_runs_created
  on private.ticketmaster_ingestion_runs (created_at desc);

create table private.ticketmaster_ingestion_pages (
  run_id uuid not null
    references private.ticketmaster_ingestion_runs (id) on delete cascade,
  page_number integer not null check (page_number between 0 and 49),
  queue_message_id bigint unique,
  status text not null default 'queued' check (
    status in ('queued', 'processing', 'completed', 'failed')
  ),
  attempt_count integer not null default 0 check (attempt_count between 0 and 5),
  raw_event_count integer check (raw_event_count is null or raw_event_count between 0 and 20),
  valid_event_count integer check (valid_event_count is null or valid_event_count between 0 and 20),
  rejected_event_count integer check (
    rejected_event_count is null or rejected_event_count between 0 and 20
  ),
  last_error_code text check (
    last_error_code is null or last_error_code ~ '^[a-z][a-z0-9_]{0,63}$'
  ),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  primary key (run_id, page_number),
  constraint ticketmaster_ingestion_page_counts_check check (
    raw_event_count is null
    or (
      valid_event_count is not null
      and rejected_event_count is not null
      and raw_event_count = valid_event_count + rejected_event_count
    )
  )
);

create table private.ticketmaster_event_observations (
  run_id uuid not null
    references private.ticketmaster_ingestion_runs (id) on delete cascade,
  catalog_event_id uuid not null
    references public.catalog_events (id) on delete cascade,
  external_event_id text not null check (
    char_length(external_event_id) between 1 and 200
    and not private.contains_control_characters(external_event_id)
  ),
  observed_at timestamptz not null default clock_timestamp(),
  primary key (run_id, external_event_id),
  unique (run_id, catalog_event_id)
);

create index ticketmaster_event_observations_event
  on private.ticketmaster_event_observations (catalog_event_id, observed_at desc);

create table private.ticketmaster_catalog_events (
  event_id uuid primary key
    references public.catalog_events (id) on delete cascade,
  external_event_id text not null unique check (
    char_length(external_event_id) between 1 and 200
    and not private.contains_control_characters(external_event_id)
  ),
  payload_hash text check (payload_hash is null or payload_hash ~ '^[a-f0-9]{32}$'),
  last_seen_run_id uuid
    references private.ticketmaster_ingestion_runs (id) on delete set null,
  last_seen_at timestamptz not null default clock_timestamp(),
  last_material_update_at timestamptz
);

create index ticketmaster_catalog_events_last_seen_run
  on private.ticketmaster_catalog_events (last_seen_run_id)
  where last_seen_run_id is not null;

insert into private.ticketmaster_catalog_events (
  event_id,
  external_event_id,
  last_seen_at,
  last_material_update_at
)
select
  source.event_id,
  source.external_event_id,
  source.last_refreshed_at,
  source.last_refreshed_at
from private.catalog_event_sources as source
where source.provider_key = 'ticketmaster'
on conflict (external_event_id) do nothing;

create function private.enqueue_ticketmaster_ingestion_page(
  p_run_id uuid,
  p_page_number integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message_id bigint;
begin
  if p_run_id is null or p_page_number not between 0 and 49 then
    raise exception 'Ticketmaster ingestion page is invalid' using errcode = '22023';
  end if;

  insert into private.ticketmaster_ingestion_pages (run_id, page_number)
  values (p_run_id, p_page_number)
  on conflict (run_id, page_number) do nothing;

  select message_id into v_message_id
  from pgmq.send(
    'ticketmaster_ingestion',
    jsonb_build_object(
      'schema_version', 1,
      'run_id', p_run_id,
      'page', p_page_number
    )
  ) as message_id;

  update private.ticketmaster_ingestion_pages
  set queue_message_id = v_message_id,
      status = 'queued',
      last_error_code = null
  where run_id = p_run_id
    and page_number = p_page_number
    and queue_message_id is null;

  if not found then
    perform pgmq.delete('ticketmaster_ingestion', v_message_id);
    select queue_message_id into v_message_id
    from private.ticketmaster_ingestion_pages
    where run_id = p_run_id and page_number = p_page_number;
  end if;

  return v_message_id;
end;
$$;

create function public.start_ticketmaster_ingestion(
  p_requested_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requested_at timestamptz := coalesce(p_requested_at, clock_timestamp());
  v_local_date date;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_run_id uuid;
begin
  if v_requested_at < timestamptz '2020-01-01 00:00:00+00'
    or v_requested_at > clock_timestamp() + interval '1 day'
  then
    raise exception 'Ticketmaster ingestion time is invalid' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('ticketmaster-ingestion:start', 0)
  );

  v_local_date := (v_requested_at at time zone 'America/Los_Angeles')::date;
  v_starts_at := v_local_date::timestamp at time zone 'America/Los_Angeles';
  v_ends_at := (v_local_date + 14)::timestamp at time zone 'America/Los_Angeles';

  select run.id into v_run_id
  from private.ticketmaster_ingestion_runs as run
  where run.coverage_starts_at = v_starts_at
    and run.coverage_ends_at = v_ends_at
    and run.status in ('queued', 'running')
  order by run.created_at desc
  limit 1
  for update;

  if v_run_id is not null then
    return v_run_id;
  end if;

  insert into private.ticketmaster_ingestion_runs (
    coverage_starts_at,
    coverage_ends_at
  ) values (
    v_starts_at,
    v_ends_at
  )
  returning id into v_run_id;

  perform private.enqueue_ticketmaster_ingestion_page(v_run_id, 0);
  return v_run_id;
end;
$$;

create function public.claim_ticketmaster_ingestion_tasks(
  p_limit integer default 1,
  p_visibility_seconds integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message record;
  v_run private.ticketmaster_ingestion_runs%rowtype;
  v_page_number integer;
  v_run_id uuid;
  v_results jsonb := '[]'::jsonb;
begin
  if p_limit not between 1 and 10 or p_visibility_seconds not between 30 and 600 then
    raise exception 'Ticketmaster ingestion claim is invalid' using errcode = '22023';
  end if;

  for v_message in
    select * from pgmq.read('ticketmaster_ingestion', p_visibility_seconds, p_limit)
  loop
    begin
      if v_message.message ->> 'schema_version' <> '1'
        or jsonb_typeof(v_message.message -> 'page') <> 'number'
      then
        raise exception 'Invalid queue message';
      end if;
      v_run_id := (v_message.message ->> 'run_id')::uuid;
      v_page_number := (v_message.message ->> 'page')::integer;
    exception when others then
      perform pgmq.delete('ticketmaster_ingestion', v_message.msg_id);
      perform pgmq.send(
        'ticketmaster_ingestion_dead_letter',
        jsonb_build_object(
          'schema_version', 1,
          'original_message', v_message.message,
          'error_code', 'invalid_queue_message',
          'failed_at', clock_timestamp()
        )
      );
      continue;
    end;

    select * into v_run
    from private.ticketmaster_ingestion_runs
    where id = v_run_id
    for update;

    if not found
      or v_run.status in ('completed', 'completed_with_rejections', 'failed')
      or v_page_number not between 0 and 49
    then
      perform pgmq.delete('ticketmaster_ingestion', v_message.msg_id);
      continue;
    end if;

    update private.ticketmaster_ingestion_pages
    set status = 'processing',
        attempt_count = least(v_message.read_ct::integer, 5),
        started_at = coalesce(started_at, clock_timestamp())
    where run_id = v_run_id
      and page_number = v_page_number
      and queue_message_id = v_message.msg_id
      and status in ('queued', 'processing');

    if not found then
      perform pgmq.delete('ticketmaster_ingestion', v_message.msg_id);
      continue;
    end if;

    update private.ticketmaster_ingestion_runs
    set status = 'running',
        started_at = coalesce(started_at, clock_timestamp())
    where id = v_run_id and status = 'queued';

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'message_id', v_message.msg_id,
      'read_count', v_message.read_ct,
      'run_id', v_run_id,
      'page', v_page_number,
      'city', v_run.city,
      'state_code', v_run.state_code,
      'country_code', v_run.country_code,
      'coverage_starts_at', v_run.coverage_starts_at,
      'coverage_ends_at', v_run.coverage_ends_at
    ));
  end loop;

  return v_results;
end;
$$;

create function public.complete_ticketmaster_ingestion_page(
  p_message_id bigint,
  p_run_id uuid,
  p_page_number integer,
  p_events jsonb,
  p_raw_event_count integer,
  p_rejected_event_count integer,
  p_total_elements integer,
  p_total_pages integer,
  p_has_more boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.ticketmaster_ingestion_runs%rowtype;
  v_event jsonb;
  v_external_event_id text;
  v_payload_hash text;
  v_existing_event_id uuid;
  v_existing_hash text;
  v_existing_catalog_event public.catalog_events%rowtype;
  v_catalog_event_id uuid;
  v_valid_count integer;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_next_message_id bigint;
  v_unlisted integer := 0;
  v_final_status text;
begin
  if p_message_id is null
    or p_run_id is null
    or p_page_number not between 0 and 49
    or p_events is null
    or jsonb_typeof(p_events) <> 'array'
    or jsonb_array_length(p_events) > 20
    or p_raw_event_count is null
    or p_raw_event_count not between 0 and 20
    or p_rejected_event_count is null
    or p_rejected_event_count not between 0 and p_raw_event_count
    or p_total_elements is null
    or p_total_elements not between 0 and 1000
    or p_total_pages is null
    or p_total_pages not between 0 and 50
    or p_has_more is null
  then
    raise exception 'Ticketmaster ingestion result is invalid' using errcode = '22023';
  end if;

  v_valid_count := jsonb_array_length(p_events);
  if v_valid_count + p_rejected_event_count <> p_raw_event_count
    or (p_has_more and p_page_number + 1 >= p_total_pages)
    or (not p_has_more and p_total_pages > 0 and p_page_number + 1 <> p_total_pages)
  then
    raise exception 'Ticketmaster ingestion pagination is inconsistent' using errcode = '22023';
  end if;

  select * into v_run
  from private.ticketmaster_ingestion_runs
  where id = p_run_id
  for update;

  if not found or v_run.status not in ('queued', 'running') then
    raise exception 'Ticketmaster ingestion run is unavailable' using errcode = 'P0002';
  end if;

  perform 1
  from private.ticketmaster_ingestion_pages
  where run_id = p_run_id
    and page_number = p_page_number
    and queue_message_id = p_message_id
    and status = 'processing'
  for update;
  if not found then
    raise exception 'Ticketmaster ingestion page is unavailable' using errcode = 'P0002';
  end if;

  for v_event in
    select item.value
    from jsonb_array_elements(p_events) as item(value)
  loop
    v_external_event_id := v_event ->> 'event_id';
    if v_external_event_id is null
      or char_length(v_external_event_id) not between 1 and 200
      or private.contains_control_characters(v_external_event_id)
    then
      raise exception 'Ticketmaster event identity is invalid' using errcode = '22023';
    end if;

    if exists (
      select 1
      from private.ticketmaster_event_observations
      where run_id = p_run_id and external_event_id = v_external_event_id
    ) then
      raise exception 'Ticketmaster page contains a duplicate event' using errcode = '22023';
    end if;

    v_payload_hash := pg_catalog.md5(v_event::text);
    select source.event_id, link.payload_hash
    into v_existing_event_id, v_existing_hash
    from private.catalog_event_sources as source
    left join private.ticketmaster_catalog_events as link
      on link.external_event_id = source.external_event_id
    where source.provider_key = 'ticketmaster'
      and source.external_event_id = v_external_event_id
    for update of source;

    if v_existing_event_id is not null and v_existing_hash = v_payload_hash then
      v_catalog_event_id := v_existing_event_id;
      v_unchanged := v_unchanged + 1;
      update private.catalog_event_sources
      set last_refreshed_at = clock_timestamp()
      where provider_key = 'ticketmaster'
        and external_event_id = v_external_event_id;
    else
      if v_existing_event_id is not null then
        select * into v_existing_catalog_event
        from public.catalog_events
        where id = v_existing_event_id
        for update;
      end if;
      v_catalog_event_id := public.upsert_ticketmaster_catalog_event(v_event);
      if v_existing_event_id is not null
        and v_event -> 'image_url' = 'null'::jsonb
      then
        update public.catalog_events
        set cover_source = v_existing_catalog_event.cover_source,
            cover_object_path = v_existing_catalog_event.cover_object_path,
            cover_remote_url = v_existing_catalog_event.cover_remote_url,
            cover_provider_name = v_existing_catalog_event.cover_provider_name,
            cover_attribution = v_existing_catalog_event.cover_attribution,
            cover_source_page_url = v_existing_catalog_event.cover_source_page_url,
            cover_license_name = v_existing_catalog_event.cover_license_name,
            cover_license_url = v_existing_catalog_event.cover_license_url,
            cover_version = v_existing_catalog_event.cover_version
        where id = v_catalog_event_id;
      end if;
      if v_existing_event_id is null then
        v_inserted := v_inserted + 1;
      else
        v_updated := v_updated + 1;
      end if;
    end if;

    insert into private.ticketmaster_catalog_events (
      event_id,
      external_event_id,
      payload_hash,
      last_seen_run_id,
      last_seen_at,
      last_material_update_at
    ) values (
      v_catalog_event_id,
      v_external_event_id,
      v_payload_hash,
      p_run_id,
      clock_timestamp(),
      case
        when v_existing_event_id is null or v_existing_hash is distinct from v_payload_hash
          then clock_timestamp()
        else null
      end
    ) on conflict (external_event_id) do update
    set event_id = excluded.event_id,
        payload_hash = excluded.payload_hash,
        last_seen_run_id = excluded.last_seen_run_id,
        last_seen_at = excluded.last_seen_at,
        last_material_update_at = coalesce(
          excluded.last_material_update_at,
          private.ticketmaster_catalog_events.last_material_update_at
        );

    insert into private.ticketmaster_event_observations (
      run_id,
      catalog_event_id,
      external_event_id
    ) values (
      p_run_id,
      v_catalog_event_id,
      v_external_event_id
    );
  end loop;

  update private.ticketmaster_ingestion_pages
  set status = 'completed',
      raw_event_count = p_raw_event_count,
      valid_event_count = v_valid_count,
      rejected_event_count = p_rejected_event_count,
      last_error_code = null,
      completed_at = clock_timestamp()
  where run_id = p_run_id and page_number = p_page_number;

  update private.ticketmaster_ingestion_runs
  set status = 'running',
      started_at = coalesce(started_at, clock_timestamp()),
      upstream_total_elements = case
        when upstream_total_elements is null then p_total_elements
        else greatest(upstream_total_elements, p_total_elements)
      end,
      upstream_total_pages = case
        when upstream_total_pages is null then p_total_pages
        else greatest(upstream_total_pages, p_total_pages)
      end,
      pages_completed = pages_completed + 1,
      raw_events_received = raw_events_received + p_raw_event_count,
      valid_events_received = valid_events_received + v_valid_count,
      rejected_events = rejected_events + p_rejected_event_count,
      unique_events_seen = unique_events_seen + v_valid_count,
      events_inserted = events_inserted + v_inserted,
      events_updated = events_updated + v_updated,
      events_unchanged = events_unchanged + v_unchanged,
      last_error_code = null
  where id = p_run_id;

  if not pgmq.delete('ticketmaster_ingestion', p_message_id) then
    raise exception 'Ticketmaster queue acknowledgement failed' using errcode = 'P0002';
  end if;

  if p_has_more then
    v_next_message_id := private.enqueue_ticketmaster_ingestion_page(
      p_run_id,
      p_page_number + 1
    );
  else
    select * into v_run
    from private.ticketmaster_ingestion_runs
    where id = p_run_id
    for update;

    if v_run.rejected_events = 0 then
      update public.catalog_events as event
      set listing = 'unlisted',
          version = version + 1,
          updated_at = clock_timestamp(),
          last_material_activity_at = clock_timestamp()
      where event.origin = 'ticketmaster'
        and event.row_state = 'active'
        and event.listing = 'listed'
        and event.area_name_snapshot = 'San Francisco'
        and event.event_date >= (v_run.coverage_starts_at at time zone 'America/Los_Angeles')::date
        and event.event_date < (v_run.coverage_ends_at at time zone 'America/Los_Angeles')::date
        and not exists (
          select 1
          from private.ticketmaster_event_observations as observation
          where observation.run_id = p_run_id
            and observation.catalog_event_id = event.id
        );
      get diagnostics v_unlisted = row_count;
      v_final_status := 'completed';
    else
      v_final_status := 'completed_with_rejections';
    end if;

    update private.ticketmaster_ingestion_runs
    set status = v_final_status,
        events_unlisted = v_unlisted,
        completed_at = clock_timestamp()
    where id = p_run_id;
  end if;

  return jsonb_build_object(
    'run_id', p_run_id,
    'page', p_page_number,
    'has_more', p_has_more,
    'next_message_id', v_next_message_id,
    'inserted', v_inserted,
    'updated', v_updated,
    'unchanged', v_unchanged
  );
end;
$$;

create function public.fail_ticketmaster_ingestion_task(
  p_message_id bigint,
  p_error_code text,
  p_retryable boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_page private.ticketmaster_ingestion_pages%rowtype;
  v_delay_seconds integer;
begin
  if p_message_id is null
    or p_error_code is null
    or p_error_code !~ '^[a-z][a-z0-9_]{0,63}$'
    or p_retryable is null
  then
    raise exception 'Ticketmaster ingestion failure is invalid' using errcode = '22023';
  end if;

  select page.* into v_page
  from private.ticketmaster_ingestion_pages as page
  where page.queue_message_id = p_message_id
  for update;

  if not found or v_page.status <> 'processing' then
    raise exception 'Ticketmaster ingestion task is unavailable' using errcode = 'P0002';
  end if;

  if p_retryable and v_page.attempt_count < 5 then
    v_delay_seconds := least(60 * (2 ^ greatest(v_page.attempt_count - 1, 0))::integer, 900);
    perform pgmq.set_vt('ticketmaster_ingestion', p_message_id, v_delay_seconds);
    update private.ticketmaster_ingestion_pages
    set status = 'queued',
        last_error_code = p_error_code
    where run_id = v_page.run_id and page_number = v_page.page_number;
    update private.ticketmaster_ingestion_runs
    set last_error_code = p_error_code
    where id = v_page.run_id;
    return jsonb_build_object(
      'outcome', 'retry',
      'delay_seconds', v_delay_seconds,
      'attempt_count', v_page.attempt_count
    );
  end if;

  perform pgmq.delete('ticketmaster_ingestion', p_message_id);
  perform pgmq.send(
    'ticketmaster_ingestion_dead_letter',
    jsonb_build_object(
      'schema_version', 1,
      'original_message', jsonb_build_object(
        'schema_version', 1,
        'run_id', v_page.run_id,
        'page', v_page.page_number
      ),
      'error_code', p_error_code,
      'attempt_count', v_page.attempt_count,
      'failed_at', clock_timestamp()
    )
  );

  update private.ticketmaster_ingestion_pages
  set status = 'failed',
      last_error_code = p_error_code,
      completed_at = clock_timestamp()
  where run_id = v_page.run_id and page_number = v_page.page_number;
  update private.ticketmaster_ingestion_runs
  set status = 'failed',
      last_error_code = p_error_code,
      started_at = coalesce(started_at, clock_timestamp()),
      completed_at = clock_timestamp()
  where id = v_page.run_id;

  return jsonb_build_object(
    'outcome', 'dead_letter',
    'attempt_count', v_page.attempt_count
  );
end;
$$;

create function public.get_ticketmaster_ingestion_status(p_run_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.ticketmaster_ingestion_runs%rowtype;
  v_queue record;
  v_dead_letter record;
begin
  if p_run_id is null then
    select * into v_run
    from private.ticketmaster_ingestion_runs
    order by created_at desc
    limit 1;
  else
    select * into v_run
    from private.ticketmaster_ingestion_runs
    where id = p_run_id;
  end if;

  select * into v_queue from pgmq.metrics('ticketmaster_ingestion');
  select * into v_dead_letter from pgmq.metrics('ticketmaster_ingestion_dead_letter');

  if v_run.id is null then
    return jsonb_build_object(
      'run', null,
      'queue_depth', v_queue.queue_length,
      'dead_letter_depth', v_dead_letter.queue_length
    );
  end if;

  return jsonb_build_object(
    'run', jsonb_build_object(
      'id', v_run.id,
      'status', v_run.status,
      'city', v_run.city,
      'state_code', v_run.state_code,
      'country_code', v_run.country_code,
      'coverage_starts_at', v_run.coverage_starts_at,
      'coverage_ends_at', v_run.coverage_ends_at,
      'upstream_total_elements', v_run.upstream_total_elements,
      'upstream_total_pages', v_run.upstream_total_pages,
      'pages_completed', v_run.pages_completed,
      'raw_events_received', v_run.raw_events_received,
      'valid_events_received', v_run.valid_events_received,
      'rejected_events', v_run.rejected_events,
      'unique_events_seen', v_run.unique_events_seen,
      'events_inserted', v_run.events_inserted,
      'events_updated', v_run.events_updated,
      'events_unchanged', v_run.events_unchanged,
      'events_unlisted', v_run.events_unlisted,
      'last_error_code', v_run.last_error_code,
      'started_at', v_run.started_at,
      'completed_at', v_run.completed_at,
      'created_at', v_run.created_at
    ),
    'queue_depth', v_queue.queue_length,
    'dead_letter_depth', v_dead_letter.queue_length,
    'pages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'page', page.page_number,
        'status', page.status,
        'attempt_count', page.attempt_count,
        'raw_event_count', page.raw_event_count,
        'valid_event_count', page.valid_event_count,
        'rejected_event_count', page.rejected_event_count,
        'last_error_code', page.last_error_code,
        'started_at', page.started_at,
        'completed_at', page.completed_at
      ) order by page.page_number)
      from private.ticketmaster_ingestion_pages as page
      where page.run_id = v_run.id
    ), '[]'::jsonb)
  );
end;
$$;

create function private.invoke_ticketmaster_ingestion_worker()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_url text;
  v_service_role_key text;
  v_request_id bigint;
begin
  begin
    execute $query$
      select
        max(decrypted_secret) filter (
          where name = 'ticketmaster_ingestion_project_url'
        ),
        max(decrypted_secret) filter (
          where name = 'ticketmaster_ingestion_service_role_key'
        )
      from vault.decrypted_secrets
    $query$
    into v_project_url, v_service_role_key;
  exception when undefined_table or invalid_schema_name then
    return null;
  end;

  if v_project_url is null
    or v_project_url !~ '^https://[a-z]+[.]supabase[.]co$'
    or v_service_role_key is null
    or char_length(v_service_role_key) > 16384
  then
    return null;
  end if;

  select net.http_post(
    url := v_project_url || '/functions/v1/ticketmaster-ingestion',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_role_key,
      'apikey', v_service_role_key,
      'Content-Type', 'application/json'
    ),
    body := '{"operation":"resume"}'::jsonb,
    timeout_milliseconds := 5000
  ) into v_request_id;
  return v_request_id;
end;
$$;

select cron.schedule(
  'ticketmaster-ingestion-daily',
  '15 12 * * *',
  $$select public.start_ticketmaster_ingestion();$$
);
select cron.alter_job(
  (select jobid from cron.job where jobname = 'ticketmaster-ingestion-daily'),
  active := false
);

select cron.schedule(
  'ticketmaster-ingestion-worker',
  '*/5 * * * *',
  $$select private.invoke_ticketmaster_ingestion_worker();$$
);
select cron.alter_job(
  (select jobid from cron.job where jobname = 'ticketmaster-ingestion-worker'),
  active := false
);

revoke all on table private.ticketmaster_ingestion_runs,
  private.ticketmaster_ingestion_pages,
  private.ticketmaster_event_observations,
  private.ticketmaster_catalog_events
  from public, anon, authenticated;

revoke all on function private.enqueue_ticketmaster_ingestion_page(uuid, integer)
  from public, anon, authenticated;
revoke all on function private.invoke_ticketmaster_ingestion_worker()
  from public, anon, authenticated;
revoke all on function public.start_ticketmaster_ingestion(timestamptz)
  from public, anon, authenticated;
revoke all on function public.claim_ticketmaster_ingestion_tasks(integer, integer)
  from public, anon, authenticated;
revoke all on function public.complete_ticketmaster_ingestion_page(
  bigint, uuid, integer, jsonb, integer, integer, integer, integer, boolean
) from public, anon, authenticated;
revoke all on function public.fail_ticketmaster_ingestion_task(bigint, text, boolean)
  from public, anon, authenticated;
revoke all on function public.get_ticketmaster_ingestion_status(uuid)
  from public, anon, authenticated;

grant execute on function public.start_ticketmaster_ingestion(timestamptz) to service_role;
grant execute on function public.claim_ticketmaster_ingestion_tasks(integer, integer)
  to service_role;
grant execute on function public.complete_ticketmaster_ingestion_page(
  bigint, uuid, integer, jsonb, integer, integer, integer, integer, boolean
) to service_role;
grant execute on function public.fail_ticketmaster_ingestion_task(bigint, text, boolean)
  to service_role;
grant execute on function public.get_ticketmaster_ingestion_status(uuid) to service_role;
