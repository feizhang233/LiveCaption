#!/bin/bash
# Compatibility entry point. The shared runner accepts either iPhone or iPad.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/test-ios-simulator.sh" "$@"
