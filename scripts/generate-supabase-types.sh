#!/usr/bin/env bash
set -euo pipefail

output="ios/tunedIn/Sources/Data/Generated/SupabaseTypes.swift"

arguments=(--local)
if [[ -n "${SUPABASE_PROJECT_REF:-}" ]]; then
  arguments=(--project-id "${SUPABASE_PROJECT_REF}")
fi

mkdir -p "$(dirname "${output}")"
supabase gen types "${arguments[@]}" --lang swift --swift-access-control public --schema public >"${output}"

# The CLI currently emits the Postgres enum value `private` without escaping the
# Swift keyword. Keep the generated API accurate and compilable until upstream
# handles Swift reserved words.
perl -0pi -e 's/^    case private = "private"$/    case `private` = "private"/m' "${output}"

printf 'Generated %s\n' "${output}"
