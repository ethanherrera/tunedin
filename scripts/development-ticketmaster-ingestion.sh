#!/usr/bin/env bash
set -euo pipefail

readonly project_ref="dmrlpyxhqhunfndihvai"
readonly function_url="https://${project_ref}.supabase.co/functions/v1/ticketmaster-ingestion"

usage() {
  cat <<'USAGE'
Usage: ./scripts/development-ticketmaster-ingestion.sh <status|run|resume>

This helper invokes the service-only Development ingestion Function from the
protected, manually dispatched GitHub workflow. It never enables either Cron
schedule and never prints an API credential.
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
    printf 'Development ingestion may run only in the manually dispatched protected workflow.\n' >&2
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

service_role_key() {
  supabase projects api-keys --project-ref "$project_ref" --output json |
    jq -er '
      first(
        .[]
        | select(.name == "service_role" and .type == "legacy")
        | .api_key
        | select(type == "string" and length > 20)
      )
    '
}

invoke() {
  local operation="$1"
  local key
  local response
  key="$(service_role_key)"
  printf '::add-mask::%s\n' "$key"
  response="$(
    curl --fail-with-body --silent --show-error \
      --request POST \
      --header "Authorization: Bearer ${key}" \
      --header "apikey: ${key}" \
      --header 'Content-Type: application/json' \
      --data "{\"operation\":\"${operation}\"}" \
      "$function_url"
  )"
  printf '%s\n' "$response" | jq -e .
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'result=%s\n' "$(printf '%s' "$response" | jq -c .)" >>"$GITHUB_OUTPUT"
  fi
}

operation="${1:-}"
if [[ "$operation" != "status" && "$operation" != "run" && "$operation" != "resume" ]]; then
  usage >&2
  exit 1
fi

require_command curl
require_command jq
require_command supabase
require_protected_workflow
invoke "$operation"
