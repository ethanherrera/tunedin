#!/usr/bin/env bash
set -euo pipefail

info_plist="ios/tunedIn/Resources/Info.plist"
icon_catalog="ios/tunedIn/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
icon_file="ios/tunedIn/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

for path in "$info_plist" "$icon_catalog" "$icon_file"; do
  if [[ ! -f "$path" ]]; then
    printf 'Missing required distribution asset: %s\n' "$path" >&2
    exit 1
  fi
done

assert_plist_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(plutil -extract "$key" raw "$file")"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s must set %s to %s (found %s).\n' "$file" "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_plist_value "$info_plist" CFBundleIconName AppIcon
assert_plist_value "$info_plist" CFBundlePackageType APPL
assert_plist_value "$info_plist" ITSAppUsesNonExemptEncryption false
assert_plist_value "$icon_catalog" images.0.filename AppIcon.png
assert_plist_value "$icon_catalog" images.0.idiom universal
assert_plist_value "$icon_catalog" images.0.platform ios
assert_plist_value "$icon_catalog" images.0.size 1024x1024

pixel_width="$(sips -g pixelWidth "$icon_file" | awk '/pixelWidth:/ { print $2 }')"
pixel_height="$(sips -g pixelHeight "$icon_file" | awk '/pixelHeight:/ { print $2 }')"
has_alpha="$(sips -g hasAlpha "$icon_file" | awk '/hasAlpha:/ { print $2 }')"

if [[ "$pixel_width" != "1024" || "$pixel_height" != "1024" ]]; then
  printf 'AppIcon.png must be exactly 1024x1024 pixels (found %sx%s).\n' "$pixel_width" "$pixel_height" >&2
  exit 1
fi

if [[ "$has_alpha" != "no" ]]; then
  printf 'AppIcon.png must be opaque because App Store icons cannot contain alpha.\n' >&2
  exit 1
fi

printf 'Distribution metadata and AppIcon.png are valid.\n'
