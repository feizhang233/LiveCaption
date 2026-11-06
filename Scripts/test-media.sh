#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/live-caption-media-tests.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
FIXTURE="${1:-/tmp/live-caption-verification-audio/ja_jp-0.wav}"
if [[ ! -f "$FIXTURE" ]]; then
    echo "Speech fixture missing. Run python3 Scripts/fetch-test-audio.py first or supply an audio path." >&2
    exit 1
fi
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_DIR/cache" \
    "$PROJECT_DIR/App/Media/MediaController.swift" "$PROJECT_DIR/Tests/MediaHarness.swift" \
    -o "$CHECK_DIR/media-checks"
"$CHECK_DIR/media-checks" "$FIXTURE"
# Use the same real human speech with a different PCM sample rate/channel layout.
/usr/bin/afconvert -f WAVE -d LEI16@48000 -c 2 "$FIXTURE" "$CHECK_DIR/stereo48k.wav"
"$CHECK_DIR/media-checks" "$CHECK_DIR/stereo48k.wav"
