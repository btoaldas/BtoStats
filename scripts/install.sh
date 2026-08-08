#!/bin/bash
# Instala BtoStats como agente de usuario (arranca solo al iniciar sesión).
#
# Se instala el ejecutable "suelto" en vez de un bundle .app a propósito:
# en macOS 26 el status item de un bundle puede quedar posicionado fuera de
# la pantalla (verificado: mismo binario, suelto -> visible; en .app ->
# frame fuera de la barra). El ejecutable directo no sufre ese problema.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="$HOME/Library/Application Support/BtoStats/bin"
AGENT="$HOME/Library/LaunchAgents/ec.bto.btostats.plist"

swift build -c release
mkdir -p "$DEST"
launchctl unload "$AGENT" 2>/dev/null || true
pkill -x BtoStats 2>/dev/null || true
sleep 1
cp .build/release/BtoStats "$DEST/BtoStats"
chmod +x "$DEST/BtoStats"

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>ec.bto.btostats</string>
    <key>ProgramArguments</key><array><string>$DEST/BtoStats</string></array>
    <key>RunAtLoad</key><true/>
    <!-- Relanzar solo tras crash (exit != 0); "Salir" del menú (exit 0) sí termina. -->
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST

launchctl load "$AGENT"
echo "Instalado y en marcha. Se abrirá solo al iniciar sesión."
echo "Para desinstalar: launchctl unload \"$AGENT\" && rm \"$AGENT\""
