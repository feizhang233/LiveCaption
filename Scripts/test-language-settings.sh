#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/live-caption-language-settings.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
PRODUCTS="${1:-}"
if [[ -z "$PRODUCTS" ]]; then
    CLANG_MODULE_CACHE_PATH="$CHECK_DIR/cache" SWIFTPM_MODULECACHE_OVERRIDE="$CHECK_DIR/swift-cache" \
        swift build --package-path "$PROJECT_DIR/Packages/CaptionCore" --scratch-path "$CHECK_DIR/core" --product CaptionCore >&2
    PRODUCTS="$CHECK_DIR/core/out/Products/Debug"
fi
WHISPER="$PROJECT_DIR/Packages/CaptionCore/Frameworks/whisper.xcframework/macos-arm64_x86_64"
SOURCES=( "$PROJECT_DIR"/App/Models/*.swift "$PROJECT_DIR"/App/Media/*.swift
    "$PROJECT_DIR"/App/Session/*.swift "$PROJECT_DIR"/App/UI/*.swift "$PROJECT_DIR"/App/Platform/macOS/*.swift )
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path "$CHECK_DIR/cache" \
    -I "$PRODUCTS" -L "$PRODUCTS" -lCaptionCore -F "$WHISPER" -framework whisper \
    -Xlinker -rpath -Xlinker "$WHISPER" "${SOURCES[@]}" \
    "$PROJECT_DIR/Tests/SourceLanguagePreferencesChecks.swift" -o "$CHECK_DIR/language-checks"
"$CHECK_DIR/language-checks"
