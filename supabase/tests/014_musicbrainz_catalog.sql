begin;

select plan(30);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e1000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'catalog-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e1000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'catalog-editor@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e1000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'catalog-outsider@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e1000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'catalog-incomplete@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e1000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'catalog-quota@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles
set username = case id
    when 'e1000000-0000-4000-8000-000000000001' then 'catalog_owner'
    when 'e1000000-0000-4000-8000-000000000002' then 'catalog_editor'
    when 'e1000000-0000-4000-8000-000000000003' then 'catalog_outsider'
    when 'e1000000-0000-4000-8000-000000000005' then 'catalog_quota'
  end,
  display_name = 'Catalog Test',
  onboarding_completed_at = now()
where id in (
  'e1000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000003',
  'e1000000-0000-4000-8000-000000000005'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000004', true);

select throws_ok(
  $$select public.create_custom_catalog_area('Incomplete City', 'US', null)$$,
  '42501', null,
  'custom creation requires completed onboarding'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);

select set_config(
  'test.catalog_area_id',
  (select catalog_id::text from public.create_custom_catalog_area('Tap City', 'US', null)),
  true
);
select set_config(
  'test.catalog_artist_id',
  (select catalog_id::text from public.create_custom_catalog_artist(
    'Tap Artist', 'Group', 'database fixture', current_setting('test.catalog_area_id')::uuid
  )),
  true
);
select set_config(
  'test.catalog_place_id',
  (select catalog_id::text from public.create_custom_catalog_place(
    'Tap Hall', current_setting('test.catalog_area_id')::uuid, 'Venue', '1 Test Way'
  )),
  true
);
select set_config(
  'test.catalog_song_id',
  (select catalog_id::text from public.create_custom_catalog_song(
    'Tap Song', array[current_setting('test.catalog_artist_id')::uuid]
  )),
  true
);
select set_config(
  'test.catalog_tour_id',
  (select catalog_id::text from public.create_custom_catalog_tour(
    'Tap Tour', array[current_setting('test.catalog_artist_id')::uuid]
  )),
  true
);

select is(
  (select count(distinct kind) from public.catalog_entities
   where id in (
     current_setting('test.catalog_area_id')::uuid,
     current_setting('test.catalog_artist_id')::uuid,
     current_setting('test.catalog_place_id')::uuid,
     current_setting('test.catalog_song_id')::uuid,
     current_setting('test.catalog_tour_id')::uuid
   ) and origin = 'tunedin_custom'),
  5::bigint,
  'custom RPCs create all five durable catalog entity kinds'
);

select is(
  (select catalog_id from public.create_custom_catalog_area('  Tap   City ', 'us', null)),
  current_setting('test.catalog_area_id')::uuid,
  'normalized custom creation reuses the creator-owned duplicate'
);

select is(
  (select metadata ->> 'areaCatalogId' from public.create_custom_catalog_artist(
    'Tap Artist', 'Group', 'database fixture', current_setting('test.catalog_area_id')::uuid
  )),
  current_setting('test.catalog_area_id'),
  'custom artist metadata preserves its tunedIn area identity'
);

select is(
  (select count(*) from public.search_catalog('artist', 'Tap Artist', null, 20, 0)),
  1::bigint,
  'creator catalog search returns the durable custom artist'
);

select throws_ok(
  $$insert into public.catalog_entities (kind, origin, display_name, sort_name)
    values ('artist', 'tunedin_custom', 'Forged', 'Forged')$$,
  '42501', null,
  'authenticated clients cannot insert catalog rows directly'
);

select throws_ok(
  $$select count(*) from private.catalog_entity_provenance$$,
  '42501', null,
  'creator and ingestion provenance is not readable by clients'
);

reset role;
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claim.sub', '', true);

select set_config(
  'test.mb_area_id',
  (select id::text from public.upsert_musicbrainz_catalog_entity(
    'area', 'f1000000-0000-4000-8000-000000000001', 'Rich Area', 'Area, Rich',
    'authoritative area',
    '{"area_type":"Subdivision","country_code":"US","subdivision_code":"US-TA","parent_mbid":null,"parent_name":null}',
    '[]'
  )),
  true
);

select is(
  (select origin::text from public.upsert_musicbrainz_catalog_entity(
    'area', 'f1000000-0000-4000-8000-000000000001', 'Rich Area', 'Area, Rich',
    'authoritative area',
    '{"area_type":"Subdivision","country_code":"US","subdivision_code":"US-TA","parent_mbid":null,"parent_name":null}',
    '[]'
  )),
  'musicbrainz',
  'service ingestion creates a MusicBrainz origin'
);

select set_config(
  'test.mb_artist_id',
  (select id::text from public.upsert_musicbrainz_catalog_entity(
    'artist', 'f1000000-0000-4000-8000-000000000002', 'Canonical Artist', 'Artist, Canonical',
    'authoritative artist',
    '{"artist_type":"Person","country_code":"US","area_mbid":"f1000000-0000-4000-8000-000000000001","area_name":"Area relation stub","life_span_begin":"2000","life_span_end":null,"ended":false}',
    '[]'
  )),
  true
);

select set_config(
  'test.mb_same_name_artist_id',
  (select id::text from public.upsert_musicbrainz_catalog_entity(
    'artist', 'f1000000-0000-4000-8000-000000000006', 'Tap Artist', 'Tap Artist',
    'distinct MusicBrainz identity',
    '{"artist_type":"Group","country_code":"US","area_mbid":null,"area_name":null,"life_span_begin":null,"life_span_end":null,"ended":false}',
    '[]'
  )),
  true
);

select is(
  (select metadata ->> 'areaCatalogId' from public.upsert_musicbrainz_catalog_entity(
    'artist', 'f1000000-0000-4000-8000-000000000002', 'Canonical Artist', 'Artist, Canonical',
    'authoritative artist',
    '{"artist_type":"Person","country_code":"US","area_mbid":"f1000000-0000-4000-8000-000000000001","area_name":"Area relation stub","life_span_begin":"2000","life_span_end":null,"ended":false}',
    '[]'
  )),
  current_setting('test.mb_area_id'),
  'MusicBrainz artist metadata resolves its related tunedIn area UUID'
);

select set_config(
  'test.mb_place_id',
  (select id::text from public.upsert_musicbrainz_catalog_entity(
    'place', 'f1000000-0000-4000-8000-000000000003', 'Canonical Hall', 'Canonical Hall', null,
    '{"place_type":"Venue","address":"2 Test Way","latitude":1.5,"longitude":2.5,"ended":false,"area_mbid":"f1000000-0000-4000-8000-000000000001","area_name":"Area relation stub"}',
    '[]'
  )),
  true
);

select is(
  (select metadata ->> 'areaCatalogId' from public.upsert_musicbrainz_catalog_entity(
    'place', 'f1000000-0000-4000-8000-000000000003', 'Canonical Hall', 'Canonical Hall', null,
    '{"place_type":"Venue","address":"2 Test Way","latitude":1.5,"longitude":2.5,"ended":false,"area_mbid":"f1000000-0000-4000-8000-000000000001","area_name":"Area relation stub"}',
    '[]'
  )),
  current_setting('test.mb_area_id'),
  'MusicBrainz place derives a tunedIn area identity'
);

select set_config(
  'test.mb_song_id',
  (select id::text from public.upsert_musicbrainz_catalog_entity(
    'song', 'f1000000-0000-4000-8000-000000000004', 'Canonical Song', null, null,
    '{"work_mbid":null,"duration_ms":123000,"first_release_date":"2026","artist_credit":"Stage Alias"}',
    '[{"artist_mbid":"f1000000-0000-4000-8000-000000000002","name":"Canonical Artist","credit_name":"Stage Alias","join_phrase":""}]'
  )),
  true
);

select is(
  (select metadata #>> '{artistCredit,0,name}' from public.upsert_musicbrainz_catalog_entity(
    'song', 'f1000000-0000-4000-8000-000000000004', 'Canonical Song', null, null,
    '{"work_mbid":null,"duration_ms":123000,"first_release_date":"2026","artist_credit":"Stage Alias"}',
    '[{"artist_mbid":"f1000000-0000-4000-8000-000000000002","name":"Canonical Artist","credit_name":"Stage Alias","join_phrase":""}]'
  )),
  'Stage Alias',
  'song metadata preserves the credited-as artist name'
);

