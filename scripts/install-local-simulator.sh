#!/usr/bin/env bash
set -euo pipefail

project="tunedIn.xcodeproj"
scheme="tunedIn-Local"
bundle_identifier="com.ethanherrera.tunedin"

device_identifier="$(xcrun simctl list devices available | awk -F '[()]' '
  /^[[:space:]]*iPhone 13 \(/ { print $2; exit }
')"

if [[ -z "${device_identifier}" ]]; then
  printf 'Could not find an available iPhone 13 Simulator runtime. Install one in Xcode, then rerun make simulator-local.\n' >&2
  exit 1
fi

destination="platform=iOS Simulator,id=${device_identifier}"

if [[ ! -f ios/Config/Local.xcconfig ]]; then
  printf 'Missing Local Xcode configuration. Run make configure-local-supabase first.\n' >&2
  exit 1
fi

if grep -q 'REPLACE_WITH_LOCAL_PUBLISHABLE_KEY' ios/Config/Local.xcconfig; then
  printf 'Local Xcode configuration is not populated. Run make configure-local-supabase first.\n' >&2
  exit 1
fi

xcrun simctl boot "${device_identifier}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${device_identifier}" -b >/dev/null

settings="$(xcodebuild -project "${project}" -scheme "${scheme}" -destination "${destination}" -showBuildSettings)"
target_build_dir="$(awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }' <<<"${settings}")"
wrapper_name="$(awk -F ' = ' '/^[[:space:]]*WRAPPER_NAME = / { print $2; exit }' <<<"${settings}")"
app_path="${target_build_dir}/${wrapper_name}"

if [[ -z "${target_build_dir}" || -z "${wrapper_name}" || ! -d "${app_path}" ]]; then
  printf 'Could not locate the Local build product. Run make build-local and try again.\n' >&2
  exit 1
fi

xcrun simctl install "${device_identifier}" "${app_path}"
xcrun simctl launch --terminate-running-process "${device_identifier}" "${bundle_identifier}" >/dev/null

printf 'Installed and launched tunedIn with the Local Supabase configuration on iPhone 13.\n'
