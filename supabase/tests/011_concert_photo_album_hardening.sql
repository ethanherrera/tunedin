begin;
select plan(18);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select is((select picker_batch_limit from public.concert_album_policy()), 10,
  'picker limit is published by the server policy');
select is((select caption_character_limit from public.concert_album_policy()), 300,
  'caption limit is published by the server policy');
select is((select pending_reservation_lifetime_seconds from public.concert_album_policy()), 3600,
  'reservation lifetime is published by the server policy');

select ok(
  (public.reserve_concert_photo(
    'd2000000-0000-0000-0000-000000000004',
    'db000000-0000-0000-0000-000000000001'
  )).expires_at between clock_timestamp() + interval '3590 seconds'
    and clock_timestamp() + interval '3610 seconds',
  'new reservation expiry is derived from server policy'
);

set local role postgres;
delete from public.concert_photos;
insert into public.concert_photos (
  id, concert_id, uploader_id, object_path, created_at, expires_at
)
select id, 'd2000000-0000-0000-0000-000000000004',
  'd1000000-0000-0000-0000-000000000001',
  'concerts/d2000000-0000-0000-0000-000000000004/album/' || id || '.jpg',
  clock_timestamp(), clock_timestamp() - interval '1 second'
from (select gen_random_uuid() id from generate_series(1, 10)) generated;
set local role authenticated;
select throws_ok(
  $$select public.reserve_concert_photo(
    'd2000000-0000-0000-0000-000000000004',
    'db000000-0000-0000-0000-000000000002')$$,
  '42900', 'You have reached the album upload limit for today',
  'expired reservations still count toward rolling abuse protection'
);

set local role postgres;
delete from public.concert_photos;
insert into public.concert_photos (
  id, concert_id, uploader_id, object_path, created_at, expires_at
)
select id, 'd2000000-0000-0000-0000-000000000004',
  'd1000000-0000-0000-0000-000000000001',
  'concerts/d2000000-0000-0000-0000-000000000004/album/' || id || '.jpg',
  clock_timestamp() - interval '2 days', clock_timestamp() - interval '1 day'
from (select gen_random_uuid() id from generate_series(1, 100)) generated;
set local role authenticated;
select lives_ok(
  $$select public.reserve_concert_photo(
    'd2000000-0000-0000-0000-000000000004',
    'db000000-0000-0000-0000-000000000003')$$,
  'expired reservations release album capacity'
);

set local role postgres;
delete from public.concert_photos;
insert into public.concert_photos (
  id, concert_id, uploader_id, object_path, status, created_at, attached_at
)
select id, 'd2000000-0000-0000-0000-000000000004',
  'd1000000-0000-0000-0000-000000000001',
  'concerts/d2000000-0000-0000-0000-000000000004/album/' || id || '.jpg',
  'ready', clock_timestamp() - interval '2 days', clock_timestamp() - interval '2 days'
from (select gen_random_uuid() id from generate_series(1, 30)) generated;
set local role authenticated;
select throws_ok(
  $$select public.reserve_concert_photo(
    'd2000000-0000-0000-0000-000000000004',
    'db000000-0000-0000-0000-000000000004')$$,
  '54000', 'You have reached your photo limit for this album',
  'contributor quota is enforced from server policy'
);

set local role postgres;
delete from public.concert_photos;
insert into public.concert_photos (
  id, concert_id, uploader_id, object_path, status, created_at, attached_at
)
select id, 'd2000000-0000-0000-0000-000000000004',
  'd1000000-0000-0000-0000-000000000002',
  'concerts/d2000000-0000-0000-0000-000000000004/album/' || id || '.jpg',
  'ready', clock_timestamp() - interval '2 days', clock_timestamp() - interval '2 days'
from (select gen_random_uuid() id from generate_series(1, 100)) generated;
set local role authenticated;
select throws_ok(
  $$select public.reserve_concert_photo(
    'd2000000-0000-0000-0000-000000000004',
    'db000000-0000-0000-0000-000000000005')$$,
  '54000', 'This album has reached its photo limit',
  'concert quota is enforced from server policy'
);

set local role postgres;
delete from public.concert_photos;
set local role authenticated;
select lives_ok(
  $$select public.reserve_concert_photo(
    'd2000000-0000-0000-0000-000000000004',
    'db000000-0000-0000-0000-000000000006')$$,
  'valid attachment reservation is created'
);

