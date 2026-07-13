#!/usr/bin/env bash
set -euo pipefail

info_plist="${1:-build/tunedIn-Staging.xcarchive/Products/Applications/tunedIn.app/Info.plist}"

if [[ ! -f "$info_plist" ]]; then
  printf 'Archived Staging Info.plist was not found at %s.\n' "$info_plist" >&2
  exit 1
fi

required_values=(
  SUPABASE_PROJECT_REF
  SUPABASE_PUBLISHABLE_KEY
  POSTHOG_PROJECT_TOKEN
  POSTHOG_PROJECT_ID
  GOOGLE_IOS_CLIENT_ID
  GOOGLE_SERVER_CLIENT_ID
  GOOGLE_REVERSED_CLIENT_ID
  GITHUB_SHA
)

for name in "${required_values[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing expected archive verification value: %s\n' "$name" >&2
    exit 1
  fi
done

assert_value() {
  local key="$1"
  local expected="$2"
  local actual

  if ! actual="$(plutil -extract "$key" raw -o - "$info_plist" 2>/dev/null)"; then
    printf 'Archived app is missing required configuration %s.\n' "$key" >&2
    exit 1
  fi

  if [[ "$actual" != "$expected" ]]; then
    printf 'Archived app contains an invalid value for %s.\n' "$key" >&2
    exit 1
  fi
}

assert_value CFBundleDisplayName 'tunedIn Staging'
assert_value CFBundleIdentifier 'com.ethanherrera.tunedin.staging'
assert_value TUNEDIN_APP_ENVIRONMENT 'Staging'
assert_value TUNEDIN_AUTH_EXPERIENCE 'NativeSocial'
assert_value TUNEDIN_AUTH_CALLBACK_SCHEME 'com.ethanherrera.tunedin.staging'
assert_value TUNEDIN_USE_LOCAL_AUTH_STORAGE 'NO'
assert_value TUNEDIN_SUPABASE_URL "https://${SUPABASE_PROJECT_REF}.supabase.co"
assert_value TUNEDIN_SUPABASE_PUBLISHABLE_KEY "$SUPABASE_PUBLISHABLE_KEY"
assert_value TUNEDIN_POSTHOG_PROJECT_TOKEN "$POSTHOG_PROJECT_TOKEN"
assert_value TUNEDIN_POSTHOG_PROJECT_ID "$POSTHOG_PROJECT_ID"
assert_value TUNEDIN_POSTHOG_HOST 'https://us.i.posthog.com'
assert_value TUNEDIN_GIT_SHA "$GITHUB_SHA"
assert_value GIDClientID "$GOOGLE_IOS_CLIENT_ID"
assert_value GIDServerClientID "$GOOGLE_SERVER_CLIENT_ID"

PLIST_PATH="$info_plist" python3 <<'PY'
import os
import plistlib

with open(os.environ["PLIST_PATH"], "rb") as source:
    info = plistlib.load(source)

schemes = {
    scheme
    for entry in info.get("CFBundleURLTypes", [])
    for scheme in entry.get("CFBundleURLSchemes", [])
}
expected = {
    "com.ethanherrera.tunedin.staging",
    os.environ["GOOGLE_REVERSED_CLIENT_ID"],
}
if not expected.issubset(schemes):
    raise SystemExit("Archived app is missing a required authentication callback URL scheme.")
PY

printf 'Archived Staging configuration is valid.\n'
