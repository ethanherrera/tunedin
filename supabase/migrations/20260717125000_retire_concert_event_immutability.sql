-- The retired concert product, its audit history, and legacy catalog identities
-- are removed by the next migration. Remove the audit table's delete guard so
-- deleting concerts can cascade through existing event rows in Development and
-- Staging.
drop trigger if exists concert_events_are_immutable
  on public.concert_events;

-- Legacy-created songs and tours may still credit a legacy artist. Those
-- restrictive junction foreign keys must be cleared before the catalog entity
-- cascade can retire the artist subtype.
delete from public.catalog_song_artists as credit
using public.catalog_entities as entity
where credit.artist_id = entity.id
  and entity.origin in ('legacy_import', 'legacy_client');

delete from public.catalog_tour_artists as credit
using public.catalog_entities as entity
where credit.artist_id = entity.id
  and entity.origin in ('legacy_import', 'legacy_client');

-- A surviving identity must not keep a restrictive merge reference to an
-- identity that the next migration intentionally removes.
update public.catalog_entities as entity
set merged_into_id = null
where entity.merged_into_id in (
  select retired.id
  from public.catalog_entities as retired
  where retired.origin in ('legacy_import', 'legacy_client')
);
