begin;

select plan(9);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select public.claim_musicbrainz_event_artwork('f5000000-0000-4000-8000-000000000001')$$,
  '42501', null,
  'ordinary clients cannot claim provider artwork work'
);

reset role;

select set_config(
  'test.mb_art_event_id',
  public.upsert_musicbrainz_catalog_event(
    '{
      "event_mbid":"f5000000-0000-4000-8000-000000000001",
      "title":"Fixture Artwork Tour",
      "event_date":"2026-08-01",
      "local_start_time":"20:00:00",
      "venue":{"mbid":"f5000000-0000-4000-8000-000000000002","name":"Fixture Artwork Hall","area_mbid":null,"area_name":null},
      "artists":[{"mbid":"f5000000-0000-4000-8000-000000000003","name":"Fixture Artwork Headliner","is_headliner":true}],
      "source_status":"active",
      "source_updated_at":null
    }'::jsonb
  )::text,
  true
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

select is(
  public.claim_musicbrainz_event_artwork(current_setting('test.mb_art_event_id')::uuid),
  true,
  'service importer claims a new MusicBrainz event only once'
);

select lives_ok(
  $$select public.complete_musicbrainz_event_artwork(
    current_setting('test.mb_art_event_id')::uuid,
    '{
      "source":"provider",
      "remote_url":"https://images.example.test/exact-event.jpg",
      "provider_name":"MusicBrainz Event Art Archive",
      "attribution":null,
      "source_page_url":"https://coverartarchive.org/event/f5000000-0000-4000-8000-000000000001",
      "license_name":null,
      "license_url":null
    }'::jsonb,
    1::smallint
  )$$,
  'service importer persists exact Event Art Archive artwork'
);

reset role;

select is(
  (
    select artists -> 0 -> 'event_cover' ->> 'remote_url'
    from private.catalog_event_projections
    where event_id = current_setting('test.mb_art_event_id')::uuid
  ),
  'https://images.example.test/exact-event.jpg',
  'provider event artwork is projected through the existing cover transport'
);

update private.catalog_event_artwork_imports
set retry_after = clock_timestamp() - interval '1 second'
where event_id = current_setting('test.mb_art_event_id')::uuid;

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

select is(
  public.claim_musicbrainz_event_artwork(current_setting('test.mb_art_event_id')::uuid),
  true,
  'a completed provider image may be rechecked after the durable retry window'
);

select lives_ok(
  $$select public.complete_musicbrainz_event_artwork(
    current_setting('test.mb_art_event_id')::uuid,
    '{
      "source":"wikimedia",
      "remote_url":"https://upload.wikimedia.org/artist.jpg",
      "provider_name":null,
      "attribution":"Fixture Photographer",
      "source_page_url":"https://commons.wikimedia.org/wiki/File:Artist.jpg",
      "license_name":"CC BY-SA 4.0",
      "license_url":"https://creativecommons.org/licenses/by-sa/4.0/"
    }'::jsonb,
    3::smallint
  )$$,
  'a lower-ranked fallback remains a valid resolution payload'
);

reset role;

select is(
  (
    select cover_remote_url
    from public.catalog_events
    where id = current_setting('test.mb_art_event_id')::uuid
  ),
  'https://images.example.test/exact-event.jpg',
  'artist artwork cannot replace a higher-priority exact event image'
);

select is(
  (
    select selected_priority
    from private.catalog_event_artwork_imports
    where event_id = current_setting('test.mb_art_event_id')::uuid
  ),
  1::smallint,
  'the selected priority remains aligned with the stored cover'
);

select throws_ok(
  $$select public.complete_musicbrainz_event_artwork(
    current_setting('test.mb_art_event_id')::uuid,
    '{"source":"provider","remote_url":"http://not-https.example.test/image.jpg","provider_name":"Bad","attribution":null,"source_page_url":null,"license_name":null,"license_url":null}'::jsonb,
    1::smallint
  )$$,
  '22023', 'Concert artwork payload is invalid',
  'the service boundary rejects insecure remote image URLs'
);

select * from finish();
rollback;
