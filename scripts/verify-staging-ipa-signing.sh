#!/usr/bin/env bash
set -euo pipefail

readonly expected_bundle_identifier="com.ethanherrera.tunedin.staging"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

ipa_path="${1:-build/StagingExport/tunedIn.ipa}"
if [[ ! -f "$ipa_path" ]]; then
  fail "Signed Staging IPA not found at $ipa_path."
fi
if [[ -z "${APPLE_DEVELOPMENT_TEAM:-}" ]]; then
  fail "APPLE_DEVELOPMENT_TEAM is required to verify the signed Staging IPA."
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
unzip -q "$ipa_path" -d "$temporary_directory/ipa"

application_count="$(find "$temporary_directory/ipa/Payload" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')"
if [[ "$application_count" -ne 1 ]]; then
  fail "Expected exactly one application in the signed Staging IPA."
fi
app_path="$(find "$temporary_directory/ipa/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
info_plist="$app_path/Info.plist"
mobileprovision="$app_path/embedded.mobileprovision"
if [[ ! -f "$info_plist" || ! -f "$mobileprovision" ]]; then
  fail "Signed Staging IPA is missing Info.plist or embedded.mobileprovision."
fi

codesign --verify --deep --strict "$app_path"
codesign -d --entitlements ":-" "$app_path" \
  >"$temporary_directory/signed-entitlements.plist" 2>"$temporary_directory/codesign.log"
security cms -D -i "$mobileprovision" >"$temporary_directory/profile.plist"

EXPECTED_BUNDLE_IDENTIFIER="$expected_bundle_identifier" \
APPLE_TEAM_ID="$APPLE_DEVELOPMENT_TEAM" \
INFO_PLIST="$info_plist" \
SIGNED_ENTITLEMENTS="$temporary_directory/signed-entitlements.plist" \
PROFILE_PLIST="$temporary_directory/profile.plist" \
  python3 <<'PY'
import datetime
import os
import plistlib


def read_plist(name):
    with open(os.environ[name], "rb") as source:
        return plistlib.load(source)


bundle_identifier = os.environ["EXPECTED_BUNDLE_IDENTIFIER"]
team_id = os.environ["APPLE_TEAM_ID"]
info = read_plist("INFO_PLIST")
signed = read_plist("SIGNED_ENTITLEMENTS")
profile = read_plist("PROFILE_PLIST")
profile_entitlements = profile.get("Entitlements", {})

if info.get("CFBundleIdentifier") != bundle_identifier:
    raise SystemExit("Signed IPA has the wrong bundle identifier.")
if signed.get("com.apple.developer.applesignin") != ["Default"]:
    raise SystemExit("Signed IPA is missing the Sign in with Apple entitlement.")
if profile_entitlements.get("com.apple.developer.applesignin") != ["Default"]:
    raise SystemExit("Distribution profile is missing the Sign in with Apple entitlement.")

expected_application_identifier = f"{team_id}.{bundle_identifier}"
if profile_entitlements.get("application-identifier") != expected_application_identifier:
    raise SystemExit("Distribution profile has the wrong application identifier.")
if profile_entitlements.get("com.apple.developer.team-identifier") != team_id:
    raise SystemExit("Distribution profile has the wrong Apple development team.")
if profile.get("TeamIdentifier") != [team_id]:
    raise SystemExit("Distribution profile TeamIdentifier does not match the protected environment.")
if profile_entitlements.get("get-task-allow") is not False:
    raise SystemExit("Distribution profile unexpectedly allows debugger attachment.")
if profile_entitlements.get("beta-reports-active") is not True:
    raise SystemExit("Distribution profile is not enabled for TestFlight beta reporting.")
if profile.get("ProvisionsAllDevices") is True or profile.get("ProvisionedDevices"):
    raise SystemExit("Signed IPA does not use an App Store distribution profile.")

expiration = profile.get("ExpirationDate")
if not isinstance(expiration, datetime.datetime):
    raise SystemExit("Distribution profile has no valid expiration date.")
now = datetime.datetime.now(tz=expiration.tzinfo) if expiration.tzinfo else datetime.datetime.now()
if expiration <= now:
    raise SystemExit("Distribution profile is expired.")

print("Signed Staging IPA and distribution profile match the Apple Sign In contract.")
PY
