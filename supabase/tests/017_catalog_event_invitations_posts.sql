begin;

select plan(39);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e4000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-social-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e4000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-social-friend@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e4000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-social-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e4000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'event-social-second@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
      when 'e4000000-0000-4000-8000-000000000001' then 'event_social_owner'
      when 'e4000000-0000-4000-8000-000000000002' then 'event_social_friend'
      when 'e4000000-0000-4000-8000-000000000003' then 'event_social_outsider'
      when 'e4000000-0000-4000-8000-000000000004' then 'event_social_second'
    end,
    display_name = case id
      when 'e4000000-0000-4000-8000-000000000001' then 'Event Social Owner'
      when 'e4000000-0000-4000-8000-000000000002' then 'Event Social Friend'
      when 'e4000000-0000-4000-8000-000000000003' then 'Event Social Outsider'
      when 'e4000000-0000-4000-8000-000000000004' then 'Event Social Second'
    end,
    onboarding_completed_at = now()
where id in (
  'e4000000-0000-4000-8000-000000000001',
  'e4000000-0000-4000-8000-000000000002',
  'e4000000-0000-4000-8000-000000000003',
  'e4000000-0000-4000-8000-000000000004'
);

insert into public.relationships (
  user_low_id, user_high_id, status, initiator_id, responder_id, requested_at, responded_at
)
values
  ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002', 'accepted', 'e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002', now(), now()),
  ('e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000004', 'accepted', 'e4000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000004', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);

select set_config('test.event_social_area', (
  select catalog_id::text from public.create_custom_catalog_area('Event Social City', 'US', null, null)
), true);
select set_config('test.event_social_artist', (
  select catalog_id::text from public.create_custom_catalog_artist(
    'Event Social Artist', 'Group', null, current_setting('test.event_social_area')::uuid, null
  )
), true);
select set_config('test.event_social_place', (
  select catalog_id::text from public.create_custom_catalog_place(
    'Event Social Hall', current_setting('test.event_social_area')::uuid, 'Venue', null, null
  )
), true);
select set_config('test.event_social_event', (
  select event_id::text from public.create_catalog_event(
    jsonb_build_array(jsonb_build_object(
      'catalog_artist_id', current_setting('test.event_social_artist'), 'is_primary', true
    )),
    current_setting('test.event_social_place')::uuid,
    current_date + 30,
    null,
    ((current_date + 30) + time '20:00') at time zone 'UTC',
    'UTC',
    'listed'
  )
), true);

select is(
  (select count(*) from public.list_catalog_event_invite_candidates(
    current_setting('test.event_social_event')::uuid
  )),
  2::bigint,
  'invite candidates contain current friends only'
);
select is(
  (select count(*) from public.list_catalog_event_invite_candidates(
    current_setting('test.event_social_event')::uuid
  ) where id = 'e4000000-0000-4000-8000-000000000003'),
  0::bigint,
  'unrelated profiles are not exposed as invite candidates'
);
select throws_ok(
  $$select * from public.send_catalog_event_invitations(
    current_setting('test.event_social_event')::uuid,
    array['e4000000-0000-4000-8000-000000000003'::uuid]
  )$$,
  '42501', null,
  'invitations can be sent only to current friends'
);
select is(
  (select sent_count from public.send_catalog_event_invitations(
    current_setting('test.event_social_event')::uuid,
    array['e4000000-0000-4000-8000-000000000002'::uuid]
  )),
  1,
  'a sender can invite a friend'
);
select is(
  (select sent_count from public.send_catalog_event_invitations(
    current_setting('test.event_social_event')::uuid,
    array['e4000000-0000-4000-8000-000000000002'::uuid]
  )),
  0,
  'a pending invitation is idempotent'
);
select is(
  (select sent_count from public.send_catalog_event_invitations(
    current_setting('test.event_social_event')::uuid,
    array['e4000000-0000-4000-8000-000000000004'::uuid]
  )),
  1,
  'another current friend can receive an independent invitation'
);
select lives_ok(
  $$select public.remove_friend('e4000000-0000-4000-8000-000000000004')$$,
  'the sender can later remove the invited friendship'
);

