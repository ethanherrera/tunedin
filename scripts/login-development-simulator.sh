#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${EMAIL:-}" ]]; then
  printf 'EMAIL must name the Development test identity to sign in.\n' >&2
  exit 1
fi

for command in pbpaste xcrun; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  fi
done

./scripts/generate-development-login-link.sh

auth_url="$(pbpaste)"
case "$auth_url" in
  com.ethanherrera.tunedin://auth-callback\?token_hash=*\&type=email) ;;
  *)
    printf 'Generated an unexpected Development callback URL.\n' >&2
    exit 1
    ;;
esac

if ! xcrun simctl openurl booted "$auth_url" >/dev/null; then
  printf 'Could not open the Development login link. Boot an iOS Simulator with tunedIn installed and try again.\n' >&2
  exit 1
fi

unset auth_url
printf 'Opened the Development login link in the booted Simulator. Choose Open if iOS asks to reopen tunedIn.\n'
