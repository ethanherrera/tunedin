begin;

select plan(49);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e3000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attendance-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e3000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attendance-friend@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e3000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attendance-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e3000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attendance-private@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e3000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'attendance-incomplete@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
      when 'e3000000-0000-4000-8000-000000000001' then 'attendance_owner'
      when 'e3000000-0000-4000-8000-000000000002' then 'attendance_friend'
      when 'e3000000-0000-4000-8000-000000000003' then 'attendance_outsider'
      when 'e3000000-0000-4000-8000-000000000004' then 'attendance_private'
    end,
    display_name = case id
      when 'e3000000-0000-4000-8000-000000000001' then 'Attendance Owner'
      when 'e3000000-0000-4000-8000-000000000002' then 'Attendance Friend'
      when 'e3000000-0000-4000-8000-000000000003' then 'Attendance Outsider'
      when 'e3000000-0000-4000-8000-000000000004' then 'Attendance Private'
    end,
    onboarding_completed_at = now()
where id in (
  'e3000000-0000-4000-8000-000000000001',
  'e3000000-0000-4000-8000-000000000002',
  'e3000000-0000-4000-8000-000000000003',
  'e3000000-0000-4000-8000-000000000004'
);

insert into public.relationships (
  user_low_id, user_high_id, status, initiator_id, responder_id,
  requested_at, responded_at
)
values (
  'e3000000-0000-4000-8000-000000000001',
  'e3000000-0000-4000-8000-000000000002',
  'accepted',
  'e3000000-0000-4000-8000-000000000001',
  'e3000000-0000-4000-8000-000000000002',
  now(),
  now()
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);

select set_config(
  'test.attendance_area_id',
  (select catalog_id::text from public.create_custom_catalog_area(
    'Attendance City', 'US', null, null
  )),
  true
);
select set_config(
  'test.attendance_artist_id',
  (select catalog_id::text from public.create_custom_catalog_artist(
    'Attendance Headliner', 'Group', null,
    current_setting('test.attendance_area_id')::uuid, null
  )),
  true
);
select set_config(
  'test.attendance_place_id',
  (select catalog_id::text from public.create_custom_catalog_place(
    'Attendance Hall', current_setting('test.attendance_area_id')::uuid,
    'Venue', null, null
  )),
  true
);

select set_config(
  'test.attendance_future_event_id',
  (select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.attendance_artist_id'),
      'is_primary', true
    )),
    current_setting('test.attendance_place_id')::uuid,
    current_date + 30,
    null,
    ((current_date + 30) + time '20:00') at time zone 'UTC',
    'UTC',
    'listed'
  )),
  true
);
select set_config(
  'test.attendance_past_event_id',
  (select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.attendance_artist_id'),
      'is_primary', true
    )),
    current_setting('test.attendance_place_id')::uuid,
    current_date - 10,
    null,
    ((current_date - 10) + time '20:00') at time zone 'UTC',
    'UTC',
    'listed'
  )),
  true
);
select set_config(
  'test.attendance_unlisted_event_id',
  (select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.attendance_artist_id'),
      'is_primary', true
    )),
    current_setting('test.attendance_place_id')::uuid,
    current_date + 31,
    null,
    ((current_date + 31) + time '20:00') at time zone 'UTC',
    'UTC',
    'listed'
  )),
  true
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'friends'
  )$$,
  '42501', null,
  'attendance mutations require completed onboarding'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'went', 'friends'
  )$$,
  '22023', null,
  'Went cannot be confirmed before the memory boundary'
);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.attendance_past_event_id')::uuid, 'going', 'friends'
  )$$,
  '22023', null,
  'Going cannot be selected after the memory boundary'
);

