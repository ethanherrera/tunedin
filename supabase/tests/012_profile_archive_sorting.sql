begin;

select plan(9);

update public.concerts
set updated_at = timestamptz '2030-01-01 00:00:00+00'
where id = 'd2000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select is(
  (select primary_artist from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_sort => 'newest', p_limit => 1
  )),
  'Waxahatchee',
  'newest sorts by concert date descending'
);

select is(
  (select primary_artist from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_sort => 'oldest', p_limit => 1
  )),
  'Bon Iver',
  'oldest sorts by concert date ascending'
);

select is(
  (select primary_artist from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_sort => 'recently_updated', p_limit => 1
  )),
  'Mitski',
  'recently updated sorts by database update time descending'
);

select is(
  (select primary_artist from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_sort => 'artist', p_limit => 1
  )),
  'Big Thief',
  'artist sorting is case-insensitive and ascending'
);

select is(
  (select venue_name from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_sort => 'venue', p_limit => 1
  )),
  'Bill Graham Civic Auditorium',
  'venue sorting is case-insensitive and ascending'
);

select is(
  (select count(*) from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_year => 2025
  )),
  6::bigint,
  'year filtering includes owned and visible collaborator concerts'
);

select is(
  (select count(*) from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_visibility => 'private'
  )),
  2::bigint,
  'visibility filtering remains available with the expanded archive contract'
);

select is(
  (select primary_artist from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001',
    p_sort => 'oldest',
    p_cursor_date => date '2025-05-29',
    p_cursor_id => 'd2000000-0000-0000-0000-000000000002',
    p_limit => 1
  )),
  'Fleet Foxes',
  'oldest cursor pagination continues after the supplied concert'
);

select throws_ok(
  $$select * from public.profile_concert_history(
    'd1000000-0000-0000-0000-000000000001', p_sort => 'random'
  )$$,
  '22023',
  'Unsupported concert-history sort',
  'unknown sort values are rejected at the database boundary'
);

select * from finish();
rollback;
