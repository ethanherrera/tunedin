begin;

select plan(13);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
('81000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'avatar-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
('82000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'avatar-viewer@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.profiles set username = case when id::text like '81%' then 'avatar_owner' else 'avatar_viewer' end,
  display_name = 'Avatar Tester', onboarding_completed_at = now()
where id in ('81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000002');

select is((select public from storage.buckets where id = 'images'), false, 'images bucket is private');
select is((select file_size_limit from storage.buckets where id = 'images'), 5242880::bigint, 'bucket limit is 5 MB');
select is((select allowed_mime_types from storage.buckets where id = 'images'), array['image/jpeg']::text[], 'bucket accepts JPEG only');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('images', 'avatars/81000000-0000-0000-0000-000000000001/profile.jpg',
  '81000000-0000-0000-0000-000000000001', '{"mimetype":"image/jpeg","size":1000}');
select pass('owner can insert the fixed avatar path');
select is((public.set_profile_avatar()).avatar_object_path,
  'avatars/81000000-0000-0000-0000-000000000001/profile.jpg', 'valid object attaches');
select is((select avatar_version from public.profiles where id = auth.uid()), 1::bigint, 'attachment increments version');

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata) values
    ('images', 'avatars/82000000-0000-0000-0000-000000000002/profile.jpg', auth.uid()::text, '{"mimetype":"image/jpeg","size":1}')$$,
  '42501', null, 'cross-user insert is denied');

reset role;
update storage.objects set metadata = '{"mimetype":"image/png","size":1000}'
where bucket_id = 'images' and name like 'avatars/81%';
set local role authenticated;
select throws_ok('select public.set_profile_avatar()', '22023', 'Profile photos must be JPEG images', 'non-JPEG attachment is rejected');

reset role;
update storage.objects set metadata = '{"mimetype":"image/jpeg","size":1048577}'
where bucket_id = 'images' and name like 'avatars/81%';
set local role authenticated;
select throws_ok('select public.set_profile_avatar()', '22023', 'Profile photos must be no larger than 1 MB', 'oversized attachment is rejected');

reset role;
update storage.objects set metadata = '{"mimetype":"image/jpeg","size":1000}'
where bucket_id = 'images' and name like 'avatars/81%';
set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-0000-0000-000000000002', true);
select is((select count(*) from storage.objects where bucket_id = 'images'), 1::bigint, 'authenticated visible profile can select avatar');

reset role;
insert into public.relationships (user_low_id, user_high_id, status, initiator_id, blocker_id, responded_at)
values ('81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000002', 'blocked',
  '82000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000002', now());
set local role authenticated;
select is((select count(*) from storage.objects where bucket_id = 'images'), 0::bigint, 'blocked viewer cannot select avatar');

reset role;
delete from public.relationships;
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select is(public.remove_profile_avatar(), 'avatars/81000000-0000-0000-0000-000000000001/profile.jpg', 'remove returns former path');
select is((select avatar_object_path from public.profiles where id = auth.uid()), null, 'remove clears profile metadata');

select * from finish();
rollback;
