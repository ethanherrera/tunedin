#!/usr/bin/env bash
set -euo pipefail

database_container="$(docker ps --filter 'name=supabase_db_tunedin' --format '{{.Names}}' | head -n 1)"

if [[ -z "$database_container" ]]; then
  echo "Local Supabase database is not running. Run 'make local-db-reset' first." >&2
  exit 1
fi

metrics="$(docker exec "$database_container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -F '|' -c "
  select
    (select count(*) from auth.users where email like '%@tunedin.local'),
    (select count(*) from public.profiles where onboarding_completed_at is not null),
    (select count(*) from public.relationships where status = 'accepted' and 'd1000000-0000-0000-0000-000000000001'::uuid in (user_low_id, user_high_id)),
    (select count(*) from information_schema.tables where table_schema in ('public', 'private') and table_name in ('setlist_items', 'concert_events', 'concert_collaborators', 'direct_collaboration_notifications', 'concerts', 'concert_artists', 'concert_photos', 'diary_reviews', 'comments', 'catalog_event_posts', 'catalog_event_diary_mutations', 'catalog_event_integrity_operations')),
    (select count(*) from pg_proc as procedure join pg_namespace as namespace on namespace.oid = procedure.pronamespace where namespace.nspname in ('public', 'private') and (procedure.proname like '%diary%' or procedure.proname like '%concert%' or procedure.proname in ('create_catalog_event_post', 'list_catalog_event_posts', 'list_catalog_event_diaries', 'reserve_concert_photo', 'attach_concert_photo'))),
    (select count(*) from public.catalog_entities where origin::text in ('legacy_import', 'legacy_client')),
    (select count(*) from public.catalog_events),
    (select count(*) from public.catalog_event_attendance),
    (select count(*) from public.event_comments),
    (select count(*) from public.event_posts where published_at is not null),
    (select count(*) from public.post_comments),
    (select count(*) from public.post_media where status = 'ready'),
    (select count(*) from private.catalog_event_notification_outbox),
    (select count(*) from public.social_activity_events),
    (select count(*) from storage.objects where bucket_id = 'images' and name like 'event-covers/%/cover.jpg');
")"

expected="24|23|13|0|0|0|10|37|12|10|10|12|5|73|6"
if [[ "$metrics" != "$expected" ]]; then
  echo "Local Supabase seed integrity check failed (expected ${expected}; received ${metrics})." >&2
  exit 1
fi

echo "Local Supabase community events, attendance, Posts, Comments, media, and catalog contracts verified."
