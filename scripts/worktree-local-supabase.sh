#!/usr/bin/env bash
set -euo pipefail

readonly command="${1:-help}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(git -C "${script_dir}/.." rev-parse --show-toplevel)"
repository_root="$(cd "${repository_root}" && pwd -P)"
source_project_directory="${repository_root}/supabase"

worktree_hash="$(printf '%s' "${repository_root}" | git hash-object --stdin | cut -c1-8)"
state_directory="${source_project_directory}/.temp/worktrees/${worktree_hash}"
project_directory="${state_directory}/project"
generated_supabase_directory="${project_directory}/supabase"
config_file="${generated_supabase_directory}/config.toml"

# Keep each stack in a high, deterministic port block. Twenty ports leave room for
# Supabase services that are enabled by a future config change without overlapping
# another worktree's block.
port_slot=$((16#${worktree_hash:0:4} % 400))
port_base=$((55000 + port_slot * 20))
project_id="tunedin-${worktree_hash}"
musicbrainz_stub_port=$((port_base + 10))

print_usage() {
  cat <<'EOF'
Usage: ./scripts/worktree-local-supabase.sh <command>

Commands:
  start       Create the generated project and start its isolated Supabase stack.
  stop        Stop only this worktree's isolated Supabase stack.
  reset       Reset this worktree's database, migrations, and seed.
  status      Show non-secret URLs for this worktree's stack.
  status-env  Print the local stack environment for helper scripts; never log it.
  project-dir Print the generated Supabase project directory.
  stub-port   Print the worktree's MusicBrainz fixture port.
  query       Run `supabase db query` against this worktree's local database.
  types       Run `supabase gen types` against this worktree's local database.
  test-db     Run the local database test suite against this worktree's stack.
  functions   Run `supabase functions` against this worktree's generated project.
EOF
}

ensure_link() {
  local name="$1"
  local target="$2"
  local link_path="${generated_supabase_directory}/${name}"

  if [[ -d "${link_path}" && ! -L "${link_path}" ]] && [[ -z "$(ls -A "${link_path}")" ]]; then
    rmdir "${link_path}"
  fi
  if [[ -e "${link_path}" || -L "${link_path}" ]]; then
    return
  fi
  ln -s "${target}" "${link_path}"
}

ensure_project() {
  mkdir -p "${generated_supabase_directory}"
  ensure_link migrations "${source_project_directory}/migrations"
  ensure_link functions "${source_project_directory}/functions"
  ensure_link seeds "${source_project_directory}/seeds"
  ensure_link tests "${source_project_directory}/tests"

  local temporary_file
  temporary_file="$(mktemp "${state_directory}/config.XXXXXX")"
  awk \
    -v project_id="${project_id}" \
    -v api_port="$((port_base + 1))" \
    -v db_port="$((port_base + 2))" \
    -v shadow_port="${port_base}" \
    -v pooler_port="$((port_base + 9))" \
    -v studio_port="$((port_base + 3))" \
    -v smtp_port="$((port_base + 4))" \
    -v inspector_port="$((port_base + 8))" \
    -v analytics_port="$((port_base + 7))" '
      /^project_id = "tunedin"$/ { print "project_id = \"" project_id "\""; next }
      /^port = 54321$/ { print "port = " api_port; next }
      /^port = 54322$/ { print "port = " db_port; next }
      /^shadow_port = 54320$/ { print "shadow_port = " shadow_port; next }
      /^port = 54329$/ { print "port = " pooler_port; next }
      /^port = 54323$/ { print "port = " studio_port; next }
      /^port = 54324$/ { print "port = " smtp_port; next }
      /^inspector_port = 8083$/ { print "inspector_port = " inspector_port; next }
      /^port = 54327$/ { print "port = " analytics_port; next }
      { print }
    ' "${source_project_directory}/config.toml" >"${temporary_file}"
  mv "${temporary_file}" "${config_file}"
}

run_supabase() {
  supabase --workdir "${project_directory}" "$@"
}

case "${command}" in
  start)
    ensure_project
    run_supabase start
    ;;
  stop)
    ensure_project
    run_supabase stop --no-backup
    ;;
  reset)
    ensure_project
    run_supabase db reset
    ;;
  status-env)
    ensure_project
    run_supabase status -o env
    ;;
  status)
    ensure_project
    status_output="$(run_supabase status -o env 2>/dev/null)"
    read_env_value() {
      local key="$1"
      awk -v wanted_key="${key}" '
        index($0, wanted_key "=") == 1 {
          value = substr($0, length(wanted_key) + 2)
          sub(/^"/, "", value)
          sub(/"$/, "", value)
          print value
          exit
        }
      ' <<<"${status_output}"
    }
    printf 'Worktree: %s\n' "${repository_root}"
    printf 'Project: %s\n' "${project_id}"
    printf 'API: %s\n' "$(read_env_value API_URL)"
    printf 'Database: %s\n' "$(read_env_value DB_URL)"
    printf 'Inbucket: %s\n' "$(read_env_value INBUCKET_URL)"
    printf 'MusicBrainz stub: http://127.0.0.1:%s\n' "${musicbrainz_stub_port}"
    ;;
  project-dir)
    ensure_project
    printf '%s\n' "${project_directory}"
    ;;
  stub-port)
    printf '%s\n' "${musicbrainz_stub_port}"
    ;;
  query)
    ensure_project
    shift
    run_supabase db query "$@"
    ;;
  types)
    ensure_project
    shift
    run_supabase gen types "$@"
    ;;
  test-db)
    ensure_project
    run_supabase test db --local "${generated_supabase_directory}/tests"
    ;;
  functions)
    ensure_project
    shift
    run_supabase functions "$@"
    ;;
  help | --help | -h)
    print_usage
    ;;
  *)
    printf 'Unknown Local Supabase command: %s\n' "${command}" >&2
    print_usage >&2
    exit 2
    ;;
esac
