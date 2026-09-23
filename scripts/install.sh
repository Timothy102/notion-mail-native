#!/bin/sh
# Builds a release NMail.app and installs it into /Applications.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product Mail
bin="$(swift build -c release --product Mail --show-bin-path)"
app="$bin/NMail.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Mail" "$app/Contents/MacOS/Mail"
cp -R "$bin/Mail_Mail.bundle" "$app/Contents/Resources/"
cp Icon/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NMail</string>
  <key>CFBundleDisplayName</key><string>NMail</string>
  <key>CFBundleIdentifier</key><string>dev.tim.nmail</string>
  <key>CFBundleExecutable</key><string>Mail</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD)</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# A stable identity keeps the Keychain's grant to NMail across rebuilds; ad-hoc signatures change every build,
# which silently locks the app out of its saved Google login.
identity="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
codesign --force --deep --sign "${identity:--}" "$app"
rm -rf /Applications/NMail.app
cp -R "$app" /Applications/NMail.app
echo "Installed /Applications/NMail.app"
