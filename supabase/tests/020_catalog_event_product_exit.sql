begin;

select plan(26);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('f2000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'exit-creator@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('f2000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'exit-friend@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('f2000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'exit-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
      when 'f2000000-0000-4000-8000-000000000001' then 'exit_creator'
      when 'f2000000-0000-4000-8000-000000000002' then 'exit_friend'
      when 'f2000000-0000-4000-8000-000000000003' then 'exit_outsider'
    end,
    display_name = case id
      when 'f2000000-0000-4000-8000-000000000001' then 'Exit Creator'
      when 'f2000000-0000-4000-8000-000000000002' then 'Exit Friend'
      when 'f2000000-0000-4000-8000-000000000003' then 'Exit Outsider'
    end,
    onboarding_completed_at = now()
where id in (
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000002',
  'f2000000-0000-4000-8000-000000000003'
);

insert into public.relationships (
  user_low_id, user_high_id, status, initiator_id, responder_id,
  requested_at, responded_at
)
values (
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000002',
  'accepted',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000002',
  now(), now()
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);

select set_config('test.exit_area', (
  select catalog_id::text from public.create_custom_catalog_area(
    'Exit City', 'US', null, null
  )
), true);
select set_config('test.exit_artist', (
  select catalog_id::text from public.create_custom_catalog_artist(
    'Exit Artist', 'Group', null, current_setting('test.exit_area')::uuid, null
  )
), true);
select set_config('test.exit_place', (
  select catalog_id::text from public.create_custom_catalog_place(
    'Exit Hall', current_setting('test.exit_area')::uuid, 'Venue', null, null
  )
), true);

-- The product defaults to shared MusicBrainz identity. Promote these deterministic
-- fixtures to that origin so every completed profile can choose them in creation.
reset role;
update public.catalog_entities
set origin = 'musicbrainz',
    musicbrainz_mbid = case id
      when current_setting('test.exit_area')::uuid
        then 'a1000000-0000-4000-8000-000000000001'::uuid
      when current_setting('test.exit_artist')::uuid
        then 'a1000000-0000-4000-8000-000000000002'::uuid
      when current_setting('test.exit_place')::uuid
        then 'a1000000-0000-4000-8000-000000000003'::uuid
    end
where id in (
  current_setting('test.exit_area')::uuid,
  current_setting('test.exit_artist')::uuid,
  current_setting('test.exit_place')::uuid
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);

select set_config('test.exit_known', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date + 30,
    null,
    ((current_date + 30) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);

select is(
  (select memory_unlock_at from public.get_catalog_event_detail(
    current_setting('test.exit_known')::uuid
  )),
  ((current_date + 30) + time '20:00') at time zone 'UTC' + interval '4 hours',
  'a known start unlocks memories four hours later'
);

select is(
  (select event_id from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date + 30,
    null,
    ((current_date + 30) + time '22:00') at time zone 'UTC',
    'UTC', 'listed'
  )),
  current_setting('test.exit_known')::uuid,
  'start-time disagreement does not create a second occurrence'
);

select set_config('test.exit_near', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date + 31,
    null,
    ((current_date + 31) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);

select isnt(
  current_setting('test.exit_near')::uuid,
  current_setting('test.exit_known')::uuid,
  'a nearby date remains a distinct occurrence'
);
select is(
  (select count(*) from public.find_catalog_event_duplicate_candidates(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date + 30,
    null,
    ((current_date + 30) + time '21:00') at time zone 'UTC',
    'UTC', 'listed', 5
  )),
  2::bigint,
  'duplicate warnings include the exact and nearby readable shows'
);

select set_config('test.exit_unknown', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date + 40,
    null, null,
    'America/Los_Angeles', 'listed'
  )
), true);
select is(
  (select memory_unlock_at from public.get_catalog_event_detail(
    current_setting('test.exit_unknown')::uuid
  )),
  ((current_date + 41) + time '03:00') at time zone 'America/Los_Angeles',
  'an unknown start unlocks at three the next venue-local morning'
);

select set_config('test.exit_unlisted', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date + 35,
    null, null, 'UTC', 'unlisted'
  )
), true);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.find_catalog_event_duplicate_candidates(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date + 35,
    null, null, 'UTC', 'listed', 5
  )),
  0::bigint,
  'duplicate warnings never disclose an inaccessible unlisted event'
);
select lives_ok(
  $$select public.report_catalog_event(
    current_setting('test.exit_known')::uuid,
    'sensitive_location',
    'Please review the public venue label.'
  )$$,
  'a user can privately report a sensitive location'
);
select throws_ok(
  $$select count(*) from private.catalog_event_reports$$,
  '42501', null,
  'event reports remain private from authenticated clients'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.exit_known')::uuid, 'going', 'community'
  )$$,
  'Going exists independently from event creation'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_catalog_profile_attendance(
    'f2000000-0000-4000-8000-000000000001', 'going', null, 50
  )),
  1::bigint,
  'a friend can see community Going on the profile'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_profile_attendance(
    'f2000000-0000-4000-8000-000000000001', 'going', null, 50
  )),
  1::bigint,
  'a public profile viewer can see community Going'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select * from public.set_catalog_event_attendance(
  current_setting('test.exit_known')::uuid, 'going', 'friends'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_profile_attendance(
    'f2000000-0000-4000-8000-000000000001', 'going', null, 50
  )),
  0::bigint,
  'friends Going is hidden from an outsider'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_catalog_profile_attendance(
    'f2000000-0000-4000-8000-000000000001', 'going', null, 50
  )),
  1::bigint,
  'friends Going remains visible to a current friend'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select * from public.create_catalog_event_post(
  current_setting('test.exit_known')::uuid, null,
  'Friends can see this plan update.', 'community'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_catalog_event_activity(null, 50)
   where action = 'event_posted'),
  1::bigint,
  'the circle feed includes a readable friend post'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_event_activity(null, 50)
   where action = 'event_posted'),
  0::bigint,
  'community strangers never enter the friend circle feed'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select set_config('test.exit_past', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date - 5,
    null,
    ((current_date - 5) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select * from public.set_catalog_event_attendance(
  current_setting('test.exit_past')::uuid, 'went', 'friends'
);
select set_config('test.exit_diary', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.exit_past')::uuid,
    9.5, 9.0, 'A durable friend memory.', 'friends', true
  )
), true);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
select is(
  (select diary ->> 'diary_id' from public.list_catalog_event_activity(null, 50)
   where action = 'diary_published'
     and subject_id = current_setting('test.exit_diary')::uuid),
  current_setting('test.exit_diary'),
  'a friend diary activity carries its authorized preview for direct routing'
);
select is(
  (select count(*) from public.list_catalog_profile_event_history(
    'f2000000-0000-4000-8000-000000000001', null, 50
  ) where history_kind = 'diary'),
  1::bigint,
  'a friend profile includes a friends diary'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_profile_event_history(
    'f2000000-0000-4000-8000-000000000001', null, 50
  )),
  0::bigint,
  'an outsider cannot infer friends Went or diary history'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select set_config('test.exit_cancelled', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
    )),
    current_setting('test.exit_place')::uuid,
    current_date - 10,
    null,
    ((current_date - 10) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select * from public.update_catalog_event(
  current_setting('test.exit_cancelled')::uuid, 1,
  jsonb_build_array(jsonb_build_object(
    'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
  )),
  current_setting('test.exit_place')::uuid,
  current_date - 10,
  null,
  ((current_date - 10) + time '20:00') at time zone 'UTC',
  'UTC', 'listed', 'cancelled'
);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.exit_cancelled')::uuid, 'went', 'friends'
  )$$,
  '22023', null,
  'ordinary Went cannot bypass a cancelled event'
);
select lives_ok(
  $$select * from public.confirm_cancelled_catalog_event_performance(
    current_setting('test.exit_cancelled')::uuid, 'friends'
  )$$,
  'a user can explicitly confirm that a cancelled listing still performed'
);
reset role;
select ok(
  (select cancelled_performance_confirmed_at is not null
   from public.catalog_event_attendance
   where event_id = current_setting('test.exit_cancelled')::uuid
     and profile_id = 'f2000000-0000-4000-8000-000000000001'),
  'cancelled performance confirmation is durable and explicit'
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.upsert_catalog_event_diary(
    current_setting('test.exit_cancelled')::uuid,
    8.5, null, 'The show happened after all.', 'friends', true
  )$$,
  'a confirmed cancelled performance can have a personal diary'
);

