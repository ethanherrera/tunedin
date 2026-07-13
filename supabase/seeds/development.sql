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
    ('d1000000-0000-0000-0000-000000000016'::uuid, 'newcomer@tunedin.local')
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
    ('d1000000-0000-0000-0000-000000000016'::uuid, 'newcomer@tunedin.local')
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
    ('d1000000-0000-0000-0000-000000000015'::uuid, 'parker_june', 'Parker June')
) as account(id, username, display_name)
where profile.id = account.id
;

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

with fixture (
  id,
  owner_id,
  artist_name,
  venue_name,
  city,
  concert_date,
  visibility,
  tour,
  created_at,
  setlist
) as (
  values
    ('d2000000-0000-0000-0000-000000000001'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'Mitski', 'The Greek Theatre', 'Berkeley', date '2025-09-18', 'private'::public.concert_visibility, 'The Land Is Inhospitable Tour', timestamptz '2025-09-19 02:00:00+00', array['First Love / Late Spring', 'My Love Mine All Mine', 'I Bet on Losing Dogs']::text[]),
    ('d2000000-0000-0000-0000-000000000002'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'Bon Iver', 'The Masonic', 'San Francisco', date '2025-05-29', 'private'::public.concert_visibility, 'SABLE, fABLE', timestamptz '2025-05-30 03:00:00+00', array['S P E Y S I D E', 'Everything Is Peaceful Love']::text[]),
    ('d2000000-0000-0000-0000-000000000003'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'LCD Soundsystem', 'Bill Graham Civic Auditorium', 'San Francisco', date '2026-02-14', 'friends'::public.concert_visibility, 'Winter Residency', timestamptz '2026-02-15 04:00:00+00', array['Dance Yrself Clean', 'All My Friends', 'New York, I Love You but You Are Bringing Me Down']::text[]),
    ('d2000000-0000-0000-0000-000000000004'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'The National', 'Fox Theater', 'Oakland', date '2026-03-06', 'collaborators'::public.concert_visibility, 'Rome Tour', timestamptz '2026-03-07 04:00:00+00', array['Bloodbuzz Ohio', 'Fake Empire', 'Terrible Love']::text[]),
    ('d2000000-0000-0000-0000-000000000005'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'Caroline Polachek', 'The Warfield', 'San Francisco', date '2026-04-11', 'friends'::public.concert_visibility, 'Desire Tour', timestamptz '2026-04-12 04:00:00+00', array['Welcome To My Island', 'Bunny Is a Rider', 'So Hot You Are Hurting My Feelings']::text[]),
    ('d2000000-0000-0000-0000-000000000006'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'Waxahatchee', 'The Fillmore', 'San Francisco', date '2026-05-08', 'friends'::public.concert_visibility, 'Tigers Blood Tour', timestamptz '2026-05-09 04:00:00+00', array['Right Back to It', 'Crowbar', 'Fire']::text[]),
    ('d2000000-0000-0000-0000-000000000007'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'Japanese Breakfast', 'The Fillmore', 'San Francisco', date '2025-10-04', 'friends'::public.concert_visibility, 'Melancholy Tour', timestamptz '2025-10-05 04:00:00+00', array['Be Sweet', 'Paprika', 'Posing in Bondage']::text[]),
    ('d2000000-0000-0000-0000-000000000008'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'Big Thief', 'Fox Theater', 'Oakland', date '2026-01-12', 'collaborators'::public.concert_visibility, 'Dragon New Warm Mountain Tour', timestamptz '2026-01-13 04:00:00+00', array['Simulation Swarm', 'Vampire Empire', 'Not']::text[]),
    ('d2000000-0000-0000-0000-000000000009'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'Lorde', 'Chase Center', 'San Francisco', date '2026-03-22', 'friends'::public.concert_visibility, 'Ultrasound World Tour', timestamptz '2026-03-23 04:00:00+00', array['Green Light', 'Ribs', 'Supercut']::text[]),
    ('d2000000-0000-0000-0000-000000000010'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'MUNA', 'The Regency Ballroom', 'San Francisco', date '2025-11-19', 'private'::public.concert_visibility, 'Live Again', timestamptz '2025-11-20 04:00:00+00', array['Silk Chiffon', 'Anything But Me']::text[]),
    ('d2000000-0000-0000-0000-000000000011'::uuid, 'd1000000-0000-0000-0000-000000000003'::uuid, 'Turnstile', 'The Warfield', 'San Francisco', date '2026-02-02', 'friends'::public.concert_visibility, 'Never Enough Tour', timestamptz '2026-02-03 04:00:00+00', array['BLACKOUT', 'MYSTERY', 'HOLIDAY']::text[]),
    ('d2000000-0000-0000-0000-000000000012'::uuid, 'd1000000-0000-0000-0000-000000000003'::uuid, 'boygenius', 'Greek Theatre', 'Los Angeles', date '2025-08-15', 'collaborators'::public.concert_visibility, 'The Record Tour', timestamptz '2025-08-16 04:00:00+00', array['Not Strong Enough', 'Satanist', '$20']::text[]),
    ('d2000000-0000-0000-0000-000000000013'::uuid, 'd1000000-0000-0000-0000-000000000003'::uuid, 'St. Vincent', 'The UC Theatre', 'Berkeley', date '2026-04-02', 'friends'::public.concert_visibility, 'All Born Screaming Tour', timestamptz '2026-04-03 04:00:00+00', array['Broken Man', 'Los Ageless', 'Digital Witness']::text[]),
    ('d2000000-0000-0000-0000-000000000014'::uuid, 'd1000000-0000-0000-0000-000000000003'::uuid, 'FKA twigs', 'The Regency Ballroom', 'San Francisco', date '2025-06-10', 'private'::public.concert_visibility, 'EUSEXUA Tour', timestamptz '2025-06-11 04:00:00+00', array['Two Weeks', 'Cellophane']::text[]),
    ('d2000000-0000-0000-0000-000000000015'::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid, 'Charli xcx', 'Chase Center', 'San Francisco', date '2025-09-27', 'friends'::public.concert_visibility, 'BRAT Arena Tour', timestamptz '2025-09-28 04:00:00+00', array['360', 'Von dutch', 'Girl, so confusing']::text[]),
    ('d2000000-0000-0000-0000-000000000016'::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid, 'Khruangbin', 'The Greek Theatre', 'Berkeley', date '2026-05-20', 'friends'::public.concert_visibility, 'A LA SALA Tour', timestamptz '2026-05-21 04:00:00+00', array['Time (You and I)', 'August 10', 'Friday Morning']::text[]),
    ('d2000000-0000-0000-0000-000000000017'::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid, 'Fleet Foxes', 'The Masonic', 'San Francisco', date '2025-07-22', 'collaborators'::public.concert_visibility, 'Shore Tour', timestamptz '2025-07-23 04:00:00+00', array['Can I Believe You', 'Mykonos', 'Blue Ridge Mountains']::text[]),
    ('d2000000-0000-0000-0000-000000000018'::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid, 'Phoebe Bridgers', 'The Greek Theatre', 'Berkeley', date '2025-04-18', 'private'::public.concert_visibility, 'Reunion Tour', timestamptz '2025-04-19 04:00:00+00', array['Kyoto', 'I Know the End']::text[]),
    ('d2000000-0000-0000-0000-000000000019'::uuid, 'd1000000-0000-0000-0000-000000000005'::uuid, 'Kendrick Lamar', 'Oakland Arena', 'Oakland', date '2026-01-30', 'friends'::public.concert_visibility, 'Grand National Tour', timestamptz '2026-01-31 04:00:00+00', array['DNA.', 'N95', 'HUMBLE.']::text[]),
    ('d2000000-0000-0000-0000-000000000020'::uuid, 'd1000000-0000-0000-0000-000000000005'::uuid, 'Sampha', 'Bimbo''s 365 Club', 'San Francisco', date '2025-10-20', 'friends'::public.concert_visibility, 'Lahai Tour', timestamptz '2025-10-21 04:00:00+00', array['Spirit 2.0', 'Only', 'Treasure']::text[]),
    ('d2000000-0000-0000-0000-000000000021'::uuid, 'd1000000-0000-0000-0000-000000000005'::uuid, 'SZA', 'Chase Center', 'San Francisco', date '2026-03-14', 'collaborators'::public.concert_visibility, 'SOS Tour', timestamptz '2026-03-15 04:00:00+00', array['Snooze', 'Kill Bill', 'Good Days']::text[]),
    ('d2000000-0000-0000-0000-000000000022'::uuid, 'd1000000-0000-0000-0000-000000000006'::uuid, 'Radiohead', 'Bill Graham Civic Auditorium', 'San Francisco', date '2025-12-12', 'friends'::public.concert_visibility, 'The Smile Sessions', timestamptz '2025-12-13 04:00:00+00', array['Paranoid Android', 'Weird Fishes/Arpeggi', 'Karma Police']::text[]),
    ('d2000000-0000-0000-0000-000000000023'::uuid, 'd1000000-0000-0000-0000-000000000006'::uuid, 'HAIM', 'The Fillmore', 'San Francisco', date '2026-04-25', 'friends'::public.concert_visibility, 'I quit Tour', timestamptz '2026-04-26 04:00:00+00', array['The Steps', 'The Wire', 'Want You Back']::text[]),
    ('d2000000-0000-0000-0000-000000000024'::uuid, 'd1000000-0000-0000-0000-000000000006'::uuid, 'The xx', 'The Independent', 'San Francisco', date '2025-08-08', 'collaborators'::public.concert_visibility, 'I See You Tour', timestamptz '2025-08-09 04:00:00+00', array['Intro', 'Crystalised', 'On Hold']::text[])
),
inserted_concerts as (
  insert into public.concerts (
    id,
    owner_id,
    venue_name,
    city,
    concert_date,
    tour,
    visibility,
    created_at,
    updated_at,
    last_activity_at,
    version
  )
  select
    id,
    owner_id,
    venue_name,
    city,
    concert_date,
    tour,
    visibility,
    created_at,
    created_at + interval '3 days',
    created_at + interval '3 days',
    3
  from fixture
  returning id
),
inserted_artists as (
  insert into public.concert_artists (
    id,
    concert_id,
    lineup_position,
    artist_name,
    is_primary,
    created_at,
    updated_at
  )
  select
    md5('artist:' || id::text)::uuid,
    id,
    1,
    artist_name,
    true,
    created_at,
    created_at
  from fixture
  returning id
),
inserted_setlist_items as (
  insert into public.setlist_items (
    id,
    concert_id,
    set_position,
    song_title,
    created_at,
    updated_at
  )
  select
    md5('setlist:' || concert.id::text || ':' || song.ordinality::text)::uuid,
    concert.id,
    song.ordinality::smallint,
    song.title,
    concert.created_at,
    concert.created_at
  from fixture as concert
  cross join lateral unnest(concert.setlist) with ordinality as song(title, ordinality)
  returning id
)
select count(*) from inserted_concerts;

