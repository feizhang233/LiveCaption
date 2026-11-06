#!/bin/bash
# Development-only: relink the same measurement harness against a chosen core.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ $# -ne 2 ]]; then
    echo "Usage: bash Verification/latency/build-probe.sh /path/DebugProducts /path/CaptionProbe" >&2
    exit 2
fi
PRODUCTS="$(cd "$1" && pwd)"
OUTPUT="$2"
mkdir -p "$(dirname "$OUTPUT")"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos26.0 \
    -module-cache-path /tmp/live-caption-latency-probe-cache \
    -I "$PRODUCTS" -L "$PRODUCTS" -lCaptionCore -F "$PRODUCTS" -framework whisper \
    -Xlinker -rpath -Xlinker "$PRODUCTS" \
    "$PROJECT_DIR/Packages/CaptionCore/Sources/CaptionProbe/main.swift" -o "$OUTPUT"
