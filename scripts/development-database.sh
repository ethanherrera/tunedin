#!/usr/bin/env bash
set -euo pipefail

readonly project_ref="dmrlpyxhqhunfndihvai"
readonly keychain_service="tunedin/supabase/dev/database"

usage() {
  cat <<'USAGE'
Usage: ./scripts/development-database.sh <status|plan|apply>

Commands:
  status  Show migration parity for the linked tunedin-dev project.
  plan    Print the migrations that would be applied to tunedin-dev.
  apply   Apply pending migrations from the protected GitHub workflow on an
          explicitly requested branch.

This script never resets the hosted database or pushes seed data, Supabase
configuration, or Edge Functions. Those operations require their own review and
runbook.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s is required. Run make setup, then try again.\n' "$1" >&2
    exit 1
  fi
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
    printf 'Missing Development database password in Keychain item %s.\n' "$keychain_service" >&2
    exit 1
  fi
}

link_development_project() {
  local password="$1"
  supabase link --project-ref "$project_ref" --password "$password" >/dev/null
}

require_protected_workflow() {
  if [[ "${GITHUB_ACTIONS:-}" != "true" || "${GITHUB_REF:-}" != refs/heads/* ]]; then
    printf 'Development migrations may be applied only by the manually dispatched GitHub workflow from an explicitly requested branch.\n' >&2
    exit 1
  fi
}

show_status() {
  local password="$1"
  link_development_project "$password"
  printf 'Migration status for tunedin-dev (%s):\n' "$project_ref"
  supabase migration list --linked
}

command="${1:-}"
if [[ "$command" != "status" && "$command" != "plan" && "$command" != "apply" ]]; then
  usage >&2
  exit 1
fi

require_command supabase
password="$(database_password)"

case "$command" in
status)
  show_status "$password"
  ;;
plan)
  link_development_project "$password"
  printf 'Migration plan for tunedin-dev (%s):\n' "$project_ref"
  supabase db push --linked --password "$password" --dry-run
  ;;
apply)
  require_protected_workflow
  link_development_project "$password"
  printf 'Checking the Development migration plan before applying it.\n'
  supabase db push --linked --password "$password" --dry-run
  supabase db push --linked --password "$password"
  show_status "$password"
  printf 'Development migrations applied from commit %s.\n' "$(git rev-parse --verify HEAD)"
  ;;
esac
