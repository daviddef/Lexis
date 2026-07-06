#!/usr/bin/env bash
#
# Build, archive, and upload LEXIS to TestFlight — entirely from the CLI, no
# Xcode GUI. This is exactly what Xcode's Organizer does, scripted.
#
#   ./scripts/testflight.sh            bump the build number and upload
#   ./scripts/testflight.sh 1.3        set marketing version to 1.3 (build 1) and upload
#
# Each upload needs a UNIQUE build number within a marketing version, so with
# no argument this auto-increments CURRENT_PROJECT_VERSION in project.yml.
# Pass a version string to start a new marketing version (build resets to 1).
#
# Requirements (all already set up on this machine):
#   • xcodegen on PATH
#   • App Store Connect API key at the path below (the .p8 stays local; only
#     the Key ID / Issuer ID live here, which is fine — they aren't secrets)
#   • an Apple Developer account with distribution rights; the API key +
#     -allowProvisioningUpdates create/fetch the distribution cert + profiles
#     automatically, so no manual signing is needed.
#
set -euo pipefail

# ---- config ---------------------------------------------------------------
API_KEY_ID="9K9486HSDF"
API_ISSUER_ID="69a6de8c-a266-47e3-e053-5b8c7c11a4d1"
TEAM_ID="L9SAXP2E2W"
SCHEME="LEXIS"
PROJECT="LEXIS.xcodeproj"
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"

# Run from the repo root regardless of where this is invoked from.
cd "$(dirname "$0")/.."

# ---- preflight ------------------------------------------------------------
command -v xcodegen >/dev/null || { echo "❌ xcodegen not found on PATH"; exit 1; }
[[ -f "$API_KEY_PATH" ]] || { echo "❌ API key not found at $API_KEY_PATH"; exit 1; }

NEW_VERSION="${1:-}"

# BSD (macOS) sed needs the empty-string suffix for in-place edits.
sedi() { sed -i '' "$@"; }

CUR_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([0-9]+)".*/\1/')"

if [[ -n "$NEW_VERSION" ]]; then
  NEW_BUILD=1
  sedi -E "s/(MARKETING_VERSION: )\"[^\"]*\"/\1\"$NEW_VERSION\"/" project.yml
else
  NEW_BUILD=$(( CUR_BUILD + 1 ))
fi
sedi -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$NEW_BUILD\"/" project.yml

MKT="$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]*)".*/\1/')"
echo "▸ Uploading LEXIS ${MKT} (build ${NEW_BUILD})"

# ---- regenerate + archive -------------------------------------------------
xcodegen generate

ARCHIVE="build/LEXIS.xcarchive"
rm -rf build && mkdir -p build

echo "▸ Archiving…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  archive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID"

# ---- export + upload ------------------------------------------------------
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "▸ Exporting + uploading to App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID"

echo ""
echo "✅ Uploaded LEXIS ${MKT} (build ${NEW_BUILD})."
echo "   It'll appear in TestFlight after App Store Connect finishes processing (a few min)."
echo "   Tip: commit the version bump in project.yml so it doesn't drift —"
echo "        git commit -am \"Bump to ${MKT} (build ${NEW_BUILD})\""
