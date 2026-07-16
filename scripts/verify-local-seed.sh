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
    (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('setlist_items', 'concert_events', 'concert_collaborators', 'direct_collaboration_notifications')),
    (select count(*) from pg_proc as procedure join pg_namespace as namespace on namespace.oid = procedure.pronamespace where namespace.nspname = 'public' and procedure.proname in ('create_private_concert', 'create_private_concert_v2', 'update_concert', 'update_concert_v2', 'friends_activity_feed', 'profile_concert_history', 'tag_concert_collaborator', 'remove_concert_collaborator', 'transfer_concert_ownership')),
    (select count(*) from public.catalog_entities where origin in ('legacy_import', 'legacy_client')),
    (select count(*) from public.catalog_events),
    (select count(*) from public.catalog_event_attendance),
    (select count(*) from public.catalog_event_posts),
    (select count(*) from public.concerts where record_model = 'personal_diary'),
    (select count(*) from public.concerts where record_model = 'legacy_shared'),
    (select count(*) from public.diary_reviews),
    (select count(*) from public.comments),
    (select count(*) from public.concert_photos where status = 'ready'),
    (select count(*) from private.catalog_event_notification_outbox),
    (select count(*) from public.social_activity_events),
    (select count(*) from storage.objects where bucket_id = 'images' and name like 'event-covers/%/cover.jpg');
")"

expected="24|23|13|0|0|0|10|37|12|10|0|10|10|12|45|73|6"
if [[ "$metrics" != "$expected" ]]; then
  echo "Local Supabase seed integrity check failed (expected ${expected}; received ${metrics})." >&2
  exit 1
fi

echo "Local Supabase community events, attendance, Posts, Comments, media, and catalog contracts verified."
