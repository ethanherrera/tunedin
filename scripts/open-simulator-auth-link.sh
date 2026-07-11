#!/usr/bin/env bash

set -euo pipefail

if ! command -v xcrun >/dev/null 2>&1; then
  printf 'Xcode command-line tools are required. Open Xcode and finish its first-launch setup.\n' >&2
  exit 1
fi

if ! command -v pbpaste >/dev/null 2>&1; then
  printf 'The macOS clipboard command pbpaste is required.\n' >&2
  exit 1
fi

auth_url="$(pbpaste)"

if [[ -z "${auth_url}" ]]; then
  printf 'Clipboard is empty. Copy the Sign in link address from the Supabase email first.\n' >&2
  exit 1
fi

case "${auth_url}" in
  https://*.supabase.co/auth/v1/verify\?* | \
    http://127.0.0.1:54321/auth/v1/verify\?* | \
    http://localhost:54321/auth/v1/verify\?*) ;;
  *)
    printf 'Clipboard does not contain a recognized Supabase Auth verification URL.\n' >&2
    exit 1
    ;;
esac

if ! xcrun simctl openurl booted "${auth_url}" >/dev/null; then
  printf 'Could not open the link. Boot an iOS Simulator with tunedIn installed and try again.\n' >&2
  exit 1
fi

unset auth_url
printf 'Opened the Supabase sign-in link in the booted iOS Simulator. Choose Open if iOS asks to reopen tunedIn.\n'
