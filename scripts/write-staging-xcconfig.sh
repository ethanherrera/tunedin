#!/usr/bin/env bash
set -euo pipefail

output_path="${1:-ios/Config/Staging.xcconfig}"
development_project_ref="dmrlpyxhqhunfndihvai"

required_values=(
  SUPABASE_PROJECT_REF
  SUPABASE_PUBLISHABLE_KEY
  POSTHOG_PROJECT_TOKEN
  POSTHOG_PROJECT_ID
  GOOGLE_IOS_CLIENT_ID
  GOOGLE_SERVER_CLIENT_ID
  GOOGLE_REVERSED_CLIENT_ID
  TUNEDIN_GIT_SHA
)

for name in "${required_values[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing required Staging configuration value: %s\n' "$name" >&2
    exit 1
  fi

  if [[ "${!name}" == *$'\n'* || "${!name}" == *$'\r'* ]]; then
    printf 'Staging configuration value %s must be a single line.\n' "$name" >&2
    exit 1
  fi
done

if [[ "$SUPABASE_PROJECT_REF" == "$development_project_ref" ]]; then
  printf 'Refusing to configure Staging with the Development Supabase project.\n' >&2
  exit 1
fi

if [[ ! "$SUPABASE_PROJECT_REF" =~ ^[a-z]{20}$ ]]; then
  printf 'SUPABASE_PROJECT_REF must be a 20-character lowercase project ref.\n' >&2
  exit 1
fi

if [[ "$POSTHOG_PROJECT_ID" != "507318" ]]; then
  printf 'POSTHOG_PROJECT_ID must be the approved Staging project 507318.\n' >&2
  exit 1
fi

if [[ ! "$GOOGLE_IOS_CLIENT_ID" =~ ^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$ ]] ||
  [[ ! "$GOOGLE_SERVER_CLIENT_ID" =~ ^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$ ]]; then
  printf 'Staging Google OAuth client IDs are invalid.\n' >&2
  exit 1
fi

google_ios_prefix="${GOOGLE_IOS_CLIENT_ID%.apps.googleusercontent.com}"
if [[ "$GOOGLE_REVERSED_CLIENT_ID" != "com.googleusercontent.apps.${google_ios_prefix}" ]]; then
  printf 'GOOGLE_REVERSED_CLIENT_ID does not match GOOGLE_IOS_CLIENT_ID.\n' >&2
  exit 1
fi

if [[ ! "$TUNEDIN_GIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'TUNEDIN_GIT_SHA must be a full lowercase Git commit SHA.\n' >&2
  exit 1
fi

output_directory="$(dirname "$output_path")"
mkdir -p "$output_directory"
umask 077
temporary_file="$(mktemp "${output_path}.tmp.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT

{
  printf '%s\n' '#include "Base.xcconfig"'
  printf '\n'
  printf '%s\n' 'APP_ENVIRONMENT = Staging'
  printf '%s\n' 'PRODUCT_BUNDLE_IDENTIFIER = com.ethanherrera.tunedin.staging'
  printf '%s\n' 'APP_DISPLAY_NAME = tunedIn Staging'
  printf '%s\n' 'AUTH_EXPERIENCE = NativeSocial'
  printf 'GOOGLE_IOS_CLIENT_ID = %s\n' "$GOOGLE_IOS_CLIENT_ID"
  printf 'GOOGLE_SERVER_CLIENT_ID = %s\n' "$GOOGLE_SERVER_CLIENT_ID"
  printf 'GOOGLE_REVERSED_CLIENT_ID = %s\n' "$GOOGLE_REVERSED_CLIENT_ID"
  # shellcheck disable=SC2016
  printf 'SUPABASE_URL = https:/$(TUNEDIN_URL_SLASH)%s.supabase.co\n' "$SUPABASE_PROJECT_REF"
  printf 'SUPABASE_PUBLISHABLE_KEY = %s\n' "$SUPABASE_PUBLISHABLE_KEY"
  printf 'POSTHOG_PROJECT_TOKEN = %s\n' "$POSTHOG_PROJECT_TOKEN"
  printf 'POSTHOG_PROJECT_ID = %s\n' "$POSTHOG_PROJECT_ID"
  # shellcheck disable=SC2016
  printf '%s\n' 'POSTHOG_HOST = https:/$(TUNEDIN_URL_SLASH)us.i.posthog.com'
  printf 'TUNEDIN_GIT_SHA = %s\n' "$TUNEDIN_GIT_SHA"
} >"$temporary_file"

mv "$temporary_file" "$output_path"
trap - EXIT
