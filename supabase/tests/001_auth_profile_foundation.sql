begin;

select plan(20);

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
    '11111111-1111-1111-1111-111111111111',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'first@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'second@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

select ok(
  exists (
    select 1 from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'
      and username is null
      and display_name is null
      and onboarding_completed_at is null
  ),
  'auth user creation creates an incomplete profile'
);

select is(
  public.normalize_username('  River_SIDE  '),
  'river_side',
  'username normalization trims and lowercases'
);

select is(
  public.normalize_display_name('  River   Side  '),
  'River Side',
  'display name normalization trims and collapses whitespace'
);

select ok(public.is_valid_username('river_side'), 'a normalized username is valid');
select ok(not public.is_valid_username('river-side'), 'a username cannot contain punctuation');
select ok(not public.is_valid_username('ab'), 'a username must have at least three characters');

select throws_ok(
  $$
    update public.profiles
    set
      username = 'Invalid-Name',
      display_name = 'Valid Name',
      onboarding_completed_at = now()
    where id = '11111111-1111-1111-1111-111111111111'
  $$,
  '23514',
  null,
  'invalid usernames are rejected by a database constraint'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

select lives_ok(
  $$select public.complete_onboarding('River_Side', '  River   Side  ')$$,
  'an authenticated user can complete their own onboarding'
);

select is(
  (
    select username
    from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'
  ),
  'river_side',
  'onboarding persists a normalized username'
);

select is(
  (
    select display_name
    from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'
  ),
  'River Side',
  'onboarding persists a normalized display name'
);

select ok(
  (
    select onboarding_completed_at is not null
    from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'
  ),
  'onboarding marks the profile complete'
);

select ok(
  not public.is_username_available('river_side'),
  'a claimed username is unavailable'
);

select ok(
  public.is_username_available('new_handle'),
  'an available valid username is reported as available'
);

select is(
  (
    select count(*)
    from public.profiles
    where id = '22222222-2222-2222-2222-222222222222'
  ),
  0::bigint,
  'RLS prevents a user from reading another profile'
);

select throws_ok(
  $$
    update public.profiles
    set display_name = 'Tampered'
    where id = '11111111-1111-1111-1111-111111111111'
  $$,
  '42501',
  null,
  'direct profile updates are not granted to authenticated users'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

select throws_ok(
  $$select public.complete_onboarding('river_side', 'Second User')$$,
  '23505',
  null,
  'the transactional onboarding RPC rejects username races'
);

select throws_ok(
  $$select public.complete_onboarding('second_user', E'Second\nUser')$$,
  '22023',
  null,
  'the onboarding RPC rejects display names with control characters'
);

select is(
  (
    select public.complete_onboarding('second_user', 'Second User')
  ).username,
  'second_user',
  'a different user can claim an available username'
);

select ok(
  not public.is_username_available('bad-name'),
  'invalid usernames are never reported available'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$select public.complete_onboarding('guest_user', 'Guest User')$$,
  '42501',
  null,
  'anonymous callers cannot execute the onboarding RPC'
);

select * from finish();

rollback;
