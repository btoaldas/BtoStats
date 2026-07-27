#!/bin/bash
# Compila y relanza BtoStats en la barra de menús (modo desarrollo).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
pkill -x BtoStats 2>/dev/null || true
sleep 0.3
nohup .build/debug/BtoStats >/tmp/btostats-dev.log 2>&1 &
echo "BtoStats lanzado (PID $!). Log: /tmp/btostats-dev.log"
