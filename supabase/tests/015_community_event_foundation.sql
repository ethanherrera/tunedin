begin;

select plan(49);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e2000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e2000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e2000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-incomplete@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
    when 'e2000000-0000-4000-8000-000000000001' then 'event_owner'
    when 'e2000000-0000-4000-8000-000000000002' then 'event_outsider'
  end,
  display_name = 'Event Test',
  onboarding_completed_at = now()
where id in (
  'e2000000-0000-4000-8000-000000000001',
  'e2000000-0000-4000-8000-000000000002'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000003', true);

select throws_ok(
  $$select * from public.create_catalog_event(
    '[]'::jsonb,
    '00000000-0000-4000-8000-000000000001',
    current_date + 30
  )$$,
  '42501', null,
  'community event creation requires completed onboarding'
);

select throws_ok(
  $$select * from public.search_catalog_events(null, '{}'::jsonb, null, 20)$$,
  '42501', null,
  'community event search requires completed onboarding'
);

select set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000001', true);

select set_config(
  'test.event_area_id',
  (select catalog_id::text from public.create_custom_catalog_area('Event City', 'US', null)),
  true
);
select set_config(
  'test.event_artist_id',
  (select catalog_id::text from public.create_custom_catalog_artist(
    'Tap Headliner', 'Group', 'event fixture', current_setting('test.event_area_id')::uuid
  )),
  true
);
select set_config(
  'test.event_target_artist_id',
  (select catalog_id::text from public.create_custom_catalog_artist(
    'Canonical Headliner', 'Group', 'merge target', current_setting('test.event_area_id')::uuid
  )),
  true
);
select set_config(
  'test.event_place_id',
  (select catalog_id::text from public.create_custom_catalog_place(
    'Tap Event Hall', current_setting('test.event_area_id')::uuid, 'Venue', '1 Event Way'
  )),
  true
);
select set_config(
  'test.event_tour_id',
  (select catalog_id::text from public.create_custom_catalog_tour(
    'Tap Event Tour', array[current_setting('test.event_artist_id')::uuid]
  )),
  true
);

select
  set_config('test.event_id', created.event_id::text, true),
  set_config('test.event_was_created', created.was_created::text, true)
from public.create_catalog_event(
  jsonb_build_array(jsonb_build_object(
    'catalog_artist_id', current_setting('test.event_artist_id'),
    'is_primary', true
  )),
  current_setting('test.event_place_id')::uuid,
  current_date + 30,
  current_setting('test.event_tour_id')::uuid,
  ((current_date + 30) + time '20:00') at time zone 'America/Los_Angeles',
  'America/Los_Angeles',
  'listed'
) as created;

select is(
  current_setting('test.event_was_created')::boolean,
  true,
  'the first exact occurrence creates a canonical event'
);

select is(
  (select detail.event_id from public.get_catalog_event_detail(
    current_setting('test.event_id')::uuid
  ) as detail),
  current_setting('test.event_id')::uuid,
  'the creator can reopen the shared event detail'
);

select is(
  (select detail.artists #>> '{0,display_name}' from public.get_catalog_event_detail(
    current_setting('test.event_id')::uuid
  ) as detail),
  'Tap Headliner',
  'event detail derives its ordered artist snapshot from the catalog'
);

select is(
  (select detail.area_name from public.get_catalog_event_detail(
    current_setting('test.event_id')::uuid
  ) as detail),
  'Event City',
  'event detail derives its area from the catalog place'
);

select is(
  (select detail.lifecycle::text from public.get_catalog_event_detail(
    current_setting('test.event_id')::uuid
  ) as detail),
  'scheduled',
  'a future occurrence begins in the scheduled lifecycle'
);

select throws_ok(
  $$insert into public.catalog_events (
      created_by, catalog_place_id, headliner_catalog_artist_id, event_date,
      time_zone_identifier, memory_unlock_at, venue_name_snapshot,
      area_name_snapshot, headliner_name_snapshot, search_text, exact_duplicate_key
    ) values (
      auth.uid(), current_setting('test.event_place_id')::uuid,
      current_setting('test.event_artist_id')::uuid, current_date + 1, 'UTC', now(),
      'Forged Hall', 'Forged City', 'Forged Artist', 'forged event', md5('forged')
    )$$,
  '42501', null,
  'authenticated clients cannot insert shared event rows directly'
);

select throws_ok(
  $$select count(*) from public.catalog_events$$,
  '42501', null,
  'authenticated clients cannot bypass bounded event projections'
);

select is(
  (select duplicate.event_id from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 30,
    current_setting('test.event_tour_id')::uuid,
    ((current_date + 30) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'listed'
  ) as duplicate),
  current_setting('test.event_id')::uuid,
  'an exact duplicate resolves to the existing canonical event'
);

select is(
  (select duplicate.was_created from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 30,
    current_setting('test.event_tour_id')::uuid,
    ((current_date + 30) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'listed'
  ) as duplicate),
  false,
  'an exact duplicate does not consume another creation'
);

