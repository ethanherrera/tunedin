begin;
select plan(15);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select is((select policy_version from public.concert_album_policy()), 1, 'album policy is versioned');
select is((select concert_photo_limit from public.concert_album_policy()), 100, 'concert quota is published');
select is((select contributor_photo_limit from public.concert_album_policy()), 30, 'contributor quota is published');
select is((select reservation_limit_24_hours from public.concert_album_policy()), 10, 'rolling reservation quota is published');
select is((select attached_file_byte_limit from public.concert_album_policy()), 2097152::bigint, 'attachment byte limit is published');

select is(
  (public.reserve_concert_photo('d2000000-0000-0000-0000-000000000004',
    'da000000-0000-0000-0000-000000000001')).object_path,
  'concerts/d2000000-0000-0000-0000-000000000004/album/da000000-0000-0000-0000-000000000001.jpg',
  'reservation creates the exact immutable path'
);
select is(
  (public.reserve_concert_photo('d2000000-0000-0000-0000-000000000004',
    'da000000-0000-0000-0000-000000000001')).id,
  'da000000-0000-0000-0000-000000000001'::uuid,
  'retry reuses the reservation without another row'
);

insert into storage.objects (bucket_id, name, owner_id, metadata) values (
  'images',
  'concerts/d2000000-0000-0000-0000-000000000004/album/da000000-0000-0000-0000-000000000001.jpg',
  auth.uid()::text, '{"mimetype":"image/jpeg","size":2048}'
);
select is((public.attach_concert_photo('da000000-0000-0000-0000-000000000001')).status,
  'ready'::public.concert_photo_status, 'valid reserved JPEG attaches');
select is((select count(*) from public.list_concert_photos('d2000000-0000-0000-0000-000000000004')),
  1::bigint, 'visible album listing includes the ready photo');

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);
select is((select count(*) from public.list_concert_photos('d2000000-0000-0000-0000-000000000004')),
  1::bigint, 'current editor can browse the album');
select throws_ok(
  $$select public.prepare_concert_photo_deletion('da000000-0000-0000-0000-000000000001')$$,
  '42501', 'You cannot delete this photo', 'editor cannot delete another uploader photo'
);

set local role postgres;
delete from public.concert_collaborators where concert_id = 'd2000000-0000-0000-0000-000000000004'
  and profile_id = 'd1000000-0000-0000-0000-000000000002';
set local role authenticated;
select throws_ok(
  $$select public.reserve_concert_photo('d2000000-0000-0000-0000-000000000004',
    'da000000-0000-0000-0000-000000000002')$$,
  '42501', 'You no longer have permission to edit this concert', 'removed editor immediately loses upload permission'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
select is(public.prepare_concert_photo_deletion('da000000-0000-0000-0000-000000000001'),
  'concerts/d2000000-0000-0000-0000-000000000004/album/da000000-0000-0000-0000-000000000001.jpg',
  'owner may prepare moderation deletion');
select throws_ok(
  $$select public.finalize_concert_photo_deletion('da000000-0000-0000-0000-000000000001')$$,
  '55000', 'Delete the stored photo before finalizing',
  'deletion cannot finalize before Storage API cleanup'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000010', true);
select throws_ok(
  $$select * from public.list_concert_photos('d2000000-0000-0000-0000-000000000004')$$,
  '42501', 'You cannot view this concert', 'outsider cannot browse collaborator album'
);

select * from finish();
rollback;
