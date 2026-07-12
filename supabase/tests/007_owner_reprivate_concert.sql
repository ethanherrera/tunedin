begin;

select plan(9);

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
    '71000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'reprivate-owner@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '72000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'reprivate-editor@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '73000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'reprivate-friend@example.test',
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
    when '71000000-0000-0000-0000-000000000001'::uuid then 'reprivate_owner'
    when '72000000-0000-0000-0000-000000000002'::uuid then 'reprivate_editor'
    when '73000000-0000-0000-0000-000000000003'::uuid then 'reprivate_friend'
  end,
  display_name = case id
    when '71000000-0000-0000-0000-000000000001'::uuid then 'Reprivate Owner'
    when '72000000-0000-0000-0000-000000000002'::uuid then 'Reprivate Editor'
    when '73000000-0000-0000-0000-000000000003'::uuid then 'Reprivate Friend'
  end,
  onboarding_completed_at = now()
where id in (
  '71000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000002',
  '73000000-0000-0000-0000-000000000003'
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
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000002',
    'accepted',
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000002',
    now(),
    now()
  ),
  (
    '71000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000003',
    'accepted',
    '71000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000003',
    now(),
    now()
  );

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);

select set_config(
  'test.reprivate_concert_id',
  (
    select (public.create_private_concert(
      '[{"name":"Fiona Apple","is_primary":true}]'::jsonb,
      'The Masonic',
      date '2026-10-08'
    )).id::text
  ),
  true
);

select lives_ok(
  $$select public.update_concert(
    current_setting('test.reprivate_concert_id')::uuid,
    1,
    '[{"name":"Fiona Apple","is_primary":true}]'::jsonb,
    'The Masonic',
    date '2026-10-08',
    p_setlist => '[]'::jsonb,
    p_visibility => 'collaborators'
  )$$,
  'the owner can share the re-private fixture with collaborators'
);
select is(
  (
    select (public.tag_concert_collaborator(
      current_setting('test.reprivate_concert_id')::uuid,
      '72000000-0000-0000-0000-000000000002',
      2
    )).version
  ),
  3::bigint,
  'the owner can add a collaborator before re-privatizing'
);
select is(
  (
    select (public.update_concert(
      current_setting('test.reprivate_concert_id')::uuid,
      3,
      '[{"name":"Fiona Apple","is_primary":true}]'::jsonb,
      'The Masonic',
      date '2026-10-08',
      p_setlist => '[]'::jsonb,
      p_visibility => 'friends'
    )).version
  ),
  4::bigint,
  'the owner can broaden the shared fixture to Friends'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '72000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.update_concert(
    current_setting('test.reprivate_concert_id')::uuid,
    4,
    '[{"name":"Fiona Apple","is_primary":true}]'::jsonb,
    'The Masonic',
    date '2026-10-08',
    p_setlist => '[]'::jsonb,
    p_visibility => 'private'
  )$$,
  '42501',
  'Only the concert owner can make this concert private',
  'an editor cannot make a shared concert private'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);

select is(
  (
    select (public.update_concert(
      current_setting('test.reprivate_concert_id')::uuid,
      4,
      '[{"name":"Fiona Apple","is_primary":true}]'::jsonb,
      'The Masonic',
      date '2026-10-08',
      p_setlist => '[]'::jsonb,
      p_visibility => 'private'
    )).version
  ),
  5::bigint,
  'the owner can make a shared concert private'
);

reset role;
select is(
  (select count(*) from public.concert_collaborators where concert_id = current_setting('test.reprivate_concert_id')::uuid),
  0::bigint,
  'making a concert private removes every persisted collaborator'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '73000000-0000-0000-0000-000000000003', true);
select is(
  (select count(*) from public.concerts where id = current_setting('test.reprivate_concert_id')::uuid),
  0::bigint,
  'a former Friends viewer immediately loses access to the private concert'
);

select set_config('request.jwt.claim.sub', '72000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*) from public.concerts where id = current_setting('test.reprivate_concert_id')::uuid),
  0::bigint,
  'a revoked editor immediately loses access to the private concert'
);

reset role;
select is(
  (
    select metadata ->> 'reason'
    from public.concert_events
    where concert_id = current_setting('test.reprivate_concert_id')::uuid
      and event_type = 'collaborator_removed'
    order by occurred_at desc, id desc
    limit 1
  ),
  'owner_made_private',
  'the access-revocation event records why the editor was removed'
);

select * from finish();

rollback;
