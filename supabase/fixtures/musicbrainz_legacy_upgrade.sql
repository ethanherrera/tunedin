-- Disposable pre-catalog rows for the MusicBrainz upgrade-path regression.
-- This lives outside tests/ so Supabase does not discover it as pgTAP.
-- This fixture is loaded only after resetting Local through 20260712231500.

begin;

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
values (
  '00000000-0000-0000-0000-000000000000',
  'e1000000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'legacy-upgrade@tunedin.local',
  extensions.crypt(
    'tunedIn-local-legacy-upgrade',
    '$2a$10$N9qo8uLOickgx2ZMRZoMye'
  ),
  timestamptz '2026-01-01 12:00:00+00',
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
  timestamptz '2026-01-01 12:00:00+00',
  timestamptz '2026-01-01 12:00:00+00',
  false,
  false
);

update public.profiles
set
  username = 'legacy_upgrade',
  display_name = 'Legacy Upgrade',
  onboarding_completed_at = timestamptz '2026-01-01 12:00:00+00'
where id = 'e1000000-0000-0000-0000-000000000001';

insert into public.concerts (
  id,
  owner_id,
  venue_name,
  city,
  concert_date,
  tour,
  visibility
)
values
  (
    'e2000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000001',
    'Legacy Upgrade Hall',
    'San Francisco',
    date '2026-01-10',
    'Legacy Upgrade Tour',
    'private'
  ),
  (
    'e2000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000001',
    'Legacy Upgrade Hall',
    'San Francisco',
    date '2026-02-10',
    'Legacy Upgrade Tour',
    'private'
  );

insert into public.concert_artists (
  id,
  concert_id,
  lineup_position,
  artist_name,
  is_primary
)
values
  (
    'e2100000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001',
    1,
    'Legacy Upgrade Artist',
    true
  ),
  (
    'e2100000-0000-0000-0000-000000000002',
    'e2000000-0000-0000-0000-000000000002',
    1,
    'Legacy Upgrade Artist',
    true
  );

insert into public.setlist_items (
  id,
  concert_id,
  set_position,
  song_title
)
values
  (
    'e2200000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001',
    1,
    'Legacy Upgrade Song'
  ),
  (
    'e2200000-0000-0000-0000-000000000002',
    'e2000000-0000-0000-0000-000000000002',
    1,
    'Legacy Upgrade Song'
  );

set constraints all immediate;

commit;
