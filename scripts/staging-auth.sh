#!/usr/bin/env bash
set -euo pipefail

readonly approved_staging_project_ref="ywsuusbnnlvgeofbbbjx"
readonly development_project_ref="dmrlpyxhqhunfndihvai"
readonly apple_client_id="com.ethanherrera.tunedin.staging"
readonly supabase_api="https://api.supabase.com"

usage() {
  cat <<'USAGE'
Usage: ./scripts/staging-auth.sh <plan|prepare|finalize|verify>

Required environment:
  SUPABASE_PROJECT_REF          Dedicated tunedin-staging project ref.
  GOOGLE_IOS_CLIENT_ID         Google iOS OAuth client for the Staging bundle ID.
  GOOGLE_SERVER_CLIENT_ID      Google Web OAuth client used to mint backend ID tokens.
  GOOGLE_REVERSED_CLIENT_ID    Reversed form of GOOGLE_IOS_CLIENT_ID.

Required for prepare:
  GOOGLE_SERVER_CLIENT_SECRET  Google Web OAuth client secret.

SUPABASE_ACCESS_TOKEN is required in CI. On macOS, the authenticated Supabase CLI
Keychain item is used when the environment variable is absent.

Commands:
  plan      Show non-secret drift from the final Staging Auth contract.
  prepare   Enable native Apple/Google before backend and TestFlight deployment.
  finalize  Disable email after TestFlight upload succeeds.
  verify    Fail unless the final native-only Staging Auth contract matches.
USAGE
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_protected_workflow() {
  if [[ "${GITHUB_ACTIONS:-}" != "true" || "${GITHUB_REF:-}" != "refs/heads/main" ]]; then
    fail "Staging Auth may be changed only by the protected GitHub workflow from main."
  fi
  if [[ "${TUNEDIN_PROMOTION_ENVIRONMENT:-}" != "Staging" ]]; then
    fail "The protected workflow must explicitly identify the Staging environment."
  fi
}

require_configuration() {
  local project_ref="${SUPABASE_PROJECT_REF:-}"
  if [[ "$project_ref" == "$development_project_ref" ]]; then
    fail "Refusing to configure Auth on the Development Supabase project."
  fi
  if [[ "$project_ref" != "$approved_staging_project_ref" ]]; then
    fail "SUPABASE_PROJECT_REF must identify the approved tunedin-staging project."
  fi

  local ios_client_id="${GOOGLE_IOS_CLIENT_ID:-}"
  local server_client_id="${GOOGLE_SERVER_CLIENT_ID:-}"
  local reversed_client_id="${GOOGLE_REVERSED_CLIENT_ID:-}"
  if [[ ! "$ios_client_id" =~ ^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$ ]]; then
    fail "GOOGLE_IOS_CLIENT_ID is not a valid Google OAuth client ID."
  fi
  if [[ ! "$server_client_id" =~ ^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$ ]]; then
    fail "GOOGLE_SERVER_CLIENT_ID is not a valid Google OAuth client ID."
  fi

  local ios_prefix="${ios_client_id%.apps.googleusercontent.com}"
  if [[ "$reversed_client_id" != "com.googleusercontent.apps.${ios_prefix}" ]]; then
    fail "GOOGLE_REVERSED_CLIENT_ID does not match GOOGLE_IOS_CLIENT_ID."
  fi
}

access_token() {
  if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    printf '%s' "$SUPABASE_ACCESS_TOKEN"
    return
  fi
  if command -v security >/dev/null 2>&1; then
    security find-generic-password -a supabase -s "Supabase CLI" -w 2>/dev/null && return
  fi
  fail "SUPABASE_ACCESS_TOKEN is required and no authenticated Supabase CLI Keychain item was found."
}

request() {
  local method="$1"
  local output_path="$2"
  local payload_path="${3:-}"
  local token
  token="$(access_token)"
  local curl_config="$temporary_directory/curl-config"
  printf 'header = "Authorization: Bearer %s"\n' "$token" >"$curl_config"
  printf '%s\n' 'header = "Content-Type: application/json"' >>"$curl_config"
  chmod 600 "$curl_config"

  local status
  if [[ -n "$payload_path" ]]; then
    status="$(curl --silent --show-error --config "$curl_config" \
      --request "$method" --data-binary "@$payload_path" \
      --output "$output_path" --write-out '%{http_code}' \
      "$supabase_api/v1/projects/$approved_staging_project_ref/config/auth")"
  else
    status="$(curl --silent --show-error --config "$curl_config" \
      --request "$method" --output "$output_path" --write-out '%{http_code}' \
      "$supabase_api/v1/projects/$approved_staging_project_ref/config/auth")"
  fi
  if [[ ! "$status" =~ ^2 ]]; then
    fail "Supabase Auth configuration request failed with HTTP $status."
  fi
}

write_payload() {
  local phase="$1"
  local output_path="$2"
  PHASE="$phase" APPLE_CLIENT_ID="$apple_client_id" python3 - "$output_path" <<'PY'
import json
import os
import sys

payload = {
    "external_anonymous_users_enabled": False,
    "external_apple_enabled": True,
    "external_apple_client_id": os.environ["APPLE_CLIENT_ID"],
    "external_google_enabled": True,
    "external_google_client_id": ",".join([
        os.environ["GOOGLE_SERVER_CLIENT_ID"],
        os.environ["GOOGLE_IOS_CLIENT_ID"],
    ]),
    "external_google_skip_nonce_check": False,
    "external_phone_enabled": False,
    "security_manual_linking_enabled": False,
}
if os.environ["PHASE"] == "prepare":
    secret = os.environ.get("GOOGLE_SERVER_CLIENT_SECRET", "")
    if not secret:
        raise SystemExit("GOOGLE_SERVER_CLIENT_SECRET is required for provider preparation.")
    payload["external_google_secret"] = secret
elif os.environ["PHASE"] == "final":
    payload["external_email_enabled"] = False
else:
    raise SystemExit("Unknown Staging Auth payload phase.")

with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(payload, output, separators=(",", ":"))
PY
  chmod 600 "$output_path"
}

check_contract() {
  local response_path="$1"
  local phase="$2"
  PHASE="$phase" APPLE_CLIENT_ID="$apple_client_id" python3 - "$response_path" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    actual = json.load(source)

expected = {
    "external_anonymous_users_enabled": False,
    "external_apple_enabled": True,
    "external_apple_client_id": os.environ["APPLE_CLIENT_ID"],
    "external_google_enabled": True,
    "external_google_client_id": ",".join([
        os.environ["GOOGLE_SERVER_CLIENT_ID"],
        os.environ["GOOGLE_IOS_CLIENT_ID"],
    ]),
    "external_google_skip_nonce_check": False,
    "external_phone_enabled": False,
    "security_manual_linking_enabled": False,
}
if os.environ["PHASE"] == "final":
    expected["external_email_enabled"] = False

drift = []
for key, value in expected.items():
    if actual.get(key) != value:
        drift.append(f"{key}: expected {value!r}, found {actual.get(key)!r}")

if drift:
    print("Staging Auth drift:")
    for item in drift:
        print(f"  - {item}")
    raise SystemExit(1)

print(f"Staging Auth {os.environ['PHASE']} contract matches.")
PY
}

command="${1:-}"
if [[ "$command" != "plan" && "$command" != "prepare" && "$command" != "finalize" && "$command" != "verify" ]]; then
  usage >&2
  exit 1
fi

require_configuration
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
response_path="$temporary_directory/auth-response.json"

case "$command" in
plan)
  request GET "$response_path"
  if check_contract "$response_path" final; then
    exit 0
  fi
  printf 'Run the protected Staging promotion to reconcile this drift.\n'
  ;;
prepare)
  require_protected_workflow
  payload_path="$temporary_directory/prepare.json"
  write_payload prepare "$payload_path"
  request PATCH "$response_path" "$payload_path"
  request GET "$response_path"
  check_contract "$response_path" prepare
  ;;
finalize)
  require_protected_workflow
  payload_path="$temporary_directory/finalize.json"
  write_payload final "$payload_path"
  request PATCH "$response_path" "$payload_path"
  request GET "$response_path"
  check_contract "$response_path" final
  ;;
verify)
  request GET "$response_path"
  check_contract "$response_path" final
  ;;
esac
