#!/usr/bin/env bash
set -euo pipefail

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin"

cat >"$temporary_directory/bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
output_path=""
payload_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --request)
    method="$2"
    shift 2
    ;;
  --output)
    output_path="$2"
    shift 2
    ;;
  --data-binary)
    payload_path="${2#@}"
    shift 2
    ;;
  *)
    shift
    ;;
  esac
done

if [[ "$method" == "PATCH" ]]; then
  STATE_PATH="$FAKE_AUTH_STATE" PAYLOAD_PATH="$payload_path" python3 <<'PY'
import json
import os

with open(os.environ["STATE_PATH"], encoding="utf-8") as source:
    state = json.load(source)
with open(os.environ["PAYLOAD_PATH"], encoding="utf-8") as source:
    state.update(json.load(source))
with open(os.environ["STATE_PATH"], "w", encoding="utf-8") as output:
    json.dump(state, output)
PY
fi

cp "$FAKE_AUTH_STATE" "$output_path"
printf '200'
FAKE_CURL
chmod +x "$temporary_directory/bin/curl"

cat >"$temporary_directory/state.json" <<'JSON'
{
  "external_anonymous_users_enabled": false,
  "external_apple_enabled": false,
  "external_apple_client_id": "",
  "external_email_enabled": true,
  "external_google_enabled": false,
  "external_google_client_id": "",
  "external_google_additional_client_ids": "",
  "external_google_skip_nonce_check": true,
  "external_phone_enabled": false,
  "security_manual_linking_enabled": false
}
JSON

export PATH="$temporary_directory/bin:$PATH"
export FAKE_AUTH_STATE="$temporary_directory/state.json"
export SUPABASE_ACCESS_TOKEN="sbp_auth_contract_test"
export SUPABASE_PROJECT_REF="ywsuusbnnlvgeofbbbjx"
export GOOGLE_IOS_CLIENT_ID="123456-staging-ios.apps.googleusercontent.com"
export GOOGLE_SERVER_CLIENT_ID="123456-staging-server.apps.googleusercontent.com"
export GOOGLE_REVERSED_CLIENT_ID="com.googleusercontent.apps.123456-staging-ios"
export GOOGLE_SERVER_CLIENT_SECRET="test-secret-never-printed"
export GITHUB_ACTIONS="true"
export GITHUB_REF="refs/heads/main"
export TUNEDIN_PROMOTION_ENVIRONMENT="Staging"

./scripts/staging-auth.sh plan >/dev/null
./scripts/staging-auth.sh prepare >/dev/null

if ./scripts/staging-auth.sh verify >/dev/null 2>&1; then
  printf 'Staging Auth verification accepted email before finalization.\n' >&2
  exit 1
fi

./scripts/staging-auth.sh finalize >/dev/null
./scripts/staging-auth.sh verify >/dev/null

if ! python3 - "$FAKE_AUTH_STATE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    state = json.load(source)
assert state["external_apple_enabled"] is True
assert state["external_google_enabled"] is True
assert state["external_email_enabled"] is False
assert state["external_google_skip_nonce_check"] is False
PY
then
  printf 'Staging Auth final state did not match the native-only contract.\n' >&2
  exit 1
fi

if SUPABASE_PROJECT_REF="dmrlpyxhqhunfndihvai" ./scripts/staging-auth.sh plan >/dev/null 2>&1; then
  printf 'Staging Auth helper accepted the Development project.\n' >&2
  exit 1
fi

printf 'Staging Auth preparation and finalization contract is valid.\n'
