#!/usr/bin/env bash
set -euo pipefail

project="tunedIn.xcodeproj"
scheme="tunedIn-Local"
destination="platform=iOS Simulator,name=iPhone 13"
bundle_identifier="com.ethanherrera.tunedin"

if [[ ! -f ios/Config/Local.xcconfig ]]; then
  printf 'Missing Local Xcode configuration. Run make configure-local-supabase first.\n' >&2
  exit 1
fi

if grep -q 'REPLACE_WITH_LOCAL_PUBLISHABLE_KEY' ios/Config/Local.xcconfig; then
  printf 'Local Xcode configuration is not populated. Run make configure-local-supabase first.\n' >&2
  exit 1
fi

if ! xcrun simctl bootstatus booted -b >/dev/null 2>&1; then
  printf 'Boot an iPhone 13 Simulator in Xcode or Simulator, then rerun make simulator-local.\n' >&2
  exit 1
fi

settings="$(xcodebuild -project "${project}" -scheme "${scheme}" -destination "${destination}" -showBuildSettings)"
target_build_dir="$(awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }' <<<"${settings}")"
wrapper_name="$(awk -F ' = ' '/^[[:space:]]*WRAPPER_NAME = / { print $2; exit }' <<<"${settings}")"
app_path="${target_build_dir}/${wrapper_name}"

if [[ -z "${target_build_dir}" || -z "${wrapper_name}" || ! -d "${app_path}" ]]; then
  printf 'Could not locate the Local build product. Run make build-local and try again.\n' >&2
  exit 1
fi

xcrun simctl install booted "${app_path}"
xcrun simctl launch --terminate-running-process booted "${bundle_identifier}" >/dev/null

printf 'Installed and launched tunedIn with the Local Supabase configuration.\n'
