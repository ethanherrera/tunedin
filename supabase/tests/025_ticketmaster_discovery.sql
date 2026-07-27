begin;

select plan(11);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select public.upsert_ticketmaster_catalog_event('{}'::jsonb)$$,
  '42501', null,
  'ordinary clients cannot invoke the Ticketmaster importer'
);

select throws_ok(
  $$select public.get_ticketmaster_cache('v1:' || repeat('a', 64))$$,
  '42501', null,
  'ordinary clients cannot read the provider cache'
);

reset role;

select set_config(
  'test.tm_event_id',
  public.upsert_ticketmaster_catalog_event(
    '{
      "event_id":"G5vYZbfixture",
      "title":"Fixture Source Separation Tour",
      "event_date":"2026-08-01",
      "local_start_time":"20:00:00",
      "starts_at":"2026-08-02T03:00:00Z",
      "time_zone":"America/Los_Angeles",
      "status":"active",
      "source_url":"https://www.ticketmaster.com/event/G5vYZbfixture",
      "image_url":"https://example.com/ticketmaster-event.jpg",
      "source_updated_at":null,
      "venue":{
        "id":"KovZfixtureVenue",
        "name":"Fixture Shared Hall",
        "url":"https://www.ticketmaster.com/venue/KovZfixtureVenue",
        "address":"1 Fixture Way",
        "latitude":"37.7841",
        "longitude":"-122.4330",
        "area":{"city":"Fixture City","state_code":"CA","country_code":"US"}
      },
      "artists":[
        {
          "id":"K8vZfixtureArtist",
          "name":"Fixture Shared Artist",
          "url":"https://www.ticketmaster.com/artist/K8vZfixtureArtist",
          "is_headliner":true
        }
      ]
    }'::jsonb
  )::text,
  true
);

select is(
  (select origin from public.catalog_events
   where id = current_setting('test.tm_event_id')::uuid),
  'ticketmaster',
  'the imported event has Ticketmaster origin'
);

select is(
  (select count(*)::integer
   from public.catalog_event_artists as lineup
   join public.catalog_entities as entity on entity.id = lineup.catalog_artist_id
   where lineup.event_id = current_setting('test.tm_event_id')::uuid
     and entity.origin = 'ticketmaster'),
  1,
  'the imported lineup uses a separate Ticketmaster catalog artist'
);

select isnt(
  (select entity.id
   from public.catalog_event_artists as lineup
   join public.catalog_entities as entity on entity.id = lineup.catalog_artist_id
   where lineup.event_id = current_setting('test.tm_event_id')::uuid),
  (
    select id from public.upsert_musicbrainz_catalog_entity(
      'artist',
      'f5000000-0000-4000-8000-000000000001',
      'Fixture Shared Artist',
      'Fixture Shared Artist',
      null,
      '{}'::jsonb,
      '[]'::jsonb
    )
  ),
  'same-looking Ticketmaster and MusicBrainz artists stay independent'
);

select is(
  public.upsert_ticketmaster_catalog_event(
    '{
      "event_id":"G5vYZbfixture",
      "title":"Fixture Source Separation Tour Updated",
      "event_date":"2026-08-01",
      "local_start_time":"21:00:00",
      "starts_at":"2026-08-02T04:00:00Z",
      "time_zone":"America/Los_Angeles",
      "status":"active",
      "source_url":"https://www.ticketmaster.com/event/G5vYZbfixture",
      "image_url":"https://example.com/ticketmaster-event.jpg",
      "source_updated_at":null,
      "venue":{
        "id":"KovZfixtureVenue",
        "name":"Fixture Shared Hall",
        "url":"https://www.ticketmaster.com/venue/KovZfixtureVenue",
        "address":"1 Fixture Way",
        "latitude":"37.7841",
        "longitude":"-122.4330",
        "area":{"city":"Fixture City","state_code":"CA","country_code":"US"}
      },
      "artists":[
        {
          "id":"K8vZfixtureArtist",
          "name":"Fixture Shared Artist",
          "url":"https://www.ticketmaster.com/artist/K8vZfixtureArtist",
          "is_headliner":true
        }
      ]
    }'::jsonb
  ),
  current_setting('test.tm_event_id')::uuid,
  'reopening the same Ticketmaster identity updates one tunedIn event'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e5000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'ticketmaster-discovery@example.test', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
update public.profiles
set username = 'ticketmaster_discovery',
    display_name = 'Ticketmaster Discovery',
    onboarding_completed_at = now()
where id = 'e5000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);

select is(
  public.get_discoverable_catalog_event_detail(
    current_setting('test.tm_event_id')::uuid
  ) ->> 'source_label',
  'Ticketmaster',
  'event detail names the Ticketmaster source'
);

select is(
  public.get_discoverable_catalog_event_detail(
    current_setting('test.tm_event_id')::uuid
  ) ->> 'source_url',
  'https://www.ticketmaster.com/event/G5vYZbfixture',
  'event detail preserves the Ticketmaster source URL'
);

select is(
  (
    select count(*)::integer
    from public.search_discoverable_catalog_events('fixture source separation')
  ),
  0,
  'Ticketmaster imports do not leak into global concert search'
);

reset role;

select public.put_ticketmaster_cache(
  'v1:' || repeat('a', 64),
  'discover',
  '{"events":[]}'::jsonb,
  600
);

select is(
  public.get_ticketmaster_cache('v1:' || repeat('a', 64)),
  '{"events":[]}'::jsonb,
  'the service-only discovery cache returns a live entry'
);

select is(
  (
    select extract(epoch from (hard_delete_at - updated_at))::integer
    from private.ticketmaster_cache
    where cache_key = 'v1:' || repeat('a', 64)
  ),
  86400,
  'cached provider payloads have a 24-hour hard ejection boundary'
);

select * from finish();
rollback;
