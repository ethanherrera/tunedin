#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null || { echo "jq is required for the Storage API test." >&2; exit 1; }

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
  echo "Storage integration tests run only against Local Supabase. Run 'make local-db-reset'." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
if [[ "$(uname -s)" == Darwin ]]; then
  printf '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAEf/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==' | base64 -D > "$tmp_dir/avatar.jpg"
else
  printf '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAEf/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==' | base64 --decode > "$tmp_dir/avatar.jpg"
fi
dd if=/dev/zero of="$tmp_dir/oversized.jpg" bs=1048576 count=6 status=none

sign_in() {
  curl --silent --show-error --fail "$api_url/auth/v1/token?grant_type=password" \
    -H "apikey: $publishable_key" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1@tunedin.local\",\"password\":\"tunedIn-local-seeded-account\"}" | jq -er '.access_token'
}

listener_token="$(sign_in listener)"
morgan_token="$(sign_in morgan)"
listener_id="d1000000-0000-0000-0000-000000000001"
morgan_id="d1000000-0000-0000-0000-000000000002"
path="avatars/$listener_id/profile.jpg"

request_status() {
  curl --silent --output /dev/null --write-out '%{http_code}' "$@"
}

status="$(request_status -X POST "$api_url/storage/v1/object/images/$path" -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" -H 'Content-Type: image/jpeg' -H 'x-upsert: true' --data-binary @"$tmp_dir/avatar.jpg")"
[[ "$status" == 200 ]] || { echo "Owner avatar upload failed with HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/rest/v1/rpc/set_profile_avatar" -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" -H 'Content-Type: application/json' --data '{}')"
[[ "$status" == 200 ]] || { echo "Avatar attachment failed with HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/storage/v1/object/sign/images/$path" -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" -H 'Content-Type: application/json' --data '{"expiresIn":3600}')"
[[ "$status" == 200 ]] || { echo "Authorized signed read failed with HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/storage/v1/object/sign/images/$path" -H "apikey: $publishable_key" -H 'Content-Type: application/json' --data '{"expiresIn":3600}')"
[[ "$status" == 400 || "$status" == 401 || "$status" == 403 ]] || { echo "Anonymous signed read unexpectedly returned HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/storage/v1/object/images/$path" -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" -H 'Content-Type: image/jpeg' -H 'x-upsert: true' --data-binary @"$tmp_dir/avatar.jpg")"
[[ "$status" == 400 || "$status" == 401 || "$status" == 403 ]] || { echo "Cross-user mutation unexpectedly returned HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/storage/v1/object/images/avatars/$morgan_id/profile.jpg" -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" -H 'Content-Type: image/png' --data-binary @"$tmp_dir/avatar.jpg")"
[[ "$status" == 400 || "$status" == 415 ]] || { echo "MIME rejection returned HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/storage/v1/object/images/avatars/$morgan_id/profile.jpg" -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" -H 'Content-Type: image/jpeg' --data-binary @"$tmp_dir/oversized.jpg")"
[[ "$status" == 400 || "$status" == 413 ]] || { echo "Size rejection returned HTTP $status." >&2; exit 1; }

status="$(request_status -X DELETE "$api_url/storage/v1/object/images" -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" -H 'Content-Type: application/json' --data "{\"prefixes\":[\"$path\"]}")"
[[ "$status" == 200 ]] || { echo "Owner avatar deletion failed with HTTP $status." >&2; exit 1; }

# Album uploads are new objects, so they intentionally use INSERT semantics
# without x-upsert. This exercises the same request shape as the iOS client.
album_concert_id="d2000000-0000-0000-0000-000000000006"
album_photo_id="da000000-0000-0000-0000-000000000099"
album_path="concerts/$album_concert_id/album/$album_photo_id.jpg"
reserve_body="$(curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/reserve_concert_photo" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' \
  --data "{\"p_concert_id\":\"$album_concert_id\",\"p_photo_id\":\"$album_photo_id\"}")"
[[ "$(jq -r '.object_path' <<<"$reserve_body")" == "$album_path" ]] || {
  echo "Album reservation did not return the fixed path." >&2; exit 1;
}

status="$(request_status -X POST "$api_url/storage/v1/object/images/$album_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: image/jpeg' --data-binary @"$tmp_dir/avatar.jpg")"
[[ "$status" == 200 ]] || { echo "Reserved album upload failed with HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/rest/v1/rpc/attach_concert_photo" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' --data "{\"p_photo_id\":\"$album_photo_id\"}")"
[[ "$status" == 200 ]] || { echo "Album attachment failed with HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/storage/v1/object/sign/images/$album_path" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" \
  -H 'Content-Type: application/json' --data '{"expiresIn":3600}')"
[[ "$status" == 200 ]] || { echo "Friend album signed read failed with HTTP $status." >&2; exit 1; }

status="$(request_status -X POST "$api_url/storage/v1/object/images/concerts/$album_concert_id/album/da000000-0000-0000-0000-000000000098.jpg" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $morgan_token" \
  -H 'Content-Type: image/jpeg' --data-binary @"$tmp_dir/avatar.jpg")"
[[ "$status" == 400 || "$status" == 401 || "$status" == 403 ]] || {
  echo "Friend album upload unexpectedly returned HTTP $status." >&2; exit 1;
}

delete_path="$(curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/prepare_concert_photo_deletion" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' --data "{\"p_photo_id\":\"$album_photo_id\"}" | jq -r '.')"
[[ "$delete_path" == "$album_path" ]] || { echo "Album deletion returned the wrong path." >&2; exit 1; }
status="$(request_status -X DELETE "$api_url/storage/v1/object/images" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' --data "{\"prefixes\":[\"$album_path\"]}")"
[[ "$status" == 200 ]] || { echo "Album object deletion failed with HTTP $status." >&2; exit 1; }
status="$(request_status -X POST "$api_url/rest/v1/rpc/finalize_concert_photo_deletion" \
  -H "apikey: $publishable_key" -H "Authorization: Bearer $listener_token" \
  -H 'Content-Type: application/json' --data "{\"p_photo_id\":\"$album_photo_id\"}")"
[[ "$status" == 200 || "$status" == 204 ]] || { echo "Album deletion finalization failed with HTTP $status." >&2; exit 1; }

echo "Local Storage API verified: profile and album lifecycles, signed reads, mutation denial, MIME and size limits."
