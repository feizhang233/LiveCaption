#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/live-caption-language-settings.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
PRODUCTS="${1:-}"
source "$PROJECT_DIR/Scripts/test-support.sh"
compile_app_test_harness "$PROJECT_DIR" "$CHECK_DIR" "$PRODUCTS" \
    "$PROJECT_DIR/Tests/SourceLanguagePreferencesChecks.swift" "$CHECK_DIR/language-checks"
"$CHECK_DIR/language-checks"
