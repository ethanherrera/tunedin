#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(git -C "${script_dir}/.." rev-parse --show-toplevel)"
repository_root="$(cd "${repository_root}" && pwd -P)"

destination="${TUNEDIN_SIMULATOR_DESTINATION:-}"
if [[ -z "${destination}" ]]; then
  device_identifier="$("${script_dir}/worktree-simulator.sh" udid)"
  destination="platform=iOS Simulator,id=${device_identifier}"
fi

derived_data_path="${TUNEDIN_DERIVED_DATA_PATH:-${repository_root}/DerivedData}"

exec xcodebuild \
  -destination "${destination}" \
  -derivedDataPath "${derived_data_path}" \
  "$@"
