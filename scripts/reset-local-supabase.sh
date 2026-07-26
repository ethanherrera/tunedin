#!/usr/bin/env bash
set -euo pipefail

readonly max_attempts=2

for attempt in $(seq 1 "$max_attempts"); do
  if ./scripts/worktree-local-supabase.sh start >/dev/null && ./scripts/worktree-local-supabase.sh reset; then
    echo "Disposable Local Supabase database reset successfully."
    exit 0
  fi

  if [[ "$attempt" -eq "$max_attempts" ]]; then
    echo "Local Supabase reset failed after $max_attempts attempts." >&2
    exit 1
  fi

  echo "Local Supabase reset failed; rebuilding the disposable stack and retrying once." >&2
  ./scripts/worktree-local-supabase.sh stop >/dev/null 2>&1 || true
done
