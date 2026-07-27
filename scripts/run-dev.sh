#!/bin/bash
# Compila y relanza BetoStats en la barra de menús (modo desarrollo).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
pkill -x BetoStats 2>/dev/null || true
sleep 0.3
nohup .build/debug/BetoStats >/tmp/betostats-dev.log 2>&1 &
echo "BetoStats lanzado (PID $!). Log: /tmp/betostats-dev.log"