reset role;
update public.catalog_events
set listing = 'unlisted'
where id = current_setting('test.event_social_event')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000004', true);
select is(
  (select count(*) from public.list_pending_catalog_event_invitations(null, 20)),
  0::bigint,
  'a stale invitation disappears immediately when the friendship ends'
);
select throws_ok(
  $$select * from public.get_catalog_event_detail(
    current_setting('test.event_social_event')::uuid
  )$$,
  '42501', null,
  'a stale invitation no longer grants access to an unlisted event'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000002', true);

select is(
  (select count(*) from public.list_pending_catalog_event_invitations(null, 20)),
  1::bigint,
  'the recipient sees one private pending invitation'
);
select is(
  (select event ->> 'venue_name'
    from public.list_pending_catalog_event_invitations(null, 20)),
  'Event Social Hall',
  'the invitation inbox returns its event card without another event request'
);
select is(
  (select event_id from public.get_catalog_event_detail(
    current_setting('test.event_social_event')::uuid
  )),
  current_setting('test.event_social_event')::uuid,
  'a pending invitation grants access to an unlisted event'
);
select set_config('test.event_social_invitation', (
  select invitation_id::text from public.list_pending_catalog_event_invitations(null, 20) limit 1
), true);
select is(
  (select status::text from public.respond_catalog_event_invitation(
    current_setting('test.event_social_invitation')::uuid, 'accepted', 'friends'
  )),
  'accepted',
  'a recipient can accept a current invitation'
);
select is(
  (select current_user_status::text from public.get_catalog_event_social_summaries(
    array[current_setting('test.event_social_event')::uuid]
  )),
  'going',
  'accepting an invitation transactionally creates Going'
);
select is(
  (select count(*) from public.list_my_catalog_event_plans(null, 50)),
  1::bigint,
  'an accepted invitation immediately appears in Plans'
);
select is(
  (select count(*) from public.list_pending_catalog_event_invitations(null, 20)),
  0::bigint,
  'accepted invitations leave the pending inbox'
);
select throws_ok(
  $$select * from public.respond_catalog_event_invitation(
    current_setting('test.event_social_invitation')::uuid, 'accepted', 'friends'
  )$$,
  '42501', null,
  'an invitation cannot be accepted twice'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);
select is(
  (select count(*) from public.list_catalog_event_activity(null, 50)
    where action = 'invitation_accepted'),
  1::bigint,
  'the sender feed can see a visible invitation acceptance'
);

reset role;
update public.catalog_events
set listing = 'listed'
where id = current_setting('test.event_social_event')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);

