#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
simulator_script="${repository_root}/scripts/worktree-simulator.sh"
xcodebuild_script="${repository_root}/scripts/xcodebuild-simulator.sh"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

mock_bin="${temporary_directory}/bin"
mock_state="${temporary_directory}/state"
mock_developer="${temporary_directory}/Developer"
mkdir -p "${mock_bin}" "${mock_state}" "${mock_developer}/Applications/Simulator.app"

cat >"${mock_bin}/xcrun" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "simctl" ]]; then
  exit 2
fi
shift

readonly identifier="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

print_devices() {
  printf '%s\n' '== Devices ==' '-- iOS 26.5 --'
  if [[ -f "${MOCK_SIMCTL_STATE}/device-name" ]]; then
    name="$(<"${MOCK_SIMCTL_STATE}/device-name")"
    state="Shutdown"
    if [[ -f "${MOCK_SIMCTL_STATE}/booted" ]]; then
      state="Booted"
    fi
    printf '    %s (%s) (%s) \n' "${name}" "${identifier}" "${state}"
  fi
}

case "${1:-}" in
  list)
    print_devices
    ;;
  create)
    printf '%s\n' "${2:?}" >"${MOCK_SIMCTL_STATE}/device-name"
    count=0
    if [[ -f "${MOCK_SIMCTL_STATE}/create-count" ]]; then
      count="$(<"${MOCK_SIMCTL_STATE}/create-count")"
    fi
    printf '%d\n' "$((count + 1))" >"${MOCK_SIMCTL_STATE}/create-count"
    printf '%s\n' "${identifier}"
    ;;
  bootstatus)
    [[ "${2:?}" == "${identifier}" ]]
    touch "${MOCK_SIMCTL_STATE}/booted"
    ;;
  shutdown)
    [[ "${2:?}" == "${identifier}" ]]
    rm -f "${MOCK_SIMCTL_STATE}/booted"
    ;;
  delete)
    [[ "${2:?}" == "${identifier}" ]]
    rm -f "${MOCK_SIMCTL_STATE}/device-name" "${MOCK_SIMCTL_STATE}/booted"
    ;;
  *)
    printf 'Unexpected mock simctl command: %s\n' "$*" >&2
    exit 2
    ;;
esac
MOCK

cat >"${mock_bin}/xcode-select" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "-p" ]]
printf '%s\n' "${MOCK_DEVELOPER_DIR}"
MOCK

cat >"${mock_bin}/open" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${MOCK_SIMCTL_STATE}/open-arguments"
MOCK

cat >"${mock_bin}/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${MOCK_SIMCTL_STATE}/xcodebuild-arguments"
MOCK

chmod +x "${mock_bin}/xcrun" "${mock_bin}/xcode-select" "${mock_bin}/open" "${mock_bin}/xcodebuild"

export PATH="${mock_bin}:${PATH}"
export MOCK_SIMCTL_STATE="${mock_state}"
export MOCK_DEVELOPER_DIR="${mock_developer}"
export TUNEDIN_SIMULATOR_LOCK_ROOT="${temporary_directory}/locks"

expected_identifier="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
actual_identifier="$("${simulator_script}" udid)"
[[ "${actual_identifier}" == "${expected_identifier}" ]]
[[ "$(<"${mock_state}/create-count")" == "1" ]]

actual_identifier="$("${simulator_script}" udid)"
[[ "${actual_identifier}" == "${expected_identifier}" ]]
[[ "$(<"${mock_state}/create-count")" == "1" ]]

actual_identifier="$("${simulator_script}" boot)"
[[ "${actual_identifier}" == "${expected_identifier}" ]]
grep -Fq -- "-CurrentDeviceUDID ${expected_identifier}" "${mock_state}/open-arguments"

status_output="$("${simulator_script}" status)"
grep -Fq "${expected_identifier}" <<<"${status_output}"
grep -Fq '(Booted)' <<<"${status_output}"

"${xcodebuild_script}" -project tunedIn.xcodeproj -scheme tunedIn-Development build
xcodebuild_arguments="$(<"${mock_state}/xcodebuild-arguments")"
grep -Fq -- "-destination platform=iOS Simulator,id=${expected_identifier}" <<<"${xcodebuild_arguments}"
grep -Fq -- "-derivedDataPath ${repository_root}/DerivedData" <<<"${xcodebuild_arguments}"

TUNEDIN_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17' \
  TUNEDIN_DERIVED_DATA_PATH="${temporary_directory}/ci-derived-data" \
  "${xcodebuild_script}" test
xcodebuild_arguments="$(<"${mock_state}/xcodebuild-arguments")"
grep -Fq -- '-destination platform=iOS Simulator,name=iPhone 17' <<<"${xcodebuild_arguments}"
grep -Fq -- "-derivedDataPath ${temporary_directory}/ci-derived-data" <<<"${xcodebuild_arguments}"

delete_output="$("${simulator_script}" delete)"
grep -Fq 'Deleted 1 Simulator device(s)' <<<"${delete_output}"
[[ ! -f "${mock_state}/device-name" ]]

printf 'Worktree Simulator scripts passed.\n'
