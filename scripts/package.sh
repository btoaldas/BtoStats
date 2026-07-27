#!/bin/bash
# Empaqueta BtoStats como .app firmada ad hoc con su helper privilegiado.
# NO instala nada: el bundle queda en dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP="dist/BtoStats.app"
HELPER_ID="ec.bto.BtoStats.helper"

swift build -c release

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$APP/Contents/Library/LaunchDaemons"
cp .build/release/BtoStats "$APP/Contents/MacOS/BtoStats"
cp assets/BtoStats.icns "$APP/Contents/Resources/AppIcon.icns"

# Helper privilegiado embebido (SMAppService lo busca en Contents/MacOS).
cp .build/release/BtoStatsHelper "$APP/Contents/MacOS/${HELPER_ID}"

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
    <!-- Sin esto macOS corre la app en "modo compatibilidad de área segura":
         le presenta la pantalla SIN la zona del notch, la barra le parece de
         22 pt y el status item termina desplazado fuera de la pantalla
         (verificado: bundle sin la clave -> X=1314 invisible; con ella y en
         binario suelto -> X=922 visible). -->
    <key>NSPrefersDisplaySafeAreaCompatibilityMode</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 btoaldas — PolyForm Strict 1.0.0</string>
</dict>
</plist>
PLIST

# LaunchDaemon del helper (SMAppService.daemon lo lee de Contents/Library/LaunchDaemons).
cat > "$APP/Contents/Library/LaunchDaemons/${HELPER_ID}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${HELPER_ID}</string>
    <key>BundleProgram</key><string>Contents/MacOS/${HELPER_ID}</string>
    <key>MachServices</key><dict><key>${HELPER_ID}</key><true/></dict>
    <key>AssociatedBundleIdentifiers</key><array><string>ec.bto.BtoStats</string></array>
</dict>
</plist>
PLIST

# Firmar helper primero, luego la app (orden requerido).
# --options runtime (hardened runtime): activa library validation incluso con
# firma ad hoc → dyld deja de honrar DYLD_INSERT_LIBRARIES, cerrando la vía de
# escalada a root por inyección en el cliente (security review, crítico).
codesign --force --options runtime --sign - "$APP/Contents/MacOS/${HELPER_ID}"
codesign --force --options runtime --sign - "$APP/Contents/MacOS/BtoStats"
codesign --force --options runtime --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

cd dist && zip -qry "BtoStats-${VERSION}.zip" BtoStats.app && cd ..
echo "Listo: $APP y dist/BtoStats-${VERSION}.zip"
