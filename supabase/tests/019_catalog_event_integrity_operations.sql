begin;

select plan(48);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    'f1000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'integrity-operator@example.test', '', now(),
    '{"provider":"email","providers":["email"],"catalog_event_operator":true}',
    '{}', now(), now()
  ),
  (
    'f1000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'integrity-owner@example.test', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    'f1000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'integrity-friend@example.test', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    'f1000000-0000-4000-8000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'integrity-normal@example.test', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

update public.profiles
set username = case id
      when 'f1000000-0000-4000-8000-000000000001' then 'integrity_operator'
      when 'f1000000-0000-4000-8000-000000000002' then 'integrity_owner'
      when 'f1000000-0000-4000-8000-000000000003' then 'integrity_friend'
      when 'f1000000-0000-4000-8000-000000000004' then 'integrity_normal'
    end,
    display_name = case id
      when 'f1000000-0000-4000-8000-000000000001' then 'Integrity Operator'
      when 'f1000000-0000-4000-8000-000000000002' then 'Integrity Owner'
      when 'f1000000-0000-4000-8000-000000000003' then 'Integrity Friend'
      when 'f1000000-0000-4000-8000-000000000004' then 'Integrity Normal'
    end,
    onboarding_completed_at = now()
where id in (
  'f1000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000002',
  'f1000000-0000-4000-8000-000000000003',
  'f1000000-0000-4000-8000-000000000004'
);

insert into public.relationships (
  user_low_id, user_high_id, status, initiator_id, responder_id,
  requested_at, responded_at
)
values (
  'f1000000-0000-4000-8000-000000000002',
  'f1000000-0000-4000-8000-000000000003',
  'accepted',
  'f1000000-0000-4000-8000-000000000002',
  'f1000000-0000-4000-8000-000000000003',
  now(), now()
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000001',
    'app_metadata', jsonb_build_object('catalog_event_operator', true)
  )::text,
  true
);

select set_config('test.integrity_area', (
  select catalog_id::text from public.create_custom_catalog_area(
    'Integrity City', 'US', null, null
  )
), true);
select set_config('test.integrity_artist', (
  select catalog_id::text from public.create_custom_catalog_artist(
    'Integrity Artist', 'Group', null,
    current_setting('test.integrity_area')::uuid, null
  )
), true);
select set_config('test.integrity_place', (
  select catalog_id::text from public.create_custom_catalog_place(
    'Integrity Hall', current_setting('test.integrity_area')::uuid,
    'Venue', null, null
  )
), true);

select set_config('test.merge_source', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 30,
    null,
    ((current_date - 30) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select set_config('test.merge_target', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 29,
    null,
    ((current_date - 29) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select set_config('test.tombstone_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 20,
    null,
    ((current_date - 20) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select set_config('test.detach_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 15,
    null,
    ((current_date - 15) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select set_config('test.relink_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 14,
    null,
    ((current_date - 14) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select set_config('test.future_relink_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date + 14,
    null,
    ((current_date + 14) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select set_config('test.conflict_source', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 10,
    null,
    ((current_date - 10) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);
select set_config('test.conflict_target', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 9,
    null,
    ((current_date - 9) + time '20:00') at time zone 'UTC',
    'UTC', 'listed'
  )
), true);

-- Build durable attendance and diaries with an ordinary account.
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000002',
    'app_metadata', '{}'::jsonb
  )::text,
  true
);

select * from public.set_catalog_event_attendance(
  current_setting('test.merge_source')::uuid, 'went', 'friends'
);
select set_config('test.merge_diary', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.merge_source')::uuid,
    9.5, 9, 'Keep this merge memory.', 'friends', true
  )
), true);
select * from public.set_catalog_event_attendance(
  current_setting('test.merge_target')::uuid, 'went', 'community'
);

select * from public.set_catalog_event_attendance(
  current_setting('test.tombstone_event')::uuid, 'went', 'community'
);
select set_config('test.tombstone_diary', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.tombstone_event')::uuid,
    8.5, null, 'Keep this tombstoned memory.', 'community', true
  )
), true);

select * from public.set_catalog_event_attendance(
  current_setting('test.detach_event')::uuid, 'went', 'friends'
);
select set_config('test.detach_diary', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.detach_event')::uuid,
    10, 9.5, 'Keep this detached memory.', 'friends', true
  )
), true);

select * from public.set_catalog_event_attendance(
  current_setting('test.conflict_source')::uuid, 'went', 'private'
);
select set_config('test.conflict_source_diary', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.conflict_source')::uuid,
    7.5, null, 'Source perspective.', 'private', true
  )
), true);
select * from public.set_catalog_event_attendance(
  current_setting('test.conflict_target')::uuid, 'went', 'private'
);
select set_config('test.conflict_target_diary', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.conflict_target')::uuid,
    8, null, 'Target perspective.', 'private', true
  )
), true);

