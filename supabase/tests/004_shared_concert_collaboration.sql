begin;

select plan(40);

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
    '41000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'shared-owner@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '42000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'shared-editor@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '43000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'shared-friend@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '44000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'shared-outsider@example.test',
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
    when '41000000-0000-0000-0000-000000000001'::uuid then 'shared_owner'
    when '42000000-0000-0000-0000-000000000002'::uuid then 'shared_editor'
    when '43000000-0000-0000-0000-000000000003'::uuid then 'shared_friend'
    when '44000000-0000-0000-0000-000000000004'::uuid then 'shared_outside'
  end,
  display_name = case id
    when '41000000-0000-0000-0000-000000000001'::uuid then 'Shared Owner'
    when '42000000-0000-0000-0000-000000000002'::uuid then 'Shared Editor'
    when '43000000-0000-0000-0000-000000000003'::uuid then 'Shared Friend'
    when '44000000-0000-0000-0000-000000000004'::uuid then 'Shared Outside'
  end,
  onboarding_completed_at = now()
where id in (
  '41000000-0000-0000-0000-000000000001',
  '42000000-0000-0000-0000-000000000002',
  '43000000-0000-0000-0000-000000000003',
  '44000000-0000-0000-0000-000000000004'
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
    '41000000-0000-0000-0000-000000000001',
    '42000000-0000-0000-0000-000000000002',
    'accepted',
    '41000000-0000-0000-0000-000000000001',
    '42000000-0000-0000-0000-000000000002',
    now(),
    now()
  ),
  (
    '41000000-0000-0000-0000-000000000001',
    '43000000-0000-0000-0000-000000000003',
    'accepted',
    '41000000-0000-0000-0000-000000000001',
    '43000000-0000-0000-0000-000000000003',
    now(),
    now()
  );

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);

select set_config(
  'test.shared_concert_id',
  (
    select (public.create_private_concert(
      '[{"name":"  Soccer   Mommy ","is_primary":true}]'::jsonb,
      '  The  Warfield ',
      date '2026-08-18',
      p_setlist => '["Circle the Drain"]'::jsonb
    )).id::text
  ),
  true
);

