begin;

select plan(42);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e5000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'post-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e5000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'post-friend@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e5000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'post-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e5000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'post-second@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
      when 'e5000000-0000-4000-8000-000000000001' then 'post_owner'
      when 'e5000000-0000-4000-8000-000000000002' then 'post_friend'
      when 'e5000000-0000-4000-8000-000000000003' then 'post_outsider'
      when 'e5000000-0000-4000-8000-000000000004' then 'post_second'
    end,
    display_name = case id
      when 'e5000000-0000-4000-8000-000000000001' then 'Post Owner'
      when 'e5000000-0000-4000-8000-000000000002' then 'Post Friend'
      when 'e5000000-0000-4000-8000-000000000003' then 'Post Outsider'
      when 'e5000000-0000-4000-8000-000000000004' then 'Post Second'
    end,
    onboarding_completed_at = now()
where id in (
  'e5000000-0000-4000-8000-000000000001',
  'e5000000-0000-4000-8000-000000000002',
  'e5000000-0000-4000-8000-000000000003',
  'e5000000-0000-4000-8000-000000000004'
);

insert into public.relationships (
  user_low_id, user_high_id, status, initiator_id, responder_id, requested_at, responded_at
)
values (
  'e5000000-0000-4000-8000-000000000001',
  'e5000000-0000-4000-8000-000000000002',
  'accepted',
  'e5000000-0000-4000-8000-000000000001',
  'e5000000-0000-4000-8000-000000000002',
  now(), now()
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);

select set_config('test.post_area', (
  select catalog_id::text from public.create_custom_catalog_area('Post City', 'US', null)
), true);
select set_config('test.post_artist', (
  select catalog_id::text from public.create_custom_catalog_artist(
    'Post Artist', 'Group', null, current_setting('test.post_area')::uuid
  )
), true);
select set_config('test.post_place', (
  select catalog_id::text from public.create_custom_catalog_place(
    'Post Hall', current_setting('test.post_area')::uuid, 'Venue', null
  )
), true);
select set_config('test.post_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.post_artist'), 'is_primary', true
    )),
    current_setting('test.post_place')::uuid,
    current_date - 10,
    null,
    ((current_date - 10) + time '20:00') at time zone 'UTC',
    'UTC',
    'listed'
  )
), true);

select lives_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.post_event')::uuid, 'went', 'private'
  )$$,
  'Went can exist privately without a Post'
);
select is(
  (select count(*) from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'all', null, 30
  )),
  0::bigint,
  'attendance alone does not create a Post'
);
select throws_ok(
  $$select * from public.upsert_event_post(
    current_setting('test.post_event')::uuid, null, null, null, 'friends', true
  )$$,
  '22023', null,
  'an empty Post cannot be published'
);
select throws_ok(
  $$select * from public.upsert_event_post(
    current_setting('test.post_event')::uuid, 9.2, null, 'Invalid score step', 'friends', true
  )$$,
  '22023', null,
  'Post scores use a fixed half-point scale'
);

select set_config('test.post_id', (
  select post_id::text from public.upsert_event_post(
    current_setting('test.post_event')::uuid,
    9.5, 9.0, 'The final run was unforgettable.', 'friends', true
  )
), true);

