#!/bin/bash
# Archives NMailPhone and uploads the build to App Store Connect for TestFlight.
# Tim runs this by hand; the one-time setup is in ios/README.md. The build number is the git commit count.
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -q "REPLACE_WITH_IOS_CLIENT_ID" project.yml; then
  echo "Set GOOGLE_CLIENT_ID_PREFIX in ios/project.yml to the iOS OAuth client first (see ios/README.md)." >&2
  exit 1
fi

BUILD=$(git rev-list --count HEAD)
ARCHIVE=build/NMail.xcarchive
rm -rf "$ARCHIVE" build/export

xcodegen generate
xcodebuild archive \
  -project NMail.xcodeproj -scheme NMailPhone -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath build/export \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates

echo "Uploaded build $BUILD. It shows up in App Store Connect → TestFlight after processing (usually 5–15 minutes)."
