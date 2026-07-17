#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null || { echo "jq is required to seed Local Post media." >&2; exit 1; }
command -v psql >/dev/null || { echo "psql is required to seed Local feed activity." >&2; exit 1; }

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
api_url=""
publishable_key=""
db_url=""
while IFS='=' read -r key quoted_value; do
  value="${quoted_value%\"}"
  value="${value#\"}"
  case "$key" in
    API_URL) api_url="$value" ;;
    PUBLISHABLE_KEY) publishable_key="$value" ;;
    DB_URL) db_url="$value" ;;
  esac
done < <(supabase status -o env)

if [[ "$api_url" != http://127.0.0.1:* || -z "$publishable_key" || -z "$db_url" ]]; then
  echo "Post media fixtures run only against Local Supabase." >&2
  exit 1
fi

sign_in() {
  curl --silent --show-error --fail "$api_url/auth/v1/token?grant_type=password" \
    -H "apikey: $publishable_key" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1@tunedin.local\",\"password\":\"tunedIn-local-seeded-account\"}" \
    | jq -er '.access_token'
}

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

prepare_jpeg() {
  local source="$1"
  local destination="$2"
  if command -v sips >/dev/null 2>&1; then
    sips -s format jpeg -s formatOptions 84 -Z 1400 "$source" --out "$destination" >/dev/null
  elif command -v convert >/dev/null 2>&1; then
    convert "$source" -resize '1400x1400>' -quality 84 "$destination"
  else
    cp "$source" "$destination"
  fi
}

afterglow="$temporary_dir/afterglow.jpg"
midnight="$temporary_dir/midnight.jpg"
neon_orchard="$temporary_dir/neon-orchard.jpg"
blue_hour_club="$temporary_dir/blue-hour-club.jpg"
juniper_static="$temporary_dir/juniper-static.jpg"
velvet_transit="$temporary_dir/velvet-transit.jpg"
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/afterglow-stage.png" "$afterglow"
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/midnight-theatre.png" "$midnight"
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/neon-orchard-stage.png" "$neon_orchard"
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/blue-hour-club-stage.png" "$blue_hour_club"
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/juniper-static-stage.png" "$juniper_static"
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/velvet-transit-stage.png" "$velvet_transit"

seed_media() {
  local token="$1"
  local post_id="$2"
  local media_id="$3"
  local source="$4"
  local path="posts/$post_id/media/$media_id.jpg"
  local reservation
  reservation="$(curl --silent --show-error --fail -X POST \
    "$api_url/rest/v1/rpc/reserve_post_media" \
    -H "apikey: $publishable_key" -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    --data "{\"p_post_id\":\"$post_id\",\"p_media_id\":\"$media_id\"}")"
  [[ "$(jq -r '.object_path' <<<"$reservation")" == "$path" ]] || {
    echo "Post media reservation returned an unexpected path." >&2
    exit 1
  }
  if [[ "$(jq -r '.status' <<<"$reservation")" == "ready" ]]; then return; fi
  curl --silent --show-error --fail -X POST "$api_url/storage/v1/object/images/$path" \
    -H "apikey: $publishable_key" -H "Authorization: Bearer $token" \
    -H 'Content-Type: image/jpeg' --data-binary @"$source" >/dev/null
  curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/attach_post_media" \
    -H "apikey: $publishable_key" -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' --data "{\"p_media_id\":\"$media_id\"}" >/dev/null
}

seed_event_cover() {
  local token="$1"
  local event_id="$2"
  local source="$3"
  local path="event-covers/$event_id/cover.jpg"
  curl --silent --show-error --fail -X POST "$api_url/storage/v1/object/images/$path" \
    -H "apikey: $publishable_key" -H "Authorization: Bearer $token" \
    -H 'Content-Type: image/jpeg' --data-binary @"$source" >/dev/null
  curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/set_catalog_event_cover" \
    -H "apikey: $publishable_key" -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' --data "{\"p_event_id\":\"$event_id\"}" >/dev/null
}

listener_token="$(sign_in listener)"
morgan_token="$(sign_in morgan)"
remi_token="$(sign_in remi)"
kai_token="$(sign_in kai)"
rowan_token="$(sign_in rowan)"
mia_token="$(sign_in mia)"
leo_token="$(sign_in leo)"
nia_token="$(sign_in nia)"
owen_token="$(sign_in owen)"
zoe_token="$(sign_in zoe)"

seed_media "$listener_token" d4500000-0000-0000-0000-000000000001 d4600000-0000-0000-0000-000000000001 "$midnight"
seed_media "$listener_token" d4500000-0000-0000-0000-000000000001 d4600000-0000-0000-0000-000000000002 "$afterglow"
seed_media "$morgan_token" d4500000-0000-0000-0000-000000000002 d4600000-0000-0000-0000-000000000003 "$afterglow"
seed_media "$morgan_token" d4500000-0000-0000-0000-000000000002 d4600000-0000-0000-0000-000000000004 "$midnight"
seed_media "$remi_token" d4500000-0000-0000-0000-000000000003 d4600000-0000-0000-0000-000000000005 "$midnight"
seed_media "$kai_token" d4500000-0000-0000-0000-000000000004 d4600000-0000-0000-0000-000000000006 "$afterglow"
seed_media "$rowan_token" d4500000-0000-0000-0000-000000000005 d4600000-0000-0000-0000-000000000007 "$midnight"
seed_media "$mia_token" d4500000-0000-0000-0000-000000000006 d4600000-0000-0000-0000-000000000008 "$afterglow"
seed_media "$leo_token" d4500000-0000-0000-0000-000000000007 d4600000-0000-0000-0000-000000000009 "$midnight"
seed_media "$nia_token" d4500000-0000-0000-0000-000000000008 d4600000-0000-0000-0000-000000000010 "$afterglow"
seed_media "$owen_token" d4500000-0000-0000-0000-000000000009 d4600000-0000-0000-0000-000000000011 "$midnight"
seed_media "$zoe_token" d4500000-0000-0000-0000-000000000010 d4600000-0000-0000-0000-000000000012 "$afterglow"

# Events 003-006 intentionally retain the no-upload fallback.
seed_event_cover "$listener_token" d4000000-0000-0000-0000-000000000001 "$afterglow"
seed_event_cover "$morgan_token" d4000000-0000-0000-0000-000000000002 "$midnight"
seed_event_cover "$listener_token" d4000000-0000-0000-0000-000000000007 "$neon_orchard"
seed_event_cover "$listener_token" d4000000-0000-0000-0000-000000000008 "$blue_hour_club"
seed_event_cover "$listener_token" d4000000-0000-0000-0000-000000000009 "$juniper_static"
seed_event_cover "$listener_token" d4000000-0000-0000-0000-000000000010 "$velvet_transit"

# Keep the newest feed page visually varied after the deterministic uploads.
psql "$db_url" -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
with fixture (id, actor_id, event_id, audience, fixture_position) as (
  values
    ('d4100000-0000-0000-0000-000000000125'::uuid, 'd1000000-0000-0000-0000-000000000002'::uuid, 'd4000000-0000-0000-0000-000000000007'::uuid, 'community', 5),
    ('d4100000-0000-0000-0000-000000000126'::uuid, 'd1000000-0000-0000-0000-000000000017'::uuid, 'd4000000-0000-0000-0000-000000000007'::uuid, 'friends', 1),
    ('d4100000-0000-0000-0000-000000000127'::uuid, 'd1000000-0000-0000-0000-000000000018'::uuid, 'd4000000-0000-0000-0000-000000000008'::uuid, 'community', 6),
    ('d4100000-0000-0000-0000-000000000128'::uuid, 'd1000000-0000-0000-0000-000000000019'::uuid, 'd4000000-0000-0000-0000-000000000008'::uuid, 'friends', 2),
    ('d4100000-0000-0000-0000-000000000129'::uuid, 'd1000000-0000-0000-0000-000000000020'::uuid, 'd4000000-0000-0000-0000-000000000009'::uuid, 'community', 7),
    ('d4100000-0000-0000-0000-000000000130'::uuid, 'd1000000-0000-0000-0000-000000000021'::uuid, 'd4000000-0000-0000-0000-000000000009'::uuid, 'friends', 3),
    ('d4100000-0000-0000-0000-000000000131'::uuid, 'd1000000-0000-0000-0000-000000000022'::uuid, 'd4000000-0000-0000-0000-000000000010'::uuid, 'community', 8),
    ('d4100000-0000-0000-0000-000000000132'::uuid, 'd1000000-0000-0000-0000-000000000023'::uuid, 'd4000000-0000-0000-0000-000000000010'::uuid, 'friends', 4)
)
insert into public.social_activity_events (id, actor_id, action, event_id, metadata, occurred_at)
select id, actor_id, 'marked_going', event_id, jsonb_build_object('audience', audience),
  statement_timestamp() + fixture_position * interval '1 millisecond'
from fixture;
SQL

echo "Seeded twelve Local Post photos and six event covers through production Storage/RPC paths."
