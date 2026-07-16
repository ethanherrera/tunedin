begin;

select plan(14);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
  'images',
  'event-covers/d4000000-0000-0000-0000-000000000003/cover.jpg',
  auth.uid()::text,
  '{"mimetype":"image/jpeg","size":2000}'
);
select pass('event creator can upload the fixed community cover path');

select lives_ok(
  $$select public.set_catalog_event_cover('d4000000-0000-0000-0000-000000000003')$$,
  'creator can attach a valid JPEG cover'
);
select is(
  (
    select artists -> 0 -> 'event_cover' ->> 'object_path'
    from public.get_catalog_event_detail('d4000000-0000-0000-0000-000000000003')
  ),
  'event-covers/d4000000-0000-0000-0000-000000000003/cover.jpg',
  'community cover uses the durable fixed object path'
);
select is(
  (
    select (artists -> 0 -> 'event_cover' ->> 'version')::bigint
    from public.get_catalog_event_detail('d4000000-0000-0000-0000-000000000003')
  ),
  1::bigint,
  'attaching a cover advances its independent cache version'
);
select is(
  (
    select artists -> 0 -> 'event_cover' ->> 'source'
    from public.get_catalog_event_detail('d4000000-0000-0000-0000-000000000003')
  ),
  'community',
  'read models expose the cover inside the event transport projection'
);

select is(
  (
    select count(*)
    from storage.objects
    where name = 'event-covers/d4000000-0000-0000-0000-000000000003/cover.jpg'
  ),
  1::bigint,
  'creator can read the attached unlisted event cover'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000010', true);
select is(
  (
    select count(*)
    from storage.objects
    where name = 'event-covers/d4000000-0000-0000-0000-000000000003/cover.jpg'
  ),
  0::bigint,
  'viewer without unlisted event access cannot read its cover'
);
select throws_ok(
  $$select public.set_catalog_event_cover('d4000000-0000-0000-0000-000000000003')$$,
  '42501',
  'Only the concert creator can change its cover',
  'noncreator cannot attach or replace event cover metadata'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id, metadata) values ('images', 'event-covers/d4000000-0000-0000-0000-000000000005/cover.jpg', auth.uid()::text, '{"mimetype":"image/jpeg","size":2000}')$$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'noncreator cannot upload to another event fixed cover path'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);
update storage.objects
set metadata = '{"mimetype":"image/png","size":2000}'
where name = 'event-covers/d4000000-0000-0000-0000-000000000003/cover.jpg';
select throws_ok(
  $$select public.set_catalog_event_cover('d4000000-0000-0000-0000-000000000003')$$,
  '22023',
  'Concert covers must be JPEG images',
  'attachment rejects non-JPEG media at the database boundary'
);
update storage.objects
set metadata = '{"mimetype":"image/jpeg","size":3145729}'
where name = 'event-covers/d4000000-0000-0000-0000-000000000003/cover.jpg';
select throws_ok(
  $$select public.set_catalog_event_cover('d4000000-0000-0000-0000-000000000003')$$,
  '22023',
  'Concert covers must be no larger than 3 MB',
  'attachment rejects oversized media at the database boundary'
);

select throws_ok(
  $$update public.catalog_events set cover_source = null where id = 'd4000000-0000-0000-0000-000000000003'$$,
  '42501',
  'permission denied for table catalog_events',
  'ordinary clients cannot bypass the cover RPC with direct event mutation'
);
select is(
  public.remove_catalog_event_cover('d4000000-0000-0000-0000-000000000003'),
  'event-covers/d4000000-0000-0000-0000-000000000003/cover.jpg',
  'remove returns the former object path for Storage cleanup'
);
select is(
  (
    select artists -> 0 -> 'event_cover'
    from public.get_catalog_event_detail('d4000000-0000-0000-0000-000000000003')
  ),
  'null'::jsonb,
  'remove restores the no-upload community event state'
);

select * from finish();
rollback;
