#!/usr/bin/env bash
set -euo pipefail

readonly command="${1:-help}"
readonly device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-13"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(git -C "${script_dir}/.." rev-parse --show-toplevel)"
repository_root="$(cd "${repository_root}" && pwd -P)"

common_git_dir="$(git -C "${repository_root}" rev-parse --git-common-dir)"
if [[ "${common_git_dir}" != /* ]]; then
  common_git_dir="${repository_root}/${common_git_dir}"
fi
common_git_dir="$(cd "${common_git_dir}" && pwd -P)"
main_worktree_root="$(cd "${common_git_dir}/.." && pwd -P)"

if [[ "${repository_root}" == "${main_worktree_root}" ]]; then
  worktree_label="main"
else
  worktree_label="$(basename "$(dirname "${repository_root}")")"
fi

worktree_label="${worktree_label//[^[:alnum:]_.-]/-}"
worktree_label="${worktree_label:0:16}"
if [[ -z "${worktree_label}" ]]; then
  worktree_label="worktree"
fi

worktree_hash="$(printf '%s' "${repository_root}" | git hash-object --stdin | cut -c1-8)"
readonly device_name="tunedIn Worktree ${worktree_label}-${worktree_hash}"
readonly lock_root="${TUNEDIN_SIMULATOR_LOCK_ROOT:-${TMPDIR:-/tmp}}"
readonly lock_directory="${lock_root%/}/tunedin-simulator-${worktree_hash}.lock"

lock_owned=false
device_identifier=""

print_usage() {
  cat <<'EOF'
Usage: ./scripts/worktree-simulator.sh <command>

Commands:
  udid     Create the worktree's iPhone 13 Simulator when needed and print its UUID.
  boot     Create and boot the device, open its Simulator window, and print its UUID.
  status   Show the device assigned to the current Git worktree.
  delete   Shut down and delete only the device assigned to the current Git worktree.
  name     Print the deterministic device name without creating it.
EOF
}

release_lock() {
  if [[ "${lock_owned}" != true ]]; then
    return
  fi

  local owner=""
  if [[ -f "${lock_directory}/pid" ]]; then
    owner="$(<"${lock_directory}/pid")"
  fi

  if [[ "${owner}" == "$$" ]]; then
    rm -f "${lock_directory}/pid"
    rmdir "${lock_directory}" 2>/dev/null || true
  fi
  lock_owned=false
}

trap release_lock EXIT

acquire_lock() {
  local attempts=0
  local owner=""

  mkdir -p "${lock_root}"
  while ! mkdir "${lock_directory}" 2>/dev/null; do
    owner=""
    if [[ -f "${lock_directory}/pid" ]]; then
      owner="$(<"${lock_directory}/pid")"
    fi

    if [[ "${owner}" =~ ^[0-9]+$ ]] && ! kill -0 "${owner}" 2>/dev/null; then
      rm -f "${lock_directory}/pid"
      rmdir "${lock_directory}" 2>/dev/null || true
      continue
    fi

    attempts=$((attempts + 1))
    if ((attempts >= 300)); then
      printf 'Timed out waiting for another process to finish preparing %s.\n' "${device_name}" >&2
      exit 1
    fi
    sleep 0.1
  done

  printf '%s\n' "$$" >"${lock_directory}/pid"
  lock_owned=true
}

matching_device_identifiers() {
  local scope="$1"
  local listing=""
  local line=""
  local trimmed=""
  local suffix=""
  local identifier=""

  if [[ "${scope}" == "available" ]]; then
    listing="$(xcrun simctl list devices available)"
  else
    listing="$(xcrun simctl list devices)"
  fi

  while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "${trimmed}" in
      "${device_name} ("*)
        suffix="${trimmed#"${device_name} ("}"
        identifier="${suffix%%)*}"
        if [[ "${identifier}" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
          printf '%s\n' "${identifier}"
        fi
        ;;
    esac
  done <<<"${listing}"
}

ensure_device() {
  local create_output=""

  if ! command -v xcrun >/dev/null 2>&1; then
    printf 'Xcode command-line tools are required. Open Xcode and finish its first-launch setup.\n' >&2
    exit 1
  fi

  acquire_lock
  device_identifier="$(matching_device_identifiers available | sed -n '1p')"

  if [[ -z "${device_identifier}" ]]; then
    if ! create_output="$(xcrun simctl create "${device_name}" "${device_type}" 2>&1)"; then
      printf 'Could not create the worktree iPhone 13 Simulator. Install an iOS runtime in Xcode and try again.\n' >&2
      printf '%s\n' "${create_output}" >&2
      exit 1
    fi
    device_identifier="$(printf '%s\n' "${create_output}" | tail -n 1)"
  fi

  if [[ ! "${device_identifier}" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    printf 'CoreSimulator returned an invalid device identifier for %s.\n' "${device_name}" >&2
    exit 1
  fi

  release_lock
}

boot_device() {
  local developer_directory=""
  local simulator_application=""

  ensure_device

  if ! xcrun simctl bootstatus "${device_identifier}" -b >/dev/null; then
    printf 'Could not boot the worktree Simulator: %s (%s).\n' "${device_name}" "${device_identifier}" >&2
    exit 1
  fi

  developer_directory="$(xcode-select -p)"
  simulator_application="${developer_directory}/Applications/Simulator.app"
  if [[ ! -d "${simulator_application}" ]]; then
    printf 'Could not find Simulator.app under the selected Xcode: %s\n' "${developer_directory}" >&2
    exit 1
  fi

  if ! open "${simulator_application}" --args -CurrentDeviceUDID "${device_identifier}" >/dev/null; then
    printf 'The device booted, but its Simulator window could not be opened: %s\n' "${device_name}" >&2
    exit 1
  fi
}

show_status() {
  local listing=""
  local line=""
  local trimmed=""
  local matches=0

  printf 'Worktree: %s\n' "${repository_root}"
  printf 'Simulator: %s\n' "${device_name}"

  listing="$(xcrun simctl list devices)"
  while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "${trimmed}" in
      "${device_name} ("*)
        printf 'Device: %s\n' "${trimmed}"
        matches=$((matches + 1))
        ;;
    esac
  done <<<"${listing}"

  if ((matches == 0)); then
    printf 'Device: not created (run make simulator-create)\n'
  fi
}

delete_devices() {
  local identifiers=""
  local identifier=""
  local deleted=0

  acquire_lock
  identifiers="$(matching_device_identifiers all)"

  while IFS= read -r identifier; do
    if [[ -z "${identifier}" ]]; then
      continue
    fi
    xcrun simctl shutdown "${identifier}" >/dev/null 2>&1 || true
    xcrun simctl delete "${identifier}"
    deleted=$((deleted + 1))
  done <<<"${identifiers}"

  release_lock

  if ((deleted == 0)); then
    printf 'No Simulator exists for this worktree: %s\n' "${device_name}"
  else
    printf 'Deleted %d Simulator device(s) for this worktree: %s\n' "${deleted}" "${device_name}"
  fi
}

case "${command}" in
  udid)
    ensure_device
    printf '%s\n' "${device_identifier}"
    ;;
  boot)
    boot_device
    printf '%s\n' "${device_identifier}"
    ;;
  status)
    show_status
    ;;
  delete)
    delete_devices
    ;;
  name)
    printf '%s\n' "${device_name}"
    ;;
  help | --help | -h)
    print_usage
    ;;
  *)
    printf 'Unknown Simulator command: %s\n' "${command}" >&2
    print_usage >&2
    exit 2
    ;;
esac
