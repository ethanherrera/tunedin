begin;

select plan(25);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select public.start_ticketmaster_ingestion(timestamptz '2026-03-01 12:00:00+00')$$,
  '42501', null,
  'ordinary clients cannot start Ticketmaster ingestion'
);

select throws_ok(
  $$select public.get_ticketmaster_ingestion_status(null)$$,
  '42501', null,
  'ordinary clients cannot read ingestion operations'
);

select throws_ok(
  $$select count(*) from private.ticketmaster_ingestion_runs$$,
  '42501', null,
  'ordinary clients cannot read private ingestion state'
);

reset role;

select is(
  (
    select count(*)::integer
    from cron.job
    where jobname in (
      'ticketmaster-ingestion-daily',
      'ticketmaster-ingestion-worker'
    )
      and not active
  ),
  2,
  'both Ticketmaster ingestion schedules are installed inactive'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

select set_config(
  'test.ingestion_payload',
  '{
    "event_id":"G5vYZbingestion",
    "title":"Fixture Ingestion Tour",
    "event_date":"2026-03-05",
    "local_start_time":"20:00:00",
    "starts_at":"2026-03-06T04:00:00Z",
    "time_zone":"America/Los_Angeles",
    "status":"active",
    "source_url":"https://www.ticketmaster.com/event/G5vYZbingestion",
    "image_url":null,
    "source_updated_at":null,
    "venue":{
      "id":"KovZingestionVenue",
      "name":"Fixture Ingestion Hall",
      "url":"https://www.ticketmaster.com/venue/KovZingestionVenue",
      "address":"1 Fixture Way",
      "latitude":"37.7841",
      "longitude":"-122.4330",
      "area":{"city":"San Francisco","state_code":"CA","country_code":"US"}
    },
    "artists":[
      {
        "id":"K8vZingestionArtist",
        "name":"Fixture Ingestion Artist",
        "url":"https://www.ticketmaster.com/artist/K8vZingestionArtist",
        "is_headliner":true
      }
    ]
  }',
  false
);

select set_config(
  'test.ingestion_run',
  public.start_ticketmaster_ingestion(
    timestamptz '2026-03-01 12:00:00+00'
  )::text,
  false
);

reset role;

select is(
  (
    select jsonb_build_array(
      coverage_starts_at at time zone 'America/Los_Angeles',
      coverage_ends_at at time zone 'America/Los_Angeles'
    )
    from private.ticketmaster_ingestion_runs
    where id = current_setting('test.ingestion_run')::uuid
  ),
  '["2026-03-01T00:00:00", "2026-03-15T00:00:00"]'::jsonb,
  'the 14-day window uses San Francisco calendar midnights across DST'
);

select is(
  public.start_ticketmaster_ingestion(
    timestamptz '2026-03-01 18:00:00+00'
  ),
  current_setting('test.ingestion_run')::uuid,
  'starting the same active local-date window is idempotent'
);

select is(
  (
    select status
    from private.ticketmaster_ingestion_pages
    where run_id = current_setting('test.ingestion_run')::uuid
      and page_number = 0
  ),
  'queued',
  'a new run durably queues page zero'
);

select is(
  (select queue_length from pgmq.metrics('ticketmaster_ingestion')),
  1::bigint,
  'the work queue contains one page'
);

select set_config(
  'test.ingestion_claim',
  public.claim_ticketmaster_ingestion_tasks(1, 120)::text,
  false
);

select is(
  jsonb_array_length(current_setting('test.ingestion_claim')::jsonb),
  1,
  'the service role claims one bounded ingestion task'
);

select is(
  (
    select status || ':' || attempt_count::text
    from private.ticketmaster_ingestion_pages
    where run_id = current_setting('test.ingestion_run')::uuid
      and page_number = 0
  ),
  'processing:1',
  'claiming records processing state and the queue read count'
);

select public.complete_ticketmaster_ingestion_page(
  (current_setting('test.ingestion_claim')::jsonb -> 0 ->> 'message_id')::bigint,
  current_setting('test.ingestion_run')::uuid,
  0,
  jsonb_build_array(current_setting('test.ingestion_payload')::jsonb),
  1,
  0,
  1,
  1,
  false
);

select is(
  (
    select status
    from private.ticketmaster_ingestion_runs
    where id = current_setting('test.ingestion_run')::uuid
  ),
  'completed',
  'a clean final page completes the run'
);

select is(
  (
    select jsonb_build_array(
      pages_completed,
      raw_events_received,
      valid_events_received,
      rejected_events,
      events_inserted
    )
    from private.ticketmaster_ingestion_runs
    where id = current_setting('test.ingestion_run')::uuid
  ),
  '[1, 1, 1, 0, 1]'::jsonb,
  'the run records page, decoding, and insert metrics'
);

select is(
  (
    select event.origin
    from private.ticketmaster_catalog_events as link
    join public.catalog_events as event on event.id = link.event_id
    where link.external_event_id = 'G5vYZbingestion'
  ),
  'ticketmaster',
  'ingestion writes one Ticketmaster-origin catalog event'
);

select is(
  (
    select event.cover_remote_url
    from private.ticketmaster_catalog_events as link
    join public.catalog_events as event on event.id = link.event_id
    where link.external_event_id = 'G5vYZbingestion'
  ),
  null,
  'the ingestion path does not persist Ticketmaster image URLs'
);

