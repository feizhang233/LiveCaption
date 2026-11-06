#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -lt 1 ]]; then
    echo "Usage: Scripts/test-caption-scope-session.sh /path/ggml-tiny.bin [CaptionCore Debug products directory]" >&2
    exit 2
fi
MODEL="$1"
PRODUCTS="${2:-}"
CHECK_DIR="$(mktemp -d /tmp/live-caption-scope-session.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
source "$PROJECT_DIR/Scripts/test-support.sh"
compile_app_test_harness "$PROJECT_DIR" "$CHECK_DIR" "$PRODUCTS" \
    "$PROJECT_DIR/Tests/CaptionScopeSessionChecks.swift" "$CHECK_DIR/scope-session-checks"
"$CHECK_DIR/scope-session-checks" "$MODEL" "$CHECK_DIR"
