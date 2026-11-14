#!/bin/bash
# Wraps the compiled binary into a LiteBridge.app bundle.
set -euo pipefail

APP="build/LiteBridge.app"
BIN="$(swift build -c release --arch x86_64 --show-bin-path)/LiteBridge"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LiteBridge"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>LiteBridge</string>
  <key>CFBundleIdentifier</key><string>local.litebridge</string>
  <key>CFBundleName</key><string>LiteBridge</string>
  <key>CFBundleDisplayName</key><string>LiteBridge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSDesktopFolderUsageDescription</key><string>LiteBridge needs access to browse and organize your files.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>LiteBridge needs access to browse and organize your files.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>LiteBridge needs access to browse and organize your files.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>LiteBridge needs access to browse and organize your files.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (no Apple developer account needed)
codesign --force --deep --sign - "$APP"
echo "Built $APP"