select * from public.set_catalog_event_attendance(
  current_setting('test.exit_unknown')::uuid, 'going', 'friends'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
select * from public.set_catalog_event_attendance(
  current_setting('test.exit_unknown')::uuid, 'going', 'friends'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select * from public.update_catalog_event(
  current_setting('test.exit_unknown')::uuid, 1,
  jsonb_build_array(jsonb_build_object(
    'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
  )),
  current_setting('test.exit_place')::uuid,
  current_date + 41,
  null, null, 'America/Los_Angeles', 'listed', 'scheduled'
);
select * from public.update_catalog_event(
  current_setting('test.exit_unknown')::uuid, 2,
  jsonb_build_array(jsonb_build_object(
    'catalog_artist_id', current_setting('test.exit_artist'), 'is_primary', true
  )),
  current_setting('test.exit_place')::uuid,
  current_date + 41,
  null, null, 'America/Los_Angeles', 'listed', 'cancelled'
);

reset role;
select is(
  (select count(*) from private.catalog_event_notification_outbox
   where recipient_id = 'f2000000-0000-4000-8000-000000000001'
     and event_id = current_setting('test.exit_unknown')::uuid
     and action in ('event_schedule_changed', 'event_cancelled')),
  0::bigint,
  'event corrections never notify the actor themself'
);
select is(
  (select count(*) from private.catalog_event_notification_outbox
   where recipient_id = 'f2000000-0000-4000-8000-000000000002'
     and event_id = current_setting('test.exit_unknown')::uuid
     and action in ('event_schedule_changed', 'event_cancelled')),
  2::bigint,
  'material schedule changes and cancellations notify a person with a plan'
);
select is(
  (select count(*) from private.catalog_event_reports
   where reporter_id = 'f2000000-0000-4000-8000-000000000003'
     and reason = 'sensitive_location'),
  1::bigint,
  'the sensitive-location report is stored for private review'
);

set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.list_catalog_profile_attendance(
    'f2000000-0000-4000-8000-000000000001', 'going', null, 50
  )$$,
  '42501', null,
  'anonymous callers cannot enumerate profile attendance'
);

select * from finish();
rollback;