reset role;
select is(
  (select attendance.profile_id from public.event_posts as post
   join public.catalog_event_attendance as attendance on attendance.id = post.attendance_id
   where post.id = current_setting('test.post_id')::uuid),
  'e5000000-0000-4000-8000-000000000001'::uuid,
  'the Post links to its author Went record'
);
select is(
  (select overall_score_points from public.event_posts
   where id = current_setting('test.post_id')::uuid),
  95::smallint,
  'Post scores are stored as fixed integer points'
);
select is(
  (select event_snapshot ->> 'event_id' from public.event_posts
   where id = current_setting('test.post_id')::uuid),
  current_setting('test.post_event'),
  'each Post owns a durable event snapshot'
);
select is(
  (select count(*) from public.social_activity_events
   where subject_id = current_setting('test.post_id')::uuid and action = 'post_published'),
  1::bigint,
  'first publication records one immutable Post activity'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select is(
  (select post_id from public.upsert_event_post(
    current_setting('test.post_event')::uuid,
    10, 9.5, 'An updated Post note.', 'friends', true
  )),
  current_setting('test.post_id')::uuid,
  'saving again updates the same Post'
);
select is(
  (select count(*) from public.event_posts
   where author_id = 'e5000000-0000-4000-8000-000000000001'
     and event_id = current_setting('test.post_event')::uuid
     and deleted_at is null),
  1::bigint,
  'one person has at most one active Post per event'
);
reset role;
select is(
  (select count(*) from public.social_activity_events
   where subject_id = current_setting('test.post_id')::uuid and action = 'post_published'),
  1::bigint,
  'editing a published Post does not duplicate publication activity'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.post_event')::uuid, 'went', 'community'
  )$$,
  'attendance audience can change independently from Post audience'
);
select is(
  (select audience::text from public.event_posts where id = current_setting('test.post_id')::uuid),
  'friends',
  'changing Went audience does not change Post audience'
);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.post_event')::uuid, 'did_not_go', 'community'
  )$$,
  '23514', null,
  'a linked Went record cannot change to Did not go'
);
select throws_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.post_event')::uuid, null, 'community'
  )$$,
  '23514', null,
  'a linked Went record cannot be removed before its Post'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'all', null, 30
  )),
  1::bigint,
  'a friend can read a friends-audience Post'
);
select is(
  (select note from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'all', null, 30
  )),
  'An updated Post note.',
  'visible Post previews return the author note'
);
select lives_ok(
  format(
    'select * from public.create_post_comment(%L, %L)',
    current_setting('test.post_id'),
    'I loved this part too.'
  ),
  'a visible friend can comment on the Post'
);
select is(
  (select comment_count from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'all', null, 30
  )),
  1::bigint,
  'Post previews include the visible comment count'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'all', null, 30
  )),
  0::bigint,
  'an unrelated profile cannot read a friends-audience Post'
);
select is(
  (select post_count from public.get_event_post_summaries(
    array[current_setting('test.post_event')::uuid]
  )),
  0::bigint,
  'aggregate counts exclude Posts the viewer cannot read'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.upsert_event_post(
    current_setting('test.post_event')::uuid,
    10, 9.5, 'Community can see this version.', 'community', true
  )$$,
  'the owner can expand Post sharing to the community'
);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'community', null, 30
  )),
  1::bigint,
  'a community Post is readable without friendship'
);
select is(
  (select average_score from public.get_event_post_summaries(
    array[current_setting('test.post_event')::uuid]
  )),
  10.0::numeric,
  'visible aggregate scores use the fixed-point value'
);
select lives_ok(
  $$select public.block_profile('e5000000-0000-4000-8000-000000000001')$$,
  'a viewer can block the Post author'
);
select is(
  (select count(*) from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'all', null, 30
  )),
  0::bigint,
  'a block immediately hides a community Post'
);
select lives_ok(
  $$select public.unblock_profile('e5000000-0000-4000-8000-000000000001')$$,
  'the viewer can remove the block'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.upsert_event_post(
    current_setting('test.post_event')::uuid,
    10, 9.5, 'Private again.', 'private', true
  )$$,
  'the owner can make a Post private'
);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'all', null, 30
  )),
  0::bigint,
  'changing Post sharing immediately revokes preview reads'
);
select throws_ok(
  format('select * from public.list_post_comments(%L, null, null, 30)', current_setting('test.post_id')),
  '42501', null,
  'changing Post sharing immediately revokes comment reads'
);

select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select set_config('test.media_id', (
  select id::text from public.reserve_post_media(
    current_setting('test.post_id')::uuid,
    'e5600000-0000-4000-8000-000000000001'
  )
), true);
select is(
  (select object_path from public.post_media where id = current_setting('test.media_id')::uuid),
  'posts/' || current_setting('test.post_id') || '/media/' || current_setting('test.media_id') || '.jpg',
  'Post media reservations use a fixed owner-scoped path'
);
insert into storage.objects (bucket_id, name, owner_id, metadata)
select 'images', object_path, auth.uid()::text, '{"mimetype":"image/jpeg","size":2000}'::jsonb
from public.post_media where id = current_setting('test.media_id')::uuid;
select lives_ok(
  $$select * from public.attach_post_media(current_setting('test.media_id')::uuid)$$,
  'the Post author can attach a valid reserved JPEG'
);
select is(
  (select status::text from public.post_media where id = current_setting('test.media_id')::uuid),
  'ready',
  'attached Post media becomes ready'
);
select is(
  (select photo_count from public.list_event_posts(
    current_setting('test.post_event')::uuid, 'mine', null, 30
  )),
  1::bigint,
  'Post previews include ready photo count'
);
reset role;
select is(
  (select count(*) from public.social_activity_events
   where subject_id = current_setting('test.post_id')::uuid and action = 'post_media_added'),
  1::bigint,
  'attaching media to a published Post records supported activity'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$select * from public.set_catalog_event_attendance(
    current_setting('test.post_event')::uuid, 'went', 'friends'
  )$$,
  'a second attendee can keep an independent Went row'
);
select lives_ok(
  $$select * from public.upsert_event_post(
    current_setting('test.post_event')::uuid, null, null, null, 'friends', false
  )$$,
  'an empty unpublished Post draft is allowed for a photo-first flow'
);

reset role;
select lives_ok(
  $$delete from public.catalog_events
    where id = current_setting('test.post_event')::uuid$$,
  'a hard source-event removal succeeds after detaching personal Posts'
);
select is(
  (select event_id from public.event_posts where id = current_setting('test.post_id')::uuid),
  null::uuid,
  'the surviving Post no longer points at the removed event'
);
select is(
  (select attendance_id from public.event_posts where id = current_setting('test.post_id')::uuid),
  null::uuid,
  'the surviving Post no longer depends on deleted attendance'
);
select is(
  (select event_snapshot ->> 'event_id' from public.event_posts
   where id = current_setting('test.post_id')::uuid),
  current_setting('test.post_event'),
  'the surviving Post retains its immutable event snapshot'
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
select is(
  (select count(*) from public.list_catalog_profile_event_history(
    'e5000000-0000-4000-8000-000000000001', null, 50
  ) where history_kind = 'post'
      and post ->> 'post_id' = current_setting('test.post_id')),
  1::bigint,
  'profile history still exposes the Post after its source event is gone'
);

select * from finish();
rollback;
