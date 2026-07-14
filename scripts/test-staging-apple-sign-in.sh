#!/usr/bin/env bash
set -euo pipefail

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin"

openssl ecparam -name prime256v1 -genkey -noout \
  -out "$temporary_directory/AuthKey_ABCDEFGHIJ.p8" 2>/dev/null

cat >"$temporary_directory/bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
output_path=""
payload_path=""
config_path=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --config)
    config_path="$2"
    shift 2
    ;;
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
  --write-out | --silent | --show-error)
    if [[ "$1" == "--write-out" ]]; then
      shift 2
    else
      shift
    fi
    ;;
  *)
    url="$1"
    shift
    ;;
  esac
done

CONFIG_PATH="$config_path" python3 <<'PY'
import base64
import json
import os
import time

config = open(os.environ["CONFIG_PATH"], encoding="utf-8").read()
prefix = 'header = "Authorization: Bearer '
line = next(line for line in config.splitlines() if line.startswith(prefix))
token = line[len(prefix):-1]
header, payload, signature = token.split(".")

def decode(value):
    return json.loads(base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)))

assert decode(header)["kid"] == "ABCDEFGHIJ"
claims = decode(payload)
assert claims["iss"] == "12345678-1234-1234-1234-123456789abc"
assert claims["aud"] == "appstoreconnect-v1"
assert 0 < claims["exp"] - claims["iat"] <= 1200
assert claims["exp"] > int(time.time())
assert len(base64.urlsafe_b64decode(signature + "=" * (-len(signature) % 4))) == 64
PY

if [[ "$url" == *"/v1/bundleIds?"* ]]; then
  if [[ "${FAKE_STATUS:-200}" != "200" ]]; then
    cp "$FAKE_ERROR_STATE" "$output_path"
    printf '%s' "$FAKE_STATUS"
    exit 0
  fi
  cp "$FAKE_BUNDLE_STATE" "$output_path"
elif [[ "$url" == *"/bundleIdCapabilities?"* ]]; then
  cp "$FAKE_CAPABILITY_STATE" "$output_path"
elif [[ "$method" == "POST" || "$method" == "PATCH" ]]; then
  METHOD="$method" PAYLOAD_PATH="$payload_path" STATE_PATH="$FAKE_CAPABILITY_STATE" \
    python3 <<'PY'
import json
import os

payload = json.load(open(os.environ["PAYLOAD_PATH"], encoding="utf-8"))["data"]
settings = payload["attributes"]["settings"]
assert settings == [{
    "key": "APPLE_ID_AUTH_APP_CONSENT",
    "options": [{"key": "PRIMARY_APP_CONSENT"}],
}]
if os.environ["METHOD"] == "POST":
    assert payload["attributes"]["capabilityType"] == "APPLE_ID_AUTH"
    assert payload["relationships"]["bundleId"]["data"]["id"] == "BUNDLE123"
else:
    assert payload["id"] == "CAPABILITY123"

state = {
    "data": [{
        "type": "bundleIdCapabilities",
        "id": "CAPABILITY123",
        "attributes": {
            "capabilityType": "APPLE_ID_AUTH",
            "settings": [{
                "key": "APPLE_ID_AUTH_APP_CONSENT",
                "options": [{"key": "PRIMARY_APP_CONSENT", "enabled": True}],
            }],
        },
    }]
}
json.dump(state, open(os.environ["STATE_PATH"], "w", encoding="utf-8"))
PY
  cp "$FAKE_CAPABILITY_STATE" "$output_path"
else
  printf 'Unexpected fake App Store Connect request: %s %s\n' "$method" "$url" >&2
  exit 1
fi
printf '200'
FAKE_CURL
chmod +x "$temporary_directory/bin/curl"

cat >"$temporary_directory/bundle.json" <<'JSON'
{
  "data": [{
    "type": "bundleIds",
    "id": "BUNDLE123",
    "attributes": {
      "identifier": "com.ethanherrera.tunedin.staging",
      "platform": "IOS"
    }
  }]
}
JSON
printf '{"data":[]}' >"$temporary_directory/capabilities.json"

export PATH="$temporary_directory/bin:$PATH"
export FAKE_BUNDLE_STATE="$temporary_directory/bundle.json"
export FAKE_CAPABILITY_STATE="$temporary_directory/capabilities.json"
cat >"$temporary_directory/error.json" <<'JSON'
{"errors":[{"status":"400","code":"PARAMETER_ERROR.INVALID","title":"Request parameter is invalid","detail":"filter[identifier] is invalid"}]}
JSON
export FAKE_ERROR_STATE="$temporary_directory/error.json"
export APP_STORE_CONNECT_KEY_ID="ABCDEFGHIJ"
export APP_STORE_CONNECT_ISSUER_ID="12345678-1234-1234-1234-123456789abc"
export APP_STORE_CONNECT_KEY_PATH="$temporary_directory/AuthKey_ABCDEFGHIJ.p8"

./scripts/staging-apple-sign-in.sh plan >/dev/null
if ./scripts/staging-apple-sign-in.sh verify >/dev/null 2>&1; then
  printf 'Apple capability verification accepted a missing capability.\n' >&2
  exit 1
fi
if ./scripts/staging-apple-sign-in.sh apply >/dev/null 2>&1; then
  printf 'Apple capability apply ran outside the protected workflow.\n' >&2
  exit 1
fi

export GITHUB_ACTIONS="true"
export GITHUB_REF="refs/heads/main"
export TUNEDIN_PROMOTION_ENVIRONMENT="Staging"
./scripts/staging-apple-sign-in.sh apply >/dev/null
./scripts/staging-apple-sign-in.sh verify >/dev/null

if FAKE_STATUS=400 ./scripts/staging-apple-sign-in.sh plan >"$temporary_directory/error-output" 2>&1; then
  printf 'Apple API error handling accepted an HTTP 400 response.\n' >&2
  exit 1
fi
if ! grep -Eq 'PARAMETER_ERROR.INVALID.*filter\[identifier\] is invalid' "$temporary_directory/error-output"; then
  printf 'Apple API error handling did not report the structured API error.\n' >&2
  exit 1
fi

python3 - "$FAKE_CAPABILITY_STATE" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding="utf-8"))
option = state["data"][0]["attributes"]["settings"][0]["options"][0]
assert option == {"key": "PRIMARY_APP_CONSENT", "enabled": True}
PY

python3 - "$FAKE_CAPABILITY_STATE" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding="utf-8"))
state["data"][0]["attributes"]["settings"][0]["options"][0]["enabled"] = False
json.dump(state, open(sys.argv[1], "w", encoding="utf-8"))
PY
./scripts/staging-apple-sign-in.sh apply >/dev/null
./scripts/staging-apple-sign-in.sh verify >/dev/null

printf 'Staging Apple Sign In capability reconciliation is valid.\n'
