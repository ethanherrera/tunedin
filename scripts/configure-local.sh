#!/usr/bin/env bash
set -euo pipefail

config_dir="ios/Config"
names=(Base Development Staging Production)

for name in "${names[@]}"; do
  source_file="${config_dir}/${name}.xcconfig.example"
  destination_file="${config_dir}/${name}.xcconfig"

  if [[ ! -f "${destination_file}" ]]; then
    cp "${source_file}" "${destination_file}"
    printf 'Created %s\n' "${destination_file}"
  fi
done

printf 'Add your Development Supabase URL and publishable key to ios/Config/Development.xcconfig.\n'
