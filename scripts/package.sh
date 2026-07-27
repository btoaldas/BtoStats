#!/bin/bash
# Empaqueta BtoStats como .app firmada ad hoc y genera el zip de release.
# NO instala nada: el bundle queda en dist/ (la instalación local llega en fase 8/9).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.6.0}"
APP="dist/BtoStats.app"

swift build -c release

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BtoStats "$APP/Contents/MacOS/BtoStats"
cp assets/BtoStats.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>BtoStats</string>
    <key>CFBundleIdentifier</key><string>ec.bto.BtoStats</string>
    <key>CFBundleName</key><string>BtoStats</string>
    <key>CFBundleDisplayName</key><string>BtoStats</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>PolyForm Strict 1.0.0</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"

cd dist && zip -qry "BtoStats-${VERSION}.zip" BtoStats.app && cd ..
echo "Listo: $APP y dist/BtoStats-${VERSION}.zip"
