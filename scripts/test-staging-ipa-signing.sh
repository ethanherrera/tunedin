#!/usr/bin/env bash
set -euo pipefail

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/Payload/tunedIn.app" "$temporary_directory/bin"
app_path="$temporary_directory/Payload/tunedIn.app"

cat >"$app_path/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>tunedIn</string>
  <key>CFBundleIdentifier</key>
  <string>com.ethanherrera.tunedin.staging</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST
cp /usr/bin/true "$app_path/tunedIn"
printf 'fixture' >"$app_path/embedded.mobileprovision"

cat >"$temporary_directory/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.applesignin</key>
  <array><string>Default</string></array>
</dict>
</plist>
PLIST
codesign --force --sign - --entitlements "$temporary_directory/entitlements.plist" \
  --generate-entitlement-der "$app_path"

cat >"$temporary_directory/profile.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>ExpirationDate</key>
  <date>2035-01-01T00:00:00Z</date>
  <key>TeamIdentifier</key>
  <array><string>TEAM123456</string></array>
  <key>Entitlements</key>
  <dict>
    <key>application-identifier</key>
    <string>TEAM123456.com.ethanherrera.tunedin.staging</string>
    <key>beta-reports-active</key>
    <true/>
    <key>com.apple.developer.applesignin</key>
    <array><string>Default</string></array>
    <key>com.apple.developer.team-identifier</key>
    <string>TEAM123456</string>
    <key>get-task-allow</key>
    <false/>
  </dict>
</dict>
</plist>
PLIST

cat >"$temporary_directory/bin/security" <<'FAKE_SECURITY'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != "cms" || "$2" != "-D" || "$3" != "-i" ]]; then
  printf 'Unexpected security fixture invocation.\n' >&2
  exit 1
fi
cat "$FAKE_PROFILE_PLIST"
FAKE_SECURITY
chmod +x "$temporary_directory/bin/security"

(
  cd "$temporary_directory"
  /usr/bin/zip -qry tunedIn.ipa Payload
)

export PATH="$temporary_directory/bin:$PATH"
export FAKE_PROFILE_PLIST="$temporary_directory/profile.plist"
export APPLE_DEVELOPMENT_TEAM="TEAM123456"
./scripts/verify-staging-ipa-signing.sh "$temporary_directory/tunedIn.ipa" >/dev/null

/usr/libexec/PlistBuddy -c 'Delete :Entitlements:com.apple.developer.applesignin' "$FAKE_PROFILE_PLIST"
if ./scripts/verify-staging-ipa-signing.sh "$temporary_directory/tunedIn.ipa" >/dev/null 2>&1; then
  printf 'Signed IPA verification accepted a profile without Sign in with Apple.\n' >&2
  exit 1
fi

printf 'Staging signed IPA verification is valid.\n'
