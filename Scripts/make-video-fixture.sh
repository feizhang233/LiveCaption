#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/live-caption-video-fixture.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
SOURCE_AUDIO="${1:-/tmp/live-caption-verification-audio/fr_fr-0.wav}"
OUTPUT_VIDEO="${2:-/tmp/live-caption-verification-audio/fr-native-video.mp4}"
if [[ ! -f "$SOURCE_AUDIO" ]]; then
    echo "Speech fixture missing. Run python3 Scripts/fetch-test-audio.py or supply a real audio file." >&2
    exit 1
fi
xcrun swiftc -swift-version 6 -O -module-cache-path "$CHECK_DIR/cache" \
    -parse-as-library "$PROJECT_DIR/Tests/MakeVideoFixture.swift" -o "$CHECK_DIR/make-video-fixture"
"$CHECK_DIR/make-video-fixture" "$SOURCE_AUDIO" "$OUTPUT_VIDEO"
shasum -a 256 "$OUTPUT_VIDEO"
