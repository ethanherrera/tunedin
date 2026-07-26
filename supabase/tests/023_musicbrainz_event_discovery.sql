begin;

select plan(6);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select public.upsert_musicbrainz_catalog_event('{}'::jsonb)$$,
  '42501', null,
  'ordinary clients cannot invoke the MusicBrainz event importer'
);

reset role;

select set_config(
  'test.mb_event_id',
  public.upsert_musicbrainz_catalog_event(
    '{
      "event_mbid":"f3000000-0000-4000-8000-000000000001",
      "title":"Fixture MusicBrainz Tour",
      "event_date":"2026-08-01",
      "local_start_time":"20:00:00",
      "venue":{"mbid":"f3000000-0000-4000-8000-000000000002","name":"Fixture MusicBrainz Hall","area_mbid":"f3000000-0000-4000-8000-000000000003","area_name":"Fixture City"},
      "artists":[
        {"mbid":"f3000000-0000-4000-8000-000000000004","name":"Fixture Headliner","is_headliner":true},
        {"mbid":"f3000000-0000-4000-8000-000000000005","name":"Fixture Support","is_headliner":false}
      ],
      "source_status":"active",
      "source_updated_at":null
    }'::jsonb
  )::text,
  true
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e3000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'event-discovery@example.test', '', now(), '{"provider":"email","providers":["email"]}',
  '{}', now(), now()
);
update public.profiles
set username = 'event_discovery', display_name = 'Event Discovery', onboarding_completed_at = now()
where id = 'e3000000-0000-4000-8000-000000000001';

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);

select is(
  (select public.get_discoverable_catalog_event_detail(current_setting('test.mb_event_id')::uuid) ->> 'source_label'),
  'MusicBrainz',
  'provider detail carries a transparent MusicBrainz label'
);

select is(
  (select public.get_discoverable_catalog_event_detail(current_setting('test.mb_event_id')::uuid) ->> 'source_local_start_time'),
  '20:00:00',
  'provider local start time is readable without an inferred timezone'
);

select is(
  (select public.get_discoverable_catalog_event_detail(current_setting('test.mb_event_id')::uuid) ->> 'source_url'),
  'https://musicbrainz.org/event/f3000000-0000-4000-8000-000000000001',
  'provider detail exposes the stable MusicBrainz source link'
);

select is(
  (select (event ->> 'event_id')::uuid
   from public.search_discoverable_catalog_events('fixture support')
   limit 1),
  current_setting('test.mb_event_id')::uuid,
  'provider search matches a supporting artist in the MusicBrainz lineup'
);

reset role;

select is(
  public.upsert_musicbrainz_catalog_event(
    '{
      "event_mbid":"f3000000-0000-4000-8000-000000000001",
      "title":"Fixture MusicBrainz Tour (updated)",
      "event_date":"2026-08-01",
      "local_start_time":"21:00:00",
      "venue":{"mbid":"f3000000-0000-4000-8000-000000000002","name":"Fixture MusicBrainz Hall","area_mbid":"f3000000-0000-4000-8000-000000000003","area_name":"Fixture City"},
      "artists":[
        {"mbid":"f3000000-0000-4000-8000-000000000004","name":"Fixture Headliner","is_headliner":true},
        {"mbid":"f3000000-0000-4000-8000-000000000005","name":"Fixture Support","is_headliner":false}
      ],
      "source_status":"active",
      "source_updated_at":null
    }'::jsonb
  ),
  current_setting('test.mb_event_id')::uuid,
  'the same provider identity updates its existing tunedIn concert'
);

select * from finish();
rollback;
