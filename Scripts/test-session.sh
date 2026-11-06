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
source "$PROJECT_DIR/Scripts/test-support.sh"
compile_app_test_harness "$PROJECT_DIR" "$CHECK_DIR" "$PRODUCTS" \
    "$PROJECT_DIR/Tests/SessionHarness.swift" "$CHECK_DIR/session-checks"
"$CHECK_DIR/session-checks" "$MODEL" "$AUDIO" "$CHECK_DIR" "$SOURCE_LANGUAGE"
