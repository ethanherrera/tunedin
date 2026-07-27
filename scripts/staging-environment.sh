#!/usr/bin/env bash
set -euo pipefail

readonly development_project_ref="dmrlpyxhqhunfndihvai"
readonly function_names=("music-catalog" "event-discovery")
readonly keychain_service="tunedin/supabase/staging/database"

usage() {
  cat <<'USAGE'
Usage: ./scripts/staging-environment.sh <status|plan|apply>

Required environment:
  SUPABASE_PROJECT_REF  Project ref for the dedicated tunedin-staging project.

Commands:
  status  Show migration parity for tunedin-staging.
  plan    Print the migrations that would be applied to tunedin-staging.
  apply   Apply migrations and deploy tracked Edge Functions from the protected workflow.

This script never resets hosted data, copies seed data, or copies Storage objects.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s is required. Run make setup, then try again.\n' "$1" >&2
    exit 1
  fi
}

staging_project_ref() {
  local project_ref="${SUPABASE_PROJECT_REF:-}"
  if [[ ! "$project_ref" =~ ^[a-z]{20}$ ]]; then
    printf 'SUPABASE_PROJECT_REF must be the 20-letter tunedin-staging project ref.\n' >&2
    exit 1
  fi
  if [[ "$project_ref" == "$development_project_ref" ]]; then
    printf 'The Staging workflow refuses to target the Development project.\n' >&2
    exit 1
  fi
  printf '%s' "$project_ref"
}

database_password() {
  if [[ -n "${SUPABASE_DB_PASSWORD:-}" ]]; then
    printf '%s' "${SUPABASE_DB_PASSWORD}"
    return
  fi

  if ! command -v security >/dev/null 2>&1; then
    printf 'SUPABASE_DB_PASSWORD is required outside macOS.\n' >&2
    exit 1
  fi

  if ! security find-generic-password -a "$USER" -s "$keychain_service" -w 2>/dev/null; then
    printf 'Missing Staging database password in Keychain item %s.\n' "$keychain_service" >&2
    exit 1
  fi
}

require_protected_workflow() {
  if [[ "${GITHUB_ACTIONS:-}" != "true" || "${GITHUB_REF:-}" != "refs/heads/main" ]]; then
    printf 'Staging may be mutated only by the protected GitHub workflow from main.\n' >&2
    exit 1
  fi
  if [[ "${TUNEDIN_PROMOTION_ENVIRONMENT:-}" != "Staging" ]]; then
    printf 'The protected workflow must explicitly identify the Staging environment.\n' >&2
    exit 1
  fi
}

link_project() {
  local project_ref="$1"
  local password="$2"
  supabase link --project-ref "$project_ref" --password "$password" >/dev/null
}

show_status() {
  local project_ref="$1"
  local password="$2"
  link_project "$project_ref" "$password"
  printf 'Migration status for tunedin-staging (%s):\n' "$project_ref"
  supabase migration list --linked
}

deploy_functions() {
  local project_ref="$1"
  local temporary_file
  umask 077
  temporary_file="$(mktemp)"
  trap "rm -f '$temporary_file'" EXIT
  {
    printf 'TUNEDIN_ENVIRONMENT=Staging\n'
    printf 'MUSICBRAINZ_USER_AGENT=%s\n' "$MUSICBRAINZ_USER_AGENT"
    printf 'TICKETMASTER_DISCOVERY_API_KEY=%s\n' "$TICKETMASTER_DISCOVERY_API_KEY"
  } >"$temporary_file"
  supabase secrets set --project-ref "$project_ref" --env-file "$temporary_file" >/dev/null
  rm -f "$temporary_file"
  trap - EXIT

  local function_name
  local output_name
  local deployed_version
  for function_name in "${function_names[@]}"; do
    printf 'Deploying the allow-listed Staging %s Edge Function.\n' "$function_name"
    supabase functions deploy "$function_name" --project-ref "$project_ref" --use-api
    if ! deployed_version="$(
      supabase functions list --project-ref "$project_ref" --output json |
        deno run scripts/verify-deployed-function.ts "$function_name"
    )"; then
      printf 'Staging %s deployment verification failed.\n' "$function_name" >&2
      exit 1
    fi
    printf 'Verified Staging %s is active at deployed version %s.\n' \
      "$function_name" "$deployed_version"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      output_name="${function_name//-/_}_version"
      printf '%s=%s\n' "$output_name" "$deployed_version" >>"$GITHUB_OUTPUT"
    fi
  done
}

validate_musicbrainz_runtime() {
  MUSICBRAINZ_USER_AGENT="${MUSICBRAINZ_USER_AGENT:-}" \
    deno run --allow-env=MUSICBRAINZ_USER_AGENT \
      scripts/validate-musicbrainz-runtime.ts Staging >/dev/null
}

command="${1:-}"
if [[ "$command" != "status" && "$command" != "plan" && "$command" != "apply" ]]; then
  usage >&2
  exit 1
fi

require_command supabase
project_ref="$(staging_project_ref)"
password="$(database_password)"

case "$command" in
status)
  show_status "$project_ref" "$password"
  ;;
plan)
  link_project "$project_ref" "$password"
  printf 'Migration plan for tunedin-staging (%s):\n' "$project_ref"
  supabase db push --linked --password "$password" --dry-run
  ;;
apply)
  require_protected_workflow
  require_command deno
  if [[ -z "${TICKETMASTER_DISCOVERY_API_KEY:-}" ]]; then
    printf 'TICKETMASTER_DISCOVERY_API_KEY is required in the protected Staging environment.\n' >&2
    exit 1
  fi
  validate_musicbrainz_runtime
  link_project "$project_ref" "$password"
  printf 'Checking the Staging migration plan before applying it.\n'
  supabase db push --linked --password "$password" --dry-run
  supabase db push --linked --password "$password"
  deploy_functions "$project_ref"
  show_status "$project_ref" "$password"
  printf 'Staging backend promoted from commit %s.\n' "$(git rev-parse --verify HEAD)"
  ;;
esac
