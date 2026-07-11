#!/usr/bin/env bash

set -euo pipefail

scenario="${1:-}"
bundle_identifier="com.ethanherrera.tunedin"

case "${scenario}" in
  live | signed-out | onboarding | profile | profile-error) ;;
  *)
    printf 'Unknown Development scenario. Use live, signed-out, onboarding, profile, or profile-error.\n' >&2
    exit 1
    ;;
esac

if ! command -v xcrun >/dev/null 2>&1; then
  printf 'Xcode command-line tools are required. Open Xcode and finish its first-launch setup.\n' >&2
  exit 1
fi

if ! xcrun simctl get_app_container booted "${bundle_identifier}" app >/dev/null 2>&1; then
  printf 'Boot an iOS Simulator and install tunedIn with Xcode or make test before launching a scenario.\n' >&2
  exit 1
fi

if [[ "${scenario}" == "live" ]]; then
  xcrun simctl launch \
    --terminate-running-process \
    booted \
    "${bundle_identifier}" >/dev/null
else
  xcrun simctl launch \
    --terminate-running-process \
    booted \
    "${bundle_identifier}" \
    -TUNEDIN_DEVELOPMENT_SCENARIO \
    "${scenario}" >/dev/null
fi

printf 'Launched tunedIn Development scenario: %s.\n' "${scenario}"
