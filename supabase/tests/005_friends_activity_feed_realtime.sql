begin;

select plan(24);

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '51000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'feed-owner@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '52000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'feed-editor@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '53000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'feed-friend@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '54000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'feed-outsider@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

update public.profiles
set
  username = case id
    when '51000000-0000-0000-0000-000000000001'::uuid then 'feed_owner'
    when '52000000-0000-0000-0000-000000000002'::uuid then 'feed_editor'
    when '53000000-0000-0000-0000-000000000003'::uuid then 'feed_friend'
    when '54000000-0000-0000-0000-000000000004'::uuid then 'feed_outside'
  end,
  display_name = case id
    when '51000000-0000-0000-0000-000000000001'::uuid then 'Feed Owner'
    when '52000000-0000-0000-0000-000000000002'::uuid then 'Feed Editor'
    when '53000000-0000-0000-0000-000000000003'::uuid then 'Feed Friend'
    when '54000000-0000-0000-0000-000000000004'::uuid then 'Feed Outside'
  end,
  onboarding_completed_at = now()
where id in (
  '51000000-0000-0000-0000-000000000001',
  '52000000-0000-0000-0000-000000000002',
  '53000000-0000-0000-0000-000000000003',
  '54000000-0000-0000-0000-000000000004'
);

insert into public.relationships (
  user_low_id,
  user_high_id,
  status,
  initiator_id,
  responder_id,
  requested_at,
  responded_at
)
values
  (
    '51000000-0000-0000-0000-000000000001',
    '52000000-0000-0000-0000-000000000002',
    'accepted',
    '51000000-0000-0000-0000-000000000001',
    '52000000-0000-0000-0000-000000000002',
    now(),
    now()
  ),
  (
    '51000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000003',
    'accepted',
    '51000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000003',
    now(),
    now()
  );

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);

select set_config(
  'test.feed_shared_concert_id',
  (
    select (public.create_private_concert(
      '[{"name":"Ethel Cain","is_primary":true}]'::jsonb,
      'The Independent',
      date '2026-07-08',
      p_setlist => '["American Teenager"]'::jsonb
    )).id::text
  ),
  true
);

select is(
  (
    select (public.update_concert(
      current_setting('test.feed_shared_concert_id')::uuid,
      1,
      '[{"name":"Ethel Cain","is_primary":true}]'::jsonb,
      'The Independent',
      date '2026-07-08',
      p_setlist => '["American Teenager"]'::jsonb,
      p_visibility => 'collaborators'
    )).version
  ),
  2::bigint,
  'the feed fixture concert can become Collaborators-visible'
);
select is(
  (
    select (public.tag_concert_collaborator(
      current_setting('test.feed_shared_concert_id')::uuid,
      '52000000-0000-0000-0000-000000000002',
      2
    )).version
  ),
  3::bigint,
  'the fixture has one editor before feed visibility broadens'
);
select is(
  (
    select (public.update_concert(
      current_setting('test.feed_shared_concert_id')::uuid,
      3,
      '[{"name":"Ethel Cain","is_primary":true}]'::jsonb,
      'The Independent',
      date '2026-07-08',
      p_tour => 'Willoughby Tucker Tour',
      p_setlist => '["American Teenager"]'::jsonb,
      p_visibility => 'collaborators'
    )).version
  ),
  4::bigint,
  'an owner edit merges into the existing direct-notification job'
);

reset role;
select is(
  (
    select count(*)
    from public.direct_collaboration_notifications
    where concert_id = current_setting('test.feed_shared_concert_id')::uuid
      and recipient_id = '52000000-0000-0000-0000-000000000002'
  ),
  1::bigint,
  'tag plus rapid edit create one five-minute notification job'
);
select is(
  (
    select activity_count
    from public.direct_collaboration_notifications
    where concert_id = current_setting('test.feed_shared_concert_id')::uuid
      and recipient_id = '52000000-0000-0000-0000-000000000002'
  ),
  2,
  'the notification outbox records aggregate activity count without payload content'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '52000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*) from public.profile_concert_history('52000000-0000-0000-0000-000000000002')),
  1::bigint,
  'a collaborator profile includes concerts they are tagged on'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '53000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*) from public.profile_concert_history('51000000-0000-0000-0000-000000000001')),
  0::bigint,
  'a friend profile history still hides Collaborators-only concerts'
);
select is(
  (select count(*) from public.friends_activity_feed()),
  0::bigint,
  'Friends activity honors current concert visibility rather than historic events alone'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);

