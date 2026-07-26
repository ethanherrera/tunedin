#!/usr/bin/env bash

set -euo pipefail

scenario="${1:-}"
bundle_identifier="com.ethanherrera.tunedin"
project="tunedIn.xcodeproj"
scheme="tunedIn-Development"

case "${scenario}" in
  live | signed-out | onboarding | profile | profile-error | community-events) ;;
  *)
    printf 'Unknown Development scenario. Use live, signed-out, onboarding, profile, profile-error, or community-events.\n' >&2
    exit 1
    ;;
esac

if ! command -v xcrun >/dev/null 2>&1; then
  printf 'Xcode command-line tools are required. Open Xcode and finish its first-launch setup.\n' >&2
  exit 1
fi

device_identifier="$(./scripts/worktree-simulator.sh boot)"
destination="platform=iOS Simulator,id=${device_identifier}"

settings="$(
  TUNEDIN_SIMULATOR_DESTINATION="${destination}" \
    ./scripts/xcodebuild-simulator.sh \
    -project "${project}" \
    -scheme "${scheme}" \
    -showBuildSettings
)"
target_build_dir="$(awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }' <<<"${settings}")"
wrapper_name="$(awk -F ' = ' '/^[[:space:]]*WRAPPER_NAME = / { print $2; exit }' <<<"${settings}")"
app_path="${target_build_dir}/${wrapper_name}"

if [[ -z "${target_build_dir}" || -z "${wrapper_name}" || ! -d "${app_path}" ]]; then
  printf 'Could not locate the Development build product. Run make build and try again.\n' >&2
  exit 1
fi

xcrun simctl install "${device_identifier}" "${app_path}"

if [[ "${scenario}" == "live" ]]; then
  xcrun simctl launch \
    --terminate-running-process \
    "${device_identifier}" \
    "${bundle_identifier}" >/dev/null
else
  xcrun simctl launch \
    --terminate-running-process \
    "${device_identifier}" \
    "${bundle_identifier}" \
    -TUNEDIN_DEVELOPMENT_SCENARIO \
    "${scenario}" >/dev/null
fi

printf 'Installed and launched tunedIn Development scenario %s on this worktree Simulator: %s.\n' \
  "${scenario}" \
  "${device_identifier}"