select is(
  (
    select count(*)::integer
    from private.catalog_event_sources
    where provider_key = 'ticketmaster'
      and external_event_id = 'G5vYZbingestion'
  ),
  1,
  'the provider identity maps to exactly one tunedIn event'
);

select public.upsert_ticketmaster_catalog_event(
  (current_setting('test.ingestion_payload')::jsonb)
    || '{
      "event_id":"G5vYZbunseen",
      "title":"Fixture Unseen Tour",
      "event_date":"2026-03-06",
      "starts_at":"2026-03-07T04:00:00Z",
      "source_url":"https://www.ticketmaster.com/event/G5vYZbunseen"
    }'::jsonb
);

select set_config(
  'test.ingestion_run',
  public.start_ticketmaster_ingestion(
    timestamptz '2026-03-01 13:00:00+00'
  )::text,
  false
);
select set_config(
  'test.ingestion_claim',
  public.claim_ticketmaster_ingestion_tasks(1, 120)::text,
  false
);
select public.complete_ticketmaster_ingestion_page(
  (current_setting('test.ingestion_claim')::jsonb -> 0 ->> 'message_id')::bigint,
  current_setting('test.ingestion_run')::uuid,
  0,
  jsonb_build_array(current_setting('test.ingestion_payload')::jsonb),
  1,
  0,
  1,
  1,
  false
);

select is(
  (
    select jsonb_build_array(status, events_unchanged, events_unlisted)
    from private.ticketmaster_ingestion_runs
    where id = current_setting('test.ingestion_run')::uuid
  ),
  '["completed", 1, 1]'::jsonb,
  'an unchanged payload avoids a rewrite and a clean run unlists one unseen event'
);

select is(
  (
    select event.listing::text
    from private.catalog_event_sources as link
    join public.catalog_events as event on event.id = link.event_id
    where link.provider_key = 'ticketmaster'
      and link.external_event_id = 'G5vYZbunseen'
  ),
  'unlisted',
  'only the unseen in-window Ticketmaster event is unlisted'
);

select is(
  (
    select count(*)::integer
    from private.catalog_event_sources
    where provider_key = 'ticketmaster'
      and external_event_id = 'G5vYZbingestion'
  ),
  1,
  'repeat ingestion preserves the one-to-one provider mapping'
);

select public.upsert_ticketmaster_catalog_event(
  (current_setting('test.ingestion_payload')::jsonb)
    || '{
      "event_id":"G5vYZbunseen",
      "title":"Fixture Unseen Tour",
      "event_date":"2026-03-06",
      "starts_at":"2026-03-07T04:00:00Z",
      "source_url":"https://www.ticketmaster.com/event/G5vYZbunseen"
    }'::jsonb
);

select set_config(
  'test.ingestion_run',
  public.start_ticketmaster_ingestion(
    timestamptz '2026-03-01 14:00:00+00'
  )::text,
  false
);
select set_config(
  'test.ingestion_claim',
  public.claim_ticketmaster_ingestion_tasks(1, 120)::text,
  false
);
select public.complete_ticketmaster_ingestion_page(
  (current_setting('test.ingestion_claim')::jsonb -> 0 ->> 'message_id')::bigint,
  current_setting('test.ingestion_run')::uuid,
  0,
  jsonb_build_array(current_setting('test.ingestion_payload')::jsonb),
  2,
  1,
  2,
  1,
  false
);

select is(
  (
    select status
    from private.ticketmaster_ingestion_runs
    where id = current_setting('test.ingestion_run')::uuid
  ),
  'completed_with_rejections',
  'a run with rejected provider records is explicitly partial'
);

select is(
  (
    select event.listing::text
    from private.catalog_event_sources as link
    join public.catalog_events as event on event.id = link.event_id
    where link.provider_key = 'ticketmaster'
      and link.external_event_id = 'G5vYZbunseen'
  ),
  'listed',
  'a partial run does not unlist an unseen event'
);

select is(
  (
    select jsonb_build_array(raw_events_received, valid_events_received, rejected_events)
    from private.ticketmaster_ingestion_runs
    where id = current_setting('test.ingestion_run')::uuid
  ),
  '[2, 1, 1]'::jsonb,
  'partial-run counters reconcile raw, valid, and rejected records'
);

select set_config(
  'test.failed_run',
  public.start_ticketmaster_ingestion(
    timestamptz '2026-03-02 12:00:00+00'
  )::text,
  false
);
select set_config(
  'test.failed_claim',
  public.claim_ticketmaster_ingestion_tasks(1, 120)::text,
  false
);

select is(
  public.fail_ticketmaster_ingestion_task(
    (current_setting('test.failed_claim')::jsonb -> 0 ->> 'message_id')::bigint,
    'upstream_invalid',
    false
  ) ->> 'outcome',
  'dead_letter',
  'a terminal page failure moves the task to dead letter'
);

select is(
  (
    select status || ':' || last_error_code
    from private.ticketmaster_ingestion_runs
    where id = current_setting('test.failed_run')::uuid
  ),
  'failed:upstream_invalid',
  'a dead-lettered page fails the run with a safe error code'
);

select is(
  (
    select queue_length
    from pgmq.metrics('ticketmaster_ingestion_dead_letter')
  ),
  1::bigint,
  'dead-letter queue depth is observable'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.start_ticketmaster_ingestion(timestamptz)',
    'EXECUTE'
  ),
  'only the service role receives the ingestion execution grant'
);

select * from finish();
rollback;
