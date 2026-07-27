-- Disposable Local Supabase journey catalog.
--
-- These are synthetic, deterministic accounts and current database states for
-- exercising the real Local app without creating profiles, friendships, or
-- concerts first. Every row is reset by `make local-db-reset`; do not apply
-- this file to the hosted Development project.

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change,
  phone_change,
  phone_change_token,
  email_change_token_current,
  reauthentication_token,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
select
  '00000000-0000-0000-0000-000000000000',
  id,
  'authenticated',
  'authenticated',
  email,
  extensions.crypt(
    'tunedIn-local-seeded-account',
    '$2a$10$N9qo8uLOickgx2ZMRZoMye'
  ),
  timestamptz '2025-01-01 12:00:00+00',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  timestamptz '2025-01-01 12:00:00+00',
  timestamptz '2025-01-01 12:00:00+00',
  false,
  false
from (
  values
    ('d1000000-0000-0000-0000-000000000001'::uuid, 'listener@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000002'::uuid, 'morgan@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000003'::uuid, 'ava@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000004'::uuid, 'jules@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000005'::uuid, 'riley@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000006'::uuid, 'casey@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000007'::uuid, 'sasha@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000008'::uuid, 'theo@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000009'::uuid, 'june@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000010'::uuid, 'noah@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000011'::uuid, 'blair@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000012'::uuid, 'elena@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000013'::uuid, 'quinn@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000014'::uuid, 'marin@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000015'::uuid, 'parker@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000016'::uuid, 'newcomer@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000017'::uuid, 'remi@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000018'::uuid, 'kai@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000019'::uuid, 'rowan@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000020'::uuid, 'mia@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000021'::uuid, 'leo@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000022'::uuid, 'nia@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000023'::uuid, 'owen@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000024'::uuid, 'zoe@tunedin.local')
) as account(id, email);

insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
select
  md5('identity:' || id::text)::uuid,
  id::text,
  id,
  jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true),
  'email',
  null,
  timestamptz '2025-01-01 12:00:00+00',
  timestamptz '2025-01-01 12:00:00+00'
from (
  values
    ('d1000000-0000-0000-0000-000000000001'::uuid, 'listener@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000002'::uuid, 'morgan@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000003'::uuid, 'ava@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000004'::uuid, 'jules@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000005'::uuid, 'riley@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000006'::uuid, 'casey@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000007'::uuid, 'sasha@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000008'::uuid, 'theo@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000009'::uuid, 'june@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000010'::uuid, 'noah@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000011'::uuid, 'blair@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000012'::uuid, 'elena@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000013'::uuid, 'quinn@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000014'::uuid, 'marin@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000015'::uuid, 'parker@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000016'::uuid, 'newcomer@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000017'::uuid, 'remi@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000018'::uuid, 'kai@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000019'::uuid, 'rowan@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000020'::uuid, 'mia@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000021'::uuid, 'leo@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000022'::uuid, 'nia@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000023'::uuid, 'owen@tunedin.local'),
    ('d1000000-0000-0000-0000-000000000024'::uuid, 'zoe@tunedin.local')
) as account(id, email);

update public.profiles as profile
set
  username = account.username,
  display_name = account.display_name,
  onboarding_completed_at = timestamptz '2025-01-01 12:00:00+00'
from (
  values
    ('d1000000-0000-0000-0000-000000000001'::uuid, 'local_listener', 'Local Listener'),
    ('d1000000-0000-0000-0000-000000000002'::uuid, 'luna_local', 'Morgan Moon'),
    ('d1000000-0000-0000-0000-000000000003'::uuid, 'ava_park', 'Ava Park'),
    ('d1000000-0000-0000-0000-000000000004'::uuid, 'jules_river', 'Jules River'),
    ('d1000000-0000-0000-0000-000000000005'::uuid, 'riley_santos', 'Riley Santos'),
    ('d1000000-0000-0000-0000-000000000006'::uuid, 'casey_chen', 'Casey Chen'),
    ('d1000000-0000-0000-0000-000000000007'::uuid, 'sasha_lane', 'Sasha Lane'),
    ('d1000000-0000-0000-0000-000000000008'::uuid, 'theo_gray', 'Theo Gray'),
    ('d1000000-0000-0000-0000-000000000009'::uuid, 'june_lee', 'June Lee'),
    ('d1000000-0000-0000-0000-000000000010'::uuid, 'noah_king', 'Noah King'),
    ('d1000000-0000-0000-0000-000000000011'::uuid, 'blair_song', 'Blair Song'),
    ('d1000000-0000-0000-0000-000000000012'::uuid, 'elena_rose', 'Elena Rose'),
    ('d1000000-0000-0000-0000-000000000013'::uuid, 'quinn_west', 'Quinn West'),
    ('d1000000-0000-0000-0000-000000000014'::uuid, 'marin_haze', 'Marin Haze'),
    ('d1000000-0000-0000-0000-000000000015'::uuid, 'parker_june', 'Parker June'),
    ('d1000000-0000-0000-0000-000000000017'::uuid, 'remi_cole', 'Remi Cole'),
    ('d1000000-0000-0000-0000-000000000018'::uuid, 'kai_mercer', 'Kai Mercer'),
    ('d1000000-0000-0000-0000-000000000019'::uuid, 'rowan_ellis', 'Rowan Ellis'),
    ('d1000000-0000-0000-0000-000000000020'::uuid, 'mia_torres', 'Mia Torres'),
    ('d1000000-0000-0000-0000-000000000021'::uuid, 'leo_hart', 'Leo Hart'),
    ('d1000000-0000-0000-0000-000000000022'::uuid, 'nia_brooks', 'Nia Brooks'),
    ('d1000000-0000-0000-0000-000000000023'::uuid, 'owen_cruz', 'Owen Cruz'),
    ('d1000000-0000-0000-0000-000000000024'::uuid, 'zoe_kim', 'Zoe Kim')
) as account(id, username, display_name)
where profile.id = account.id
;