set local role postgres;
insert into storage.objects (bucket_id, name, owner_id, metadata) values (
  'images',
  'concerts/d2000000-0000-0000-0000-000000000004/album/db000000-0000-0000-0000-000000000006.jpg',
  'd1000000-0000-0000-0000-000000000001',
  '{"mimetype":"image/png","size":1024}'
);
set local role authenticated;
select throws_ok(
  $$select public.attach_concert_photo('db000000-0000-0000-0000-000000000006')$$,
  '22023', 'Album photos must be JPEG images', 'attachment rejects non-JPEG metadata'
);

set local role postgres;
update storage.objects set metadata = '{"mimetype":"image/jpeg","size":0}'
where name like '%db000000-0000-0000-0000-000000000006.jpg';
set local role authenticated;
select throws_ok(
  $$select public.attach_concert_photo('db000000-0000-0000-0000-000000000006')$$,
  '22023', 'Album photo size is invalid', 'attachment rejects zero-byte objects'
);

set local role postgres;
update storage.objects set metadata = '{"mimetype":"image/jpeg","size":2097153}'
where name like '%db000000-0000-0000-0000-000000000006.jpg';
set local role authenticated;
select throws_ok(
  $$select public.attach_concert_photo('db000000-0000-0000-0000-000000000006')$$,
  '22023', 'Album photo size is invalid', 'attachment rejects objects above policy size'
);

set local role postgres;
update storage.objects set metadata = '{"mimetype":"image/jpeg","size":2097152}'
where name like '%db000000-0000-0000-0000-000000000006.jpg';
set local role authenticated;
select is(
  (public.attach_concert_photo('db000000-0000-0000-0000-000000000006')).status,
  'ready'::public.concert_photo_status,
  'attachment accepts the exact policy byte limit'
);

select throws_ok(
  $$select public.update_concert_photo_caption(
    'db000000-0000-0000-0000-000000000006', repeat('x', 301))$$,
  '22023', 'Caption must contain no more than 300 characters',
  'caption enforcement matches the published limit'
);

select is(
  (public.update_concert_photo_caption(
    'db000000-0000-0000-0000-000000000006', 'Front row')).caption,
  'Front row', 'uploader can set a valid caption'
);

set local role postgres;
update storage.objects set name = 'test-cleanup/db000000-0000-0000-0000-000000000006.jpg'
where name like '%db000000-0000-0000-0000-000000000006.jpg';
delete from public.concert_photos;
insert into public.concert_photos (
  id, concert_id, uploader_id, object_path, status, attached_at
) values (
  'db000000-0000-0000-0000-000000000007',
  'd2000000-0000-0000-0000-000000000006',
  'd1000000-0000-0000-0000-000000000001',
  'concerts/d2000000-0000-0000-0000-000000000006/album/db000000-0000-0000-0000-000000000007.jpg',
  'ready', clock_timestamp()
);
insert into storage.objects (bucket_id, name, owner_id, metadata) values (
  'images',
  'concerts/d2000000-0000-0000-0000-000000000006/album/db000000-0000-0000-0000-000000000007.jpg',
  'd1000000-0000-0000-0000-000000000001',
  '{"mimetype":"image/jpeg","size":1024}'
);
set local role authenticated;
select is(
  (select count(*) from public.prepare_concert_deletion(
    'd2000000-0000-0000-0000-000000000006')),
  1::bigint, 'concert deletion returns every stored album object path'
);
select throws_ok(
  $$select public.finalize_concert_deletion(
    'd2000000-0000-0000-0000-000000000006')$$,
  '55000', 'Delete stored concert images before finalizing',
  'concert deletion cannot finalize while an object remains'
);

set local role postgres;
update storage.objects set name = 'test-cleanup/db000000-0000-0000-0000-000000000007.jpg'
where name = 'concerts/d2000000-0000-0000-0000-000000000006/album/db000000-0000-0000-0000-000000000007.jpg';
set local role authenticated;
select lives_ok(
  $$select public.finalize_concert_deletion(
    'd2000000-0000-0000-0000-000000000006')$$,
  'concert deletion finalizes after Storage cleanup'
);

select * from finish();
rollback;
