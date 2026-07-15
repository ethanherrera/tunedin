#!/usr/bin/env bash
set -euo pipefail

readonly previous_migration="20260712231500"
readonly catalog_migration="20260715180000"

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
project_name="$(basename "$root_dir")"

cd "$root_dir"

supabase db reset \
  --local \
  --version "$previous_migration" \
  --sql-paths './fixtures/musicbrainz_legacy_upgrade.sql' \
  --yes
supabase migration up --local --yes

database_container="$(docker ps \
  --filter "label=com.supabase.cli.project=${project_name}" \
  --format '{{.Names}}' | awk '/^supabase_db_/ { print; exit }')"

if [[ -z "$database_container" ]]; then
  echo "Local Supabase database is not running." >&2
  exit 1
fi

metrics="$(docker exec "$database_container" psql \
  -U postgres \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -At \
  -F '|' \
  -c "
    select
      (select count(*) from supabase_migrations.schema_migrations where version = '${catalog_migration}'),
      (select count(*) from public.concerts as concert
        where concert.id in (
          'e2000000-0000-0000-0000-000000000001'::uuid,
          'e2000000-0000-0000-0000-000000000002'::uuid
        )
          and concert.owner_id = 'e1000000-0000-0000-0000-000000000001'::uuid
          and concert.venue_name = 'Legacy Upgrade Hall'
          and concert.city = 'San Francisco'
          and concert.tour = 'Legacy Upgrade Tour'),
      (select count(*) from public.concert_artists as artist
        where artist.id in (
          'e2100000-0000-0000-0000-000000000001'::uuid,
          'e2100000-0000-0000-0000-000000000002'::uuid
        )
          and artist.lineup_position = 1
          and artist.artist_name = 'Legacy Upgrade Artist'
          and artist.is_primary),
      (select count(*) from public.setlist_items as item
        where item.id in (
          'e2200000-0000-0000-0000-000000000001'::uuid,
          'e2200000-0000-0000-0000-000000000002'::uuid
        )
          and item.set_position = 1
          and item.song_title = 'Legacy Upgrade Song'),
      ((select count(*) from public.concerts where catalog_place_id is null)
        + (select count(*) from public.concert_artists where catalog_artist_id is null)
        + (select count(*) from public.setlist_items where catalog_song_id is null)),
      (select count(distinct catalog_place_id) from public.concerts),
      (select count(distinct catalog_area_id) from public.concerts),
      (select count(distinct catalog_tour_id) from public.concerts),
      (select count(distinct catalog_artist_id) from public.concert_artists),
      (select count(distinct catalog_song_id) from public.setlist_items),
      (select count(*) from public.catalog_entities
        where origin = 'legacy_import' and status = 'needs_review'),
      (select count(distinct kind) from public.catalog_entities
        where origin = 'legacy_import' and status = 'needs_review'),
      (select count(*) from private.catalog_entity_provenance
        where creator_id = 'e1000000-0000-0000-0000-000000000001'::uuid),
      (select count(*) from information_schema.columns
        where table_schema = 'public'
          and (table_name, column_name) in (
            ('concerts', 'catalog_place_id'),
            ('concert_artists', 'catalog_artist_id'),
            ('setlist_items', 'catalog_song_id')
          )
          and is_nullable = 'NO'),
      (select count(*) from pg_catalog.pg_trigger
        where tgname in (
          'concerts_require_valid_lineup',
          'concert_artists_require_valid_lineup'
        )
          and tgdeferrable
          and tginitdeferred),
      (select count(*) from public.concerts as concert
        join public.catalog_places as place on place.id = concert.catalog_place_id
        left join public.catalog_entities as area on area.id = place.area_id
        where concert.catalog_area_id is distinct from place.area_id
          or concert.city is distinct from area.display_name),
      (select count(*) from public.catalog_tour_artists as tour_artist
        join public.concerts as concert on concert.catalog_tour_id = tour_artist.tour_id
        join public.concert_artists as artist
          on artist.concert_id = concert.id and artist.is_primary
        where tour_artist.artist_id = artist.catalog_artist_id),
      (select count(*) from public.catalog_song_artists as song_artist
        join public.setlist_items as item on item.catalog_song_id = song_artist.song_id
        join public.concert_artists as artist
          on artist.concert_id = item.concert_id and artist.is_primary
        where song_artist.artist_id = artist.catalog_artist_id);
  ")"

expected="1|2|2|2|0|1|1|1|1|1|5|5|5|3|2|0|2|2"
if [[ "$metrics" != "$expected" ]]; then
  echo "MusicBrainz legacy upgrade check failed (expected ${expected}; received ${metrics})." >&2
  exit 1
fi

echo "MusicBrainz legacy rows migrated with snapshots, identity, and deferred constraints intact."
