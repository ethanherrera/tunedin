-- Retain a bounded, sanitized explanation for every provider record rejected
-- by the ingestion decoder. Raw Ticketmaster payloads and credentials remain
-- intentionally absent; this table exists so operators and Codex can audit a
-- run without reconstructing discarded upstream responses.

create table private.ticketmaster_ingestion_rejections (
  run_id uuid not null,
  page_number integer not null check (page_number between 0 and 49),
  raw_position smallint not null check (raw_position between 0 and 19),
  external_event_id text check (
    external_event_id is null
    or (
      char_length(external_event_id) between 1 and 200
      and not private.contains_control_characters(external_event_id)
    )
  ),
  event_name text check (
    event_name is null or private.is_normalized_user_text(event_name, 160)
  ),
  event_date date check (
    event_date is null or event_date between date '1900-01-01' and date '2200-12-31'
  ),
  venue_name text check (
    venue_name is null or private.is_normalized_user_text(venue_name, 160)
  ),
  rejection_stage text not null check (
    rejection_stage in ('event_shape', 'event_dates', 'venue', 'lineup', 'source_url')
  ),
  rejection_code text not null check (
    (rejection_stage = 'event_shape' and rejection_code = 'event_shape_invalid')
    or (rejection_stage = 'event_dates' and rejection_code = 'event_dates_invalid')
    or (rejection_stage = 'venue' and rejection_code = 'venue_invalid')
    or (
      rejection_stage = 'lineup'
      and rejection_code in (
        'attractions_missing',
        'attractions_not_array',
        'attractions_too_many',
        'attractions_empty',
        'attractions_all_invalid'
      )
    )
    or (rejection_stage = 'source_url' and rejection_code = 'source_url_invalid')
  ),
  attraction_count integer check (
    attraction_count is null or attraction_count between 0 and 1000
  ),
  invalid_attraction_shape_count smallint not null default 0 check (
    invalid_attraction_shape_count between 0 and 20
  ),
  invalid_artist_id_count smallint not null default 0 check (
    invalid_artist_id_count between 0 and 20
  ),
  invalid_artist_name_count smallint not null default 0 check (
    invalid_artist_name_count between 0 and 20
  ),
  invalid_artist_url_count smallint not null default 0 check (
    invalid_artist_url_count between 0 and 20
  ),
  observed_at timestamptz not null default clock_timestamp(),
  primary key (run_id, page_number, raw_position),
  foreign key (run_id, page_number)
    references private.ticketmaster_ingestion_pages (run_id, page_number)
    on delete cascade,
  constraint ticketmaster_ingestion_rejection_attraction_counts_check check (
    invalid_attraction_shape_count
      + invalid_artist_id_count
      + invalid_artist_name_count
      + invalid_artist_url_count
      <= coalesce(attraction_count, 20)
  )
);

create index ticketmaster_ingestion_rejections_observed
  on private.ticketmaster_ingestion_rejections (observed_at);

revoke all on table private.ticketmaster_ingestion_rejections
from public, anon, authenticated, service_role;

-- Remove the service-role grant from the original completion RPC. The new
-- overload below wraps it in the same transaction and makes rejection
-- persistence mandatory for all newly deployed workers.
revoke execute on function public.complete_ticketmaster_ingestion_page(
  bigint, uuid, integer, jsonb, integer, integer, integer, integer, boolean
) from service_role;