insert into public.concert_collaborators (
  concert_id,
  profile_id,
  tagged_by,
  created_at,
  updated_at
)
values
  ('d2000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', timestamptz '2026-03-07 05:00:00+00', timestamptz '2026-03-07 05:00:00+00'),
  ('d2000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', timestamptz '2026-03-07 05:01:00+00', timestamptz '2026-03-07 05:01:00+00'),
  ('d2000000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', timestamptz '2025-10-05 05:00:00+00', timestamptz '2025-10-05 05:00:00+00'),
  ('d2000000-0000-0000-0000-000000000008', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', timestamptz '2026-01-13 05:00:00+00', timestamptz '2026-01-13 05:00:00+00'),
  ('d2000000-0000-0000-0000-000000000012', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000003', timestamptz '2025-08-16 05:00:00+00', timestamptz '2025-08-16 05:00:00+00'),
  ('d2000000-0000-0000-0000-000000000017', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000004', timestamptz '2025-07-23 05:00:00+00', timestamptz '2025-07-23 05:00:00+00'),
  ('d2000000-0000-0000-0000-000000000021', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000005', timestamptz '2026-03-15 05:00:00+00', timestamptz '2026-03-15 05:00:00+00'),
  ('d2000000-0000-0000-0000-000000000024', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000006', timestamptz '2025-08-09 05:00:00+00', timestamptz '2025-08-09 05:00:00+00');

insert into public.comments (id, concert_id, author_id, body, created_at, updated_at)
select
  md5('comment:' || key)::uuid,
  concert_id,
  author_id,
  body,
  created_at,
  created_at
from (
  values
    ('mitski-owner', 'd2000000-0000-0000-0000-000000000001'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'That encore was unreal.', timestamptz '2025-09-19 05:30:00+00'),
    ('lcd-morgan', 'd2000000-0000-0000-0000-000000000003'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'The room lit up for the last song.', timestamptz '2026-02-15 06:00:00+00'),
    ('national-ava', 'd2000000-0000-0000-0000-000000000004'::uuid, 'd1000000-0000-0000-0000-000000000003'::uuid, 'The horns were perfect from the balcony.', timestamptz '2026-03-07 06:30:00+00'),
    ('caroline-jules', 'd2000000-0000-0000-0000-000000000005'::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid, 'Still thinking about the opening run.', timestamptz '2026-04-12 06:00:00+00'),
    ('japanese-listener', 'd2000000-0000-0000-0000-000000000007'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'The set flowed beautifully.', timestamptz '2025-10-05 06:00:00+00'),
    ('big-thief-listener', 'd2000000-0000-0000-0000-000000000008'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'That closer needed a second listen immediately.', timestamptz '2026-01-13 06:00:00+00'),
    ('turnstile-riley', 'd2000000-0000-0000-0000-000000000011'::uuid, 'd1000000-0000-0000-0000-000000000005'::uuid, 'The crowd never stopped moving.', timestamptz '2026-02-03 06:00:00+00'),
    ('boygenius-listener', 'd2000000-0000-0000-0000-000000000012'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'Three voices, one huge room.', timestamptz '2025-08-16 06:00:00+00'),
    ('charli-morgan', 'd2000000-0000-0000-0000-000000000015'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'No notes. Maximum energy.', timestamptz '2025-09-28 06:00:00+00'),
    ('kendrick-listener', 'd2000000-0000-0000-0000-000000000019'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'Every transition landed.', timestamptz '2026-01-31 06:00:00+00'),
    ('radiohead-listener', 'd2000000-0000-0000-0000-000000000022'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'The guitar line is still in my head.', timestamptz '2025-12-13 06:00:00+00'),
    ('haim-listener', 'd2000000-0000-0000-0000-000000000023'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'The whole place sang the bridge.', timestamptz '2026-04-26 06:00:00+00')
) as fixture(key, concert_id, author_id, body, created_at);

insert into public.concert_events (id, concert_id, actor_id, event_type, occurred_at, metadata)
select
  md5('event:created:' || id::text)::uuid,
  id,
  owner_id,
  'concert_created'::public.concert_event_type,
  created_at,
  '{}'::jsonb
from public.concerts
where id between 'd2000000-0000-0000-0000-000000000001'::uuid
  and 'd2000000-0000-0000-0000-000000000024'::uuid
union all
select
  md5('event:updated:' || id::text)::uuid,
  id,
  owner_id,
  'concert_updated'::public.concert_event_type,
  created_at + interval '3 days',
  jsonb_build_object('changed_fields', jsonb_build_array('setlist'))
from public.concerts
where id between 'd2000000-0000-0000-0000-000000000001'::uuid
  and 'd2000000-0000-0000-0000-000000000024'::uuid
union all
select
  md5('event:comment:' || id::text)::uuid,
  concert_id,
  author_id,
  'comment_added'::public.concert_event_type,
  created_at,
  '{}'::jsonb
from public.comments
where id in (
  select md5('comment:' || key)::uuid
  from (
    values
      ('mitski-owner'), ('lcd-morgan'), ('national-ava'), ('caroline-jules'),
      ('japanese-listener'), ('big-thief-listener'), ('turnstile-riley'),
      ('boygenius-listener'), ('charli-morgan'), ('kendrick-listener'),
      ('radiohead-listener'), ('haim-listener')
  ) as seeded_comment(key)
)
union all
select
  md5('event:' || key)::uuid,
  concert_id,
  actor_id,
  event_type,
  occurred_at,
  metadata
from (
  values
    ('tag-national-morgan', 'd2000000-0000-0000-0000-000000000004'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2026-03-07 05:00:00+00', '{}'::jsonb),
    ('tag-national-ava', 'd2000000-0000-0000-0000-000000000004'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2026-03-07 05:01:00+00', '{}'::jsonb),
    ('tag-japanese-listener', 'd2000000-0000-0000-0000-000000000007'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2025-10-05 05:00:00+00', '{}'::jsonb),
    ('tag-big-thief-listener', 'd2000000-0000-0000-0000-000000000008'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2026-01-13 05:00:00+00', '{}'::jsonb),
    ('tag-boygenius-listener', 'd2000000-0000-0000-0000-000000000012'::uuid, 'd1000000-0000-0000-0000-000000000003'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2025-08-16 05:00:00+00', '{}'::jsonb),
    ('tag-fleet-foxes-listener', 'd2000000-0000-0000-0000-000000000017'::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2025-07-23 05:00:00+00', '{}'::jsonb),
    ('tag-sza-listener', 'd2000000-0000-0000-0000-000000000021'::uuid, 'd1000000-0000-0000-0000-000000000005'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2026-03-15 05:00:00+00', '{}'::jsonb),
    ('tag-xx-listener', 'd2000000-0000-0000-0000-000000000024'::uuid, 'd1000000-0000-0000-0000-000000000006'::uuid, 'collaborator_tagged'::public.concert_event_type, timestamptz '2025-08-09 05:00:00+00', '{}'::jsonb),
    ('visibility-lcd', 'd2000000-0000-0000-0000-000000000003'::uuid, 'd1000000-0000-0000-0000-000000000001'::uuid, 'visibility_changed'::public.concert_event_type, timestamptz '2026-02-15 05:00:00+00', jsonb_build_object('changed_fields', jsonb_build_array('visibility'))),
    ('visibility-japanese', 'd2000000-0000-0000-0000-000000000007'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'visibility_changed'::public.concert_event_type, timestamptz '2025-10-05 05:20:00+00', jsonb_build_object('changed_fields', jsonb_build_array('visibility'))),
    ('visibility-turnstile', 'd2000000-0000-0000-0000-000000000011'::uuid, 'd1000000-0000-0000-0000-000000000003'::uuid, 'visibility_changed'::public.concert_event_type, timestamptz '2026-02-03 05:20:00+00', jsonb_build_object('changed_fields', jsonb_build_array('visibility'))),
    ('visibility-charli', 'd2000000-0000-0000-0000-000000000015'::uuid, 'd1000000-0000-0000-0000-000000000004'::uuid, 'visibility_changed'::public.concert_event_type, timestamptz '2025-09-28 05:20:00+00', jsonb_build_object('changed_fields', jsonb_build_array('visibility'))),
    ('visibility-kendrick', 'd2000000-0000-0000-0000-000000000019'::uuid, 'd1000000-0000-0000-0000-000000000005'::uuid, 'visibility_changed'::public.concert_event_type, timestamptz '2026-01-31 05:20:00+00', jsonb_build_object('changed_fields', jsonb_build_array('visibility')))
) as fixture(key, concert_id, actor_id, event_type, occurred_at, metadata);
