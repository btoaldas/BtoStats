#!/bin/bash
# Build release de BetoStats.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
echo "Binario: .build/release/BetoStats"