select set_config(
  'test.near_event_id',
  (select created.event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 31,
    current_setting('test.event_tour_id')::uuid,
    ((current_date + 31) + time '21:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'listed'
  ) as created),
  true
);

select isnt(
  current_setting('test.near_event_id')::uuid,
  current_setting('test.event_id')::uuid,
  'a nearby-date show remains a distinct occurrence'
);

select is(
  (select count(*) from public.search_catalog_events('Tap Headliner', '{}'::jsonb, null, 20)),
  2::bigint,
  'event search matches the derived headliner snapshot'
);

select is(
  (select count(*) from public.search_catalog_events('Event Hall', '{}'::jsonb, null, 20)),
  2::bigint,
  'event search matches the derived venue snapshot'
);

select is(
  (select count(*) from public.search_catalog_events(
    null,
    jsonb_build_object('artist_catalog_id', current_setting('test.event_artist_id')),
    null,
    20
  )),
  2::bigint,
  'event search supports exact catalog artist filtering'
);

select set_config(
  'test.first_page_event_id',
  (select page.event_id::text from public.search_catalog_events(
    'Tap Headliner', '{}'::jsonb, null, 1
  ) as page),
  true
);
select set_config(
  'test.event_cursor',
  (select page.next_cursor::text from public.search_catalog_events(
    'Tap Headliner', '{}'::jsonb, null, 1
  ) as page),
  true
);

select is(
  (select count(*) from public.search_catalog_events(
    'Tap Headliner', '{}'::jsonb, null, 1
  )),
  1::bigint,
  'event search returns a bounded first cursor page'
);

select is(
  (select count(*) from public.search_catalog_events(
    'Tap Headliner', '{}'::jsonb, current_setting('test.event_cursor')::jsonb, 1
  )),
  1::bigint,
  'event search returns the next cursor page'
);

select isnt(
  (select page.event_id from public.search_catalog_events(
    'Tap Headliner', '{}'::jsonb, current_setting('test.event_cursor')::jsonb, 1
  ) as page),
  current_setting('test.first_page_event_id')::uuid,
  'cursor pagination does not replay the prior event'
);

select set_config(
  'test.unlisted_event_id',
  (select created.event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 31,
    current_setting('test.event_tour_id')::uuid,
    ((current_date + 31) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'unlisted'
  ) as created),
  true
);

select isnt(
  current_setting('test.unlisted_event_id')::uuid,
  null::uuid,
  'a creator can add an unlisted community event'
);

select is(
  (select count(*) from public.search_catalog_events('Tap Headliner', '{}'::jsonb, null, 20)),
  3::bigint,
  'the creator can find their own unlisted event'
);

select set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000002', true);

select is(
  (select count(*) from public.search_catalog_events('Tap Headliner', '{}'::jsonb, null, 20)),
  2::bigint,
  'another completed user sees listed events but not the unlisted event'
);

select is(
  (select detail.event_id from public.get_catalog_event_detail(
    current_setting('test.event_id')::uuid
  ) as detail),
  current_setting('test.event_id')::uuid,
  'a completed user can open a listed event backed by another users custom catalog snapshot'
);

select throws_ok(
  $$select * from public.get_catalog_event_detail(
    current_setting('test.unlisted_event_id')::uuid
  )$$,
  '42501', null,
  'another user cannot open an unlisted event without an access reason'
);

select throws_ok(
  $$select * from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 40
  )$$,
  '22023', null,
  'another user cannot reuse creator-scoped custom catalog identities'
);

select throws_ok(
  $$select * from public.update_catalog_event(
    current_setting('test.event_id')::uuid,
    1,
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 30
  )$$,
  '42501', null,
  'a non-creator cannot mutate a shared event'
);

select set_config(
  'test.event_report_id',
  public.report_catalog_event(
    current_setting('test.event_id')::uuid, 'wrong_date', 'Please verify'
  )::text,
  true
);

select isnt(
  current_setting('test.event_report_id')::uuid,
  null::uuid,
  'a viewer can submit a private moderation report for a listed event'
);

select is(
  public.report_catalog_event(current_setting('test.event_id')::uuid, 'wrong_date', 'Repeated'),
  current_setting('test.event_report_id')::uuid,
  'replaying an open report returns the existing private report'
);

select throws_ok(
  $$select count(*) from private.catalog_event_reports$$,
  '42501', null,
  'event report content is not readable by authenticated clients'
);

select throws_ok(
  $$select public.report_catalog_event(
    current_setting('test.event_id')::uuid, 'unsupported', null
  )$$,
  '22023', null,
  'event reports reject unsupported reason values'
);

select set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000001', true);

