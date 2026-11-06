#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/live-caption-platform-audio-tests.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
# Supply an existing CaptionCore Debug products directory to avoid rebuilding.
PRODUCTS="${1:-}"
if [[ -z "$PRODUCTS" ]]; then
    swift build --package-path "$PROJECT_DIR/Packages/CaptionCore" --scratch-path "$CHECK_DIR/core" --product CaptionCore
    PRODUCTS="$CHECK_DIR/core/out/Products/Debug"
fi
WHISPER="$PROJECT_DIR/Packages/CaptionCore/Frameworks/whisper.xcframework/macos-arm64_x86_64"
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path "$CHECK_DIR/cache" \
    -I "$PRODUCTS" -L "$PRODUCTS" -lCaptionCore -F "$WHISPER" -framework whisper \
    -Xlinker -rpath -Xlinker "$WHISPER" \
    "$PROJECT_DIR/App/Platform/macOS/MacSystemAudioCapture.swift" \
    "$PROJECT_DIR/App/Platform/macOS/CaptionPanelController.swift" \
    "$PROJECT_DIR/Experimental/BroadcastExtension/SampleHandler.swift" \
    "$PROJECT_DIR/Tests/PlatformAudioHarness.swift" \
    -o "$CHECK_DIR/platform-audio-checks"
"$CHECK_DIR/platform-audio-checks"
