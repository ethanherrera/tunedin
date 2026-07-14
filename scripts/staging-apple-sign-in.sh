#!/usr/bin/env bash
set -euo pipefail

readonly bundle_identifier="com.ethanherrera.tunedin.staging"
readonly app_store_connect_api="https://api.appstoreconnect.apple.com"

usage() {
  cat <<'USAGE'
Usage: ./scripts/staging-apple-sign-in.sh <plan|apply|verify>

Required environment:
  APP_STORE_CONNECT_KEY_ID       App Store Connect API key ID.
  APP_STORE_CONNECT_ISSUER_ID    App Store Connect API issuer ID.
  APP_STORE_CONNECT_KEY_PATH     Path to the matching private .p8 key.

The apply command is restricted to the protected main-branch Staging workflow.
USAGE
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_configuration() {
  local name
  for name in \
    APP_STORE_CONNECT_KEY_ID \
    APP_STORE_CONNECT_ISSUER_ID \
    APP_STORE_CONNECT_KEY_PATH
  do
    if [[ -z "${!name:-}" ]]; then
      fail "$name is required."
    fi
  done

  if [[ ! -f "$APP_STORE_CONNECT_KEY_PATH" ]]; then
    fail "APP_STORE_CONNECT_KEY_PATH does not point to a readable private key."
  fi
  if [[ ! "$APP_STORE_CONNECT_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    fail "APP_STORE_CONNECT_KEY_ID must be a 10-character App Store Connect key ID."
  fi
  if [[ ! "$APP_STORE_CONNECT_ISSUER_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    fail "APP_STORE_CONNECT_ISSUER_ID must be an App Store Connect issuer UUID."
  fi
}

require_protected_workflow() {
  if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
    fail "Apple capability changes are allowed only in the protected Staging workflow."
  fi
  if [[ "${GITHUB_REF:-}" != "refs/heads/main" ]]; then
    fail "Apple capability changes require the main branch."
  fi
  if [[ "${TUNEDIN_PROMOTION_ENVIRONMENT:-}" != "Staging" ]]; then
    fail "Apple capability changes require the protected Staging environment."
  fi
}

app_store_connect_token() {
  local now expires unsigned signature_path signature
  now="$(date +%s)"
  expires="$((now + 600))"
  unsigned="$({
    KEY_ID="$APP_STORE_CONNECT_KEY_ID" \
    ISSUER_ID="$APP_STORE_CONNECT_ISSUER_ID" \
    ISSUED_AT="$now" \
    EXPIRES_AT="$expires" \
      python3 <<'PY'
import base64
import json
import os


def encode(value):
    encoded = json.dumps(value, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(encoded).rstrip(b"=").decode()


header = {"alg": "ES256", "kid": os.environ["KEY_ID"], "typ": "JWT"}
payload = {
    "iss": os.environ["ISSUER_ID"],
    "iat": int(os.environ["ISSUED_AT"]),
    "exp": int(os.environ["EXPIRES_AT"]),
    "aud": "appstoreconnect-v1",
}
print(f"{encode(header)}.{encode(payload)}")
PY
  })"

  signature_path="$temporary_directory/signature.der"
  printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$APP_STORE_CONNECT_KEY_PATH" -out "$signature_path"
  signature="$(python3 - "$signature_path" <<'PY'
import base64
import sys


def read_length(data, offset):
    first = data[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    count = first & 0x7F
    if count == 0 or count > 4:
        raise SystemExit("Invalid ECDSA signature length.")
    return int.from_bytes(data[offset:offset + count], "big"), offset + count


def read_integer(data, offset):
    if data[offset] != 0x02:
        raise SystemExit("Invalid ECDSA signature integer.")
    length, offset = read_length(data, offset + 1)
    value = int.from_bytes(data[offset:offset + length], "big")
    return value, offset + length


signature = open(sys.argv[1], "rb").read()
if not signature or signature[0] != 0x30:
    raise SystemExit("Invalid ECDSA signature sequence.")
sequence_length, offset = read_length(signature, 1)
if offset + sequence_length != len(signature):
    raise SystemExit("Invalid ECDSA signature sequence length.")
r, offset = read_integer(signature, offset)
s, offset = read_integer(signature, offset)
if offset != len(signature):
    raise SystemExit("Unexpected ECDSA signature data.")
raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
print(base64.urlsafe_b64encode(raw).rstrip(b"=").decode())
PY
  )"
  printf '%s.%s' "$unsigned" "$signature"
}

request() {
  local method="$1"
  local url="$2"
  local output_path="$3"
  local payload_path="${4:-}"
  local curl_config="$temporary_directory/curl-config"
  local token status
  token="$(app_store_connect_token)"
  printf 'header = "Authorization: Bearer %s"\n' "$token" >"$curl_config"
  printf '%s\n' 'header = "Content-Type: application/json"' >>"$curl_config"
  chmod 600 "$curl_config"

  if [[ -n "$payload_path" ]]; then
    status="$(curl --silent --show-error --config "$curl_config" \
      --request "$method" --data-binary "@$payload_path" \
      --output "$output_path" --write-out '%{http_code}' "$url")"
  else
    status="$(curl --silent --show-error --config "$curl_config" \
      --request "$method" --output "$output_path" \
      --write-out '%{http_code}' "$url")"
  fi
  if [[ ! "$status" =~ ^2 ]]; then
    fail "App Store Connect request failed with HTTP $status: $(error_summary "$output_path")"
  fi
}

error_summary() {
  local response_path="$1"
  python3 - "$response_path" <<'PY'
import json
import sys


try:
    with open(sys.argv[1], encoding="utf-8") as source:
        payload = json.load(source)
except (OSError, json.JSONDecodeError):
    print("Apple returned no structured error detail")
    raise SystemExit(0)

errors = payload.get("errors")
if not isinstance(errors, list) or not errors:
    print("Apple returned no structured error detail")
    raise SystemExit(0)

summaries = []
for error in errors[:3]:
    if not isinstance(error, dict):
        continue
    parts = [
        str(error[key]).strip()
        for key in ("code", "title", "detail")
        if isinstance(error.get(key), str) and error[key].strip()
    ]
    if parts:
        summaries.append(" — ".join(parts))

summary = " | ".join(summaries) or "Apple returned no structured error detail"
print(summary[:1000])
PY
}

load_bundle_id() {
  local response_path="$temporary_directory/bundle-id.json"
  request GET \
    "$app_store_connect_api/v1/bundleIds?filter%5Bidentifier%5D=$bundle_identifier&limit=2" \
    "$response_path"
  BUNDLE_IDENTIFIER="$bundle_identifier" python3 - "$response_path" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    response = json.load(source)

matches = response.get("data", [])
if len(matches) != 1:
    raise SystemExit(
        f"Expected one registered Bundle ID for {os.environ['BUNDLE_IDENTIFIER']}, found {len(matches)}."
    )
bundle = matches[0]
attributes = bundle.get("attributes", {})
if attributes.get("identifier") != os.environ["BUNDLE_IDENTIFIER"]:
    raise SystemExit("App Store Connect returned the wrong Bundle ID.")
if attributes.get("platform") not in {"IOS", "UNIVERSAL"}:
    raise SystemExit("The Staging Bundle ID is not registered for iOS.")
print(bundle["id"])
PY
}

load_capabilities() {
  local bundle_id="$1"
  request GET \
    "$app_store_connect_api/v1/bundleIds/$bundle_id/bundleIdCapabilities" \
    "$capabilities_path"
}

capability_id() {
  python3 - "$capabilities_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    response = json.load(source)

matches = [
    capability
    for capability in response.get("data", [])
    if capability.get("attributes", {}).get("capabilityType") == "APPLE_ID_AUTH"
]
if len(matches) > 1:
    raise SystemExit("App Store Connect returned duplicate Sign in with Apple capabilities.")
if matches:
    print(matches[0]["id"])
PY
}

check_contract() {
  python3 - "$capabilities_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    response = json.load(source)

matches = [
    capability
    for capability in response.get("data", [])
    if capability.get("attributes", {}).get("capabilityType") == "APPLE_ID_AUTH"
]
if not matches:
    print("Staging Apple Sign In drift: capability is not enabled.")
    raise SystemExit(1)
if len(matches) != 1:
    print("Staging Apple Sign In drift: duplicate capabilities were returned.")
    raise SystemExit(1)

settings = matches[0].get("attributes", {}).get("settings") or []
consent = next(
    (setting for setting in settings if setting.get("key") == "APPLE_ID_AUTH_APP_CONSENT"),
    None,
)
options = [] if consent is None else consent.get("options") or []
primary = next((option for option in options if option.get("key") == "PRIMARY_APP_CONSENT"), None)
if primary is None:
    print("Staging Apple Sign In drift: App ID is not configured as a primary App ID.")
    raise SystemExit(1)

print("Staging Apple Sign In App ID contract matches.")
PY
}

write_payload() {
  local bundle_id="$1"
  local capability="$2"
  local output_path="$3"
  BUNDLE_ID="$bundle_id" CAPABILITY_ID="$capability" python3 - "$output_path" <<'PY'
import json
import os
import sys

settings = [{
    "key": "APPLE_ID_AUTH_APP_CONSENT",
    "options": [{"key": "PRIMARY_APP_CONSENT"}],
}]
capability_id = os.environ["CAPABILITY_ID"]
if capability_id:
    data = {
        "type": "bundleIdCapabilities",
        "id": capability_id,
        "attributes": {"settings": settings},
    }
else:
    data = {
        "type": "bundleIdCapabilities",
        "attributes": {
            "capabilityType": "APPLE_ID_AUTH",
            "settings": settings,
        },
        "relationships": {
            "bundleId": {
                "data": {"type": "bundleIds", "id": os.environ["BUNDLE_ID"]},
            }
        },
    }

with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump({"data": data}, output, separators=(",", ":"))
PY
  chmod 600 "$output_path"
}

command="${1:-}"
if [[ "$command" != "plan" && "$command" != "apply" && "$command" != "verify" ]]; then
  usage >&2
  exit 1
fi

require_configuration
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
capabilities_path="$temporary_directory/capabilities.json"

bundle_id="$(load_bundle_id)"
load_capabilities "$bundle_id"

case "$command" in
plan)
  if check_contract; then
    exit 0
  fi
  printf 'The protected Staging promotion will reconcile this drift.\n'
  ;;
verify)
  check_contract
  ;;
apply)
  require_protected_workflow
  if check_contract; then
    exit 0
  fi

  current_capability_id="$(capability_id)"
  payload_path="$temporary_directory/capability.json"
  write_payload "$bundle_id" "$current_capability_id" "$payload_path"
  response_path="$temporary_directory/capability-response.json"
  if [[ -n "$current_capability_id" ]]; then
    request PATCH \
      "$app_store_connect_api/v1/bundleIdCapabilities/$current_capability_id" \
      "$response_path" "$payload_path"
  else
    request POST \
      "$app_store_connect_api/v1/bundleIdCapabilities" \
      "$response_path" "$payload_path"
  fi

  load_capabilities "$bundle_id"
  check_contract
  ;;
esac
