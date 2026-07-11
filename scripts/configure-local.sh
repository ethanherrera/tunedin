#!/usr/bin/env bash
set -euo pipefail

config_dir="ios/Config"
names=(Base Local Development Staging Production)

for name in "${names[@]}"; do
  source_file="${config_dir}/${name}.xcconfig.example"
  destination_file="${config_dir}/${name}.xcconfig"

  if [[ ! -f "${destination_file}" ]]; then
    cp "${source_file}" "${destination_file}"
    printf 'Created %s\n' "${destination_file}"
  fi
done

# Xcode treats `//` as the start of a comment in an xcconfig value. Preserve
# existing local configuration while replacing the literal second slash with a
# build-setting expansion. Values are never printed.
base_configuration_file="${config_dir}/Base.xcconfig"
if ! grep -q '^[[:space:]]*TUNEDIN_URL_SLASH[[:space:]]*=' "${base_configuration_file}"; then
  printf '\nTUNEDIN_URL_SLASH = /\n' >>"${base_configuration_file}"
fi

for name in "${names[@]}"; do
  configuration_file="${config_dir}/${name}.xcconfig"
  temporary_file="$(mktemp)"

  awk '
    /^[[:space:]]*(SUPABASE_URL|POSTHOG_HOST)[[:space:]]*=/ {
      split($0, parts, "=")
      key = parts[1]
      value = parts[2]
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      sub(/^\"/, "", value)
      sub(/\"$/, "", value)
      sub(/^https:\/\//, "https:/$(TUNEDIN_URL_SLASH)", value)
      sub(/^http:\/\//, "http:/$(TUNEDIN_URL_SLASH)", value)
      print key "= " value
      next
    }
    { print }
  ' "${configuration_file}" >"${temporary_file}"

  mv "${temporary_file}" "${configuration_file}"
done

printf 'Add your Development Supabase URL and publishable key to ios/Config/Development.xcconfig.\n'
printf 'Run make configure-local-supabase after supabase start to configure ios/Config/Local.xcconfig.\n'
