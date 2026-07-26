#!/usr/bin/env bash
set -euo pipefail

readonly project_ref="dmrlpyxhqhunfndihvai"
readonly project_url="https://${project_ref}.supabase.co"
readonly callback_url="com.ethanherrera.tunedin://auth-callback"

email="${EMAIL:-}"

if [[ ! "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  echo "EMAIL must be a valid email-shaped Development test identity." >&2
  exit 1
fi

for command in curl jq pbcopy supabase; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

keys_json="$(supabase projects api-keys --project-ref "$project_ref" --reveal --output json)"
admin_key="$(jq -er '
  first(
    .[]
    | select(
        (.type == "secret" and .name == "default")
        or (.type == "legacy" and .name == "service_role")
      )
    | .api_key
  )
' <<<"$keys_json")"

request_body="$(jq -nc \
  --arg email "$email" \
  --arg redirect_to "$callback_url" \
  '{type: "magiclink", email: $email, redirect_to: $redirect_to}')"

response="$(curl --silent --show-error --fail \
  --request POST \
  --header "apikey: $admin_key" \
  --header "Authorization: Bearer $admin_key" \
  --header "Content-Type: application/json" \
  --data "$request_body" \
  "$project_url/auth/v1/admin/generate_link")"

token_hash="$(jq -er '.hashed_token' <<<"$response")"
returned_redirect="$(jq -er '.redirect_to' <<<"$response")"
if [[ "$returned_redirect" != "$callback_url" ]]; then
  echo "Supabase did not accept the tunedIn Development callback URL." >&2
  exit 1
fi

login_url="$(jq -nr \
  --arg callback_url "$callback_url" \
  --arg token_hash "$token_hash" \
  '$callback_url + "?token_hash=" + ($token_hash | @uri) + "&type=email"')"

printf '%s' "$login_url" | pbcopy
echo "A one-time tunedin-dev login link for $email was copied to the clipboard."
echo "Paste it into Safari on the test iPhone; it expires and must not be shared."
