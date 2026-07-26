#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly local_supabase_helper="${repository_root}/scripts/worktree-local-supabase.sh"
readonly state_directory="${repository_root}/supabase/.temp/music-catalog"
readonly stub_pid_file="${state_directory}/stub.pid"
readonly function_pid_file="${state_directory}/function.pid"
readonly stub_log_file="${state_directory}/stub.log"
readonly function_log_file="${state_directory}/function.log"
readonly function_env_file="${state_directory}/function.env"
stub_port="${MUSICBRAINZ_STUB_PORT:-}"
if [[ -z "${stub_port}" ]]; then
  stub_port="$("${local_supabase_helper}" stub-port)"
fi

usage() {
  cat <<'USAGE'
Usage: ./scripts/local-music-catalog.sh <start|stop|status|verify>

  start   Start/reuse the fixture-only MusicBrainz stub and local Edge Function worker.
  stop    Stop only the processes tracked by this helper.
  status  Report whether both tracked local processes are running.
  verify  Start/reuse them and exercise the authenticated gateway against Local Supabase.

This helper accepts only the disposable loopback Supabase stack and never contacts a
hosted Supabase project or the live MusicBrainz service.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s is required. Run make setup, then try again.\n' "$1" >&2
    exit 1
  fi
}

read_pid() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local pid
    pid="$(<"$file")"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      printf '%s' "$pid"
      return 0
    fi
  fi
  return 1
}

stop_tracked_process() {
  local pid_file="$1"
  local pid=""
  if pid="$(read_pid "$pid_file")"; then
    kill "$pid" 2>/dev/null || true
    for _ in {1..20}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
  fi
  rm -f "$pid_file"
}

write_function_environment() {
  umask 077
  {
    printf 'TUNEDIN_ENVIRONMENT=Local\n'
    printf 'MUSICBRAINZ_BASE_URL=http://host.docker.internal:%s/ws/2/\n' "$stub_port"
    printf 'MUSICBRAINZ_ARTWORK_BASE_URL=http://host.docker.internal:%s/\n' "$stub_port"
    printf 'MUSICBRAINZ_USER_AGENT=tunedIn/local-fixture (mailto:fixture-only@tunedin.invalid)\n'
  } >"$function_env_file"
}

wait_for_process() {
  local pid_file="$1"
  local label="$2"
  for _ in {1..100}; do
    if read_pid "$pid_file" >/dev/null; then
      sleep 0.1
      if read_pid "$pid_file" >/dev/null; then
        return 0
      fi
    fi
    sleep 0.1
  done
  printf '%s did not stay running. Inspect the ignored log under %s.\n' "$label" "$state_directory" >&2
  return 1
}

wait_for_stub_ready() {
  for _ in {1..100}; do
    local status
    status="$(curl --silent --output /dev/null --max-time 1 --write-out '%{http_code}' \
      -H 'Accept: application/json' \
      -H 'User-Agent: tunedIn/local-readiness (mailto:fixture-only@tunedin.invalid)' \
      "http://127.0.0.1:${stub_port}/ws/2/artist?query=artist%3A%22fixture%22&fmt=json&limit=15&offset=0" || true)"
    if [[ "$status" == "200" ]]; then
      return 0
    fi
    sleep 0.2
  done
  printf 'MusicBrainz fixture stub did not become ready. Inspect %s.\n' "$stub_log_file" >&2
  return 1
}

wait_for_function_ready() {
  local api_url="$1"
  for _ in {1..150}; do
    local status
    status="$(curl --silent --output /dev/null --max-time 1 --write-out '%{http_code}' \
      -X OPTIONS "${api_url%/}/functions/v1/music-catalog" || true)"
    if [[ "$status" == "204" || "$status" == "401" ]]; then
      return 0
    fi
    sleep 0.2
  done
  printf 'Local music-catalog Function did not become ready. Inspect %s.\n' "$function_log_file" >&2
  return 1
}

