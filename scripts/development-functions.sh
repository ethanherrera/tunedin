#!/usr/bin/env bash
set -euo pipefail

readonly project_ref="dmrlpyxhqhunfndihvai"
readonly function_names=("music-catalog" "event-discovery")

usage() {
  cat <<'USAGE'
Usage: ./scripts/development-functions.sh <status|plan|apply>

Commands:
  status  List the deployed allow-listed functions and configured secret names.
  plan    Show the reviewed commit and exact functions that a later apply would deploy.
  apply   Reconcile runtime configuration and deploy only the allow-listed functions from the
          manually dispatched GitHub Development workflow on an explicitly requested
          branch.

This helper never applies migrations, resets or seeds hosted data, deploys Supabase
configuration, or deploys an unlisted Edge Function.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s is required. Run make setup, then try again.\n' "$1" >&2
    exit 1
  fi
}

require_protected_workflow() {
  if [[ "${GITHUB_ACTIONS:-}" != "true" || "${GITHUB_REF:-}" != refs/heads/* ]]; then
    printf 'Development Functions may be deployed only by the manually dispatched workflow from an explicitly requested branch.\n' >&2
    exit 1
  fi
  if [[ "${TUNEDIN_DEPLOYMENT_ENVIRONMENT:-}" != "Development" ]]; then
    printf 'The protected workflow must identify the Development environment.\n' >&2
    exit 1
  fi
  if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    printf 'SUPABASE_ACCESS_TOKEN is required in the protected Development environment.\n' >&2
    exit 1
  fi
}

validate_runtime() {
  MUSICBRAINZ_USER_AGENT="${MUSICBRAINZ_USER_AGENT:-}" \
    deno run --allow-env=MUSICBRAINZ_USER_AGENT \
      scripts/validate-musicbrainz-runtime.ts Development >/dev/null
}

show_status() {
  printf 'Development Edge Functions:\n'
  supabase functions list --project-ref "$project_ref"
  printf '\nDevelopment Function secret names (values are never shown):\n'
  supabase secrets list --project-ref "$project_ref"
}

verify_deployed_function() {
  local function_name="$1"
  local output_name="$2"
  local deployed_version
  if ! deployed_version="$(
    supabase functions list --project-ref "$project_ref" --output json |
      deno run scripts/verify-deployed-function.ts "$function_name"
  )"; then
    printf 'Development %s deployment verification failed.\n' "$function_name" >&2
    exit 1
  fi
  printf 'Verified Development %s is active at deployed version %s.\n' \
    "$function_name" "$deployed_version"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$output_name" "$deployed_version" >>"$GITHUB_OUTPUT"
  fi
}

configure_runtime() {
  local temporary_file
  umask 077
  temporary_file="$(mktemp)"
  trap "rm -f '$temporary_file'" EXIT
  {
    printf 'TUNEDIN_ENVIRONMENT=Development\n'
    printf 'MUSICBRAINZ_USER_AGENT=%s\n' "$MUSICBRAINZ_USER_AGENT"
    printf 'TICKETMASTER_DISCOVERY_API_KEY=%s\n' "$TICKETMASTER_DISCOVERY_API_KEY"
  } >"$temporary_file"
  supabase secrets set --project-ref "$project_ref" --env-file "$temporary_file" >/dev/null
  rm -f "$temporary_file"
  trap - EXIT
}

command="${1:-}"
if [[ "$command" != "status" && "$command" != "plan" && "$command" != "apply" ]]; then
  usage >&2
  exit 1
fi

require_command supabase
require_command git

case "$command" in
status)
  show_status
  ;;
plan)
  printf 'Development Function deployment plan:\n'
  printf '  Commit: %s\n' "$(git rev-parse --verify HEAD)"
  printf '  Project: tunedin-dev (%s)\n' "$project_ref"
  printf '  Function allow-list: %s\n' "${function_names[*]}"
  printf '  Hosted database, seed data, and Supabase configuration: unchanged\n'
  show_status
  ;;
apply)
  require_command deno
  require_protected_workflow
  if [[ -z "${TICKETMASTER_DISCOVERY_API_KEY:-}" ]]; then
    printf 'TICKETMASTER_DISCOVERY_API_KEY is required in the protected Development environment.\n' >&2
    exit 1
  fi
  validate_runtime
  configure_runtime
  supabase functions deploy "music-catalog" --project-ref "$project_ref" --use-api
  verify_deployed_function "music-catalog" "music_catalog_version"
  supabase functions deploy "event-discovery" --project-ref "$project_ref" --use-api
  verify_deployed_function "event-discovery" "event_discovery_version"
  printf 'Development Edge Functions deployed from commit %s.\n' "$(git rev-parse --verify HEAD)"
  ;;
esac
