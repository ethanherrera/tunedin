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
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'concert-owner@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'concert-outsider@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'incomplete-owner@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

update public.profiles
set
  username = 'concert_owner',
  display_name = 'Concert Owner',
  onboarding_completed_at = now()
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
set local role authenticated;

select set_config(
  'test.private_concert_id',
  (
    select (public.create_private_concert(
      '[
        {"name":"  The   National  ","is_primary":true},
        {"name":"Future Islands","is_primary":false}
      ]'::jsonb,
      '  The   Fillmore  ',
      date '2026-04-03',
      '  San   Francisco ',
      '  Rome   (Deluxe) ',
      '2026-04-04 03:30:00+00'::timestamptz,
      'America/Los_Angeles',
      '["  Don\u0027t Swallow the Cap  ","Bloodbuzz Ohio"]'::jsonb
    )).id::text
  ),
  true
);

select is(
  (select visibility::text from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  'private',
  'new concerts default to Private'
);
select is(
  (select owner_id from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
  'the caller owns the concert'
);
select is(
  (select venue_name from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  'The Fillmore',
  'venue text is normalized'
);
select is(
  (select city from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  'San Francisco',
  'city text is normalized'
);
select is(
  (select tour from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  'Rome (Deluxe)',
  'tour text is normalized'
);
select is(
  (select venue_time_zone from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  'America/Los_Angeles',
  'the IANA venue time zone is stored'
);
select is(
  (select count(*) from public.concert_artists where concert_id = current_setting('test.private_concert_id')::uuid),
  2::bigint,
  'the ordered artist lineup is created transactionally'
);
select is(
  (select artist_name from public.concert_artists where concert_id = current_setting('test.private_concert_id')::uuid and lineup_position = 1),
  'The National',
  'artist text is normalized'
);
select is(
  (select count(*) from public.concert_artists where concert_id = current_setting('test.private_concert_id')::uuid and is_primary),
  1::bigint,
  'exactly one artist is primary'
);
select is(
  (select count(*) from public.setlist_items where concert_id = current_setting('test.private_concert_id')::uuid),
  2::bigint,
  'the ordered setlist is created transactionally'
);
select is(
  (select song_title from public.setlist_items where concert_id = current_setting('test.private_concert_id')::uuid and set_position = 1),
  'Don''t Swallow the Cap',
  'setlist text is normalized'
);
select is(
  (select count(*) from public.concert_events where concert_id = current_setting('test.private_concert_id')::uuid),
  1::bigint,
  'creation writes one event'
);
select is(
  (select event_type::text from public.concert_events where concert_id = current_setting('test.private_concert_id')::uuid),
  'concert_created',
  'the initial event has a safe fixed type'
);
select is(
  (select actor_id from public.concert_events where concert_id = current_setting('test.private_concert_id')::uuid),
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
  'the event actor is the owner'
);
select is(
  (select count(*) from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  1::bigint,
  'the owner can read their own private concert'
);

select throws_ok(
  $$
    select public.create_private_concert(
      '[]'::jsonb,
      'No Artists Hall',
      date '2026-04-03'
    )
  $$,
  '22023',
  'Concerts require between 1 and 10 artists',
  'an empty lineup is rejected'
);
select is(
  (select count(*) from public.concerts where venue_name = 'No Artists Hall'),
  0::bigint,
  'a rejected empty-lineup RPC leaves no concert behind'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[
        {"name":"Artist One","is_primary":true},
        {"name":"Artist Two","is_primary":true}
      ]'::jsonb,
      'Two Primaries Hall',
      date '2026-04-03'
    )
  $$,
  '22023',
  'Concerts require exactly one primary artist',
  'two primary artists are rejected'
);
select throws_ok(
  $$
    select public.create_private_concert(
      (
        select jsonb_agg(
          jsonb_build_object('name', 'Artist ' || value, 'is_primary', value = 1)
        )
        from generate_series(1, 11) as value
      ),
      'Too Many Artists Hall',
      date '2026-04-03'
    )
  $$,
  '22023',
  'Concerts require between 1 and 10 artists',
  'an 11-artist lineup is rejected'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      null::text,
      date '2026-04-03'
    )
  $$,
  '22023',
  'Venue name is required',
  'a venue is required'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      'No Date Hall',
      null::date
    )
  $$,
  '22023',
  'Concert date is required',
  'a venue-local date is required'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      'Missing Zone Hall',
      date '2026-04-03',
      p_starts_at => '2026-04-04 03:30:00+00'::timestamptz
    )
  $$,
  '22023',
  'Start time and venue time zone must be provided together',
  'a start time requires an IANA time zone'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      'Invalid Zone Hall',
      date '2026-04-03',
      p_starts_at => '2026-04-04 03:30:00+00'::timestamptz,
      p_venue_time_zone => 'PST'
    )
  $$,
  '22023',
  'Venue time zone must be a valid IANA time-zone identifier',
  'time-zone abbreviations are rejected'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      E'Bad\tVenue',
      date '2026-04-03'
    )
  $$,
  '22023',
  'Venue name cannot contain control characters',
  'control characters are rejected before normalization'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      'Invalid Setlist Hall',
      date '2026-04-03',
      p_setlist => '[1]'::jsonb
    )
  $$,
  '22023',
  'Every setlist entry must be a string',
  'non-string setlist entries are rejected'
);
select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      'Too Many Songs Hall',
      date '2026-04-03',
      p_setlist => (
        select jsonb_agg('Song ' || value)
        from generate_series(1, 51) as value
      )
    )
  $$,
  '22023',
  'Concerts may have no more than 50 setlist entries',
  'a 51-song setlist is rejected'
);
select is(
  (select count(*) from public.concerts where venue_name = 'Too Many Songs Hall'),
  0::bigint,
  'a rejected setlist RPC leaves no concert behind'
);

reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);
set local role authenticated;

select throws_ok(
  $$
    select public.create_private_concert(
      '[{"name":"Artist","is_primary":true}]'::jsonb,
      'Incomplete Owner Hall',
      date '2026-04-03'
    )
  $$,
  '42501',
  'Complete onboarding before creating a concert',
  'onboarding is required before concert creation'
);

reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);
set local role authenticated;

select is(
  (select count(*) from public.concerts where id = current_setting('test.private_concert_id')::uuid),
  0::bigint,
  'a non-owner cannot read the private concert'
);
select is(
  (select count(*) from public.concert_artists where concert_id = current_setting('test.private_concert_id')::uuid),
  0::bigint,
  'a non-owner cannot read the artist lineup'
);
select is(
  (select count(*) from public.setlist_items where concert_id = current_setting('test.private_concert_id')::uuid),
  0::bigint,
  'a non-owner cannot read the setlist'
);
select is(
  (select count(*) from public.concert_events where concert_id = current_setting('test.private_concert_id')::uuid),
  0::bigint,
  'a non-owner cannot read event history'
);
select throws_ok(
  $$
    insert into public.concerts (owner_id, venue_name, concert_date)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bypass Hall', date '2026-04-03')
  $$,
  '42501',
  null,
  'authenticated users cannot insert concerts directly'
);
select throws_ok(
  $$
    update public.concerts
    set venue_name = 'Changed Hall'
    where id = current_setting('test.private_concert_id')::uuid
  $$,
  '42501',
  null,
  'authenticated users cannot update concerts directly'
);
select throws_ok(
  $$
    delete from public.concert_events
    where concert_id = current_setting('test.private_concert_id')::uuid
  $$,
  '42501',
  null,
  'authenticated users cannot delete events directly'
);

reset role;
select throws_ok(
  $$
    update public.concert_events
    set occurred_at = now()
    where concert_id = current_setting('test.private_concert_id')::uuid
  $$,
  '55000',
  'Concert events are immutable',
  'event immutability also protects privileged mistakes'
);

create function public.test_concert_without_artists()
returns void
language plpgsql
as $$
declare
  v_concert_id uuid;
begin
  insert into public.concerts (owner_id, venue_name, concert_date)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Constraint Hall', date '2026-04-03')
  returning id into v_concert_id;

  set constraints concerts_require_valid_lineup immediate;
end;
$$;

create function public.test_concert_without_primary_artist()
returns void
language plpgsql
as $$
declare
  v_concert_id uuid;
begin
  insert into public.concerts (owner_id, venue_name, concert_date)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Constraint Hall', date '2026-04-03')
  returning id into v_concert_id;

  insert into public.concert_artists (concert_id, lineup_position, artist_name, is_primary)
  values (v_concert_id, 1, 'Support Artist', false);

  set constraints concerts_require_valid_lineup immediate;
end;
$$;

select throws_ok(
  'select public.test_concert_without_artists()',
  '23514',
  'Concerts must have at least one artist',
  'the deferred database constraint rejects a concert without artists'
);
select throws_ok(
  'select public.test_concert_without_primary_artist()',
  '23514',
  'Concerts must have exactly one primary artist',
  'the deferred database constraint rejects a concert without a primary artist'
);

with inserted_concert as (
  insert into public.concerts (owner_id, venue_name, concert_date)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Maximum Artists Hall', date '2026-04-03')
  returning id
)
select set_config('test.maximum_artists_concert_id', id::text, true)
from inserted_concert;

insert into public.concert_artists (concert_id, lineup_position, artist_name, is_primary)
values (current_setting('test.maximum_artists_concert_id')::uuid, 1, 'Primary Artist', true);

select throws_ok(
  $$
    insert into public.concert_artists (concert_id, lineup_position, artist_name, is_primary)
    values (
      current_setting('test.maximum_artists_concert_id')::uuid,
      11,
      'Eleventh Artist',
      false
    )
  $$,
  '23514',
  'new row for relation "concert_artists" violates check constraint "concert_artists_position_range_check"',
  'artist positions enforce the maximum lineup size'
);
select throws_ok(
  $$
    insert into public.concerts (owner_id, venue_name, concert_date, starts_at, venue_time_zone)
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'Time Zone Constraint Hall',
      date '2026-04-03',
      now(),
      'PST'
    )
  $$,
  '23514',
  'new row for relation "concerts" violates check constraint "concerts_time_zone_pair_check"',
  'the database rejects a non-IANA time zone'
);

select * from finish();

rollback;
