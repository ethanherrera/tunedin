#!/usr/bin/env bash
set -euo pipefail

config_dir="ios/Config"
configuration_file="${config_dir}/Local.xcconfig"

if ! command -v supabase >/dev/null 2>&1; then
  printf 'Supabase CLI is required. Run make setup, then try again.\n' >&2
  exit 1
fi

if [[ ! -f "${config_dir}/Base.xcconfig" || ! -f "${configuration_file}" ]]; then
  ./scripts/configure-local.sh >/dev/null
fi

if ! grep -q '^[[:space:]]*TUNEDIN_USE_LOCAL_AUTH_STORAGE[[:space:]]*=' "${configuration_file}"; then
  printf '\nTUNEDIN_USE_LOCAL_AUTH_STORAGE = YES\n' >>"${configuration_file}"
fi

if ! status_output="$(./scripts/worktree-local-supabase.sh status-env 2>/dev/null)"; then
  printf 'This worktree Local Supabase is not running. Run make local-db-start, then rerun make configure-local-supabase.\n' >&2
  exit 1
fi

read_env_value() {
  local key="$1"
  awk -v wanted_key="${key}" '
    index($0, wanted_key "=") == 1 {
      value = substr($0, length(wanted_key) + 2)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
      exit
    }
  ' <<<"${status_output}"
}

api_url="$(read_env_value API_URL)"
publishable_key="$(read_env_value PUBLISHABLE_KEY)"

if [[ -z "${api_url}" || -z "${publishable_key}" ]]; then
  printf 'Local Supabase did not return the API URL and publishable key. Run supabase start and try again.\n' >&2
  exit 1
fi

# Xcode treats a literal `//` in xcconfig values as a comment. Keep the URL
# intact by using the slash setting defined in Base.xcconfig, just like the
# checked-in configuration templates do.
xcconfig_api_url="$(sed \
  -e 's#^https://#https:/$(TUNEDIN_URL_SLASH)#' \
  -e 's#^http://#http:/$(TUNEDIN_URL_SLASH)#' \
  <<<"${api_url}")"

temporary_file="$(mktemp)"
trap 'rm -f "${temporary_file}"' EXIT

awk -v local_url="${xcconfig_api_url}" -v local_key="${publishable_key}" '
  /^[[:space:]]*SUPABASE_URL[[:space:]]*=/ {
    print "SUPABASE_URL = " local_url
    next
  }
  /^[[:space:]]*SUPABASE_PUBLISHABLE_KEY[[:space:]]*=/ {
    print "SUPABASE_PUBLISHABLE_KEY = " local_key
    next
  }
  { print }
' "${configuration_file}" >"${temporary_file}"

mv "${temporary_file}" "${configuration_file}"
trap - EXIT

printf 'Configured the ignored Local Xcode configuration from the running local Supabase stack.\n'
