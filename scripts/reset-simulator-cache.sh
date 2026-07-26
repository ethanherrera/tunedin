#!/usr/bin/env bash
set -euo pipefail

readonly default_bundle_identifier="com.ethanherrera.tunedin"
bundle_identifier="${TUNEDIN_CACHE_BUNDLE_ID:-$default_bundle_identifier}"

case "$bundle_identifier" in
  com.ethanherrera.tunedin | com.ethanherrera.tunedin.staging)
    ;;
  *)
    printf 'Unsupported bundle identifier: %s\n' "$bundle_identifier" >&2
    printf 'Use com.ethanherrera.tunedin or com.ethanherrera.tunedin.staging.\n' >&2
    exit 2
    ;;
esac

device_identifier="$(./scripts/worktree-simulator.sh udid)"

if ! container="$(xcrun simctl get_app_container "${device_identifier}" "$bundle_identifier" data 2>/dev/null)"; then
  printf 'The selected app is not installed in this worktree Simulator: %s\n' "$bundle_identifier" >&2
  exit 1
fi

xcrun simctl terminate "${device_identifier}" "$bundle_identifier" >/dev/null 2>&1 || true

readonly cache_root="$container/Library/Caches/tunedIn/Cache"
case "$cache_root" in
  "$container"/Library/Caches/tunedIn/Cache)
    ;;
  *)
    printf 'Refusing to clear an unexpected path.\n' >&2
    exit 1
    ;;
esac

if [[ -d "$cache_root" ]]; then
  rm -rf -- "$cache_root"
fi

printf 'Cleared the tunedIn Simulator cache for %s on %s.\n' "$bundle_identifier" "${device_identifier}"