create function public.complete_ticketmaster_ingestion_page(
  p_message_id bigint,
  p_run_id uuid,
  p_page_number integer,
  p_events jsonb,
  p_rejections jsonb,
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
  v_rejection jsonb;
  v_event_date_text text;
begin
  if p_rejections is null
    or jsonb_typeof(p_rejections) <> 'array'
    or jsonb_array_length(p_rejections) > 20
    or p_rejected_event_count is null
    or jsonb_array_length(p_rejections) <> p_rejected_event_count
  then
    raise exception 'Ticketmaster rejection audit is invalid' using errcode = '22023';
  end if;

  delete from private.ticketmaster_ingestion_rejections
  where observed_at < clock_timestamp() - interval '30 days';

  for v_rejection in
    select item.value
    from jsonb_array_elements(p_rejections) as item(value)
  loop
    if jsonb_typeof(v_rejection) <> 'object'
      or not v_rejection ?& array[
        'raw_position',
        'external_event_id',
        'event_name',
        'event_date',
        'venue_name',
        'rejection_stage',
        'rejection_code',
        'attraction_count',
        'invalid_attraction_shape_count',
        'invalid_artist_id_count',
        'invalid_artist_name_count',
        'invalid_artist_url_count'
      ]
      or v_rejection - array[
        'raw_position',
        'external_event_id',
        'event_name',
        'event_date',
        'venue_name',
        'rejection_stage',
        'rejection_code',
        'attraction_count',
        'invalid_attraction_shape_count',
        'invalid_artist_id_count',
        'invalid_artist_name_count',
        'invalid_artist_url_count'
      ] <> '{}'::jsonb
      or jsonb_typeof(v_rejection -> 'raw_position') <> 'number'
      or jsonb_typeof(v_rejection -> 'rejection_stage') <> 'string'
      or jsonb_typeof(v_rejection -> 'rejection_code') <> 'string'
      or jsonb_typeof(v_rejection -> 'invalid_attraction_shape_count') <> 'number'
      or jsonb_typeof(v_rejection -> 'invalid_artist_id_count') <> 'number'
      or jsonb_typeof(v_rejection -> 'invalid_artist_name_count') <> 'number'
      or jsonb_typeof(v_rejection -> 'invalid_artist_url_count') <> 'number'
      or v_rejection ->> 'raw_position' !~ '^(0|[1-9][0-9]*)$'
      or v_rejection ->> 'invalid_attraction_shape_count' !~ '^(0|[1-9][0-9]*)$'
      or v_rejection ->> 'invalid_artist_id_count' !~ '^(0|[1-9][0-9]*)$'
      or v_rejection ->> 'invalid_artist_name_count' !~ '^(0|[1-9][0-9]*)$'
      or v_rejection ->> 'invalid_artist_url_count' !~ '^(0|[1-9][0-9]*)$'
      or (
        jsonb_typeof(v_rejection -> 'attraction_count') not in ('number', 'null')
      )
      or (
        v_rejection ->> 'attraction_count' is not null
        and v_rejection ->> 'attraction_count' !~ '^(0|[1-9][0-9]*)$'
      )
      or (
        jsonb_typeof(v_rejection -> 'external_event_id') not in ('string', 'null')
      )
      or jsonb_typeof(v_rejection -> 'event_name') not in ('string', 'null')
      or jsonb_typeof(v_rejection -> 'event_date') not in ('string', 'null')
      or jsonb_typeof(v_rejection -> 'venue_name') not in ('string', 'null')
    then
      raise exception 'Ticketmaster rejection audit is invalid' using errcode = '22023';
    end if;

    v_event_date_text := v_rejection ->> 'event_date';
    if v_event_date_text is not null
      and v_event_date_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    then
      raise exception 'Ticketmaster rejection date is invalid' using errcode = '22023';
    end if;

    insert into private.ticketmaster_ingestion_rejections (
      run_id,
      page_number,
      raw_position,
      external_event_id,
      event_name,
      event_date,
      venue_name,
      rejection_stage,
      rejection_code,
      attraction_count,
      invalid_attraction_shape_count,
      invalid_artist_id_count,
      invalid_artist_name_count,
      invalid_artist_url_count
    ) values (
      p_run_id,
      p_page_number,
      (v_rejection ->> 'raw_position')::smallint,
      v_rejection ->> 'external_event_id',
      v_rejection ->> 'event_name',
      v_event_date_text::date,
      v_rejection ->> 'venue_name',
      v_rejection ->> 'rejection_stage',
      v_rejection ->> 'rejection_code',
      (v_rejection ->> 'attraction_count')::integer,
      (v_rejection ->> 'invalid_attraction_shape_count')::smallint,
      (v_rejection ->> 'invalid_artist_id_count')::smallint,
      (v_rejection ->> 'invalid_artist_name_count')::smallint,
      (v_rejection ->> 'invalid_artist_url_count')::smallint
    );
  end loop;

  return public.complete_ticketmaster_ingestion_page(
    p_message_id,
    p_run_id,
    p_page_number,
    p_events,
    p_raw_event_count,
    p_rejected_event_count,
    p_total_elements,
    p_total_pages,
    p_has_more
  );
end;
$$;

create function public.get_ticketmaster_ingestion_rejection_audit(
  p_run_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_id uuid;
begin
  if p_run_id is null then
    select run.id into v_run_id
    from private.ticketmaster_ingestion_runs as run
    order by run.created_at desc
    limit 1;
  else
    select run.id into v_run_id
    from private.ticketmaster_ingestion_runs as run
    where run.id = p_run_id;
  end if;

  return jsonb_build_object(
    'run_id', v_run_id,
    'retention_days', 30,
    'rejections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'page', rejection.page_number,
        'raw_position', rejection.raw_position,
        'external_event_id', rejection.external_event_id,
        'event_name', rejection.event_name,
        'event_date', rejection.event_date,
        'venue_name', rejection.venue_name,
        'rejection_stage', rejection.rejection_stage,
        'rejection_code', rejection.rejection_code,
        'attraction_count', rejection.attraction_count,
        'invalid_attraction_shape_count', rejection.invalid_attraction_shape_count,
        'invalid_artist_id_count', rejection.invalid_artist_id_count,
        'invalid_artist_name_count', rejection.invalid_artist_name_count,
        'invalid_artist_url_count', rejection.invalid_artist_url_count,
        'observed_at', rejection.observed_at
      ) order by rejection.page_number, rejection.raw_position)
      from private.ticketmaster_ingestion_rejections as rejection
      where rejection.run_id = v_run_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.complete_ticketmaster_ingestion_page(
  bigint, uuid, integer, jsonb, jsonb, integer, integer, integer, integer, boolean
) from public, anon, authenticated;
grant execute on function public.complete_ticketmaster_ingestion_page(
  bigint, uuid, integer, jsonb, jsonb, integer, integer, integer, integer, boolean
) to service_role;

revoke all on function public.get_ticketmaster_ingestion_rejection_audit(uuid)
from public, anon, authenticated;
grant execute on function public.get_ticketmaster_ingestion_rejection_audit(uuid)
to service_role;
