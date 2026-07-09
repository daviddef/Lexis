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
# Self-healing: if the chosen build number is already on App Store Connect
# (e.g. a manual Xcode upload leapfrogged the CLI), the upload is retried
# automatically at one higher than whatever ASC reports, re-archiving as needed.
# Transient ASC/network errors are also retried. So the build number in
# project.yml after a run reflects what actually landed — commit it.
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

ARCHIVE="build/LEXIS.xcarchive"
LOG="build/export.log"

# Set both targets' build number in project.yml (they must match).
set_build() { sedi -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$1\"/" project.yml; }

# Regenerate (so the current build number is baked in) and archive.
archive() {
  echo "▸ Uploading LEXIS ${MKT} (build ${NEW_BUILD})"
  xcodegen generate
  rm -rf build && mkdir -p build
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
  echo "▸ Archiving…"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    archive \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER_ID"
}

# Export + upload the existing archive. Tees to $LOG; returns xcodebuild's status.
export_upload() {
  echo "▸ Exporting + uploading to App Store Connect…"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist build/ExportOptions.plist \
    -exportPath build/export \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER_ID" 2>&1 | tee "$LOG"
  return "${PIPESTATUS[0]}"
}

set_build "$NEW_BUILD"
archive

# Upload with self-healing retries. Two failure modes are handled automatically:
#   • build number already used (manual Xcode uploads leapfrog the CLI) — parse
#     the "must be higher than 'N'" message, bump to N+1, re-archive, retry.
#   • transient ASC/network errors ("Error Downloading App Information", timeouts)
#     — wait and retry the upload without re-archiving.
tries=0
MAX_TRIES=8
while :; do
  if export_upload; then break; fi
  tries=$(( tries + 1 ))
  if [[ $tries -ge $MAX_TRIES ]]; then
    echo "❌ Upload still failing after ${MAX_TRIES} attempts — see output above."
    exit 1
  fi
  if grep -q "must be higher than the previously uploaded version" "$LOG"; then
    LATEST="$(grep "must be higher than the previously uploaded version" "$LOG" | grep -oE '[0-9]+' | tail -1)"
    NEW_BUILD=$(( LATEST + 1 ))
    echo "▸ Build number already on App Store Connect; bumping to ${NEW_BUILD} and re-archiving…"
    set_build "$NEW_BUILD"
    archive
  elif grep -qiE "Error Downloading App Information|timed out|could not connect|network connection was lost|Unable to |please try again" "$LOG"; then
    echo "▸ Transient App Store Connect error; retrying upload in 15s (attempt $((tries+1))/${MAX_TRIES})…"
    sleep 15
  else
    echo "❌ Upload failed with an unrecognized error — see output above."
    exit 1
  fi
done

echo ""
echo "✅ Uploaded LEXIS ${MKT} (build ${NEW_BUILD})."
echo "   It'll appear in TestFlight after App Store Connect finishes processing (a few min)."
echo "   Tip: commit the version bump in project.yml so it doesn't drift —"
echo "        git commit -am \"Bump to ${MKT} (build ${NEW_BUILD})\""