select is(
  (select version from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  1::bigint,
  'a newly created concert begins at optimistic version one'
);
select throws_ok(
  $$select public.tag_concert_collaborator(
    current_setting('test.shared_concert_id')::uuid,
    '42000000-0000-0000-0000-000000000002',
    1
  )$$,
  '22023',
  'Choose Collaborators or Friends before tagging someone',
  'Private concerts cannot gain hidden collaborators'
);
select is(
  (select count(*) from public.concert_collaborators where concert_id = current_setting('test.shared_concert_id')::uuid),
  0::bigint,
  'a rejected private tag leaves no collaborator access behind'
);

select is(
  (
    select (public.update_concert(
      current_setting('test.shared_concert_id')::uuid,
      1,
      '[{"name":"Soccer Mommy","is_primary":true}]'::jsonb,
      'The Warfield',
      date '2026-08-18',
      p_setlist => '["Circle the Drain"]'::jsonb,
      p_visibility => 'collaborators'
    )).version
  ),
  2::bigint,
  'changing visibility creates a new concert version'
);
select is(
  (
    select count(*)
    from public.concert_events
    where concert_id = current_setting('test.shared_concert_id')::uuid
      and event_type = 'visibility_changed'
  ),
  1::bigint,
  'a visibility-only save records a canonical visibility event'
);
select throws_ok(
  $$select public.update_concert(
    current_setting('test.shared_concert_id')::uuid,
    1,
    '[{"name":"Soccer Mommy","is_primary":true}]'::jsonb,
    'The Warfield',
    date '2026-08-18',
    p_setlist => '["Circle the Drain"]'::jsonb,
    p_visibility => 'collaborators'
  )$$,
  '40001',
  'This concert changed elsewhere. Refresh and try again.',
  'a stale shared-concert save is rejected instead of silently overwriting'
);

select is(
  (
    select (public.tag_concert_collaborator(
      current_setting('test.shared_concert_id')::uuid,
      '42000000-0000-0000-0000-000000000002',
      2
    )).version
  ),
  3::bigint,
  'tagging a friend atomically grants editor access and advances the version'
);
select is(
  (select count(*) from public.concert_collaborators where concert_id = current_setting('test.shared_concert_id')::uuid),
  1::bigint,
  'a tagged collaborator is persisted once'
);
reset role;
select is(
  (
    select count(*)
    from public.direct_collaboration_notifications
    where concert_id = current_setting('test.shared_concert_id')::uuid
      and recipient_id = '42000000-0000-0000-0000-000000000002'
      and kind = 'collaborator_tagged'
  ),
  1::bigint,
  'tagging creates an opaque direct-collaboration notification job'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '42000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*) from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  1::bigint,
  'a tagged collaborator can read the concert immediately'
);
select is(
  (select count(*) from public.concert_collaborators where concert_id = current_setting('test.shared_concert_id')::uuid),
  1::bigint,
  'a tagged collaborator can load the collaborator list'
);
select results_eq(
  $$select username, is_owner from public.list_concert_collaborators(current_setting('test.shared_concert_id')::uuid)$$,
  $$values ('shared_owner'::text, true), ('shared_editor'::text, false)$$,
  'an editor can load an ordered collaborator list'
);
select is(
  (
    select (public.update_concert(
      current_setting('test.shared_concert_id')::uuid,
      3,
      '[{"name":"Soccer Mommy","is_primary":true}]'::jsonb,
      'The Warfield',
      date '2026-08-18',
      p_tour => 'Evergreen Tour',
      p_setlist => '["Circle the Drain","Your Dog"]'::jsonb,
      p_visibility => 'collaborators'
    )).version
  ),
  4::bigint,
  'an editor can update concert details and the setlist'
);
select is(
  (select tour from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  'Evergreen Tour',
  'the editor mutation persists normalized concert content'
);
select throws_ok(
  $$select public.remove_concert_collaborator(
    current_setting('test.shared_concert_id')::uuid,
    '41000000-0000-0000-0000-000000000001',
    4
  )$$,
  '42501',
  'Only the concert owner can do that',
  'an editor cannot remove collaborators'
);
select throws_ok(
  $$select public.transfer_concert_ownership(
    current_setting('test.shared_concert_id')::uuid,
    '42000000-0000-0000-0000-000000000002',
    4
  )$$,
  '42501',
  'Only the concert owner can do that',
  'an editor cannot transfer ownership'
);
select throws_ok(
  $$select public.delete_concert(current_setting('test.shared_concert_id')::uuid)$$,
  '42501',
  'Only the concert owner can do that',
  'an editor cannot delete the concert'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '43000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*) from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  0::bigint,
  'a friend cannot read a Collaborators-only concert'
);
select is(
  (select count(*) from public.concert_collaborators where concert_id = current_setting('test.shared_concert_id')::uuid),
  0::bigint,
  'a non-editor cannot read collaborator membership'
);
select throws_ok(
  $$select public.create_concert_comment(
    current_setting('test.shared_concert_id')::uuid,
    'I was there!'
  )$$,
  '42501',
  'You no longer have access to this concert',
  'a friend cannot comment on a Collaborators-only concert'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);

select is(
  (
    select (public.update_concert(
      current_setting('test.shared_concert_id')::uuid,
      4,
      '[{"name":"Soccer Mommy","is_primary":true}]'::jsonb,
      'The Warfield',
      date '2026-08-18',
      p_tour => 'Evergreen Tour',
      p_setlist => '["Circle the Drain","Your Dog"]'::jsonb,
      p_visibility => 'friends'
    )).version
  ),
  5::bigint,
  'the owner can broaden a shared concert to Friends'
);
select throws_ok(
  $$select public.update_concert(
    current_setting('test.shared_concert_id')::uuid,
    5,
    '[{"name":"Soccer Mommy","is_primary":true}]'::jsonb,
    'The Warfield',
    date '2026-08-18',
    p_tour => 'Evergreen Tour',
    p_setlist => '["Circle the Drain","Your Dog"]'::jsonb,
    p_visibility => 'private'
  )$$,
  '22023',
  'Shared concerts cannot be made Private. Transfer ownership or delete it instead.',
  'a shared concert cannot silently become a hidden private copy'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '43000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*) from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  1::bigint,
  'an accepted friend can read a Friends-visible concert'
);
select is(
  (select (public.create_concert_comment(
    current_setting('test.shared_concert_id')::uuid,
    '  That encore was unreal.  '
  )).body),
  'That encore was unreal.',
  'a friend can add a normalized comment'
);
select set_config(
  'test.friend_comment_id',
  (
    select id::text
    from public.comments
    where concert_id = current_setting('test.shared_concert_id')::uuid
      and author_id = '43000000-0000-0000-0000-000000000003'
  ),
  true
);
select is(
  (select version from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  5::bigint,
  'a comment refreshes activity without invalidating an editor draft version'
);
select is(
  (select count(*) from public.list_concert_comments(current_setting('test.shared_concert_id')::uuid)),
  1::bigint,
  'comment pagination returns the current visible comment'
);
select throws_ok(
  $$select public.tag_concert_collaborator(
    current_setting('test.shared_concert_id')::uuid,
    '44000000-0000-0000-0000-000000000004',
    5
  )$$,
  '42501',
  'You no longer have permission to edit this concert',
  'a Friends viewer cannot tag collaborators'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$select public.update_concert_comment(
    current_setting('test.friend_comment_id')::uuid,
    'Owner rewrite'
  )$$,
  '42501',
  'Only the comment author can edit this comment',
  'an owner cannot edit someone else’s comment'
);
select is(
  (
    select count(*)
    from public.concert_events
    where concert_id = current_setting('test.shared_concert_id')::uuid
      and event_type = 'comment_added'
      and metadata = '{}'::jsonb
  ),
  1::bigint,
  'comment events keep comment text out of the immutable history stream'
);

select lives_ok(
  $$select public.block_profile('42000000-0000-0000-0000-000000000002')$$,
  'an owner can block a collaborator without forking the shared concert'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '42000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*) from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  0::bigint,
  'blocking immediately revokes a tagged collaborator’s concert access'
);
select throws_ok(
  $$select public.update_concert(
    current_setting('test.shared_concert_id')::uuid,
    5,
    '[{"name":"Soccer Mommy","is_primary":true}]'::jsonb,
    'The Warfield',
    date '2026-08-18',
    p_tour => 'Evergreen Tour',
    p_setlist => '["Circle the Drain","Your Dog","Still Clean"]'::jsonb,
    p_visibility => 'friends'
  )$$,
  '42501',
  'You no longer have permission to edit this concert',
  'a blocked collaborator cannot keep editing the shared concert'
);

reset role;
delete from public.relationships
where user_low_id = '41000000-0000-0000-0000-000000000001'
  and user_high_id = '42000000-0000-0000-0000-000000000002';
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
  '41000000-0000-0000-0000-000000000001',
  '42000000-0000-0000-0000-000000000002',
  'accepted',
  '41000000-0000-0000-0000-000000000001',
  '42000000-0000-0000-0000-000000000002',
  now(),
  now()
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);

select is(
  (
    select (public.tag_concert_collaborator(
      current_setting('test.shared_concert_id')::uuid,
      '42000000-0000-0000-0000-000000000002',
      6
    )).version
  ),
  7::bigint,
  'a new accepted friendship can explicitly grant a fresh collaborator role'
);

select is(
  (
    select (public.transfer_concert_ownership(
      current_setting('test.shared_concert_id')::uuid,
      '42000000-0000-0000-0000-000000000002',
      7
    )).owner_id
  ),
  '42000000-0000-0000-0000-000000000002'::uuid,
  'ownership transfers immediately to an existing tagged collaborator'
);
select is(
  (
    select count(*)
    from public.concert_collaborators
    where concert_id = current_setting('test.shared_concert_id')::uuid
      and profile_id = '41000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'the former owner remains an editor on the original concert'
);
select is(
  (
    select count(*)
    from public.concert_events
    where concert_id = current_setting('test.shared_concert_id')::uuid
      and event_type = 'ownership_transferred'
  ),
  1::bigint,
  'ownership transfer is preserved in the canonical event history'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '42000000-0000-0000-0000-000000000002', true);

select is(
  (
    select (public.remove_concert_collaborator(
      current_setting('test.shared_concert_id')::uuid,
      '41000000-0000-0000-0000-000000000001',
      8
    )).version
  ),
  9::bigint,
  'the new owner can immediately revoke the former owner’s editor role'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$select public.update_concert(
    current_setting('test.shared_concert_id')::uuid,
    9,
    '[{"name":"Soccer Mommy","is_primary":true}]'::jsonb,
    'The Warfield',
    date '2026-08-18',
    p_setlist => '["Circle the Drain"]'::jsonb,
    p_visibility => 'friends'
  )$$,
  '42501',
  'You no longer have permission to edit this concert',
  'removing an editor revokes their edit authority without creating a copy'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000004', true);

select is(
  (select count(*) from public.concerts where id = current_setting('test.shared_concert_id')::uuid),
  0::bigint,
  'an unrelated profile never receives current shared-concert access'
);
select is(
  (select count(*) from public.concert_events where concert_id = current_setting('test.shared_concert_id')::uuid),
  0::bigint,
  'an unrelated profile cannot read the immutable event history'
);

select * from finish();

rollback;
