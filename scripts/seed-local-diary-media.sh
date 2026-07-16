#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null || {
  echo "jq is required to seed Local diary media." >&2
  exit 1
}

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
api_url=""
publishable_key=""

while IFS='=' read -r key quoted_value; do
  value="${quoted_value%\"}"
  value="${value#\"}"
  case "$key" in
    API_URL) api_url="$value" ;;
    PUBLISHABLE_KEY) publishable_key="$value" ;;
  esac
done < <(supabase status -o env)

if [[ "$api_url" != http://127.0.0.1:* || -z "$publishable_key" ]]; then
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
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/afterglow-stage.png" "$afterglow"
prepare_jpeg "$root_dir/ios/tunedIn/Resources/Artwork/midnight-theatre.png" "$midnight"

listener_token="$(sign_in listener)"
morgan_token="$(sign_in morgan)"

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

listener_diary="d4500000-0000-0000-0000-000000000001"
morgan_diary="d4500000-0000-0000-0000-000000000002"

seed_photo "$listener_token" "$listener_diary" \
  "d4600000-0000-0000-0000-000000000001" "$midnight" "Right before the encore."
seed_photo "$listener_token" "$listener_diary" \
  "d4600000-0000-0000-0000-000000000002" "$afterglow" "The last chorus outside."
seed_photo "$morgan_token" "$morgan_diary" \
  "d4600000-0000-0000-0000-000000000003" "$afterglow" "The quietest moment of the night."
seed_photo "$morgan_token" "$morgan_diary" \
  "d4600000-0000-0000-0000-000000000004" "$midnight" "That final run of songs."

echo "Seeded four Local diary photos through the production reservation and attachment path."
