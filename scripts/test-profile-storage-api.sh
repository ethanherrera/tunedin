#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null || { echo "jq is required for the Storage API test." >&2; exit 1; }

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
local_supabase_helper="${root_dir}/scripts/worktree-local-supabase.sh"

api_url=""
publishable_key=""
while IFS='=' read -r key quoted_value; do
  value="${quoted_value%\"}"
  value="${value#\"}"
  case "$key" in
    API_URL) api_url="$value" ;;
    PUBLISHABLE_KEY) publishable_key="$value" ;;
  esac
done < <("${local_supabase_helper}" status-env)

if [[ "$api_url" != http://127.0.0.1:* || -z "$publishable_key" ]]; then
  echo "Storage integration tests run only against Local Supabase. Run 'make local-db-reset'." >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
jpeg_base64='/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAEf/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q=='
if [[ "$(uname -s)" == Darwin ]]; then
  printf '%s' "$jpeg_base64" | base64 -D > "$temporary_dir/photo.jpg"
else
  printf '%s' "$jpeg_base64" | base64 --decode > "$temporary_dir/photo.jpg"
fi
dd if=/dev/zero of="$temporary_dir/oversized.jpg" bs=1048576 count=3 status=none

sign_in() {
  curl --silent --show-error --fail "$api_url/auth/v1/token?grant_type=password" \
    -H "apikey: $publishable_key" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1@tunedin.local\",\"password\":\"tunedIn-local-seeded-account\"}" \
    | jq -er '.access_token'
}

request_status() {
  curl --silent --output /dev/null --write-out '%{http_code}' "$@"
}

listener_token="$(sign_in listener)"
morgan_token="$(sign_in morgan)"
listener_id="d1000000-0000-0000-0000-000000000001"
morgan_id="d1000000-0000-0000-0000-000000000002"
avatar_path="avatars/$listener_id/profile.jpg"

status="$(request_status -X POST "$api_url/storage/v1/object/images/$avatar_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: image/jpeg' -H 'x-upsert: true' --data-binary @"$temporary_dir/photo.jpg")"
[[ "$status" == 200 ]] || { echo "Owner avatar upload failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/rest/v1/rpc/set_profile_avatar" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' --data '{}')"
[[ "$status" == 200 ]] || { echo "Avatar attachment failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/storage/v1/object/sign/images/$avatar_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" \
  -H 'Content-Type: application/json' --data '{"expiresIn":3600}')"
[[ "$status" == 200 ]] || { echo "Authorized avatar read failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/storage/v1/object/images/$avatar_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" \
  -H 'Content-Type: image/jpeg' -H 'x-upsert: true' --data-binary @"$temporary_dir/photo.jpg")"
[[ "$status" == 400 || "$status" == 401 || "$status" == 403 ]] || {
  echo "Cross-user avatar mutation unexpectedly returned HTTP $status." >&2; exit 1;
}
status="$(request_status -X POST "$api_url/storage/v1/object/images/avatars/$morgan_id/profile.jpg" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" \
  -H 'Content-Type: image/png' --data-binary @"$temporary_dir/photo.jpg")"
[[ "$status" == 400 || "$status" == 415 ]] || { echo "Avatar MIME rejection returned HTTP $status." >&2; exit 1; }

post_id="d4500000-0000-0000-0000-000000000001"
media_id="da000000-0000-0000-0000-000000000099"
media_path="posts/$post_id/media/$media_id.jpg"
reserve_body="$(curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/reserve_post_media" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' \
  --data "{\"p_post_id\":\"$post_id\",\"p_media_id\":\"$media_id\"}")"
[[ "$(jq -r '.object_path' <<<"$reserve_body")" == "$media_path" ]] || {
  echo "Post media reservation did not return the fixed path." >&2; exit 1;
}
retry_reserve="$(curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/reserve_post_media" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' \
  --data "{\"p_post_id\":\"$post_id\",\"p_media_id\":\"$media_id\"}")"
[[ "$(jq -r '.id' <<<"$retry_reserve")" == "$media_id" ]] || {
  echo "Post media reservation retry did not reuse the media ID." >&2; exit 1;
}
status="$(request_status -X POST "$api_url/storage/v1/object/images/$media_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: image/jpeg' --data-binary @"$temporary_dir/photo.jpg")"
[[ "$status" == 200 ]] || { echo "Reserved Post media upload failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/rest/v1/rpc/attach_post_media" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' --data "{\"p_media_id\":\"$media_id\"}")"
[[ "$status" == 200 ]] || { echo "Post media attachment failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/storage/v1/object/sign/images/$media_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" \
  -H 'Content-Type: application/json' --data '{"expiresIn":3600}')"
[[ "$status" == 200 ]] || { echo "Friend Post media read failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/storage/v1/object/sign/images/$media_path" \
  -H "apikey: $publishable_key" -H 'Content-Type: application/json' --data '{"expiresIn":3600}')"
[[ "$status" == 400 || "$status" == 401 || "$status" == 403 ]] || {
  echo "Anonymous Post media read unexpectedly returned HTTP $status." >&2; exit 1;
}
status="$(request_status -X POST "$api_url/storage/v1/object/images/posts/$post_id/media/da000000-0000-0000-0000-000000000098.jpg" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" \
  -H 'Content-Type: image/jpeg' --data-binary @"$temporary_dir/photo.jpg")"
[[ "$status" == 400 || "$status" == 401 || "$status" == 403 ]] || {
  echo "Friend Post media mutation unexpectedly returned HTTP $status." >&2; exit 1;
}

oversized_id="da000000-0000-0000-0000-000000000096"
oversized_path="posts/$post_id/media/$oversized_id.jpg"
curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/reserve_post_media" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' \
  --data "{\"p_post_id\":\"$post_id\",\"p_media_id\":\"$oversized_id\"}" >/dev/null
status="$(request_status -X POST "$api_url/storage/v1/object/images/$oversized_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: image/jpeg' --data-binary @"$temporary_dir/oversized.jpg")"
[[ "$status" == 200 ]] || { echo "Oversized Post fixture upload failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/rest/v1/rpc/attach_post_media" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' --data "{\"p_media_id\":\"$oversized_id\"}")"
[[ "$status" == 400 ]] || { echo "Oversized Post media attachment returned HTTP $status." >&2; exit 1; }

echo "Local Storage API verified: avatar and Post media authorization, signed reads, idempotent reservation, MIME, and size limits."
