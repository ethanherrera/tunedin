#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null || {
  echo "jq is required to seed Local diary media." >&2
  exit 1
}
command -v psql >/dev/null || {
  echo "psql is required to normalize Local diary media activity." >&2
  exit 1
}

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
  echo "Diary media fixtures run only against Local Supabase." >&2
  exit 1
fi

sign_in() {
  curl --silent --show-error --fail "$api_url/auth/v1/token?grant_type=password" \
    -H "apikey: $publishable_key" \
    -H 'Content-Type: application/json' \
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
    # The Storage fixture contract checks the declared MIME type. Apple clients
    # also decode by file contents, so retaining the PNG bytes is a safe CI-only
    # fallback when a Linux runner has no image conversion utility.
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

seed_photo() {
  local token="$1"
  local diary_id="$2"
  local photo_id="$3"
  local source="$4"
  local caption="$5"
  local path="concerts/$diary_id/album/$photo_id.jpg"
  local reservation

  reservation="$(curl --silent --show-error --fail -X POST \
    "$api_url/rest/v1/rpc/reserve_concert_photo" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    --data "{\"p_concert_id\":\"$diary_id\",\"p_photo_id\":\"$photo_id\"}")"

  if [[ "$(jq -r '.status' <<<"$reservation")" == "ready" ]]; then
    return
  fi

  curl --silent --show-error --fail -X POST \
    "$api_url/storage/v1/object/images/$path" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: image/jpeg' \
    --data-binary @"$source" >/dev/null

  curl --silent --show-error --fail -X POST \
    "$api_url/rest/v1/rpc/attach_concert_photo" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    --data "{\"p_photo_id\":\"$photo_id\"}" >/dev/null

  curl --silent --show-error --fail -X POST \
    "$api_url/rest/v1/rpc/update_concert_photo_caption" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    --data "$(jq -cn --arg photo "$photo_id" --arg caption "$caption" \
      '{p_photo_id:$photo,p_caption:$caption}')" >/dev/null
}

seed_event_cover() {
  local token="$1"
  local event_id="$2"
  local source="$3"
  local path="event-covers/$event_id/cover.jpg"

  curl --silent --show-error --fail -X POST \
    "$api_url/storage/v1/object/images/$path" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: image/jpeg' \
    --data-binary @"$source" >/dev/null

  curl --silent --show-error --fail -X POST \
    "$api_url/rest/v1/rpc/set_catalog_event_cover" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    --data "{\"p_event_id\":\"$event_id\"}" >/dev/null
}

listener_diary="d4500000-0000-0000-0000-000000000001"
morgan_diary="d4500000-0000-0000-0000-000000000002"
remi_diary="d4500000-0000-0000-0000-000000000003"
kai_diary="d4500000-0000-0000-0000-000000000004"
rowan_diary="d4500000-0000-0000-0000-000000000005"
mia_diary="d4500000-0000-0000-0000-000000000006"
leo_diary="d4500000-0000-0000-0000-000000000007"
nia_diary="d4500000-0000-0000-0000-000000000008"
owen_diary="d4500000-0000-0000-0000-000000000009"
zoe_diary="d4500000-0000-0000-0000-000000000010"

seed_photo "$listener_token" "$listener_diary" \
  "d4600000-0000-0000-0000-000000000001" "$midnight" "Right before the encore."
seed_photo "$listener_token" "$listener_diary" \
  "d4600000-0000-0000-0000-000000000002" "$afterglow" "The last chorus outside."
seed_photo "$morgan_token" "$morgan_diary" \
  "d4600000-0000-0000-0000-000000000003" "$afterglow" "The quietest moment of the night."
seed_photo "$morgan_token" "$morgan_diary" \
  "d4600000-0000-0000-0000-000000000004" "$midnight" "That final run of songs."
seed_photo "$remi_token" "$remi_diary" \
  "d4600000-0000-0000-0000-000000000005" "$midnight" "The crowd before the first chorus."
seed_photo "$kai_token" "$kai_diary" \
  "d4600000-0000-0000-0000-000000000006" "$afterglow" "Lights during the final song."
seed_photo "$rowan_token" "$rowan_diary" \
  "d4600000-0000-0000-0000-000000000007" "$midnight" "When the set started getting loud."
seed_photo "$mia_token" "$mia_diary" \
  "d4600000-0000-0000-0000-000000000008" "$afterglow" "The room from the balcony."
seed_photo "$leo_token" "$leo_diary" \
  "d4600000-0000-0000-0000-000000000009" "$midnight" "The surprise song."
seed_photo "$nia_token" "$nia_diary" \
  "d4600000-0000-0000-0000-000000000010" "$afterglow" "A wonderfully messy night."
seed_photo "$owen_token" "$owen_diary" \
  "d4600000-0000-0000-0000-000000000011" "$midnight" "Right in the middle of the encore."
seed_photo "$zoe_token" "$zoe_diary" \
  "d4600000-0000-0000-0000-000000000012" "$afterglow" "The transition into the closer."

# Preserve the no-upload community fallback on events 003-006. The remaining
# six events prove both existing community uploads and visually distinct new
# concerts in feed, discovery, detail, plans, and profile collections.
seed_event_cover "$listener_token" "d4000000-0000-0000-0000-000000000001" "$afterglow"
seed_event_cover "$morgan_token" "d4000000-0000-0000-0000-000000000002" "$midnight"
seed_event_cover "$listener_token" "d4000000-0000-0000-0000-000000000007" "$neon_orchard"
seed_event_cover "$listener_token" "d4000000-0000-0000-0000-000000000008" "$blue_hour_club"
seed_event_cover "$listener_token" "d4000000-0000-0000-0000-000000000009" "$juniper_static"
seed_event_cover "$listener_token" "d4000000-0000-0000-0000-000000000010" "$velvet_transit"

# Production upload RPCs correctly create immutable media activity at upload
# time. Create the deterministic varied upcoming-event activity afterward so
# the first Local feed screen represents four concerts rather than letting
# twelve fixture uploads for the packed past concert monopolize it.
psql "$db_url" -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
with fixture (
  id,
  actor_id,
  event_id,
  audience,
  fixture_position
) as (
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
insert into public.social_activity_events (
  id,
  actor_id,
  action,
  event_id,
  metadata,
  occurred_at
)
select
  fixture.id,
  fixture.actor_id,
  'marked_going',
  fixture.event_id,
  jsonb_build_object('audience', fixture.audience),
  statement_timestamp() + fixture.fixture_position * interval '1 millisecond'
from fixture;
SQL

echo "Seeded twelve Local post photos and six event covers through production Storage/RPC paths."
