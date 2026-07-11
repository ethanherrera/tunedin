#!/usr/bin/env bash
set -euo pipefail

required_tools=(git gh supabase xcodebuild xcodegen swiftformat swiftlint deno docker)
missing_tools=()

for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    missing_tools+=("${tool}")
  fi
done

if ((${#missing_tools[@]} > 0)); then
  printf 'Missing required tools: %s\n' "${missing_tools[*]}" >&2
  printf 'Install Homebrew tools with: brew bundle --file=Brewfile\n' >&2
  printf 'Install Xcode from the App Store, then run: xcode-select --install\n' >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  printf 'Xcode is not selected. Run: sudo xcode-select --switch /Applications/Xcode.app\n' >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  printf 'Docker Desktop is installed but not running. Open Docker and rerun: make setup\n' >&2
  exit 1
fi

if [[ ! -f ios/Config/Development.xcconfig ]]; then
  printf 'Missing local Xcode configuration. Run: make configure\n' >&2
  exit 1
fi

printf 'Toolchain verified.\n'
xcodebuild -version | sed -n '1,2p'
supabase --version
