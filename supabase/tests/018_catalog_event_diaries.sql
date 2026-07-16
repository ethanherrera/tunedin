begin;

select plan(41);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e5000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'diary-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e5000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'diary-friend@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e5000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'diary-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e5000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'diary-second@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
      when 'e5000000-0000-4000-8000-000000000001' then 'diary_owner'
      when 'e5000000-0000-4000-8000-000000000002' then 'diary_friend'
      when 'e5000000-0000-4000-8000-000000000003' then 'diary_outsider'
      when 'e5000000-0000-4000-8000-000000000004' then 'diary_second'
    end,
    display_name = case id
      when 'e5000000-0000-4000-8000-000000000001' then 'Diary Owner'
      when 'e5000000-0000-4000-8000-000000000002' then 'Diary Friend'
      when 'e5000000-0000-4000-8000-000000000003' then 'Diary Outsider'
      when 'e5000000-0000-4000-8000-000000000004' then 'Diary Second'
    end,
    onboarding_completed_at = now()
where id in (
  'e5000000-0000-4000-8000-000000000001',
  'e5000000-0000-4000-8000-000000000002',
  'e5000000-0000-4000-8000-000000000003',
  'e5000000-0000-4000-8000-000000000004'
);

insert into public.relationships (
  user_low_id, user_high_id, status, initiator_id, responder_id,
  requested_at, responded_at
)
values
  ('e5000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000002', 'accepted', 'e5000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000002', now(), now()),
  ('e5000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000004', 'accepted', 'e5000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000004', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);

select set_config('test.diary_area', (
  select catalog_id::text from public.create_custom_catalog_area(
    'Diary City', 'US', null, null
  )
), true);
select set_config('test.diary_artist', (
  select catalog_id::text from public.create_custom_catalog_artist(
    'Diary Artist', 'Group', null, current_setting('test.diary_area')::uuid, null
  )
), true);
select set_config('test.diary_place', (
  select catalog_id::text from public.create_custom_catalog_place(
    'Diary Hall', current_setting('test.diary_area')::uuid, 'Venue', null, null
  )
), true);
select set_config('test.diary_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.diary_artist'),
      'is_primary', true
    )),
    current_setting('test.diary_place')::uuid,
    current_date - 10,
    null,
    ((current_date - 10) + time '20:00') at time zone 'UTC',
    'UTC',
    'listed'
  )
), true);

select lives_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.diary_event')::uuid, 'went', 'private'
  )$$,
  'Went can exist privately without a diary'
);
select is(
  (select count(*) from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'all', null, 30
  )),
  0::bigint,
  'attendance alone does not create a diary'
);
select throws_ok(
  $$select * from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    null, null, null, 'friends', true
  )$$,
  '22023', null,
  'an empty diary cannot be published'
);
select throws_ok(
  $$select * from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    9.2, null, 'Invalid score step', 'friends', true
  )$$,
  '22023', null,
  'scores use a fixed half-point scale'
);

select set_config('test.diary_id', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    9.5, 9.0, 'The final run was unforgettable.', 'friends', true
  )
), true);

select is(
  (select record_model::text from public.concerts
   where id = current_setting('test.diary_id')::uuid),
  'personal_diary',
  'new event memories are personal diary records'
);

reset role;
select is(
  (select attendance.profile_id from public.concerts as diary
   join public.catalog_event_attendance as attendance on attendance.id = diary.attendance_id
   where diary.id = current_setting('test.diary_id')::uuid),
  'e5000000-0000-4000-8000-000000000001'::uuid,
  'the diary links to its author Went record'
);
select is(
  (select overall_score_points from public.diary_reviews
   where concert_id = current_setting('test.diary_id')::uuid),
  95::smallint,
  'scores are stored as fixed integer points'
);
select is(
  (select count(*) from public.social_activity_events
   where subject_id = current_setting('test.diary_id')::uuid
     and action = 'diary_published'),
  1::bigint,
  'first publication records one immutable diary activity'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select is(
  (select diary_id from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    10, 9.5, 'An updated personal note.', 'friends', true
  )),
  current_setting('test.diary_id')::uuid,
  'saving again updates the same diary'
);
select is(
  (select count(*) from public.concerts
   where owner_id = 'e5000000-0000-4000-8000-000000000001'
     and catalog_event_id = current_setting('test.diary_event')::uuid
     and record_model = 'personal_diary'),
  1::bigint,
  'one person has at most one active diary per event'
);

