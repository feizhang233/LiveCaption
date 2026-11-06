#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/live-caption-scope.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path "$CHECK_DIR/cache" \
    "$PROJECT_DIR/App/Session/CaptionScope.swift" "$PROJECT_DIR/Tests/CaptionScopeChecks.swift" \
    -o "$CHECK_DIR/scope-checks"
"$CHECK_DIR/scope-checks"
