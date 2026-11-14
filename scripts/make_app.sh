#!/bin/bash
# Wraps the compiled binary into a LiteBridge.app bundle.
set -euo pipefail

APP="build/LiteBridge.app"
BIN="$(swift build -c release --arch x86_64 --show-bin-path)/LiteBridge"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LiteBridge"

# App icon: build AppIcon.icns from Resources/AppIcon.png (sips + iconutil exist on macOS runners)
if [ -f Resources/AppIcon.png ]; then
  SET="build/AppIcon.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>LiteBridge</string>
  <key>CFBundleIdentifier</key><string>local.litebridge</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
  </array>
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
