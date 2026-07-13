#!/usr/bin/env bash
set -euo pipefail

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

export SUPABASE_PROJECT_REF="abcdefghijklmnopqrst"
export SUPABASE_PUBLISHABLE_KEY="sb_publishable_regression_test"
export POSTHOG_PROJECT_TOKEN="phc_regression_test"
export POSTHOG_PROJECT_ID="507318"
export TUNEDIN_GIT_SHA="0123456789abcdef0123456789abcdef01234567"
export GITHUB_SHA="$TUNEDIN_GIT_SHA"

generated_config="$temporary_directory/Staging.xcconfig"
./scripts/write-staging-xcconfig.sh "$generated_config"

# shellcheck disable=SC2016
if ! grep -Fqx 'SUPABASE_URL = https:/$(TUNEDIN_URL_SLASH)abcdefghijklmnopqrst.supabase.co' "$generated_config"; then
  printf 'Generated Staging Supabase URL does not preserve the xcconfig slash expansion.\n' >&2
  exit 1
fi

# shellcheck disable=SC2016
if ! grep -Fqx 'POSTHOG_HOST = https:/$(TUNEDIN_URL_SLASH)us.i.posthog.com' "$generated_config"; then
  printf 'Generated Staging PostHog URL does not preserve the xcconfig slash expansion.\n' >&2
  exit 1
fi

if grep -Fq '3(TUNEDIN_URL_SLASH)' "$generated_config"; then
  printf 'Generated Staging configuration contains the invalid Bash %%c expansion.\n' >&2
  exit 1
fi

info_plist="$temporary_directory/Info.plist"
cat >"$info_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>tunedIn Staging</string>
  <key>CFBundleIdentifier</key>
  <string>com.ethanherrera.tunedin.staging</string>
  <key>TUNEDIN_APP_ENVIRONMENT</key>
  <string>Staging</string>
  <key>TUNEDIN_AUTH_CALLBACK_SCHEME</key>
  <string>com.ethanherrera.tunedin.staging</string>
  <key>TUNEDIN_USE_LOCAL_AUTH_STORAGE</key>
  <string>NO</string>
  <key>TUNEDIN_SUPABASE_URL</key>
  <string>https://abcdefghijklmnopqrst.supabase.co</string>
  <key>TUNEDIN_SUPABASE_PUBLISHABLE_KEY</key>
  <string>sb_publishable_regression_test</string>
  <key>TUNEDIN_POSTHOG_PROJECT_TOKEN</key>
  <string>phc_regression_test</string>
  <key>TUNEDIN_POSTHOG_PROJECT_ID</key>
  <string>507318</string>
  <key>TUNEDIN_POSTHOG_HOST</key>
  <string>https://us.i.posthog.com</string>
  <key>TUNEDIN_GIT_SHA</key>
  <string>0123456789abcdef0123456789abcdef01234567</string>
</dict>
</plist>
PLIST

./scripts/verify-staging-archive-configuration.sh "$info_plist" >/dev/null

plutil -replace TUNEDIN_SUPABASE_URL -string 'https:/3(TUNEDIN_URL_SLASH)abcdefghijklmnopqrst.supabase.co' "$info_plist"
if ./scripts/verify-staging-archive-configuration.sh "$info_plist" >/dev/null 2>&1; then
  printf 'Archive verification accepted the malformed Staging Supabase URL.\n' >&2
  exit 1
fi

printf 'Staging configuration generation and archive validation are valid.\n'