select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'friends'
  )),
  'going',
  'a user can mark Going on a future event'
);
select is(
  (select audience::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'friends'
  )),
  'friends',
  'attendance keeps its explicit audience'
);
select is(
  (select count(*) from public.list_my_catalog_event_plans(null, 50)),
  1::bigint,
  'Going immediately creates one Plans row'
);
select is(
  (select current_user_status::text from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_future_event_id')::uuid]
  )),
  'going',
  'event summaries return the caller attendance separately'
);
reset role;
select is(
  (select count(*) from public.social_activity_events
    where actor_id = 'e3000000-0000-4000-8000-000000000001'
      and event_id = current_setting('test.attendance_future_event_id')::uuid
      and action = 'marked_going'),
  1::bigint,
  'the first Going transition emits one immutable activity'
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select is(
  (select audience::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'community'
  )),
  'community',
  'a user can change audience without changing attendance status'
);
reset role;
select is(
  (select count(*) from public.social_activity_events
    where actor_id = 'e3000000-0000-4000-8000-000000000001'
      and event_id = current_setting('test.attendance_future_event_id')::uuid
      and action = 'marked_going'),
  1::bigint,
  'an audience-only change does not duplicate Going activity'
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000002', true);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'friends'
  )),
  'going',
  'a friend can keep a friends-audience plan'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000003', true);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'community'
  )),
  'going',
  'an unrelated profile can keep a community plan'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000004', true);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'private'
  )),
  'going',
  'a private attendance remains a valid personal plan'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select ok(
  (select friend_previews @> jsonb_build_array(jsonb_build_object(
    'profile_id', 'e3000000-0000-4000-8000-000000000002'
  )) from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_future_event_id')::uuid]
  )),
  'a visible friend plan appears in event friend previews'
);
select is(
  (select community_going_count from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_future_event_id')::uuid]
  )),
  2,
  'community counts include only community-audience Going rows'
);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'all', null, 50
  )),
  3::bigint,
  'the owner sees self, a friends row, and an unrelated community row'
);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'friends', null, 50
  )),
  1::bigint,
  'the Friends scope contains only accepted visible friends'
);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'community', null, 50
  )),
  1::bigint,
  'the Community scope excludes self and already-grouped friends'
);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'all', null, 50
  ) where id = 'e3000000-0000-4000-8000-000000000004'),
  0::bigint,
  'another profile private attendance never appears'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'all', null, 50
  )),
  3::bigint,
  'a friend sees self, their friend, and community attendance'
);
select ok(
  (select friend_previews @> jsonb_build_array(jsonb_build_object(
    'profile_id', 'e3000000-0000-4000-8000-000000000001'
  )) from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_future_event_id')::uuid]
  )),
  'friend previews are viewer-specific in both directions'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'all', null, 50
  )),
  2::bigint,
  'an outsider sees only community rows and their own attendance'
);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'friends', null, 50
  )),
  0::bigint,
  'an outsider cannot infer friends-audience attendance'
);
select is(
  (select community_going_count from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_future_event_id')::uuid]
  )),
  2,
  'community counts are stable for an unblocked outsider'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000004', true);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'all', null, 50
  )),
  3::bigint,
  'a private attendee still sees their own row and visible community rows'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select public.remove_friend('e3000000-0000-4000-8000-000000000002')$$,
  'friend removal succeeds before visibility is recomputed'
);
select is(
  (select friend_previews from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_future_event_id')::uuid]
  )),
  '[]'::jsonb,
  'friend previews disappear immediately after friendship removal'
);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'all', null, 50
  )),
  2::bigint,
  'friends-audience rows disappear immediately after friendship removal'
);
select lives_ok(
  $$select public.block_profile('e3000000-0000-4000-8000-000000000003')$$,
  'a safety block succeeds before visibility is recomputed'
);
select is(
  (select community_going_count from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_future_event_id')::uuid]
  )),
  1,
  'blocked community attendance is removed from viewer-specific aggregates'
);
select is(
  (select count(*) from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'all', null, 50
  )),
  1::bigint,
  'blocked profiles disappear from attendee rows'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000003', true);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_unlisted_event_id')::uuid, 'going', 'community'
  )),
  'going',
  'a profile can plan a listed event before its listing changes'
);
reset role;
update public.catalog_events
set listing = 'unlisted'
where id = current_setting('test.attendance_unlisted_event_id')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000003', true);
select is(
  (select event_id from public.get_catalog_event_detail(
    current_setting('test.attendance_unlisted_event_id')::uuid
  )),
  current_setting('test.attendance_unlisted_event_id')::uuid,
  'an existing attendee retains access after an event becomes unlisted'
);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_unlisted_event_id')::uuid, null, 'community'
  )),
  null,
  'clearing attendance returns an explicit empty status'
);
select throws_ok(
  $$select * from public.get_catalog_event_detail(
    current_setting('test.attendance_unlisted_event_id')::uuid
  )$$,
  '42501', null,
  'clearing attendance also removes retained unlisted access'
);

select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_past_event_id')::uuid, 'went', 'private'
  )),
  'went',
  'Went can persist without creating a diary'
);
select is(
  (select count(*) from public.list_my_catalog_event_plans(null, 50)),
  2::bigint,
  'Plans combines upcoming Going and past Went history'
);
select is(
  (select current_user_status::text from public.get_catalog_event_social_summaries(
    array[current_setting('test.attendance_past_event_id')::uuid]
  )),
  'went',
  'past event summaries return Went independently of a diary'
);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_past_event_id')::uuid, 'did_not_go', 'private'
  )),
  'did_not_go',
  'a user can correct a past plan to did not go'
);
select is(
  (select count(*) from public.list_my_catalog_event_plans(null, 50)),
  1::bigint,
  'did not go is not presented as Going or Went history'
);

select throws_ok(
  $$insert into public.catalog_event_attendance (
    event_id, profile_id, status, audience
  ) values (
    current_setting('test.attendance_future_event_id')::uuid,
    auth.uid(), 'going', 'community'
  ) on conflict (event_id, profile_id) do update set audience = excluded.audience$$,
  '42501', null,
  'authenticated clients cannot mutate attendance rows directly'
);
select throws_ok(
  $$select count(*) from public.catalog_event_attendance$$,
  '42501', null,
  'authenticated clients cannot read the attendance table directly'
);
select throws_ok(
  $$select * from public.get_catalog_event_social_summaries(array[]::uuid[])$$,
  '22023', null,
  'social summary batches reject empty or unbounded input'
);
select throws_ok(
  $$select * from public.list_catalog_event_attendees(
    current_setting('test.attendance_future_event_id')::uuid, 'everyone', null, 50
  )$$,
  '22023', null,
  'attendee reads reject unknown scopes'
);
select throws_ok(
  $$select * from public.list_my_catalog_event_plans(null, 51)$$,
  '22023', null,
  'Plans reads enforce the server-side page boundary'
);

reset role;
update private.catalog_event_attendance_quota
set rolling_hour_limit = 1,
    rolling_day_limit = 1
where singleton;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, 'going', 'private'
  )$$,
  'P0001', null,
  'attendance mutations enforce an atomic server-side rolling quota'
);
reset role;
update private.catalog_event_attendance_quota
set rolling_hour_limit = 60,
    rolling_day_limit = 500
where singleton;

set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.list_my_catalog_event_plans(null, 50)$$,
  '42501', null,
  'anonymous callers cannot read Plans'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select is(
  (select status::text from public.set_catalog_event_attendance(
    current_setting('test.attendance_future_event_id')::uuid, null, 'community'
  )),
  null,
  'a user can remove a future plan without deleting the event'
);
select is(
  (select count(*) from public.list_my_catalog_event_plans(null, 50)),
  0::bigint,
  'clearing Going leaves no plan after did not go history is excluded'
);

select * from finish();
rollback;
