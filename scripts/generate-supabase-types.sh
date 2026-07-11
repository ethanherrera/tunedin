#!/usr/bin/env bash
set -euo pipefail

project_ref="${SUPABASE_PROJECT_REF:-}"
output="ios/tunedIn/Sources/Data/Generated/SupabaseTypes.swift"

if [[ -z "${project_ref}" ]]; then
  printf 'SUPABASE_PROJECT_REF is required. Link the project with Supabase CLI or export its ref.\n' >&2
  exit 1
fi

mkdir -p "$(dirname "${output}")"
supabase gen types --project-id "${project_ref}" --lang swift --swift-access-control public --schema public >"${output}"
printf 'Generated %s\n' "${output}"