reset role;
select set_config('test.merge_source_attendance', (
  select id::text from public.catalog_event_attendance
  where event_id = current_setting('test.merge_source')::uuid
    and profile_id = 'f1000000-0000-4000-8000-000000000002'
), true);
select set_config('test.merge_target_attendance', (
  select id::text from public.catalog_event_attendance
  where event_id = current_setting('test.merge_target')::uuid
    and profile_id = 'f1000000-0000-4000-8000-000000000002'
), true);
select set_config('test.detach_attendance', (
  select id::text from public.catalog_event_attendance
  where event_id = current_setting('test.detach_event')::uuid
    and profile_id = 'f1000000-0000-4000-8000-000000000002'
), true);
set local role authenticated;

-- A second person's non-conflicting Went row should move with its stable ID.
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000003', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000003',
    'app_metadata', '{}'::jsonb
  )::text,
  true
);
select * from public.set_catalog_event_attendance(
  current_setting('test.merge_source')::uuid, 'went', 'community'
);
reset role;
select set_config('test.friend_source_attendance', (
  select id::text from public.catalog_event_attendance
  where event_id = current_setting('test.merge_source')::uuid
    and profile_id = 'f1000000-0000-4000-8000-000000000003'
), true);
set local role authenticated;

-- A normal account cannot reach any operator surface.
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000004', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000004',
    'app_metadata', '{}'::jsonb
  )::text,
  true
);
select throws_ok(
  $$select * from public.review_catalog_event_merge(
    current_setting('test.merge_source')::uuid,
    current_setting('test.merge_target')::uuid
  )$$,
  '42501', null,
  'merge review requires the protected operator claim'
);
select throws_ok(
  $$select * from public.tombstone_catalog_event(
    current_setting('test.tombstone_event')::uuid, 1, 'safety'
  )$$,
  '42501', null,
  'event tombstones require the protected operator claim'
);
select throws_ok(
  $$select * from public.detach_personal_diary(
    current_setting('test.detach_diary')::uuid, 'privacy_request'
  )$$,
  '42501', null,
  'diary detach requires the protected operator claim'
);
select throws_ok(
  $$select count(*) from private.catalog_event_integrity_operations$$,
  '42501', null,
  'authenticated clients cannot read private integrity audits'
);

-- Review and execute the merge with a fresh operator claim.
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000001',
    'app_metadata', jsonb_build_object('catalog_event_operator', true)
  )::text,
  true
);
select is(
  (select duplicate_attendance_count from public.review_catalog_event_merge(
    current_setting('test.merge_source')::uuid,
    current_setting('test.merge_target')::uuid
  )),
  1::bigint,
  'merge review counts duplicate attendance without deleting it'
);
select is(
  (select source_diary_count from public.review_catalog_event_merge(
    current_setting('test.merge_source')::uuid,
    current_setting('test.merge_target')::uuid
  )),
  1::bigint,
  'merge review counts source diaries'
);
select ok(
  (select can_merge from public.review_catalog_event_merge(
    current_setting('test.merge_source')::uuid,
    current_setting('test.merge_target')::uuid
  )),
  'review approves a merge with no duplicate diary owner'
);
select throws_ok(
  $$select * from public.merge_catalog_events(
    current_setting('test.merge_source')::uuid,
    current_setting('test.merge_target')::uuid,
    0, 1, 'duplicate_event'
  )$$,
  'P0001', null,
  'a stale merge review cannot mutate either event'
);
select lives_ok(
  $$select * from public.merge_catalog_events(
    current_setting('test.merge_source')::uuid,
    current_setting('test.merge_target')::uuid,
    1, 1, 'duplicate_event'
  )$$,
  'an operator can merge two freshly reviewed events'
);

