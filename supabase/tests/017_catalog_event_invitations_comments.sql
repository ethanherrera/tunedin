begin;

select plan(21);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e4000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e4000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-friend@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e4000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
      when 'e4000000-0000-4000-8000-000000000001' then 'event_owner'
      when 'e4000000-0000-4000-8000-000000000002' then 'event_friend'
      when 'e4000000-0000-4000-8000-000000000003' then 'event_outsider'
    end,
    display_name = case id
      when 'e4000000-0000-4000-8000-000000000001' then 'Event Owner'
      when 'e4000000-0000-4000-8000-000000000002' then 'Event Friend'
      when 'e4000000-0000-4000-8000-000000000003' then 'Event Outsider'
    end,
    onboarding_completed_at = now()
where id in (
  'e4000000-0000-4000-8000-000000000001',
  'e4000000-0000-4000-8000-000000000002',
  'e4000000-0000-4000-8000-000000000003'
);

insert into public.relationships (
  user_low_id, user_high_id, status, initiator_id, responder_id, requested_at, responded_at
)
values (
  'e4000000-0000-4000-8000-000000000001',
  'e4000000-0000-4000-8000-000000000002',
  'accepted',
  'e4000000-0000-4000-8000-000000000001',
  'e4000000-0000-4000-8000-000000000002',
  now(), now()
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);

select set_config('test.comment_area', (
  select catalog_id::text from public.create_custom_catalog_area('Comment City', 'US', null)
), true);
select set_config('test.comment_artist', (
  select catalog_id::text from public.create_custom_catalog_artist(
    'Comment Artist', 'Group', null, current_setting('test.comment_area')::uuid
  )
), true);
select set_config('test.comment_place', (
  select catalog_id::text from public.create_custom_catalog_place(
    'Comment Hall', current_setting('test.comment_area')::uuid, 'Venue', null
  )
), true);
select set_config('test.comment_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.comment_artist'), 'is_primary', true
    )),
    current_setting('test.comment_place')::uuid,
    current_date + 30,
    null,
    ((current_date + 30) + time '20:00') at time zone 'UTC',
    'UTC',
    'listed'
  )
), true);

select is(
  (select count(*) from public.list_catalog_event_invite_candidates(
    current_setting('test.comment_event')::uuid
  )),
  1::bigint,
  'invite candidates contain current friends only'
);
select is(
  (select count(*) from public.list_catalog_event_invite_candidates(
    current_setting('test.comment_event')::uuid
  ) where id = 'e4000000-0000-4000-8000-000000000003'),
  0::bigint,
  'unrelated profiles are not exposed as invite candidates'
);
select throws_ok(
  $$select * from public.send_catalog_event_invitations(
    current_setting('test.comment_event')::uuid,
    array['e4000000-0000-4000-8000-000000000003'::uuid]
  )$$,
  '42501', null,
  'invitations can be sent only to current friends'
);
select is(
  (select sent_count from public.send_catalog_event_invitations(
    current_setting('test.comment_event')::uuid,
    array['e4000000-0000-4000-8000-000000000002'::uuid]
  )),
  1,
  'a sender can invite a friend'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.get_pending_catalog_event_invitation(
    current_setting('test.comment_event')::uuid
  )),
  0::bigint,
  'a non-recipient cannot look up a pending invitation'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_pending_catalog_event_invitations(null, 20)),
  1::bigint,
  'the recipient sees one pending invitation'
);
select is(
  (select count(*) from public.get_pending_catalog_event_invitation(
    current_setting('test.comment_event')::uuid
  )),
  1::bigint,
  'the recipient can look up the event-scoped pending invitation'
);
select set_config('test.comment_invitation', (
  select invitation_id::text from public.list_pending_catalog_event_invitations(null, 20)
), true);
select is(
  (select status::text from public.respond_catalog_event_invitation(
    current_setting('test.comment_invitation')::uuid, 'accepted', 'friends'
  )),
  'accepted',
  'a recipient can accept a current invitation'
);
select is(
  (select current_user_status::text from public.get_catalog_event_social_summaries(
    array[current_setting('test.comment_event')::uuid]
  )),
  'going',
  'accepting an invitation creates Going'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);
select set_config('test.root_comment', (
  select comment_id::text from public.create_event_comment(
    current_setting('test.comment_event')::uuid, null,
    'I hope they play the closer.', 'friends'
  )
), true);
select is(
  (select body from public.list_event_comments(
    current_setting('test.comment_event')::uuid, 'all', null, 50
  ) where id = current_setting('test.root_comment')::uuid),
  'I hope they play the closer.',
  'an author can read their event Comment'
);
select throws_ok(
  $$select * from public.create_event_comment(
    current_setting('test.comment_event')::uuid, null, 'Private Comment', 'private'
  )$$,
  '22023', null,
  'event Comments cannot use a misleading private audience'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_event_comments(
    current_setting('test.comment_event')::uuid, 'friends', null, 50
  )),
  1::bigint,
  'a friend can read a friends-audience event Comment'
);
select set_config('test.reply_comment', (
  select comment_id::text from public.create_event_comment(
    current_setting('test.comment_event')::uuid,
    current_setting('test.root_comment')::uuid,
    'Same here.', 'friends'
  )
), true);
select is(
  (select parent_comment_id from public.list_event_comments(
    current_setting('test.comment_event')::uuid, 'all', null, 50
  ) where id = current_setting('test.reply_comment')::uuid),
  current_setting('test.root_comment')::uuid,
  'one-level replies preserve their parent Comment identity'
);
select throws_ok(
  $$select * from public.create_event_comment(
    current_setting('test.comment_event')::uuid,
    current_setting('test.reply_comment')::uuid,
    'Nested reply', 'friends'
  )$$,
  '42501', null,
  'nested event Comment replies are rejected'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_event_comments(
    current_setting('test.comment_event')::uuid, 'all', null, 50
  )),
  0::bigint,
  'an unrelated profile cannot read friends-audience Comments'
);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.create_event_comment(
    current_setting('test.comment_event')::uuid, null,
    'Community can join this conversation.', 'community'
  )$$,
  'an author can share an event Comment with the community'
);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_event_comments(
    current_setting('test.comment_event')::uuid, 'community', null, 50
  )),
  1::bigint,
  'community scope exposes community Comments to unrelated profiles'
);
select throws_ok(
  $$select * from public.list_event_comments(
    current_setting('test.comment_event')::uuid, 'all', '{"created_at":"bad","comment_id":"bad"}', 50
  )$$,
  '22023', null,
  'event Comment cursors are strictly validated'
);

reset role;
update public.catalog_events
set lifecycle = 'completed'
where id = current_setting('test.comment_event')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select * from public.create_event_comment(
    current_setting('test.comment_event')::uuid, null, 'Too late', 'friends'
  )$$,
  '22023', null,
  'event Comments close when Posts unlock'
);

reset role;
select is(
  (select count(*) from public.social_activity_events
   where event_id = current_setting('test.comment_event')::uuid
     and action in ('event_commented', 'event_comment_replied')),
  3::bigint,
  'event Comment activity uses only the supported action vocabulary'
);
select is(
  (select count(*) from private.catalog_event_notification_outbox
   where subject_id = current_setting('test.reply_comment')::uuid
     and action = 'event_comment_replied'),
  1::bigint,
  'a reply creates one identifier-only notification'
);

select * from finish();
rollback;
