begin;

select plan(8);

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
    '61000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'revocation-owner@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '62000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'revocation-editor@example.test',
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
    when '61000000-0000-0000-0000-000000000001'::uuid then 'revoke_owner'
    when '62000000-0000-0000-0000-000000000002'::uuid then 'revoke_editor'
  end,
  display_name = case id
    when '61000000-0000-0000-0000-000000000001'::uuid then 'Revoke Owner'
    when '62000000-0000-0000-0000-000000000002'::uuid then 'Revoke Editor'
  end,
  onboarding_completed_at = now()
where id in (
  '61000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000002'
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
values (
  '61000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000002',
  'accepted',
  '61000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000002',
  now(),
  now()
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000001', true);

select set_config(
  'test.revocation_concert_id',
  (
    select (public.create_private_concert(
      '[{"name":"Big Thief","is_primary":true}]'::jsonb,
      'Fox Theater',
      date '2026-09-12'
    )).id::text
  ),
  true
);

select lives_ok(
  $$select public.update_concert(
    current_setting('test.revocation_concert_id')::uuid,
    1,
    '[{"name":"Big Thief","is_primary":true}]'::jsonb,
    'Fox Theater',
    date '2026-09-12',
    p_setlist => '[]'::jsonb,
    p_visibility => 'collaborators'
  )$$,
  'the access-revocation fixture can become shared'
);
select is(
  (
    select (public.tag_concert_collaborator(
      current_setting('test.revocation_concert_id')::uuid,
      '62000000-0000-0000-0000-000000000002',
      2
    )).version
  ),
  3::bigint,
  'an accepted friend receives an immediate editor role'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '62000000-0000-0000-0000-000000000002', true);

select lives_ok(
  $$select public.remove_friend('61000000-0000-0000-0000-000000000001')$$,
  'unfriending revokes the direct collaborator role in the same transaction'
);
select is(
  (select count(*) from public.concerts where id = current_setting('test.revocation_concert_id')::uuid),
  0::bigint,
  'an unfriended tagged editor no longer receives the shared concert'
);
select throws_ok(
  $$select public.create_concert_comment(
    current_setting('test.revocation_concert_id')::uuid,
    'Still here?'
  )$$,
  '42501',
  'You no longer have access to this concert',
  'an unfriended editor cannot continue to comment through stale UI'
);

reset role;
select is(
  (
    select count(*)
    from public.concert_collaborators
    where concert_id = current_setting('test.revocation_concert_id')::uuid
  ),
  0::bigint,
  'unfriending removes the persisted collaborator membership'
);
select is(
  (select version from public.concerts where id = current_setting('test.revocation_concert_id')::uuid),
  4::bigint,
  'relationship revocation advances the concert version for active editors'
);
select is(
  (
    select metadata ->> 'reason'
    from public.concert_events
    where concert_id = current_setting('test.revocation_concert_id')::uuid
      and event_type = 'collaborator_removed'
    order by occurred_at desc, id desc
    limit 1
  ),
  'friendship_ended',
  'the canonical history records the access-revocation reason without user content'
);

select * from finish();

rollback;