select is(
  (select metadata #>> '{artistCredit,0,canonicalName}' from public.upsert_musicbrainz_catalog_entity(
    'song', 'f1000000-0000-4000-8000-000000000004', 'Canonical Song', null, null,
    '{"work_mbid":null,"duration_ms":123000,"first_release_date":"2026","artist_credit":"Stage Alias"}',
    '[{"artist_mbid":"f1000000-0000-4000-8000-000000000002","name":"Canonical Artist","credit_name":"Stage Alias","join_phrase":""}]'
  )),
  'Canonical Artist',
  'song metadata preserves the canonical artist name separately'
);

select is(
  (select metadata #>> '{artistCredit,0,joinPhrase}' from public.upsert_musicbrainz_catalog_entity(
    'song', 'f1000000-0000-4000-8000-000000000004', 'Canonical Song', null, null,
    '{"work_mbid":null,"duration_ms":123000,"first_release_date":"2026","artist_credit":"Stage Alias"}',
    '[{"artist_mbid":"f1000000-0000-4000-8000-000000000002","name":"Canonical Artist","credit_name":"Stage Alias","join_phrase":" feat. "}]'
  )),
  ' feat. ',
  'song metadata preserves MusicBrainz join-phrase boundary whitespace exactly'
);

reset role;
select is(
  (select sort_name from public.catalog_entities where id = current_setting('test.mb_artist_id')::uuid),
  'Artist, Canonical',
  'credit relation stubs do not clobber authoritative artist sort metadata'
);

select is(
  (select sort_name from public.catalog_entities where id = current_setting('test.mb_area_id')::uuid),
  'Area, Rich',
  'area relation stubs do not clobber authoritative area metadata'
);
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

