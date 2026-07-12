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
    (select count(*) from public.comments as comment join public.concerts as concert on concert.id = comment.concert_id where comment.concert_id between 'd2000000-0000-0000-0000-000000000001'::uuid and 'd2000000-0000-0000-0000-000000000024'::uuid and comment.author_id <> concert.owner_id and not exists (select 1 from public.concert_collaborators as collaborator where collaborator.concert_id = concert.id and collaborator.profile_id = comment.author_id) and not exists (select 1 from public.relationships as relationship where relationship.status = 'accepted' and comment.author_id in (relationship.user_low_id, relationship.user_high_id) and concert.owner_id in (relationship.user_low_id, relationship.user_high_id)));
")"

expected="16|16|16|16|15|1|5|1|1|1|6|24|8|12|73|0|0"
if [[ "$metrics" != "$expected" ]]; then
  echo "Local Supabase seed integrity check failed (expected ${expected}; received ${metrics})." >&2
  exit 1
fi

echo "Local Supabase journey seed verified: 16 accounts, 24 concerts, 8 collaborations, 12 comments, and 73 activity events."
