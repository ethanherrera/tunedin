#!/usr/bin/env bash
set -euo pipefail

committed="ios/tunedIn/Sources/Data/Generated/SupabaseTypes.swift"
generated="$(mktemp)"
trap 'rm -f "${generated}"' EXIT

supabase gen types --local --lang swift --swift-access-control public --schema public >"${generated}"
perl -0pi -e 's/^    case private = "private"$/    case `private` = "private"/mg' "${generated}"

if ! cmp -s "${committed}" "${generated}"; then
  diff -u "${committed}" "${generated}" || true
  printf 'Generated Supabase Swift types are stale. Run: make supabase-types\n' >&2
  exit 1
fi

printf 'Generated Supabase Swift types are current.\n'