select set_config(
  'test.mb_tour_id',
  (select id::text from public.upsert_musicbrainz_catalog_entity(
    'tour', 'f1000000-0000-4000-8000-000000000005', 'Canonical Tour', null, null,
    '{"series_type":"Tour","disambiguation":null}',
    '[{"artist_mbid":"f1000000-0000-4000-8000-000000000002","name":"Canonical Artist","credit_name":"Canonical Artist","join_phrase":""}]'
  )),
  true
);

select is(
  (select metadata #>> '{artistCredit,0,canonicalName}'
   from public.upsert_musicbrainz_catalog_entity(
     'tour', 'f1000000-0000-4000-8000-000000000005', 'Canonical Tour', null, null,
     '{"series_type":"Tour","disambiguation":null}',
     '[{"artist_mbid":"f1000000-0000-4000-8000-000000000002","name":"Canonical Artist","credit_name":"Canonical Artist","join_phrase":""}]'
   )),
  'Canonical Artist',
  'tour ingestion stores structured artist relations'
);

select lives_ok(
  $$select public.put_musicbrainz_cache(
    'v1:' || repeat('a', 64), 'artist', 'lookup', '{"fixture":true}', 60
  )$$,
  'service role can write a bounded MusicBrainz cache entry'
);

select is(
  public.get_musicbrainz_cache('v1:' || repeat('a', 64)),
  '{"fixture":true}'::jsonb,
  'service role reads the cached payload'
);

reset role;
insert into private.musicbrainz_cache (
  cache_key, kind, request_type, payload, expires_at
)
values ('v1:' || repeat('b', 64), 'artist', 'lookup', '{}', clock_timestamp() - interval '1 second');
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

select is(
  public.get_musicbrainz_cache('v1:' || repeat('c', 64)),
  null::jsonb,
  'an unrelated cache read returns a miss'
);

reset role;
select is(
  (select count(*) from private.musicbrainz_cache where cache_key = 'v1:' || repeat('b', 64)),
  0::bigint,
  'bounded opportunistic cleanup removes expired cache rows'
);

set local role service_role;
select ok(
  public.claim_musicbrainz_request(
    'v1:' || repeat('d', 64), 'f2000000-0000-4000-8000-000000000001', 60
  ),
  'the first service worker claims an upstream request'
);
select ok(
  not public.claim_musicbrainz_request(
    'v1:' || repeat('d', 64), 'f2000000-0000-4000-8000-000000000002', 60
  ),
  'a second worker cannot steal a live request lease'
);

reset role;
insert into private.musicbrainz_request_leases (cache_key, lease_id, lease_expires_at)
values (
  'v1:' || repeat('e', 64),
  'f2000000-0000-4000-8000-000000000003',
  clock_timestamp() - interval '1 second'
);
set local role service_role;
select ok(
  public.claim_musicbrainz_request(
    'v1:' || repeat('f', 64), 'f2000000-0000-4000-8000-000000000004', 60
  ),
  'a later request can claim after cleaning expired leases'
);
reset role;
select is(
  (select count(*) from private.musicbrainz_request_leases
   where cache_key = 'v1:' || repeat('e', 64)),
  0::bigint,
  'expired request leases are cleaned opportunistically'
);

set local role service_role;
select set_config('test.slot_one', public.reserve_musicbrainz_request_slot(5000)::text, true);
select set_config('test.slot_two', public.reserve_musicbrainz_request_slot(5000)::text, true);
select ok(
  current_setting('test.slot_two')::timestamptz
    >= current_setting('test.slot_one')::timestamptz + interval '1 second',
  'the database enforces one MusicBrainz request slot per second globally'
);

reset role;
insert into private.catalog_search_requests (profile_id, requested_at)
select 'e1000000-0000-4000-8000-000000000001', clock_timestamp()
from generate_series(1, 120);
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select throws_ok(
  $$select public.consume_catalog_search_quota(
    'e1000000-0000-4000-8000-000000000001'
  )$$,
  'P0001', null,
  'the service-side database boundary rejects catalog search above its hourly quota'
);

select is(
  (select catalog_id from public.get_catalog_artist_search_context(
    'e1000000-0000-4000-8000-000000000001',
    array[current_setting('test.catalog_artist_id')::uuid]
  )),
  current_setting('test.catalog_artist_id')::uuid,
  'service search context preserves validated artist input order'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select public.upsert_musicbrainz_catalog_entity(
    'artist', 'f3000000-0000-4000-8000-000000000001', 'Forged MB Artist'
  )$$,
  '42501', null,
  'authenticated users cannot forge MusicBrainz provenance'
);

select throws_ok(
  $$select public.get_catalog_artist_search_context(
    'e1000000-0000-4000-8000-000000000001',
    array[current_setting('test.catalog_artist_id')::uuid]
  )$$,
  '42501', null,
  'artist context expansion is service-role-only'
);

select throws_ok(
  $$select public.consume_catalog_search_quota(
    'e1000000-0000-4000-8000-000000000001'
  )$$,
  '42501', null,
  'authenticated clients cannot invoke the service-only search quota RPC'
);

select * from finish();
rollback;