reset role;
select is(
  (select row_state::text from public.catalog_events
   where id = current_setting('test.merge_source')::uuid),
  'merged',
  'the source becomes a durable redirect row'
);
select is(
  (select merged_into_event_id from public.catalog_events
   where id = current_setting('test.merge_source')::uuid),
  current_setting('test.merge_target')::uuid,
  'the source redirect points at the reviewed target'
);
select is(
  (select count(*) from public.catalog_event_attendance
   where profile_id in (
     'f1000000-0000-4000-8000-000000000002',
     'f1000000-0000-4000-8000-000000000003'
   )
     and event_id in (
       current_setting('test.merge_source')::uuid,
       current_setting('test.merge_target')::uuid
     )),
  3::bigint,
  'merge preserves every underlying attendance row'
);
select is(
  (select superseded_by_attendance_id from public.catalog_event_attendance
   where id = current_setting('test.merge_source_attendance')::uuid),
  current_setting('test.merge_target_attendance')::uuid,
  'duplicate attendance remains as an explicitly superseded record'
);
select is(
  (select event_id from public.catalog_event_attendance
   where id = current_setting('test.friend_source_attendance')::uuid),
  current_setting('test.merge_target')::uuid,
  'non-conflicting attendance keeps its stable ID while moving to the target'
);
select is(
  (select catalog_event_id from public.concerts
   where id = current_setting('test.merge_diary')::uuid),
  current_setting('test.merge_target')::uuid,
  'the source diary moves to the canonical event'
);
select is(
  (select attendance_id from public.concerts
   where id = current_setting('test.merge_diary')::uuid),
  current_setting('test.merge_target_attendance')::uuid,
  'the moved diary links to the effective Went row'
);
select is(
  (select review_body from public.diary_reviews
   where concert_id = current_setting('test.merge_diary')::uuid),
  'Keep this merge memory.',
  'merge preserves the personal review content'
);
select is(
  (select count(*) from private.catalog_event_integrity_operations
   where operation = 'merge'
     and source_event_id = current_setting('test.merge_source')::uuid),
  1::bigint,
  'merge appends one private audit record'
);
select is(
  (select count(*) from private.catalog_event_revisions
   where event_id in (
     current_setting('test.merge_source')::uuid,
     current_setting('test.merge_target')::uuid
   ) and changed_by = 'f1000000-0000-4000-8000-000000000001'),
  2::bigint,
  'merge records correction history for source and target'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000002',
    'app_metadata', '{}'::jsonb
  )::text,
  true
);
select is(
  (select event_id from public.get_catalog_event_detail(
    current_setting('test.merge_source')::uuid
  )),
  current_setting('test.merge_target')::uuid,
  'opening the old event ID redirects to canonical detail'
);
select is(
  (select count(*) from public.list_catalog_event_diaries(
    current_setting('test.merge_source')::uuid, 'mine', null, 30
  ) where diary_id = current_setting('test.merge_diary')::uuid),
  1::bigint,
  'the old event ID also resolves the moved diary collection'
);

-- Cancellation and tombstoning never cascade into user history.
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000001',
    'app_metadata', jsonb_build_object('catalog_event_operator', true)
  )::text,
  true
);
select lives_ok(
  $$select * from public.update_catalog_event(
    current_setting('test.tombstone_event')::uuid,
    1,
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.integrity_artist'),
      'is_primary', true
    )),
    current_setting('test.integrity_place')::uuid,
    current_date - 20,
    null,
    ((current_date - 20) + time '20:00') at time zone 'UTC',
    'UTC', 'listed', 'cancelled'
  )$$,
  'a creator cancellation is a factual event correction'
);
select is(
  (select count(*) from public.concerts
   where id = current_setting('test.tombstone_diary')::uuid),
  1::bigint,
  'cancellation preserves the personal diary row'
);
select lives_ok(
  $$select * from public.tombstone_catalog_event(
    current_setting('test.tombstone_event')::uuid, 2, 'invalid_event'
  )$$,
  'an operator can tombstone a reviewed invalid occurrence'
);

reset role;
select is(
  (select count(*) from public.catalog_event_attendance
   where event_id = current_setting('test.tombstone_event')::uuid),
  1::bigint,
  'tombstoning preserves Went attendance'
);
select is(
  (select count(*) from public.concerts
   where id = current_setting('test.tombstone_diary')::uuid
     and catalog_event_id = current_setting('test.tombstone_event')::uuid),
  1::bigint,
  'tombstoning preserves the linked diary and its event snapshot'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000002',
    'app_metadata', '{}'::jsonb
  )::text,
  true
);
select throws_ok(
  $$select * from public.get_catalog_event_detail(
    current_setting('test.tombstone_event')::uuid
  )$$,
  '42501', null,
  'a tombstoned occurrence no longer opens as shared event detail'
);
select is(
  (select event ->> 'row_state'
   from public.list_catalog_profile_event_history(
     'f1000000-0000-4000-8000-000000000002', null, 50
   )
   where history_kind = 'diary'
     and diary ->> 'diary_id' = current_setting('test.tombstone_diary')),
  'tombstoned',
  'the owner still sees a tombstoned diary through durable profile history'
);

-- Exceptional detach preserves the diary privately, then relink reuses it.
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000001',
    'app_metadata', jsonb_build_object('catalog_event_operator', true)
  )::text,
  true
);
select lives_ok(
  $$select * from public.detach_personal_diary(
    current_setting('test.detach_diary')::uuid, 'privacy_request'
  )$$,
  'an operator can exceptionally detach a diary with a fixed reason code'
);
select throws_ok(
  $$select * from public.relink_personal_diary(
    current_setting('test.detach_diary')::uuid,
    current_setting('test.future_relink_event')::uuid,
    'recovery'
  )$$,
  '22023', null,
  'a detached concert memory cannot be relinked to a future occurrence'
);