start_catalog() {
  require_command deno
  require_command supabase
  require_command curl
  cd "$repository_root"
  local status_output
  if ! status_output="$("${local_supabase_helper}" status-env 2>/dev/null)"; then
    printf 'Disposable Local Supabase is not running. Run make local-db-start first.\n' >&2
    exit 1
  fi
  mkdir -p "$state_directory"
  write_function_environment

  if ! read_pid "$stub_pid_file" >/dev/null; then
    MUSICBRAINZ_STUB_PORT="$stub_port" nohup deno run \
      --allow-env=MUSICBRAINZ_STUB_PORT \
      --allow-net="0.0.0.0:${stub_port},127.0.0.1:${stub_port}" \
      --allow-read="${repository_root}/supabase/functions/music-catalog/fixtures" \
      scripts/musicbrainz-stub.ts >"$stub_log_file" 2>&1 &
    printf '%s\n' "$!" >"$stub_pid_file"
    wait_for_process "$stub_pid_file" "MusicBrainz fixture stub" || {
      stop_tracked_process "$stub_pid_file"
      exit 1
    }
  fi

  if ! read_pid "$function_pid_file" >/dev/null; then
    nohup "${local_supabase_helper}" functions serve --env-file "$function_env_file" \
      >"$function_log_file" 2>&1 &
    printf '%s\n' "$!" >"$function_pid_file"
    wait_for_process "$function_pid_file" "Local Edge Function worker" || {
      stop_tracked_process "$function_pid_file"
      stop_tracked_process "$stub_pid_file"
      exit 1
    }
  fi

  local api_url
  api_url="$(read_env_value "$status_output" API_URL)"
  if [[ ! "$api_url" =~ ^http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]+/?$ ]]; then
    printf 'The Local Function lifecycle refuses a non-loopback Supabase URL.\n' >&2
    stop_tracked_process "$function_pid_file"
    stop_tracked_process "$stub_pid_file"
    exit 1
  fi
  wait_for_stub_ready || {
    stop_tracked_process "$function_pid_file"
    stop_tracked_process "$stub_pid_file"
    exit 1
  }
  wait_for_function_ready "$api_url" || {
    stop_tracked_process "$function_pid_file"
    stop_tracked_process "$stub_pid_file"
    exit 1
  }

  printf 'Local music catalog fixture gateway is running against disposable Local Supabase.\n'
}

stop_catalog() {
  stop_tracked_process "$function_pid_file"
  stop_tracked_process "$stub_pid_file"
  rm -f "$function_env_file" "$function_log_file" "$stub_log_file"
  printf 'Stopped the tracked Local music catalog processes. Local Supabase was not stopped.\n'
}

show_status() {
  local stub_pid=""
  local function_pid=""
  stub_pid="$(read_pid "$stub_pid_file" || true)"
  function_pid="$(read_pid "$function_pid_file" || true)"
  if [[ -n "$stub_pid" && -n "$function_pid" ]]; then
    printf 'Local music catalog is running (stub PID %s, function PID %s).\n' \
      "$stub_pid" "$function_pid"
    return 0
  fi
  printf 'Local music catalog is not fully running. Use make local-catalog-start.\n' >&2
  return 1
}

read_env_value() {
  local status_output="$1"
  local key="$2"
  awk -v wanted_key="$key" '
    index($0, wanted_key "=") == 1 {
      value = substr($0, length(wanted_key) + 2)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
      exit
    }
  ' <<<"$status_output"
}

verify_catalog() {
  start_catalog >/dev/null
  local status_output
  status_output="$("${local_supabase_helper}" status-env 2>/dev/null)"
  local api_url
  local publishable_key
  api_url="$(read_env_value "$status_output" API_URL)"
  publishable_key="$(read_env_value "$status_output" PUBLISHABLE_KEY)"
  if [[ -z "$publishable_key" ]]; then
    publishable_key="$(read_env_value "$status_output" ANON_KEY)"
  fi
  if [[ ! "$api_url" =~ ^http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]+/?$ ]]; then
    printf 'The catalog verifier refuses a non-loopback Supabase URL.\n' >&2
    exit 1
  fi
  if [[ -z "$publishable_key" ]]; then
    printf 'Local Supabase did not return a publishable key.\n' >&2
    exit 1
  fi
  LOCAL_SUPABASE_URL="$api_url" \
  LOCAL_SUPABASE_PUBLISHABLE_KEY="$publishable_key" \
    deno run \
      --allow-env=LOCAL_SUPABASE_URL,LOCAL_SUPABASE_PUBLISHABLE_KEY \
      --allow-net="127.0.0.1,localhost,[::1]" \
      scripts/verify-local-music-catalog.ts
}

command="${1:-}"
case "$command" in
start)
  start_catalog
  ;;
stop)
  stop_catalog
  ;;
status)
  show_status
  ;;
verify)
  verify_catalog
  ;;
*)
  usage >&2
  exit 1
  ;;
esac
