#!/usr/bin/env bash

set -euo pipefail

scenario="${1:-}"
bundle_identifier="com.ethanherrera.tunedin"
project="tunedIn.xcodeproj"
scheme="tunedIn-Development"

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

device_identifier="$(xcrun simctl list devices available | awk -F '[()]' '
  /^[[:space:]]*iPhone 13 \(/ { print $2; exit }
')"

if [[ -z "${device_identifier}" ]]; then
  printf 'Could not find an available iPhone 13 Simulator runtime. Install one in Xcode, then rerun the scenario command.\n' >&2
  exit 1
fi

destination="platform=iOS Simulator,id=${device_identifier}"

xcrun simctl boot "${device_identifier}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${device_identifier}" -b >/dev/null

settings="$(xcodebuild -project "${project}" -scheme "${scheme}" -destination "${destination}" -showBuildSettings)"
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

printf 'Installed and launched tunedIn Development scenario on iPhone 13: %s.\n' "${scenario}"