select set_config('test.event_social_friend_post', (
  select post_id::text from public.create_catalog_event_post(
    current_setting('test.event_social_event')::uuid, null,
    'I hope they play the closer', 'friends'
  )
), true);
select is(
  (select body from public.list_catalog_event_posts(
    current_setting('test.event_social_event')::uuid, 'all', null, 50
  ) where id = current_setting('test.event_social_friend_post')::uuid),
  'I hope they play the closer',
  'an author can read a friends-audience event post'
);
select throws_ok(
  $$select * from public.create_catalog_event_post(
    current_setting('test.event_social_event')::uuid, null, 'Too soon', 'friends'
  )$$,
  'P0001', null,
  'event post rate limits are enforced atomically'
);
select throws_ok(
  $$select * from public.create_catalog_event_post(
    current_setting('test.event_social_event')::uuid, null, 'Private post', 'private'
  )$$,
  '22023', null,
  'event conversation cannot use a misleading private audience'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000002', true);
select is(
  (select count(*) from public.list_catalog_event_posts(
    current_setting('test.event_social_event')::uuid, 'all', null, 50
  )),
  1::bigint,
  'a current friend can read a friends-audience post'
);
select set_config('test.event_social_reply', (
  select post_id::text from public.create_catalog_event_post(
    current_setting('test.event_social_event')::uuid,
    current_setting('test.event_social_friend_post')::uuid,
    'Same here', 'friends'
  )
), true);
select is(
  (select parent_post_id from public.list_catalog_event_posts(
    current_setting('test.event_social_event')::uuid, 'all', null, 50
  ) where id = current_setting('test.event_social_reply')::uuid),
  current_setting('test.event_social_friend_post')::uuid,
  'one-level replies preserve their parent identity'
);
select throws_ok(
  $$select * from public.create_catalog_event_post(
    current_setting('test.event_social_event')::uuid,
    current_setting('test.event_social_reply')::uuid,
    'Nested reply', 'friends'
  )$$,
  '42501', null,
  'nested replies are rejected in the MVP'
);

reset role;
alter table public.catalog_event_posts disable trigger set_catalog_event_post_updated_at;
update public.catalog_event_posts
set created_at = created_at - interval '10 seconds'
where author_id = 'e4000000-0000-4000-8000-000000000002';
alter table public.catalog_event_posts enable trigger set_catalog_event_post_updated_at;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000002', true);
select set_config('test.event_social_community_post', (
  select post_id::text from public.create_catalog_event_post(
    current_setting('test.event_social_event')::uuid, null,
    'The whole community can join this thread', 'community'
  )
), true);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*) from public.list_catalog_event_posts(
    current_setting('test.event_social_event')::uuid, 'all', null, 50
  ) where author_id = 'e4000000-0000-4000-8000-000000000002'),
  1::bigint,
  'an outsider sees community conversation but not friends conversation'
);
select is(
  (select count(*) from public.list_catalog_event_activity(null, 50)
    where action = 'event_posted'
      and (event ->> 'event_id')::uuid = current_setting('test.event_social_event')::uuid),
  0::bigint,
  'the friend circle feed excludes community activity from strangers'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select public.remove_friend('e4000000-0000-4000-8000-000000000002')$$,
  'friend removal succeeds before post visibility is recomputed'
);
select is(
  (select count(*) from public.list_catalog_event_posts(
    current_setting('test.event_social_event')::uuid, 'all', null, 50
  ) where author_id = 'e4000000-0000-4000-8000-000000000002'
      and audience = 'friends'),
  0::bigint,
  'friends-audience posts disappear immediately after friendship removal'
);
select lives_ok(
  $$select public.block_profile('e4000000-0000-4000-8000-000000000002')$$,
  'a safety block succeeds before community visibility is recomputed'
);
select is(
  (select count(*) from public.list_catalog_event_posts(
    current_setting('test.event_social_event')::uuid, 'all', null, 50
  ) where author_id = 'e4000000-0000-4000-8000-000000000002'),
  0::bigint,
  'a block removes the author community posts immediately'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000002', true);
select is(
  (select post_id from public.delete_catalog_event_post(
    current_setting('test.event_social_community_post')::uuid
  )),
  current_setting('test.event_social_community_post')::uuid,
  'an author can soft-delete their event post'
);
select is(
  (select body from public.list_catalog_event_posts(
    current_setting('test.event_social_event')::uuid, 'all', null, 50
  ) where id = current_setting('test.event_social_community_post')::uuid),
  'Post deleted',
  'soft-deleted posts retain thread position without content'
);

select throws_ok(
  $$select count(*) from public.catalog_event_invitations$$,
  '42501', null,
  'ordinary clients cannot read invitation rows directly'
);
select throws_ok(
  $$select count(*) from public.catalog_event_posts$$,
  '42501', null,
  'ordinary clients cannot read event post rows directly'
);
select throws_ok(
  $$select * from private.catalog_event_notification_outbox$$,
  '42501', null,
  'the notification outbox remains private from clients'
);

reset role;
select is(
  (select count(*) from private.catalog_event_notification_outbox
    where action = 'event_invited'
      and event_id = current_setting('test.event_social_event')::uuid),
  2::bigint,
  'each delivered invitation enqueues one opaque direct notification'
);
select is(
  (select count(*) from private.catalog_event_notification_outbox
    where action = 'invitation_accepted'
      and event_id = current_setting('test.event_social_event')::uuid),
  1::bigint,
  'accepting an invitation notifies only the sender'
);
select is(
  (select count(*) from information_schema.columns
    where table_schema = 'private'
      and table_name = 'catalog_event_notification_outbox'
      and column_name in ('body', 'review', 'caption', 'event_name', 'profile_name')),
  0::bigint,
  'notification outbox rows cannot store user-authored or identity text'
);

set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.list_pending_catalog_event_invitations(null, 20)$$,
  '42501', null,
  'anonymous callers cannot read invitation inboxes'
);

select * from finish();
rollback;