reset role;
select is(
  (select detached_event_reason from public.concerts
   where id = current_setting('test.detach_diary')::uuid),
  'privacy_request',
  'the diary records a generic detachment marker'
);
select is(
  (select diary_audience::text from public.concerts
   where id = current_setting('test.detach_diary')::uuid),
  'private',
  'exceptional detach fails closed to a private diary'
);
select is(
  (select review_body from public.diary_reviews
   where concert_id = current_setting('test.detach_diary')::uuid),
  'Keep this detached memory.',
  'detachment preserves review content'
);
select is(
  (select event_id from public.catalog_event_attendance
   where id = current_setting('test.detach_attendance')::uuid),
  current_setting('test.detach_event')::uuid,
  'detachment preserves the original Went row'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000002',
    'app_metadata', '{}'::jsonb
  )::text,
  true
);
select is(
  (select event ->> 'event_id'
   from public.list_catalog_profile_event_history(
     'f1000000-0000-4000-8000-000000000002', null, 50
   )
   where history_kind = 'diary'
     and diary ->> 'diary_id' = current_setting('test.detach_diary')),
  current_setting('test.detach_event'),
  'the owner profile uses the private detachment snapshot'
);

select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000003', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000003',
    'app_metadata', '{}'::jsonb
  )::text,
  true
);
select is(
  (select count(*) from public.list_catalog_profile_event_history(
    'f1000000-0000-4000-8000-000000000002', null, 50
  ) where history_kind = 'diary'
    and diary ->> 'diary_id' = current_setting('test.detach_diary')),
  0::bigint,
  'a friend immediately loses the force-private detached diary'
);

select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000001',
    'app_metadata', jsonb_build_object('catalog_event_operator', true)
  )::text,
  true
);
select lives_ok(
  $$select * from public.relink_personal_diary(
    current_setting('test.detach_diary')::uuid,
    current_setting('test.relink_event')::uuid,
    'recovery'
  )$$,
  'an audited recovery can relink the same diary to a recreated occurrence'
);

reset role;
select is(
  (select catalog_event_id from public.concerts
   where id = current_setting('test.detach_diary')::uuid),
  current_setting('test.relink_event')::uuid,
  'relink reuses the stable diary ID on the new event'
);
select is(
  (select id from public.catalog_event_attendance
   where event_id = current_setting('test.relink_event')::uuid
     and profile_id = 'f1000000-0000-4000-8000-000000000002'),
  current_setting('test.detach_attendance')::uuid,
  'relink reuses the stable Went row when no target conflict exists'
);
select is(
  (select count(*) from private.catalog_event_integrity_operations
   where diary_id = current_setting('test.detach_diary')::uuid
     and operation in ('diary_detach', 'diary_relink')),
  2::bigint,
  'detach and relink each append an immutable recovery audit'
);

-- Duplicate diaries are surfaced for review and never guessed away.
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'sub', 'f1000000-0000-4000-8000-000000000001',
    'app_metadata', jsonb_build_object('catalog_event_operator', true)
  )::text,
  true
);
select is(
  (select duplicate_diary_count from public.review_catalog_event_merge(
    current_setting('test.conflict_source')::uuid,
    current_setting('test.conflict_target')::uuid
  )),
  1::bigint,
  'merge review identifies a same-owner diary conflict'
);
select ok(
  not (select can_merge from public.review_catalog_event_merge(
    current_setting('test.conflict_source')::uuid,
    current_setting('test.conflict_target')::uuid
  )),
  'review refuses to approve a merge that would guess between diaries'
);
select throws_ok(
  $$select * from public.merge_catalog_events(
    current_setting('test.conflict_source')::uuid,
    current_setting('test.conflict_target')::uuid,
    1, 1, 'duplicate_event'
  )$$,
  'P0001', null,
  'the merge transaction refuses duplicate diary ownership'
);

reset role;
select is(
  (select count(*) from public.catalog_events
   where id in (
     current_setting('test.conflict_source')::uuid,
     current_setting('test.conflict_target')::uuid
   ) and row_state = 'active'),
  2::bigint,
  'a rejected conflict leaves both events and diaries untouched'
);
select throws_ok(
  $$update private.catalog_event_integrity_operations
    set reason_code = 'safety'$$,
  '42501', null,
  'integrity audit rows cannot be updated even by a database operator'
);
select throws_ok(
  $$delete from private.catalog_event_integrity_operations$$,
  '42501', null,
  'integrity audit rows cannot be deleted even by a database operator'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.merge_catalog_events(uuid,uuid,integer,integer,text)',
    'execute'
  ),
  'anonymous clients cannot execute merge operations'
);
select ok(
  (select bool_and(pg_column_size(record_snapshot) <= 65536)
   from private.catalog_event_integrity_operations),
  'private integrity snapshots stay within their bounded audit size'
);

select * from finish();
rollback;