reset role;
select is(
  (select count(*) from public.social_activity_events
   where subject_id = current_setting('test.diary_id')::uuid
     and action = 'diary_published'),
  1::bigint,
  'editing a published diary does not duplicate publication activity'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.diary_event')::uuid, 'went', 'community'
  )$$,
  'attendance audience can change independently from diary audience'
);
select is(
  (select diary_audience::text from public.concerts
   where id = current_setting('test.diary_id')::uuid),
  'friends',
  'changing Went audience does not change diary audience'
);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.diary_event')::uuid, 'did_not_go', 'community'
  )$$,
  '23503', null,
  'a linked Went record cannot be changed to Did not go'
);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.diary_event')::uuid, null, 'community'
  )$$,
  '23503', null,
  'a linked Went record cannot be deleted before its diary'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'all', null, 30
  )),
  1::bigint,
  'a friend can read a friends-audience diary'
);
select is(
  (select review_body from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'all', null, 30
  )),
  'An updated personal note.',
  'visible diary previews return the author review'
);
select lives_ok(
  format(
    'select * from public.create_concert_comment(%L, %L)',
    current_setting('test.diary_id'),
    'I loved this part too.'
  ),
  'a visible friend can comment on the personal diary'
);
select is(
  (select comment_count from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'all', null, 30
  )),
  1::bigint,
  'diary previews include a bounded comment count'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'all', null, 30
  )),
  0::bigint,
  'an unrelated profile cannot read a friends-audience diary'
);
select is(
  (select diary_count from public.get_catalog_event_diary_summaries(
    array[current_setting('test.diary_event')::uuid]
  )),
  0::bigint,
  'aggregate counts exclude diaries the viewer cannot read'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    10, 9.5, 'Community can see this version.', 'community', true
  )$$,
  'the owner can expand the diary audience'
);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'community', null, 30
  )),
  1::bigint,
  'a community diary is readable without friendship'
);
select is(
  (select average_score from public.get_catalog_event_diary_summaries(
    array[current_setting('test.diary_event')::uuid]
  )),
  10.0::numeric,
  'visible aggregate scores use the fixed-point value'
);
select lives_ok(
  $$select public.block_profile('e5000000-0000-4000-8000-000000000001')$$,
  'an unrelated viewer can block the diary author'
);
select is(
  (select count(*) from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'all', null, 30
  )),
  0::bigint,
  'a block immediately hides a community diary'
);
select lives_ok(
  $$select public.unblock_profile('e5000000-0000-4000-8000-000000000001')$$,
  'the unrelated viewer can remove the block'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    10, 9.5, 'Private again.', 'private', true
  )$$,
  'the owner can make the diary private'
);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
select throws_ok(
  format('select * from public.list_concert_comments(%L, null, null, 30)', current_setting('test.diary_id')),
  '42501', null,
  'changing diary audience immediately revokes comment reads'
);
select throws_ok(
  format('select * from public.list_concert_photos(%L, null, null, 30)', current_setting('test.diary_id')),
  '42501', null,
  'changing diary audience immediately revokes album reads'
);
select throws_ok(
  $$select * from public.diary_reviews$$,
  '42501', null,
  'review rows are not directly exposed to clients'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.diary_event')::uuid, 'went', 'friends'
  )$$,
  'a second attendee can keep an independent Went row'
);
select set_config('test.photo_diary_id', (
  select diary_id::text from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    null, null, null, 'community', false
  )
), true);
select is(
  (select published_at from public.concerts
   where id = current_setting('test.photo_diary_id')::uuid),
  null::timestamptz,
  'an empty draft may exist before its photo is attached'
);

reset role;
insert into public.concert_photos (
  id, concert_id, uploader_id, object_path, status, created_at, expires_at
) values (
  'e5100000-0000-4000-8000-000000000001',
  current_setting('test.photo_diary_id')::uuid,
  'e5000000-0000-4000-8000-000000000004',
  'concerts/' || current_setting('test.photo_diary_id') || '/album/e5100000-0000-4000-8000-000000000001.jpg',
  'pending',
  clock_timestamp(),
  clock_timestamp() + interval '1 hour'
);
update public.concert_photos
set status = 'ready', attached_at = clock_timestamp()
where id = 'e5100000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$select * from public.upsert_catalog_event_diary(
    current_setting('test.diary_event')::uuid,
    null, null, null, 'community', true
  )$$,
  'a ready photo satisfies the diary publication requirement'
);
select is(
  (select photo_count from public.list_catalog_event_diaries(
    current_setting('test.diary_event')::uuid, 'mine', null, 30
  )),
  1::bigint,
  'a photo-only diary reports its ready media count'
);
select throws_ok(
  $$select public.prepare_concert_photo_deletion(
    'e5100000-0000-4000-8000-000000000001'
  )$$,
  '23514', null,
  'the only content on a published photo-only diary cannot be removed'
);

reset role;
insert into public.concert_photos (
  id, concert_id, uploader_id, object_path, status, created_at, expires_at
) values (
  'e5100000-0000-4000-8000-000000000002',
  current_setting('test.diary_id')::uuid,
  'e5000000-0000-4000-8000-000000000001',
  'concerts/' || current_setting('test.diary_id') || '/album/e5100000-0000-4000-8000-000000000002.jpg',
  'pending',
  clock_timestamp(),
  clock_timestamp() + interval '1 hour'
);
update public.concert_photos
set status = 'ready', attached_at = clock_timestamp()
where id = 'e5100000-0000-4000-8000-000000000002';

select is(
  (select count(*) from public.social_activity_events
   where subject_id = current_setting('test.diary_id')::uuid
     and action = 'diary_media_added'),
  1::bigint,
  'ready media on a published diary records immutable activity'
);
select ok(
  (select count(*) > 0 from private.catalog_event_notification_outbox
   where subject_id = current_setting('test.diary_id')::uuid
     and action in ('diary_published', 'diary_media_added')),
  'visible diary actions enqueue opaque friend notifications'
);
select is(
  (select count(*) from information_schema.columns
   where table_schema = 'private'
     and table_name = 'catalog_event_notification_outbox'
     and column_name in ('body', 'review', 'review_body', 'caption', 'event_name', 'profile_name')),
  0::bigint,
  'notification rows contain no review, caption, profile, or event text columns'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_catalog_profile_event_history(
    'e5000000-0000-4000-8000-000000000001', null, 50
  ) where history_kind = 'went'),
  1::bigint,
  'profile history exposes a visible Went record independently'
);
select is(
  (select count(*) from public.list_catalog_profile_event_history(
    'e5000000-0000-4000-8000-000000000004', null, 50
  ) where history_kind = 'diary'),
  1::bigint,
  'profile history exposes a visible personal diary separately'
);

select * from finish();
rollback;
