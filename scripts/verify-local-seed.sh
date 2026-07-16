#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
project_name="$(basename "$root_dir")"
database_container="$(docker ps \
  --filter "label=com.supabase.cli.project=${project_name}" \
  --format '{{.Names}}' | awk '/^supabase_db_/ { print; exit }')"

if [[ -z "$database_container" ]]; then
  echo "Local Supabase database is not running. Run 'make local-db-reset' first." >&2
  exit 1
fi

metrics="$(docker exec "$database_container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -F '|' -c "
  select
    (select count(*) from auth.users where email like '%@tunedin.local'),
    (select count(*) from auth.identities where provider = 'email'),
    (select count(*) from auth.users where email like '%@tunedin.local' and encrypted_password <> ''),
    (select count(*) from auth.users where email like '%@tunedin.local' and confirmation_token is not null and recovery_token is not null and email_change_token_new is not null and email_change is not null and phone_change is not null and phone_change_token is not null and email_change_token_current is not null and reauthentication_token is not null),
    (select count(*) from public.profiles where onboarding_completed_at is not null),
    (select count(*) from public.profiles where id = 'd1000000-0000-0000-0000-000000000016'::uuid and onboarding_completed_at is null),
    (select count(*) from public.relationships where status = 'accepted' and ('d1000000-0000-0000-0000-000000000001'::uuid in (user_low_id, user_high_id))),
    (select count(*) from public.relationships where status = 'pending' and initiator_id = 'd1000000-0000-0000-0000-000000000001'::uuid),
    (select count(*) from public.relationships where status = 'pending' and responder_id is null and initiator_id = 'd1000000-0000-0000-0000-000000000008'::uuid),
    (select count(*) from public.relationships where status = 'declined' and 'd1000000-0000-0000-0000-000000000001'::uuid in (user_low_id, user_high_id)),
    (select count(*) from public.profiles as profile where profile.id between 'd1000000-0000-0000-0000-000000000010'::uuid and 'd1000000-0000-0000-0000-000000000015'::uuid and not exists (select 1 from public.relationships as relationship where profile.id in (relationship.user_low_id, relationship.user_high_id) and 'd1000000-0000-0000-0000-000000000001'::uuid in (relationship.user_low_id, relationship.user_high_id))),
    (select count(*) from public.concerts where id between 'd2000000-0000-0000-0000-000000000001'::uuid and 'd2000000-0000-0000-0000-000000000024'::uuid),
    (select count(*) from public.concert_collaborators where concert_id between 'd2000000-0000-0000-0000-000000000001'::uuid and 'd2000000-0000-0000-0000-000000000024'::uuid),
    (select count(*) from public.comments where concert_id between 'd2000000-0000-0000-0000-000000000001'::uuid and 'd2000000-0000-0000-0000-000000000024'::uuid),
    (select count(*) from public.concert_events where concert_id between 'd2000000-0000-0000-0000-000000000001'::uuid and 'd2000000-0000-0000-0000-000000000024'::uuid),
    (select count(*) from public.concerts as concert join public.concert_collaborators as collaborator on collaborator.concert_id = concert.id where concert.visibility = 'private'),
    (select count(*) from public.comments as comment join public.concerts as concert on concert.id = comment.concert_id where comment.concert_id between 'd2000000-0000-0000-0000-000000000001'::uuid and 'd2000000-0000-0000-0000-000000000024'::uuid and comment.author_id <> concert.owner_id and not exists (select 1 from public.concert_collaborators as collaborator where collaborator.concert_id = concert.id and collaborator.profile_id = comment.author_id) and not exists (select 1 from public.relationships as relationship where relationship.status = 'accepted' and comment.author_id in (relationship.user_low_id, relationship.user_high_id) and concert.owner_id in (relationship.user_low_id, relationship.user_high_id))),
    (select count(*) from storage.buckets where id = 'images' and public = false and file_size_limit = 5242880 and allowed_mime_types = array['image/jpeg']::text[]),
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name in ('avatar_object_path', 'avatar_version')),
    (select count(*) from public.catalog_entities where id between 'd3000000-0000-0000-0000-000000000001'::uuid and 'd3000000-0000-0000-0000-000000000205'::uuid),
    (select count(*) from private.catalog_entity_provenance where entity_id = 'd3000000-0000-0000-0000-000000000001'::uuid and creator_id is null and source_updated_at is not null and refreshed_at is not null),
    (select count(distinct kind) from public.catalog_entities where id between 'd3000000-0000-0000-0000-000000000101'::uuid and 'd3000000-0000-0000-0000-000000000105'::uuid and origin = 'tunedin_custom'),
    (select count(distinct kind) from public.catalog_entities where id between 'd3000000-0000-0000-0000-000000000201'::uuid and 'd3000000-0000-0000-0000-000000000205'::uuid and origin = 'legacy_import'),
    (select count(*) from private.catalog_entity_provenance where entity_id between 'd3000000-0000-0000-0000-000000000101'::uuid and 'd3000000-0000-0000-0000-000000000205'::uuid and creator_id = 'd1000000-0000-0000-0000-000000000001'::uuid),
    (select count(*) from public.concerts where catalog_place_id = 'd3000000-0000-0000-0000-000000000103'::uuid),
    (select count(*) from public.catalog_entities where (origin = 'musicbrainz') <> (musicbrainz_mbid is not null)),
    ((select count(*) from public.concerts where catalog_place_id is null) + (select count(*) from public.concert_artists where catalog_artist_id is null) + (select count(*) from public.setlist_items where catalog_song_id is null)),
    (select count(*) from public.concerts as concert join public.catalog_places as place on place.id = concert.catalog_place_id left join public.catalog_entities as area on area.id = place.area_id where concert.catalog_area_id is distinct from place.area_id or concert.city is distinct from area.display_name),
    ((select count(*) from public.concerts as concert join public.catalog_entities as place on place.id = concert.catalog_place_id where concert.venue_name is distinct from place.display_name) + (select count(*) from public.concert_artists as artist join public.catalog_entities as entity on entity.id = artist.catalog_artist_id where artist.artist_name is distinct from entity.display_name) + (select count(*) from public.setlist_items as item join public.catalog_entities as entity on entity.id = item.catalog_song_id where item.song_title is distinct from entity.display_name)),
    (select count(*) from public.catalog_events where id between 'd4000000-0000-0000-0000-000000000001'::uuid and 'd4000000-0000-0000-0000-000000000004'::uuid),
    (select count(*) from public.catalog_event_artists where event_id between 'd4000000-0000-0000-0000-000000000001'::uuid and 'd4000000-0000-0000-0000-000000000004'::uuid),
    (select count(*) from public.social_activity_events where id between 'd4100000-0000-0000-0000-000000000001'::uuid and 'd4100000-0000-0000-0000-000000000005'::uuid),
    (select count(*) from public.catalog_events where id between 'd4000000-0000-0000-0000-000000000001'::uuid and 'd4000000-0000-0000-0000-000000000004'::uuid and listing = 'unlisted'),
    ((select count(*) from public.catalog_events as event join public.catalog_entities as place on place.id = event.catalog_place_id where event.id between 'd4000000-0000-0000-0000-000000000001'::uuid and 'd4000000-0000-0000-0000-000000000004'::uuid and event.venue_name_snapshot is distinct from place.display_name) + (select count(*) from public.catalog_event_artists as lineup join public.catalog_entities as artist on artist.id = lineup.catalog_artist_id where lineup.event_id between 'd4000000-0000-0000-0000-000000000001'::uuid and 'd4000000-0000-0000-0000-000000000004'::uuid and lineup.artist_name_snapshot is distinct from artist.display_name));
")"

expected="16|16|16|16|15|1|5|1|1|1|6|24|8|12|73|0|0|1|2|11|1|5|5|10|2|0|0|0|0|4|4|5|1|0"
if [[ "$metrics" != "$expected" ]]; then
  echo "Local Supabase seed integrity check failed (expected ${expected}; received ${metrics})." >&2
  exit 1
fi

echo "Local Supabase journey, catalog identity, community event, and private profile-image contracts verified."
