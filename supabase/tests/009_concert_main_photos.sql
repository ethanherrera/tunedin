begin;
select plan(8);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

insert into storage.objects (bucket_id, name, owner_id, metadata) values (
  'images', 'concerts/d2000000-0000-0000-0000-000000000001/main.jpg', auth.uid()::text,
  '{"mimetype":"image/jpeg","size":2000}'
);
select pass('concert owner can upload the fixed main photo path');
select is((public.set_concert_photo('d2000000-0000-0000-0000-000000000001')).photo_object_path,
  'concerts/d2000000-0000-0000-0000-000000000001/main.jpg', 'valid photo attaches');
select is((select photo_version from public.concerts where id = 'd2000000-0000-0000-0000-000000000001'), 1::bigint,
  'attachment increments photo version');

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000010', true);
select is((select count(*) from storage.objects where name = 'concerts/d2000000-0000-0000-0000-000000000001/main.jpg'),
  0::bigint, 'unrelated user cannot read a private concert photo');
select throws_ok($$delete from storage.objects where name = 'concerts/d2000000-0000-0000-0000-000000000001/main.jpg'$$,
  '42501', 'Direct deletion from storage tables is not allowed. Use the Storage API instead.',
  'direct metadata deletion is rejected');

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
select is((select count(*) from storage.objects where name = 'concerts/d2000000-0000-0000-0000-000000000001/main.jpg'),
  1::bigint, 'owner can read photo');
select is(public.remove_concert_photo('d2000000-0000-0000-0000-000000000001'),
  'concerts/d2000000-0000-0000-0000-000000000001/main.jpg', 'remove returns former path');
select is((select photo_object_path from public.concerts where id = 'd2000000-0000-0000-0000-000000000001'), null,
  'remove clears concert metadata');

select * from finish();
rollback;
