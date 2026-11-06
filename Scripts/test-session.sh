#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -lt 2 ]]; then
    echo "Usage: Scripts/test-session.sh /path/ggml-tiny.bin /path/audio-or-video [CaptionCore Debug products directory] [ja|fr]" >&2
    exit 2
fi
MODEL="$1"
AUDIO="$2"
PRODUCTS="${3:-}"
SOURCE_LANGUAGE="${4:-ja}"
CHECK_DIR="$(mktemp -d /tmp/live-caption-session-tests.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
if [[ -z "$PRODUCTS" ]]; then
    CLANG_MODULE_CACHE_PATH="$CHECK_DIR/cache" SWIFTPM_MODULECACHE_OVERRIDE="$CHECK_DIR/swift-cache" \
        swift build --package-path "$PROJECT_DIR/Packages/CaptionCore" --scratch-path "$CHECK_DIR/core" --product CaptionCore >&2
    PRODUCTS="$CHECK_DIR/core/out/Products/Debug"
fi
WHISPER="$PROJECT_DIR/Packages/CaptionCore/Frameworks/whisper.xcframework/macos-arm64_x86_64"
SOURCES=(
    "$PROJECT_DIR"/App/Models/*.swift
    "$PROJECT_DIR"/App/Media/*.swift
    "$PROJECT_DIR"/App/Session/*.swift
    "$PROJECT_DIR"/App/UI/*.swift
    "$PROJECT_DIR"/App/Platform/macOS/*.swift
)
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path "$CHECK_DIR/cache" \
    -I "$PRODUCTS" -L "$PRODUCTS" -lCaptionCore -F "$WHISPER" -framework whisper \
    -Xlinker -rpath -Xlinker "$WHISPER" \
    "${SOURCES[@]}" "$PROJECT_DIR/Tests/SessionHarness.swift" \
    -o "$CHECK_DIR/session-checks"
"$CHECK_DIR/session-checks" "$MODEL" "$AUDIO" "$CHECK_DIR" "$SOURCE_LANGUAGE"