select is(
  (
    select (public.update_concert(
      current_setting('test.feed_shared_concert_id')::uuid,
      4,
      '[{"name":"Ethel Cain","is_primary":true}]'::jsonb,
      'The Independent',
      date '2026-07-08',
      p_tour => 'Willoughby Tucker Tour',
      p_setlist => '["American Teenager"]'::jsonb,
      p_visibility => 'friends'
    )).version
  ),
  5::bigint,
  'the owner can make the shared concert Friends-visible'
);
select set_config(
  'test.feed_second_concert_id',
  (
    select (public.create_private_concert(
      '[{"name":"Clairo","is_primary":true}]'::jsonb,
      'The Fox',
      date '2026-06-22'
    )).id::text
  ),
  true
);
select set_config(
  'test.feed_third_concert_id',
  (
    select (public.create_private_concert(
      '[{"name":"SZA","is_primary":true}]'::jsonb,
      'Chase Center',
      date '2026-05-20'
    )).id::text
  ),
  true
);
select lives_ok(
  $$select public.update_concert(
    current_setting('test.feed_second_concert_id')::uuid,
    1,
    '[{"name":"Clairo","is_primary":true}]'::jsonb,
    'The Fox',
    date '2026-06-22',
    p_setlist => '[]'::jsonb,
    p_visibility => 'friends'
  )$$,
  'a second Friends-visible concert creates another feed source'
);
select lives_ok(
  $$select public.update_concert(
    current_setting('test.feed_third_concert_id')::uuid,
    1,
    '[{"name":"SZA","is_primary":true}]'::jsonb,
    'Chase Center',
    date '2026-05-20',
    p_setlist => '[]'::jsonb,
    p_visibility => 'friends'
  )$$,
  'a third Friends-visible concert creates another feed source'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '53000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*) from public.profile_concert_history('51000000-0000-0000-0000-000000000001')),
  3::bigint,
  'friend profile history reflects all currently Friends-visible concerts'
);
select is(
  (select count(*) from public.friends_activity_feed(p_limit => 2)),
  2::bigint,
  'Friends feed honors its cursor-page size'
);
select set_config(
  'test.feed_cursor_occurred_at',
  (
    select occurred_at::text
    from public.friends_activity_feed(p_limit => 2)
    order by occurred_at desc, id desc
    offset 1 limit 1
  ),
  true
);
select set_config(
  'test.feed_cursor_id',
  (
    select id::text
    from public.friends_activity_feed(p_limit => 2)
    order by occurred_at desc, id desc
    offset 1 limit 1
  ),
  true
);
select is(
  (
    select count(*)
    from public.friends_activity_feed(
      current_setting('test.feed_cursor_occurred_at')::timestamptz,
      current_setting('test.feed_cursor_id')::uuid,
      30
    )
  ),
  2::bigint,
  'the feed cursor loads the next older slice without duplication'
);
select is(
  (
    select count(*)
    from public.concert_events
    where concert_id = current_setting('test.feed_shared_concert_id')::uuid
  ),
  2::bigint,
  'a Friends viewer receives only the safe creation and ordinary-edit event subset'
);
select is(
  (
    select count(*)
    from public.concert_events
    where concert_id = current_setting('test.feed_shared_concert_id')::uuid
      and event_type in ('collaborator_tagged', 'visibility_changed')
  ),
  0::bigint,
  'Friends cannot read collaborator or visibility-management history entries'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '52000000-0000-0000-0000-000000000002', true);

select lives_ok(
  $$select public.update_concert(
    current_setting('test.feed_shared_concert_id')::uuid,
    5,
    '[{"name":"Ethel Cain","is_primary":true}]'::jsonb,
    'The Independent',
    date '2026-07-08',
    p_tour => 'Willoughby Tucker Tour',
    p_setlist => '["American Teenager","Crush"]'::jsonb,
    p_visibility => 'friends'
  )$$,
  'an editor update remains a canonical event but is not generic friend activity for strangers'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '53000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*) from public.friends_activity_feed()),
  4::bigint,
  'a viewer sees only actions from their own accepted friends, not an unrelated editor'
);
select set_config(
  'test.feed_comment_id',
  (
    select (public.create_concert_comment(
      current_setting('test.feed_shared_concert_id')::uuid,
      'I still think about this one.'
    )).id::text
  ),
  true
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);

select is(
  (
    select count(*)
    from public.friends_activity_feed()
    where actor_id = '53000000-0000-0000-0000-000000000003'
      and event_type = 'comment_added'
  ),
  1::bigint,
  'a concert owner sees a friend comment as a feed action without the comment body'
);
select lives_ok(
  $$select public.remove_friend('53000000-0000-0000-0000-000000000003')$$,
  'the owner can remove the feed viewer as a friend'
);
select is(
  (
    select count(*)
    from public.friends_activity_feed()
    where actor_id = '53000000-0000-0000-0000-000000000003'
  ),
  0::bigint,
  'friend removal hides prior feed activity immediately under current-relationship filtering'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '53000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*) from public.friends_activity_feed()),
  0::bigint,
  'a removed friend loses all prior activity-feed access immediately'
);
select is(
  (select count(*) from public.concerts where id = current_setting('test.feed_shared_concert_id')::uuid),
  0::bigint,
  'a removed friend also loses the currently Friends-visible concert'
);

reset role;
select is(
  (
    select count(*)
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename in ('concerts', 'concert_collaborators', 'comments', 'concert_events')
  ),
  4::bigint,
  'Realtime publishes only the concert records the app uses as targeted refresh signals'
);

select * from finish();

rollback;
