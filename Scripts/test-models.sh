#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/live-caption-model-tests.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_DIR/cache" \
    "$PROJECT_DIR"/App/Models/*.swift \
    "$PROJECT_DIR/Tests/ModelManagement/ModelManagementChecks.swift" \
    -o "$CHECK_DIR/model-checks"
"$CHECK_DIR/model-checks" "$@"
