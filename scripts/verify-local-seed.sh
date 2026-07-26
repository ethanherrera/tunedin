#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null || { echo "jq is required to verify the Local seed." >&2; exit 1; }

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
local_supabase_helper="${root_dir}/scripts/worktree-local-supabase.sh"

metrics_json="$("${local_supabase_helper}" query --local -o json "
  select
    (select count(*) from auth.users where email like '%@tunedin.local') as metric_0,
    (select count(*) from public.profiles where onboarding_completed_at is not null) as metric_1,
    (select count(*) from public.relationships where status = 'accepted' and 'd1000000-0000-0000-0000-000000000001'::uuid in (user_low_id, user_high_id)) as metric_2,
    (select count(*) from information_schema.tables where table_schema in ('public', 'private') and table_name in ('setlist_items', 'concert_events', 'concert_collaborators', 'direct_collaboration_notifications', 'concerts', 'concert_artists', 'concert_photos', 'diary_reviews', 'comments', 'catalog_event_posts', 'catalog_event_diary_mutations', 'catalog_event_integrity_operations')) as metric_3,
    (select count(*) from pg_proc as procedure join pg_namespace as namespace on namespace.oid = procedure.pronamespace where namespace.nspname in ('public', 'private') and (procedure.proname like '%diary%' or procedure.proname like '%concert%' or procedure.proname in ('create_catalog_event_post', 'list_catalog_event_posts', 'list_catalog_event_diaries', 'reserve_concert_photo', 'attach_concert_photo'))) as metric_4,
    (select count(*) from public.catalog_entities where origin::text in ('legacy_import', 'legacy_client')) as metric_5,
    (select count(*) from public.catalog_events) as metric_6,
    (select count(*) from public.catalog_event_attendance) as metric_7,
    (select count(*) from public.event_comments) as metric_8,
    (select count(*) from public.event_posts where published_at is not null) as metric_9,
    (select count(*) from public.post_comments) as metric_10,
    (select count(*) from public.post_media where status = 'ready') as metric_11,
    (select count(*) from private.catalog_event_notification_outbox) as metric_12,
    (select count(*) from public.social_activity_events) as metric_13,
    (select count(*) from storage.objects where bucket_id = 'images' and name like 'event-covers/%/cover.jpg') as event_cover_count;
")"

metrics="$(jq -er '
  (if type == "array" then .[0] else .rows[0] end) | [
    .metric_0,
    .metric_1,
    .metric_2,
    .metric_3,
    .metric_4,
    .metric_5,
    .metric_6,
    .metric_7,
    .metric_8,
    .metric_9,
    .metric_10,
    .metric_11,
    .metric_12,
    .metric_13,
    .event_cover_count
  ] | join("|")
' <<<"${metrics_json}")"

expected="24|23|13|0|0|0|10|37|12|10|10|12|5|73|6"
if [[ "$metrics" != "$expected" ]]; then
  echo "Local Supabase seed integrity check failed (expected ${expected}; received ${metrics})." >&2
  exit 1
fi

echo "Local Supabase community events, attendance, Posts, Comments, media, and catalog contracts verified."