select is(
  (select updated.version from public.update_catalog_event(
    current_setting('test.event_id')::uuid,
    1,
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 30,
    current_setting('test.event_tour_id')::uuid,
    ((current_date + 30) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'listed',
    'cancelled'
  ) as updated),
  2,
  'a creator correction increments the event version'
);

select is(
  (select detail.lifecycle::text from public.get_catalog_event_detail(
    current_setting('test.event_id')::uuid
  ) as detail),
  'cancelled',
  'a permitted lifecycle correction is reflected in event detail'
);

select throws_ok(
  $$select * from public.update_catalog_event(
    current_setting('test.event_id')::uuid,
    1,
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 30
  )$$,
  'P0001', null,
  'a stale correction cannot overwrite a newer event version'
);

reset role;

select is(
  (select count(*) from private.catalog_event_revisions
   where event_id = current_setting('test.event_id')::uuid),
  1::bigint,
  'a creator correction records one private revision snapshot'
);

select is(
  (select count(*) from public.social_activity_events
   where event_id = current_setting('test.event_id')::uuid),
  2::bigint,
  'event creation and correction append immutable social activity rows'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select * from public.update_catalog_event(
    current_setting('test.near_event_id')::uuid,
    1,
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 30,
    current_setting('test.event_tour_id')::uuid,
    ((current_date + 30) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'listed',
    'scheduled'
  )$$,
  'P0001', null,
  'an event correction cannot collide with another canonical occurrence'
);

select throws_ok(
  $$select * from public.create_catalog_event(
    jsonb_build_array(
      jsonb_build_object('catalog_artist_id', current_setting('test.event_artist_id'), 'is_primary', true),
      jsonb_build_object('catalog_artist_id', current_setting('test.event_artist_id'), 'is_primary', false)
    ),
    current_setting('test.event_place_id')::uuid,
    current_date + 50
  )$$,
  '22023', null,
  'event creation rejects a duplicate catalog artist in the lineup'
);

select throws_ok(
  $$select * from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 50,
    null,
    null,
    'PST'
  )$$,
  '22023', null,
  'event creation requires an IANA venue time zone'
);

select throws_ok(
  $$select * from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 50,
    null,
    ((current_date + 51) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles'
  )$$,
  '22023', null,
  'event creation rejects a start time outside the venue-local event date'
);

reset role;
update public.catalog_entities
set status = 'merged', merged_into_id = current_setting('test.event_target_artist_id')::uuid
where id = current_setting('test.event_artist_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000001', true);

select set_config(
  'test.merged_source_event_id',
  (select created.event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 40,
    null,
    ((current_date + 40) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'listed'
  ) as created),
  true
);

select is(
  (select detail.artists #>> '{0,catalog_artist_id}' from public.get_catalog_event_detail(
    current_setting('test.merged_source_event_id')::uuid
  ) as detail),
  current_setting('test.event_target_artist_id'),
  'a stale merged catalog ID resolves to its canonical artist at event write time'
);

select is(
  (select detail.artists #>> '{0,display_name}' from public.get_catalog_event_detail(
    current_setting('test.event_id')::uuid
  ) as detail),
  'Tap Headliner',
  'an existing event keeps its artist snapshot after catalog identity merges'
);

select is(
  (select detail.artists #>> '{0,display_name}' from public.get_catalog_event_detail(
    current_setting('test.merged_source_event_id')::uuid
  ) as detail),
  'Canonical Headliner',
  'a new event snapshots the resolved canonical artist name'
);

reset role;
update private.catalog_event_creation_quota
set rolling_hour_limit = 4, rolling_day_limit = 4
where singleton;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select * from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_target_artist_id'),
      'is_primary', true
    )),
    current_setting('test.event_place_id')::uuid,
    current_date + 41,
    null,
    ((current_date + 41) + time '20:00') at time zone 'America/Los_Angeles',
    'America/Los_Angeles',
    'listed'
  )$$,
  'P0001', null,
  'event creation quota is enforced atomically at the database boundary'
);

select throws_ok(
  $$select * from private.catalog_event_creation_quota$$,
  '42501', null,
  'event quota configuration is private from authenticated clients'
);

select throws_ok(
  $$select * from public.search_catalog_events(
    null, '{"unknown":true}'::jsonb, null, 20
  )$$,
  '22023', null,
  'event search rejects unknown filter keys'
);

select throws_ok(
  $$select * from public.search_catalog_events(
    null, '{}'::jsonb, '{"bucket":0}'::jsonb, 20
  )$$,
  '22023', null,
  'event search rejects incomplete cursors'
);

select throws_ok(
  $$select * from public.get_catalog_event_detail(
    'e2999999-9999-4999-8999-999999999999'::uuid
  )$$,
  '42501', null,
  'event detail does not reveal nonexistent rows'
);

reset role;

select is(
  (select count(*) from public.catalog_events
   where created_by = 'e2000000-0000-4000-8000-000000000001'),
  4::bigint,
  'duplicates and rejected writes do not inflate the creators canonical event count'
);

select throws_ok(
  $$update public.social_activity_events
    set metadata = '{"changed":true}'::jsonb
    where event_id = current_setting('test.event_id')::uuid$$,
  '42501', null,
  'social activity events cannot be rewritten even by a privileged direct update'
);

select is(
  (select status::text from public.catalog_entities
   where id = current_setting('test.event_artist_id')::uuid),
  'merged',
  'the stale catalog source remains a redirect identity rather than being deleted'
);

select * from finish();
rollback;