-- Fixed catalog fixtures prove MusicBrainz and community-created durable origins without contacting the
-- live MusicBrainz service. The custom Fillmore place is reused by two seeded
-- concerts below; the remaining entries make every custom form searchable.
insert into public.catalog_entities (
  id, kind, origin, status, display_name, sort_name, disambiguation,
  musicbrainz_mbid, created_at, updated_at
)
values
  ('d3000000-0000-0000-0000-000000000001', 'area', 'musicbrainz', 'active', 'San Francisco', 'San Francisco', null, '33333333-3333-4333-8333-333333333333', timestamptz '2025-01-01 12:00:00+00', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000101', 'area', 'tunedin_custom', 'active', 'San Francisco', 'San Francisco', null, null, timestamptz '2025-01-01 12:00:00+00', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000102', 'artist', 'tunedin_custom', 'active', 'The Local Signals', 'The Local Signals', null, null, timestamptz '2025-01-01 12:00:00+00', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000103', 'place', 'tunedin_custom', 'active', 'The Fillmore', 'The Fillmore', 'Local reusable venue fixture', null, timestamptz '2025-01-01 12:00:00+00', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000104', 'song', 'tunedin_custom', 'active', 'Midnight Test Signal', 'Midnight Test Signal', null, null, timestamptz '2025-01-01 12:00:00+00', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000105', 'tour', 'tunedin_custom', 'active', 'Local Fixture Tour', 'Local Fixture Tour', null, null, timestamptz '2025-01-01 12:00:00+00', timestamptz '2025-01-01 12:00:00+00');

insert into public.catalog_areas (id, country_code)
values
  ('d3000000-0000-0000-0000-000000000001', 'US'),
  ('d3000000-0000-0000-0000-000000000101', 'US');

insert into public.catalog_artists (id, artist_type, area_id, area_name)
values
  ('d3000000-0000-0000-0000-000000000102', 'Group', 'd3000000-0000-0000-0000-000000000101', 'San Francisco');

insert into public.catalog_places (id, area_id, place_type, address)
values
  ('d3000000-0000-0000-0000-000000000103', 'd3000000-0000-0000-0000-000000000101', 'Venue', '1805 Geary Blvd');

insert into public.catalog_songs (id, artist_credit)
values
  ('d3000000-0000-0000-0000-000000000104', 'The Local Signals');

insert into public.catalog_song_artists (
  song_id, artist_id, credit_position, credit_name, join_phrase
)
values
  ('d3000000-0000-0000-0000-000000000104', 'd3000000-0000-0000-0000-000000000102', 1, 'The Local Signals', '');

insert into public.catalog_tours (id)
values
  ('d3000000-0000-0000-0000-000000000105');

insert into public.catalog_tour_artists (tour_id, artist_id, credit_position)
values
  ('d3000000-0000-0000-0000-000000000105', 'd3000000-0000-0000-0000-000000000102', 1);

insert into private.catalog_entity_provenance (
  entity_id, kind, creator_id, dedupe_key, created_at
)
values
  ('d3000000-0000-0000-0000-000000000101', 'area', 'd1000000-0000-0000-0000-000000000001', 'area|san francisco|country:US|parent:-', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000102', 'artist', 'd1000000-0000-0000-0000-000000000001', 'artist|the local signals|type:group|area:d3000000-0000-0000-0000-000000000101|disambiguation:-', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000103', 'place', 'd1000000-0000-0000-0000-000000000001', 'place|the fillmore|area:d3000000-0000-0000-0000-000000000101', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000104', 'song', 'd1000000-0000-0000-0000-000000000001', 'song|midnight test signal|artists:d3000000-0000-0000-0000-000000000102|disambiguation:-', timestamptz '2025-01-01 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000105', 'tour', 'd1000000-0000-0000-0000-000000000001', 'tour|local fixture tour|artists:d3000000-0000-0000-0000-000000000102', timestamptz '2025-01-01 12:00:00+00');

-- Mirror the provenance written by production MusicBrainz ingestion without
-- assigning a tunedIn creator to the external entity.
insert into private.catalog_entity_provenance (
  entity_id, kind, source_updated_at, refreshed_at, created_at
)
values (
  'd3000000-0000-0000-0000-000000000001',
  'area',
  timestamptz '2025-01-01 12:00:00+00',
  timestamptz '2025-01-01 12:00:00+00',
  timestamptz '2025-01-01 12:00:00+00'
);

-- Distinct community-built artists make discovery and profile collections
-- visually and semantically varied without pretending they came from
-- MusicBrainz. Their event covers are attached through the same protected
-- Storage/RPC path as a real creator upload after the SQL seed completes.
insert into public.catalog_entities (
  id, kind, origin, status, display_name, sort_name, disambiguation,
  musicbrainz_mbid, created_at, updated_at
)
values
  ('d3000000-0000-0000-0000-000000000106', 'artist', 'tunedin_custom', 'active', 'Neon Orchard', 'Neon Orchard', 'Local visual journey fixture', null, timestamptz '2026-07-16 12:00:00+00', timestamptz '2026-07-16 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000107', 'artist', 'tunedin_custom', 'active', 'Blue Hour Club', 'Blue Hour Club', 'Local visual journey fixture', null, timestamptz '2026-07-16 12:00:00+00', timestamptz '2026-07-16 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000108', 'artist', 'tunedin_custom', 'active', 'Juniper Static', 'Juniper Static', 'Local visual journey fixture', null, timestamptz '2026-07-16 12:00:00+00', timestamptz '2026-07-16 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000109', 'artist', 'tunedin_custom', 'active', 'Velvet Transit', 'Velvet Transit', 'Local visual journey fixture', null, timestamptz '2026-07-16 12:00:00+00', timestamptz '2026-07-16 12:00:00+00');

insert into public.catalog_artists (id, artist_type, area_id, area_name)
values
  ('d3000000-0000-0000-0000-000000000106', 'Group', 'd3000000-0000-0000-0000-000000000101', 'San Francisco'),
  ('d3000000-0000-0000-0000-000000000107', 'Group', 'd3000000-0000-0000-0000-000000000101', 'San Francisco'),
  ('d3000000-0000-0000-0000-000000000108', 'Group', 'd3000000-0000-0000-0000-000000000101', 'San Francisco'),
  ('d3000000-0000-0000-0000-000000000109', 'Group', 'd3000000-0000-0000-0000-000000000101', 'San Francisco');

insert into private.catalog_entity_provenance (
  entity_id, kind, creator_id, dedupe_key, created_at
)
values
  ('d3000000-0000-0000-0000-000000000106', 'artist', 'd1000000-0000-0000-0000-000000000001', 'artist|neon orchard|type:group|area:d3000000-0000-0000-0000-000000000101|disambiguation:local visual journey fixture', timestamptz '2026-07-16 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000107', 'artist', 'd1000000-0000-0000-0000-000000000001', 'artist|blue hour club|type:group|area:d3000000-0000-0000-0000-000000000101|disambiguation:local visual journey fixture', timestamptz '2026-07-16 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000108', 'artist', 'd1000000-0000-0000-0000-000000000001', 'artist|juniper static|type:group|area:d3000000-0000-0000-0000-000000000101|disambiguation:local visual journey fixture', timestamptz '2026-07-16 12:00:00+00'),
  ('d3000000-0000-0000-0000-000000000109', 'artist', 'd1000000-0000-0000-0000-000000000001', 'artist|velvet transit|type:group|area:d3000000-0000-0000-0000-000000000101|disambiguation:local visual journey fixture', timestamptz '2026-07-16 12:00:00+00');

-- Shared community-event journeys are independent from personal concert
-- posts. They cover public discovery, creator-only unlisted access, packed and
-- empty upcoming/completed occurrences, and cancellation without deleting the
-- source event or its immutable activity.
do $community_event_seed$
begin
insert into public.catalog_events (
  id,
  created_by,
  catalog_place_id,
  catalog_area_id,
  catalog_tour_id,
  headliner_catalog_artist_id,
  event_date,
  starts_at,
  time_zone_identifier,
  memory_unlock_at,
  lifecycle,
  listing,
  integrity,
  row_state,
  version,
  venue_name_snapshot,
  area_name_snapshot,
  tour_name_snapshot,
  headliner_name_snapshot,
  search_text,
  exact_duplicate_key,
  created_at,
  updated_at,
  last_material_activity_at
)
values
  (
    'd4000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000103',
    'd3000000-0000-0000-0000-000000000101',
    'd3000000-0000-0000-0000-000000000105',
    'd3000000-0000-0000-0000-000000000102',
    date '2026-09-18',
    timestamptz '2026-09-19 03:00:00+00',
    'America/Los_Angeles',
    timestamptz '2026-09-19 07:00:00+00',
    'scheduled',
    'listed',
    'community_added',
    'active',
    1,
    'The Fillmore',
    'San Francisco',
    'Local Fixture Tour',
    'The Local Signals',
    'the local signals the fillmore san francisco local fixture tour',
    md5(
      'listed|d3000000-0000-0000-0000-000000000103|2026-09-18'
      || '|d3000000-0000-0000-0000-000000000102'
    ),
    timestamptz '2026-07-16 18:00:00+00',
    timestamptz '2026-07-16 18:00:00+00',
    timestamptz '2026-07-16 18:00:00+00'
  ),
  (
    'd4000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000103',
    'd3000000-0000-0000-0000-000000000101',
    null,
    'd3000000-0000-0000-0000-000000000102',
    date '2026-05-08',
    timestamptz '2026-05-09 03:00:00+00',
    'America/Los_Angeles',
    timestamptz '2026-05-09 07:00:00+00',
    'completed',
    'listed',
    'corroborated',
    'active',
    2,
    'The Fillmore',
    'San Francisco',
    null,
    'The Local Signals',
    'the local signals the fillmore san francisco',
    md5(
      'listed|d3000000-0000-0000-0000-000000000103|2026-05-08'
      || '|d3000000-0000-0000-0000-000000000102'
    ),
    timestamptz '2026-05-01 18:00:00+00',
    timestamptz '2026-05-09 09:00:00+00',
    timestamptz '2026-05-09 09:00:00+00'
  ),
  (
    'd4000000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000103',
    'd3000000-0000-0000-0000-000000000101',
    null,
    'd3000000-0000-0000-0000-000000000102',
    date '2026-10-04',
    timestamptz '2026-10-05 03:00:00+00',
    'America/Los_Angeles',
    timestamptz '2026-10-05 07:00:00+00',
    'scheduled',
    'unlisted',
    'community_added',
    'active',
    1,
    'The Fillmore',
    'San Francisco',
    null,
    'The Local Signals',
    'the local signals the fillmore san francisco',
    md5(
      'unlisted:d1000000-0000-0000-0000-000000000001|'
      || 'd3000000-0000-0000-0000-000000000103|2026-10-04'
      || '|d3000000-0000-0000-0000-000000000102'
    ),
    timestamptz '2026-07-16 19:00:00+00',
    timestamptz '2026-07-16 19:00:00+00',
    timestamptz '2026-07-16 19:00:00+00'
  ),
  (
    'd4000000-0000-0000-0000-000000000004',
    'd1000000-0000-0000-0000-000000000003',
    'd3000000-0000-0000-0000-000000000103',
    'd3000000-0000-0000-0000-000000000101',
    null,
    'd3000000-0000-0000-0000-000000000102',
    date '2026-08-22',
    timestamptz '2026-08-23 03:00:00+00',
    'America/Los_Angeles',
    timestamptz '2026-08-23 07:00:00+00',
    'cancelled',
    'listed',
    'disputed',
    'active',
    3,
    'The Fillmore',
    'San Francisco',
    null,
    'The Local Signals',
    'the local signals the fillmore san francisco',
    md5(
      'listed|d3000000-0000-0000-0000-000000000103|2026-08-22'
      || '|d3000000-0000-0000-0000-000000000102'
    ),
    timestamptz '2026-07-10 18:00:00+00',
    timestamptz '2026-07-15 18:00:00+00',
    timestamptz '2026-07-15 18:00:00+00'
  ),
  (
    'd4000000-0000-0000-0000-000000000005',
    'd1000000-0000-0000-0000-000000000017',
    'd3000000-0000-0000-0000-000000000103',
    'd3000000-0000-0000-0000-000000000101',
    null,
    'd3000000-0000-0000-0000-000000000102',
    date '2026-11-14',
    timestamptz '2026-11-15 04:00:00+00',
    'America/Los_Angeles',
    timestamptz '2026-11-15 08:00:00+00',
    'scheduled',
    'listed',
    'community_added',
    'active',
    1,
    'The Fillmore',
    'San Francisco',
    null,
    'The Local Signals',
    'the local signals the fillmore san francisco',
    md5(
      'listed|d3000000-0000-0000-0000-000000000103|2026-11-14'
      || '|d3000000-0000-0000-0000-000000000102'
    ),
    timestamptz '2026-07-12 18:00:00+00',
    timestamptz '2026-07-12 18:00:00+00',
    timestamptz '2026-07-12 18:00:00+00'
  ),
  (
    'd4000000-0000-0000-0000-000000000006',
    'd1000000-0000-0000-0000-000000000018',
    'd3000000-0000-0000-0000-000000000103',
    'd3000000-0000-0000-0000-000000000101',
    null,
    'd3000000-0000-0000-0000-000000000102',
    date '2026-04-03',
    timestamptz '2026-04-04 03:00:00+00',
    'America/Los_Angeles',
    timestamptz '2026-04-04 07:00:00+00',
    'completed',
    'listed',
    'corroborated',
    'active',
    1,
    'The Fillmore',
    'San Francisco',
    null,
    'The Local Signals',
    'the local signals the fillmore san francisco',
    md5(
      'listed|d3000000-0000-0000-0000-000000000103|2026-04-03'
      || '|d3000000-0000-0000-0000-000000000102'
    ),
    timestamptz '2026-04-01 18:00:00+00',
    timestamptz '2026-04-01 18:00:00+00',
    timestamptz '2026-04-01 18:00:00+00'
  );

insert into public.catalog_event_artists (
  event_id,
  catalog_artist_id,
  lineup_position,
  is_headliner,
  artist_name_snapshot
)
select
  event_id,
  'd3000000-0000-0000-0000-000000000102',
  1,
  true,
  'The Local Signals'
from unnest(array[
  'd4000000-0000-0000-0000-000000000001'::uuid,
  'd4000000-0000-0000-0000-000000000002'::uuid,
  'd4000000-0000-0000-0000-000000000003'::uuid,
  'd4000000-0000-0000-0000-000000000004'::uuid,
  'd4000000-0000-0000-0000-000000000005'::uuid,
  'd4000000-0000-0000-0000-000000000006'::uuid
]) as event(event_id);
end
$community_event_seed$;

insert into public.catalog_events (
  id, created_by, catalog_place_id, catalog_area_id, catalog_tour_id,
  headliner_catalog_artist_id, event_date, starts_at, time_zone_identifier,
  memory_unlock_at, lifecycle, listing, integrity, row_state, version,
  venue_name_snapshot, area_name_snapshot, tour_name_snapshot,
  headliner_name_snapshot, search_text, exact_duplicate_key,
  created_at, updated_at, last_material_activity_at
)
values
  ('d4000000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000103', 'd3000000-0000-0000-0000-000000000101', null, 'd3000000-0000-0000-0000-000000000106', date '2026-08-02', timestamptz '2026-08-03 02:30:00+00', 'America/Los_Angeles', timestamptz '2026-08-03 06:30:00+00', 'scheduled', 'listed', 'community_added', 'active', 1, 'The Fillmore', 'San Francisco', null, 'Neon Orchard', 'neon orchard the fillmore san francisco', md5('listed|d3000000-0000-0000-0000-000000000103|2026-08-02|d3000000-0000-0000-0000-000000000106'), timestamptz '2026-07-16 21:00:00+00', timestamptz '2026-07-16 21:00:00+00', timestamptz '2026-07-16 21:00:00+00'),
  ('d4000000-0000-0000-0000-000000000008', 'd1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000103', 'd3000000-0000-0000-0000-000000000101', null, 'd3000000-0000-0000-0000-000000000107', date '2026-08-27', timestamptz '2026-08-28 03:00:00+00', 'America/Los_Angeles', timestamptz '2026-08-28 07:00:00+00', 'scheduled', 'listed', 'community_added', 'active', 1, 'The Fillmore', 'San Francisco', null, 'Blue Hour Club', 'blue hour club the fillmore san francisco', md5('listed|d3000000-0000-0000-0000-000000000103|2026-08-27|d3000000-0000-0000-0000-000000000107'), timestamptz '2026-07-16 21:01:00+00', timestamptz '2026-07-16 21:01:00+00', timestamptz '2026-07-16 21:01:00+00'),
  ('d4000000-0000-0000-0000-000000000009', 'd1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000103', 'd3000000-0000-0000-0000-000000000101', null, 'd3000000-0000-0000-0000-000000000108', date '2026-10-23', timestamptz '2026-10-24 03:00:00+00', 'America/Los_Angeles', timestamptz '2026-10-24 07:00:00+00', 'scheduled', 'listed', 'community_added', 'active', 1, 'The Fillmore', 'San Francisco', null, 'Juniper Static', 'juniper static the fillmore san francisco', md5('listed|d3000000-0000-0000-0000-000000000103|2026-10-23|d3000000-0000-0000-0000-000000000108'), timestamptz '2026-07-16 21:02:00+00', timestamptz '2026-07-16 21:02:00+00', timestamptz '2026-07-16 21:02:00+00'),
  ('d4000000-0000-0000-0000-000000000010', 'd1000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000103', 'd3000000-0000-0000-0000-000000000101', null, 'd3000000-0000-0000-0000-000000000109', date '2026-12-05', timestamptz '2026-12-06 04:00:00+00', 'America/Los_Angeles', timestamptz '2026-12-06 08:00:00+00', 'scheduled', 'listed', 'community_added', 'active', 1, 'The Fillmore', 'San Francisco', null, 'Velvet Transit', 'velvet transit the fillmore san francisco', md5('listed|d3000000-0000-0000-0000-000000000103|2026-12-05|d3000000-0000-0000-0000-000000000109'), timestamptz '2026-07-16 21:03:00+00', timestamptz '2026-07-16 21:03:00+00', timestamptz '2026-07-16 21:03:00+00');

insert into public.catalog_event_artists (
  event_id, catalog_artist_id, lineup_position, is_headliner, artist_name_snapshot
)
values
  ('d4000000-0000-0000-0000-000000000007', 'd3000000-0000-0000-0000-000000000106', 1, true, 'Neon Orchard'),
  ('d4000000-0000-0000-0000-000000000008', 'd3000000-0000-0000-0000-000000000107', 1, true, 'Blue Hour Club'),
  ('d4000000-0000-0000-0000-000000000009', 'd3000000-0000-0000-0000-000000000108', 1, true, 'Juniper Static'),
  ('d4000000-0000-0000-0000-000000000010', 'd3000000-0000-0000-0000-000000000109', 1, true, 'Velvet Transit');

insert into public.social_activity_events (
  id, actor_id, action, event_id, metadata, occurred_at
)
values
  ('d4100000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'event_created', 'd4000000-0000-0000-0000-000000000001', '{}'::jsonb, timestamptz '2026-07-16 18:00:00+00'),
  ('d4100000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', 'event_created', 'd4000000-0000-0000-0000-000000000002', '{}'::jsonb, timestamptz '2026-05-01 18:00:00+00'),
  ('d4100000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'event_created', 'd4000000-0000-0000-0000-000000000003', '{}'::jsonb, timestamptz '2026-07-16 19:00:00+00'),
  ('d4100000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000003', 'event_created', 'd4000000-0000-0000-0000-000000000004', '{}'::jsonb, timestamptz '2026-07-10 18:00:00+00'),
  ('d4100000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000003', 'event_updated', 'd4000000-0000-0000-0000-000000000004', '{"version":3}'::jsonb, timestamptz '2026-07-15 18:00:00+00'),
  ('d4100000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000017', 'event_created', 'd4000000-0000-0000-0000-000000000005', '{}'::jsonb, timestamptz '2026-07-12 18:00:00+00'),
  ('d4100000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000018', 'event_created', 'd4000000-0000-0000-0000-000000000006', '{}'::jsonb, timestamptz '2026-04-01 18:00:00+00');

insert into public.relationships (
  user_low_id,
  user_high_id,
  status,
  initiator_id,
  responder_id,
  requested_at,
  responded_at,
  created_at,
  updated_at
)
values
  -- Local Listener's usable friend circle.
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'accepted', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', timestamptz '2025-01-02 10:00:00+00', timestamptz '2025-01-02 11:00:00+00', timestamptz '2025-01-02 10:00:00+00', timestamptz '2025-01-02 11:00:00+00'),
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000003', 'accepted', 'd1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', timestamptz '2025-01-03 10:00:00+00', timestamptz '2025-01-03 11:00:00+00', timestamptz '2025-01-03 10:00:00+00', timestamptz '2025-01-03 11:00:00+00'),
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000004', 'accepted', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000004', timestamptz '2025-01-04 10:00:00+00', timestamptz '2025-01-04 11:00:00+00', timestamptz '2025-01-04 10:00:00+00', timestamptz '2025-01-04 11:00:00+00'),
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000005', 'accepted', 'd1000000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000001', timestamptz '2025-01-05 10:00:00+00', timestamptz '2025-01-05 11:00:00+00', timestamptz '2025-01-05 10:00:00+00', timestamptz '2025-01-05 11:00:00+00'),
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000006', 'accepted', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000006', timestamptz '2025-01-06 10:00:00+00', timestamptz '2025-01-06 11:00:00+00', timestamptz '2025-01-06 10:00:00+00', timestamptz '2025-01-06 11:00:00+00'),
  -- Search-state journeys: outgoing, incoming, declined, and unrelated.
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000007', 'pending', 'd1000000-0000-0000-0000-000000000001', null, timestamptz '2026-06-01 10:00:00+00', null, timestamptz '2026-06-01 10:00:00+00', timestamptz '2026-06-01 10:00:00+00'),
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000008', 'pending', 'd1000000-0000-0000-0000-000000000008', null, timestamptz '2026-06-02 10:00:00+00', null, timestamptz '2026-06-02 10:00:00+00', timestamptz '2026-06-02 10:00:00+00'),
  ('d1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000009', 'declined', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000009', timestamptz '2026-05-01 10:00:00+00', timestamptz '2026-05-02 10:00:00+00', timestamptz '2026-05-01 10:00:00+00', timestamptz '2026-05-02 10:00:00+00'),
  -- Friends' own circles make profile friend lists worth exploring.
  ('d1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', 'accepted', 'd1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', timestamptz '2025-02-01 10:00:00+00', timestamptz '2025-02-01 11:00:00+00', timestamptz '2025-02-01 10:00:00+00', timestamptz '2025-02-01 11:00:00+00'),
  ('d1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000004', 'accepted', 'd1000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000002', timestamptz '2025-02-02 10:00:00+00', timestamptz '2025-02-02 11:00:00+00', timestamptz '2025-02-02 10:00:00+00', timestamptz '2025-02-02 11:00:00+00'),
  ('d1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000005', 'accepted', 'd1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000005', timestamptz '2025-02-03 10:00:00+00', timestamptz '2025-02-03 11:00:00+00', timestamptz '2025-02-03 10:00:00+00', timestamptz '2025-02-03 11:00:00+00'),
  ('d1000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000006', 'accepted', 'd1000000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000004', timestamptz '2025-02-04 10:00:00+00', timestamptz '2025-02-04 11:00:00+00', timestamptz '2025-02-04 10:00:00+00', timestamptz '2025-02-04 11:00:00+00');

insert into public.relationships (
  user_low_id,
  user_high_id,
  status,
  initiator_id,
  responder_id,
  requested_at,
  responded_at,
  created_at,
  updated_at
)
select
  'd1000000-0000-0000-0000-000000000001'::uuid,
  friend_id,
  'accepted',
  'd1000000-0000-0000-0000-000000000001'::uuid,
  friend_id,
  timestamptz '2025-03-01 10:00:00+00' + friend_index * interval '1 day',
  timestamptz '2025-03-01 11:00:00+00' + friend_index * interval '1 day',
  timestamptz '2025-03-01 10:00:00+00' + friend_index * interval '1 day',
  timestamptz '2025-03-01 11:00:00+00' + friend_index * interval '1 day'
from unnest(array[
  'd1000000-0000-0000-0000-000000000017'::uuid,
  'd1000000-0000-0000-0000-000000000018'::uuid,
  'd1000000-0000-0000-0000-000000000019'::uuid,
  'd1000000-0000-0000-0000-000000000020'::uuid,
  'd1000000-0000-0000-0000-000000000021'::uuid,
  'd1000000-0000-0000-0000-000000000022'::uuid,
  'd1000000-0000-0000-0000-000000000023'::uuid,
  'd1000000-0000-0000-0000-000000000024'::uuid
]) with ordinality as friend(friend_id, friend_index);

-- Attendance stays independent from the personal concert archive below. These
-- rows exercise own, friends, community, private, upcoming, past, and unlisted
-- Plans states through the real audience-aware Phase 2 RPCs.
insert into public.catalog_event_attendance (
  id, event_id, profile_id, status, audience, created_at, updated_at
)
values
  ('d4050000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'going', 'friends', timestamptz '2026-07-16 20:00:00+00', timestamptz '2026-07-16 20:00:00+00'),
  ('d4050000-0000-0000-0000-000000000002', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'going', 'community', timestamptz '2026-07-16 20:01:00+00', timestamptz '2026-07-16 20:01:00+00'),
  ('d4050000-0000-0000-0000-000000000003', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000003', 'going', 'private', timestamptz '2026-07-16 20:02:00+00', timestamptz '2026-07-16 20:02:00+00'),
  ('d4050000-0000-0000-0000-000000000004', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000004', 'going', 'friends', timestamptz '2026-07-16 20:03:00+00', timestamptz '2026-07-16 20:03:00+00'),
  ('d4050000-0000-0000-0000-000000000005', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000010', 'going', 'community', timestamptz '2026-07-16 20:04:00+00', timestamptz '2026-07-16 20:04:00+00'),
  ('d4050000-0000-0000-0000-000000000006', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'went', 'private', timestamptz '2026-05-09 09:00:00+00', timestamptz '2026-05-09 09:00:00+00'),
  ('d4050000-0000-0000-0000-000000000007', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', 'went', 'community', timestamptz '2026-05-09 09:01:00+00', timestamptz '2026-05-09 09:01:00+00'),
  ('d4050000-0000-0000-0000-000000000008', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', 'did_not_go', 'friends', timestamptz '2026-05-09 09:02:00+00', timestamptz '2026-05-09 09:02:00+00'),
  ('d4050000-0000-0000-0000-000000000009', 'd4000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'going', 'private', timestamptz '2026-07-16 20:05:00+00', timestamptz '2026-07-16 20:05:00+00');

insert into public.catalog_event_attendance (
  id, event_id, profile_id, status, audience, created_at, updated_at
)
values
  ('d4050000-0000-0000-0000-000000000010', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000017', 'going', 'friends', timestamptz '2026-07-16 20:10:00+00', timestamptz '2026-07-16 20:10:00+00'),
  ('d4050000-0000-0000-0000-000000000011', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000018', 'going', 'community', timestamptz '2026-07-16 20:11:00+00', timestamptz '2026-07-16 20:11:00+00'),
  ('d4050000-0000-0000-0000-000000000012', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000019', 'going', 'friends', timestamptz '2026-07-16 20:12:00+00', timestamptz '2026-07-16 20:12:00+00'),
  ('d4050000-0000-0000-0000-000000000013', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000020', 'going', 'community', timestamptz '2026-07-16 20:13:00+00', timestamptz '2026-07-16 20:13:00+00'),
  ('d4050000-0000-0000-0000-000000000014', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000021', 'going', 'friends', timestamptz '2026-07-16 20:14:00+00', timestamptz '2026-07-16 20:14:00+00'),
  ('d4050000-0000-0000-0000-000000000015', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000022', 'going', 'community', timestamptz '2026-07-16 20:15:00+00', timestamptz '2026-07-16 20:15:00+00'),
  ('d4050000-0000-0000-0000-000000000016', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000023', 'going', 'friends', timestamptz '2026-07-16 20:16:00+00', timestamptz '2026-07-16 20:16:00+00'),
  ('d4050000-0000-0000-0000-000000000017', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000024', 'going', 'community', timestamptz '2026-07-16 20:17:00+00', timestamptz '2026-07-16 20:17:00+00'),
  ('d4050000-0000-0000-0000-000000000018', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000017', 'went', 'friends', timestamptz '2026-05-09 09:10:00+00', timestamptz '2026-05-09 09:10:00+00'),
  ('d4050000-0000-0000-0000-000000000019', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000018', 'went', 'community', timestamptz '2026-05-09 09:11:00+00', timestamptz '2026-05-09 09:11:00+00'),
  ('d4050000-0000-0000-0000-000000000020', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000019', 'went', 'friends', timestamptz '2026-05-09 09:12:00+00', timestamptz '2026-05-09 09:12:00+00'),
  ('d4050000-0000-0000-0000-000000000021', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000020', 'went', 'community', timestamptz '2026-05-09 09:13:00+00', timestamptz '2026-05-09 09:13:00+00'),
  ('d4050000-0000-0000-0000-000000000022', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000021', 'went', 'friends', timestamptz '2026-05-09 09:14:00+00', timestamptz '2026-05-09 09:14:00+00'),
  ('d4050000-0000-0000-0000-000000000023', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000022', 'went', 'community', timestamptz '2026-05-09 09:15:00+00', timestamptz '2026-05-09 09:15:00+00'),
  ('d4050000-0000-0000-0000-000000000024', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000023', 'went', 'friends', timestamptz '2026-05-09 09:16:00+00', timestamptz '2026-05-09 09:16:00+00'),
  ('d4050000-0000-0000-0000-000000000025', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000024', 'went', 'community', timestamptz '2026-05-09 09:17:00+00', timestamptz '2026-05-09 09:17:00+00');

-- The primary profile has six upcoming plans total. Each added concert also
-- has a small, different friend group so the feed proves visual variety while
-- the original Local Signals event remains the intentionally packed case.
insert into public.catalog_event_attendance (
  id, event_id, profile_id, status, audience, created_at, updated_at
)
values
  ('d4050000-0000-0000-0000-000000000026', 'd4000000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000001', 'going', 'friends', timestamptz '2026-07-16 21:04:00+00', timestamptz '2026-07-16 21:04:00+00'),
  ('d4050000-0000-0000-0000-000000000027', 'd4000000-0000-0000-0000-000000000008', 'd1000000-0000-0000-0000-000000000001', 'going', 'friends', timestamptz '2026-07-16 21:05:00+00', timestamptz '2026-07-16 21:05:00+00'),
  ('d4050000-0000-0000-0000-000000000028', 'd4000000-0000-0000-0000-000000000009', 'd1000000-0000-0000-0000-000000000001', 'going', 'friends', timestamptz '2026-07-16 21:06:00+00', timestamptz '2026-07-16 21:06:00+00'),
  ('d4050000-0000-0000-0000-000000000029', 'd4000000-0000-0000-0000-000000000010', 'd1000000-0000-0000-0000-000000000001', 'going', 'friends', timestamptz '2026-07-16 21:07:00+00', timestamptz '2026-07-16 21:07:00+00'),
  ('d4050000-0000-0000-0000-000000000030', 'd4000000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000002', 'going', 'community', timestamptz '2026-07-16 21:08:00+00', timestamptz '2026-07-16 21:08:00+00'),
  ('d4050000-0000-0000-0000-000000000031', 'd4000000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000017', 'going', 'friends', timestamptz '2026-07-16 21:09:00+00', timestamptz '2026-07-16 21:09:00+00'),
  ('d4050000-0000-0000-0000-000000000032', 'd4000000-0000-0000-0000-000000000008', 'd1000000-0000-0000-0000-000000000018', 'going', 'community', timestamptz '2026-07-16 21:10:00+00', timestamptz '2026-07-16 21:10:00+00'),
  ('d4050000-0000-0000-0000-000000000033', 'd4000000-0000-0000-0000-000000000008', 'd1000000-0000-0000-0000-000000000019', 'going', 'friends', timestamptz '2026-07-16 21:11:00+00', timestamptz '2026-07-16 21:11:00+00'),
  ('d4050000-0000-0000-0000-000000000034', 'd4000000-0000-0000-0000-000000000009', 'd1000000-0000-0000-0000-000000000020', 'going', 'community', timestamptz '2026-07-16 21:12:00+00', timestamptz '2026-07-16 21:12:00+00'),
  ('d4050000-0000-0000-0000-000000000035', 'd4000000-0000-0000-0000-000000000009', 'd1000000-0000-0000-0000-000000000021', 'going', 'friends', timestamptz '2026-07-16 21:13:00+00', timestamptz '2026-07-16 21:13:00+00'),
  ('d4050000-0000-0000-0000-000000000036', 'd4000000-0000-0000-0000-000000000010', 'd1000000-0000-0000-0000-000000000022', 'going', 'community', timestamptz '2026-07-16 21:14:00+00', timestamptz '2026-07-16 21:14:00+00'),
  ('d4050000-0000-0000-0000-000000000037', 'd4000000-0000-0000-0000-000000000010', 'd1000000-0000-0000-0000-000000000023', 'going', 'friends', timestamptz '2026-07-16 21:15:00+00', timestamptz '2026-07-16 21:15:00+00');

insert into public.social_activity_events (
  id, actor_id, action, event_id, metadata, occurred_at
)
values
  ('d4100000-0000-0000-0000-000000000101', 'd1000000-0000-0000-0000-000000000001', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"friends"}'::jsonb, timestamptz '2026-07-16 20:00:00+00'),
  ('d4100000-0000-0000-0000-000000000102', 'd1000000-0000-0000-0000-000000000002', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"community"}'::jsonb, timestamptz '2026-07-16 20:01:00+00'),
  ('d4100000-0000-0000-0000-000000000103', 'd1000000-0000-0000-0000-000000000003', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"private"}'::jsonb, timestamptz '2026-07-16 20:02:00+00'),
  ('d4100000-0000-0000-0000-000000000104', 'd1000000-0000-0000-0000-000000000004', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"friends"}'::jsonb, timestamptz '2026-07-16 20:03:00+00'),
  ('d4100000-0000-0000-0000-000000000105', 'd1000000-0000-0000-0000-000000000010', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"community"}'::jsonb, timestamptz '2026-07-16 20:04:00+00'),
  ('d4100000-0000-0000-0000-000000000106', 'd1000000-0000-0000-0000-000000000001', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"private"}'::jsonb, timestamptz '2026-05-09 09:00:00+00'),
  ('d4100000-0000-0000-0000-000000000107', 'd1000000-0000-0000-0000-000000000002', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"community"}'::jsonb, timestamptz '2026-05-09 09:01:00+00'),
  ('d4100000-0000-0000-0000-000000000108', 'd1000000-0000-0000-0000-000000000001', 'marked_going', 'd4000000-0000-0000-0000-000000000003', '{"audience":"private"}'::jsonb, timestamptz '2026-07-16 20:05:00+00'),
  ('d4100000-0000-0000-0000-000000000109', 'd1000000-0000-0000-0000-000000000017', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"friends"}'::jsonb, timestamptz '2026-07-16 20:10:00+00'),
  ('d4100000-0000-0000-0000-000000000110', 'd1000000-0000-0000-0000-000000000018', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"community"}'::jsonb, timestamptz '2026-07-16 20:11:00+00'),
  ('d4100000-0000-0000-0000-000000000111', 'd1000000-0000-0000-0000-000000000019', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"friends"}'::jsonb, timestamptz '2026-07-16 20:12:00+00'),
  ('d4100000-0000-0000-0000-000000000112', 'd1000000-0000-0000-0000-000000000020', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"community"}'::jsonb, timestamptz '2026-07-16 20:13:00+00'),
  ('d4100000-0000-0000-0000-000000000113', 'd1000000-0000-0000-0000-000000000021', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"friends"}'::jsonb, timestamptz '2026-07-16 20:14:00+00'),
  ('d4100000-0000-0000-0000-000000000114', 'd1000000-0000-0000-0000-000000000022', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"community"}'::jsonb, timestamptz '2026-07-16 20:15:00+00'),
  ('d4100000-0000-0000-0000-000000000115', 'd1000000-0000-0000-0000-000000000023', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"friends"}'::jsonb, timestamptz '2026-07-16 20:16:00+00'),
  ('d4100000-0000-0000-0000-000000000116', 'd1000000-0000-0000-0000-000000000024', 'marked_going', 'd4000000-0000-0000-0000-000000000001', '{"audience":"community"}'::jsonb, timestamptz '2026-07-16 20:17:00+00'),
  ('d4100000-0000-0000-0000-000000000117', 'd1000000-0000-0000-0000-000000000017', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"friends"}'::jsonb, timestamptz '2026-05-09 09:10:00+00'),
  ('d4100000-0000-0000-0000-000000000118', 'd1000000-0000-0000-0000-000000000018', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"community"}'::jsonb, timestamptz '2026-05-09 09:11:00+00'),
  ('d4100000-0000-0000-0000-000000000119', 'd1000000-0000-0000-0000-000000000019', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"friends"}'::jsonb, timestamptz '2026-05-09 09:12:00+00'),
  ('d4100000-0000-0000-0000-000000000120', 'd1000000-0000-0000-0000-000000000020', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"community"}'::jsonb, timestamptz '2026-05-09 09:13:00+00'),
  ('d4100000-0000-0000-0000-000000000121', 'd1000000-0000-0000-0000-000000000021', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"friends"}'::jsonb, timestamptz '2026-05-09 09:14:00+00'),
  ('d4100000-0000-0000-0000-000000000122', 'd1000000-0000-0000-0000-000000000022', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"community"}'::jsonb, timestamptz '2026-05-09 09:15:00+00'),
  ('d4100000-0000-0000-0000-000000000123', 'd1000000-0000-0000-0000-000000000023', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"friends"}'::jsonb, timestamptz '2026-05-09 09:16:00+00'),
  ('d4100000-0000-0000-0000-000000000124', 'd1000000-0000-0000-0000-000000000024', 'marked_went', 'd4000000-0000-0000-0000-000000000002', '{"audience":"community"}'::jsonb, timestamptz '2026-05-09 09:17:00+00');

-- The eight varied upcoming-event activities are inserted by
-- scripts/seed-local-post-media.sh after its production-path photo uploads.
-- Creating them last keeps the first Local feed screen visually representative
-- without mutating immutable activity rows or hiding the packed past concert.

-- Social journeys include a normal invitation, an invitation that grants
-- access to an unlisted event, and a mixed-audience event conversation.
-- Notification rows contain identifiers only, never comment bodies.
insert into public.catalog_event_invitations (
  id, event_id, sender_id, recipient_id, status, created_at, updated_at
)
values
  ('d4200000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000006', 'pending', timestamptz '2026-07-15 20:10:00+00', timestamptz '2026-07-15 20:10:00+00'),
  ('d4200000-0000-0000-0000-000000000002', 'd4000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000005', 'pending', timestamptz '2026-07-15 20:11:00+00', timestamptz '2026-07-15 20:11:00+00');

insert into public.event_comments (
  id, event_id, author_id, parent_comment_id, body, audience, created_at, updated_at
)
values
  ('d4300000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', null, 'Counting down to this one.', 'friends', timestamptz '2026-07-15 20:12:00+00', timestamptz '2026-07-15 20:12:00+00'),
  ('d4300000-0000-0000-0000-000000000002', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', null, 'Hoping for the tour opener.', 'community', timestamptz '2026-07-15 20:13:00+00', timestamptz '2026-07-15 20:13:00+00'),
  ('d4300000-0000-0000-0000-000000000003', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000004', 'd4300000-0000-0000-0000-000000000001', 'Same. I hope they play it early.', 'friends', timestamptz '2026-07-15 20:14:00+00', timestamptz '2026-07-15 20:14:00+00'),
  ('d4300000-0000-0000-0000-000000000004', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000017', null, 'Who wants to meet by the north entrance?', 'friends', timestamptz '2026-07-15 20:15:00+00', timestamptz '2026-07-15 20:15:00+00'),
  ('d4300000-0000-0000-0000-000000000005', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000018', null, 'The opener is incredible live.', 'community', timestamptz '2026-07-15 20:16:00+00', timestamptz '2026-07-15 20:16:00+00'),
  ('d4300000-0000-0000-0000-000000000006', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000019', null, 'Manifesting a surprise song in the encore.', 'friends', timestamptz '2026-07-15 20:17:00+00', timestamptz '2026-07-15 20:17:00+00'),
  ('d4300000-0000-0000-0000-000000000007', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000020', null, 'Taking the early train if anyone wants to join.', 'community', timestamptz '2026-07-15 20:18:00+00', timestamptz '2026-07-15 20:18:00+00'),
  ('d4300000-0000-0000-0000-000000000008', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000021', null, 'This will be my first time at the Fillmore.', 'friends', timestamptz '2026-07-15 20:19:00+00', timestamptz '2026-07-15 20:19:00+00'),
  ('d4300000-0000-0000-0000-000000000009', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000022', null, 'Do we think doors are actually at seven?', 'community', timestamptz '2026-07-15 20:20:00+00', timestamptz '2026-07-15 20:20:00+00'),
  ('d4300000-0000-0000-0000-000000000010', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000023', null, 'Already building the pre-show playlist.', 'friends', timestamptz '2026-07-15 20:21:00+00', timestamptz '2026-07-15 20:21:00+00'),
  ('d4300000-0000-0000-0000-000000000011', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000024', 'd4300000-0000-0000-0000-000000000004', 'Yes, let us make a group chat for the meetup.', 'friends', timestamptz '2026-07-15 20:22:00+00', timestamptz '2026-07-15 20:22:00+00'),
  ('d4300000-0000-0000-0000-000000000012', 'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000017', 'd4300000-0000-0000-0000-000000000007', 'I am in for the early train.', 'friends', timestamptz '2026-07-15 20:23:00+00', timestamptz '2026-07-15 20:23:00+00');

insert into public.social_activity_events (
  id, actor_id, action, event_id, subject_id, metadata, occurred_at
)
values
  ('d4100000-0000-0000-0000-000000000201', 'd1000000-0000-0000-0000-000000000001', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000001', '{}'::jsonb, timestamptz '2026-07-15 20:12:00+00'),
  ('d4100000-0000-0000-0000-000000000202', 'd1000000-0000-0000-0000-000000000002', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000002', '{}'::jsonb, timestamptz '2026-07-15 20:13:00+00'),
  ('d4100000-0000-0000-0000-000000000203', 'd1000000-0000-0000-0000-000000000004', 'event_comment_replied', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000003', '{}'::jsonb, timestamptz '2026-07-15 20:14:00+00'),
  ('d4100000-0000-0000-0000-000000000204', 'd1000000-0000-0000-0000-000000000017', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000004', '{}'::jsonb, timestamptz '2026-07-15 20:15:00+00'),
  ('d4100000-0000-0000-0000-000000000205', 'd1000000-0000-0000-0000-000000000018', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000005', '{}'::jsonb, timestamptz '2026-07-15 20:16:00+00'),
  ('d4100000-0000-0000-0000-000000000206', 'd1000000-0000-0000-0000-000000000019', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000006', '{}'::jsonb, timestamptz '2026-07-15 20:17:00+00'),
  ('d4100000-0000-0000-0000-000000000207', 'd1000000-0000-0000-0000-000000000020', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000007', '{}'::jsonb, timestamptz '2026-07-15 20:18:00+00'),
  ('d4100000-0000-0000-0000-000000000208', 'd1000000-0000-0000-0000-000000000021', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000008', '{}'::jsonb, timestamptz '2026-07-15 20:19:00+00'),
  ('d4100000-0000-0000-0000-000000000209', 'd1000000-0000-0000-0000-000000000022', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000009', '{}'::jsonb, timestamptz '2026-07-15 20:20:00+00'),
  ('d4100000-0000-0000-0000-000000000210', 'd1000000-0000-0000-0000-000000000023', 'event_commented', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000010', '{}'::jsonb, timestamptz '2026-07-15 20:21:00+00'),
  ('d4100000-0000-0000-0000-000000000211', 'd1000000-0000-0000-0000-000000000024', 'event_comment_replied', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000011', '{}'::jsonb, timestamptz '2026-07-15 20:22:00+00'),
  ('d4100000-0000-0000-0000-000000000212', 'd1000000-0000-0000-0000-000000000017', 'event_comment_replied', 'd4000000-0000-0000-0000-000000000001', 'd4300000-0000-0000-0000-000000000012', '{}'::jsonb, timestamptz '2026-07-15 20:23:00+00');

insert into private.catalog_event_notification_outbox (
  id, recipient_id, actor_id, event_id, action, subject_id, created_at
)
values
  ('d4400000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'event_invited', 'd4200000-0000-0000-0000-000000000001', timestamptz '2026-07-15 20:10:00+00'),
  ('d4400000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000003', 'event_invited', 'd4200000-0000-0000-0000-000000000002', timestamptz '2026-07-15 20:11:00+00'),
  ('d4400000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000004', 'd4000000-0000-0000-0000-000000000001', 'event_comment_replied', 'd4300000-0000-0000-0000-000000000003', timestamptz '2026-07-15 20:14:00+00');

-- Ten independent Posts on the same shared past event make the event's post
-- grid deliberately dense. Went visibility remains separate from Post sharing.
insert into public.event_posts (
  id, event_id, author_id, attendance_id, event_snapshot, audience,
  overall_score_points, performance_score_points, note,
  published_at, created_at, updated_at
)
values
  ('d4500000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'd4050000-0000-0000-0000-000000000006', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'friends', 95, 90, 'The room felt tiny during the encore. I want to remember that last chorus.', timestamptz '2026-05-09 10:00:00+00', timestamptz '2026-05-09 10:00:00+00', timestamptz '2026-05-09 10:00:00+00'),
  ('d4500000-0000-0000-0000-000000000002', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', 'd4050000-0000-0000-0000-000000000007', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'community', 90, 95, 'The final run of songs made the whole night click.', timestamptz '2026-05-09 10:05:00+00', timestamptz '2026-05-09 10:05:00+00', timestamptz '2026-05-09 10:05:00+00'),
  ('d4500000-0000-0000-0000-000000000003', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000017', 'd4050000-0000-0000-0000-000000000018', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'friends', 80, 85, 'The crowd knew every word before the first chorus landed.', timestamptz '2026-05-09 10:10:00+00', timestamptz '2026-05-09 10:10:00+00', timestamptz '2026-05-09 10:10:00+00'),
  ('d4500000-0000-0000-0000-000000000004', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000018', 'd4050000-0000-0000-0000-000000000019', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'community', 85, 90, 'I keep replaying the lights during the final song.', timestamptz '2026-05-09 10:11:00+00', timestamptz '2026-05-09 10:11:00+00', timestamptz '2026-05-09 10:11:00+00'),
  ('d4500000-0000-0000-0000-000000000005', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000019', 'd4050000-0000-0000-0000-000000000020', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'friends', 90, 95, 'The set started quietly and just kept getting bigger.', timestamptz '2026-05-09 10:12:00+00', timestamptz '2026-05-09 10:12:00+00', timestamptz '2026-05-09 10:12:00+00'),
  ('d4500000-0000-0000-0000-000000000006', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000020', 'd4050000-0000-0000-0000-000000000021', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'community', 95, 100, 'Best sound I have heard in this room all year.', timestamptz '2026-05-09 10:13:00+00', timestamptz '2026-05-09 10:13:00+00', timestamptz '2026-05-09 10:13:00+00'),
  ('d4500000-0000-0000-0000-000000000007', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000021', 'd4050000-0000-0000-0000-000000000022', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'friends', 100, 95, 'The surprise song completely changed the energy.', timestamptz '2026-05-09 10:14:00+00', timestamptz '2026-05-09 10:14:00+00', timestamptz '2026-05-09 10:14:00+00'),
  ('d4500000-0000-0000-0000-000000000008', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000022', 'd4050000-0000-0000-0000-000000000023', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'community', 85, 90, 'A loud, warm, wonderfully messy night.', timestamptz '2026-05-09 10:15:00+00', timestamptz '2026-05-09 10:15:00+00', timestamptz '2026-05-09 10:15:00+00'),
  ('d4500000-0000-0000-0000-000000000009', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000023', 'd4050000-0000-0000-0000-000000000024', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'friends', 90, 85, 'The encore was worth losing my voice for.', timestamptz '2026-05-09 10:16:00+00', timestamptz '2026-05-09 10:16:00+00', timestamptz '2026-05-09 10:16:00+00'),
  ('d4500000-0000-0000-0000-000000000010', 'd4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000024', 'd4050000-0000-0000-0000-000000000025', private.catalog_event_history_projection_json('d4000000-0000-0000-0000-000000000002'), 'community', 95, 100, 'Still thinking about that transition into the closer.', timestamptz '2026-05-09 10:17:00+00', timestamptz '2026-05-09 10:17:00+00', timestamptz '2026-05-09 10:17:00+00');

insert into public.post_comments (
  id, post_id, author_id, body, created_at, updated_at
)
values
  (
    'd4510000-0000-0000-0000-000000000001',
    'd4500000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000002',
    'That encore is exactly what I keep thinking about too.',
    timestamptz '2026-05-09 10:10:00+00',
    timestamptz '2026-05-09 10:10:00+00'
  ),
  (
    'd4510000-0000-0000-0000-000000000002',
    'd4500000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000001',
    'Same—the transition into the closer was perfect.',
    timestamptz '2026-05-09 10:11:00+00',
    timestamptz '2026-05-09 10:11:00+00'
  );

-- The Local journey includes one provider-owned concert so source labeling,
-- attendance, and detail behavior remain testable without a live provider key.
select public.upsert_ticketmaster_catalog_event(
  '{
    "event_id":"local-ticketmaster-fixture",
    "title":"Local Ticketmaster Fixture",
    "event_date":"2026-08-30",
    "local_start_time":"20:00:00",
    "starts_at":"2026-08-31T03:00:00Z",
    "time_zone":"America/Los_Angeles",
    "status":"active",
    "source_url":"https://www.ticketmaster.com/event/local-ticketmaster-fixture",
    "image_url":null,
    "source_updated_at":null,
    "venue":{
      "id":"local-ticketmaster-venue",
      "name":"Local Provider Hall",
      "url":"https://www.ticketmaster.com/venue/local-ticketmaster-venue",
      "address":"1 Fixture Way",
      "latitude":"37.7841",
      "longitude":"-122.4330",
      "area":{"city":"San Francisco","state_code":"CA","country_code":"US"}
    },
    "artists":[
      {
        "id":"local-ticketmaster-artist",
        "name":"Local Provider Artist",
        "url":"https://www.ticketmaster.com/artist/local-ticketmaster-artist",
        "is_headliner":true
      }
    ]
  }'::jsonb
);

insert into public.post_comments (
  id, post_id, author_id, body, created_at, updated_at
)
values
  ('d4510000-0000-0000-0000-000000000003', 'd4500000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'That first chorus was unreal.', timestamptz '2026-05-09 10:20:00+00', timestamptz '2026-05-09 10:20:00+00'),
  ('d4510000-0000-0000-0000-000000000004', 'd4500000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000002', 'The lighting was perfect from the balcony.', timestamptz '2026-05-09 10:21:00+00', timestamptz '2026-05-09 10:21:00+00'),
  ('d4510000-0000-0000-0000-000000000005', 'd4500000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000001', 'Exactly how the set felt to me too.', timestamptz '2026-05-09 10:22:00+00', timestamptz '2026-05-09 10:22:00+00'),
  ('d4510000-0000-0000-0000-000000000006', 'd4500000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000002', 'The sound at the back was somehow just as good.', timestamptz '2026-05-09 10:23:00+00', timestamptz '2026-05-09 10:23:00+00'),
  ('d4510000-0000-0000-0000-000000000007', 'd4500000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000001', 'I did not expect that song at all.', timestamptz '2026-05-09 10:24:00+00', timestamptz '2026-05-09 10:24:00+00'),
  ('d4510000-0000-0000-0000-000000000008', 'd4500000-0000-0000-0000-000000000008', 'd1000000-0000-0000-0000-000000000002', 'Messy in the best possible way.', timestamptz '2026-05-09 10:25:00+00', timestamptz '2026-05-09 10:25:00+00'),
  ('d4510000-0000-0000-0000-000000000009', 'd4500000-0000-0000-0000-000000000009', 'd1000000-0000-0000-0000-000000000001', 'My voice was gone the next morning too.', timestamptz '2026-05-09 10:26:00+00', timestamptz '2026-05-09 10:26:00+00'),
  ('d4510000-0000-0000-0000-000000000010', 'd4500000-0000-0000-0000-000000000010', 'd1000000-0000-0000-0000-000000000002', 'That transition is still stuck in my head.', timestamptz '2026-05-09 10:27:00+00', timestamptz '2026-05-09 10:27:00+00');

insert into public.social_activity_events (
  id, actor_id, action, event_id, subject_id, metadata, occurred_at
)
values
  (
    'd4100000-0000-0000-0000-000000000301',
    'd1000000-0000-0000-0000-000000000001',
    'post_published',
    'd4000000-0000-0000-0000-000000000002',
    'd4500000-0000-0000-0000-000000000001',
    '{}'::jsonb,
    timestamptz '2026-05-09 10:00:00+00'
  ),
  (
    'd4100000-0000-0000-0000-000000000302',
    'd1000000-0000-0000-0000-000000000002',
    'post_published',
    'd4000000-0000-0000-0000-000000000002',
    'd4500000-0000-0000-0000-000000000002',
    '{}'::jsonb,
    timestamptz '2026-05-09 10:05:00+00'
  ),
  ('d4100000-0000-0000-0000-000000000303', 'd1000000-0000-0000-0000-000000000017', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000003', '{}'::jsonb, timestamptz '2026-05-09 10:10:00+00'),
  ('d4100000-0000-0000-0000-000000000304', 'd1000000-0000-0000-0000-000000000018', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000004', '{}'::jsonb, timestamptz '2026-05-09 10:11:00+00'),
  ('d4100000-0000-0000-0000-000000000305', 'd1000000-0000-0000-0000-000000000019', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000005', '{}'::jsonb, timestamptz '2026-05-09 10:12:00+00'),
  ('d4100000-0000-0000-0000-000000000306', 'd1000000-0000-0000-0000-000000000020', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000006', '{}'::jsonb, timestamptz '2026-05-09 10:13:00+00'),
  ('d4100000-0000-0000-0000-000000000307', 'd1000000-0000-0000-0000-000000000021', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000007', '{}'::jsonb, timestamptz '2026-05-09 10:14:00+00'),
  ('d4100000-0000-0000-0000-000000000308', 'd1000000-0000-0000-0000-000000000022', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000008', '{}'::jsonb, timestamptz '2026-05-09 10:15:00+00'),
  ('d4100000-0000-0000-0000-000000000309', 'd1000000-0000-0000-0000-000000000023', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000009', '{}'::jsonb, timestamptz '2026-05-09 10:16:00+00'),
  ('d4100000-0000-0000-0000-000000000310', 'd1000000-0000-0000-0000-000000000024', 'post_published', 'd4000000-0000-0000-0000-000000000002', 'd4500000-0000-0000-0000-000000000010', '{}'::jsonb, timestamptz '2026-05-09 10:17:00+00');

insert into private.catalog_event_notification_outbox (
  id, recipient_id, actor_id, event_id, action, subject_id, created_at
)
values
  (
    'd4400000-0000-0000-0000-000000000101',
    'd1000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000002',
    'post_published',
    'd4500000-0000-0000-0000-000000000001',
    timestamptz '2026-05-09 10:00:00+00'
  ),
  (
    'd4400000-0000-0000-0000-000000000102',
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000002',
    'd4000000-0000-0000-0000-000000000002',
    'post_published',
    'd4500000-0000-0000-0000-000000000002',
    timestamptz '2026-05-09 10:05:00+00'
  );
