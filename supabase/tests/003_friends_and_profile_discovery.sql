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
    '10000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'friends-owner@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'friends-recipient@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '30000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'friends-outsider@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '40000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'friends-decliner@example.test',
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
    when '10000000-0000-0000-0000-000000000001'::uuid then 'meadow_music'
    when '20000000-0000-0000-0000-000000000002'::uuid then 'morgan_moon'
    when '30000000-0000-0000-0000-000000000003'::uuid then 'outside_voice'
    when '40000000-0000-0000-0000-000000000004'::uuid then 'decline_dj'
  end,
  display_name = case id
    when '10000000-0000-0000-0000-000000000001'::uuid then 'Meadow Music'
    when '20000000-0000-0000-0000-000000000002'::uuid then 'Morgan Moon'
    when '30000000-0000-0000-0000-000000000003'::uuid then 'Outside Voice'
    when '40000000-0000-0000-0000-000000000004'::uuid then 'Decline DJ'
  end,
  onboarding_completed_at = now()
where id in (
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000003',
  '40000000-0000-0000-0000-000000000004'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*) from public.search_profiles('morg')),
  1::bigint,
  'username-prefix search finds a completed profile'
);
select is(
  (select relationship from public.search_profiles('morg')),
  'none',
  'a new discovery result has no relationship'
);
select is(
  (select count(*) from public.search_profiles('moon')),
  0::bigint,
  'discovery does not search display names or username middles'
);
select throws_ok(
  $$insert into public.relationships (user_low_id, user_high_id, status, initiator_id)
    values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'pending', '10000000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'relationship rows cannot be inserted directly by a client'
);
select lives_ok(
  $$select public.send_friend_request('20000000-0000-0000-0000-000000000002')$$,
  'an onboarded user can send a friend request'
);
select is(
  (select relationship from public.search_profiles('morg')),
  'outgoing',
  'the requester sees the outgoing state'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);

select is(
  (select relationship from public.profile_by_username('meadow_music')),
  'incoming',
  'the recipient sees the incoming state'
);
select is(
  (select count(*) from public.list_incoming_friend_requests()),
  1::bigint,
  'the recipient can load their incoming request list'
);
select is(
  (select count(*) from public.relationships),
  1::bigint,
  'a participant can read their relationship row'
);
select lives_ok(
  $$select public.accept_friend_request('10000000-0000-0000-0000-000000000001')$$,
  'the recipient can accept the incoming request'
);
select is(
  (select relationship from public.profile_by_username('meadow_music')),
  'friends',
  'accepted requests become friendships for the recipient'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select is(
  (select relationship from public.profile_by_username('morgan_moon')),
  'friends',
  'accepted requests become friendships for the sender'
);
select is(
  (select count(*) from public.list_profile_friends('meadow_music')),
  1::bigint,
  'a profile owner can view their friend list'
);
select is(
  (select count(*) from public.list_profile_friends('morgan_moon')),
  1::bigint,
  'an accepted friend can view the profile friend list'
);


reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.send_friend_request('40000000-0000-0000-0000-000000000004')$$,
  'another request can be sent to a different profile'
);
select lives_ok(
  $$select public.withdraw_friend_request('40000000-0000-0000-0000-000000000004')$$,
  'a requester can withdraw their pending request'
);
select is(
  (select relationship from public.profile_by_username('decline_dj')),
  'none',
  'withdrawing returns the pair to no relationship'
);
select lives_ok(
  $$select public.send_friend_request('40000000-0000-0000-0000-000000000004')$$,
  'a withdrawn request can be sent again'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000004', true);

select lives_ok(
  $$select public.decline_friend_request('10000000-0000-0000-0000-000000000001')$$,
  'a recipient can decline a request'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$select public.send_friend_request('40000000-0000-0000-0000-000000000004')$$,
  'P0001',
  'Try again in a few minutes',
  'a declined request observes the retry cooldown'
);
select lives_ok(
  $$select public.block_profile('20000000-0000-0000-0000-000000000002')$$,
  'a user can immediately block a former friend'
);
select is(
  (select count(*) from public.search_profiles('morg')),
  0::bigint,
  'blocked profiles disappear from discovery'
);


reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.unblock_profile('20000000-0000-0000-0000-000000000002')$$,
  'the blocker can unblock the profile'
);
select is(
  (select relationship from public.profile_by_username('morgan_moon')),
  'none',
  'unblocking does not restore a former friendship'
);

select * from finish();

rollback;
