#!/bin/bash
# Run one process at a time; do not run other inference while measuring.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ $# -ne 4 ]]; then
    echo "Usage: bash Verification/latency/run-benchmark.sh /path/CaptionProbe /path/ggml-tiny.bin /path/fixture-directory /path/results" >&2
    exit 2
fi
PROBE="$1"
MODEL="$2"
FIXTURES="$3"
RESULTS="$4"
mkdir -p "$RESULTS"
for item in ja_jp-0 ja_jp-1 fr_fr-0 fr_fr-1; do
    language="${item%%_*}"
    "$PROBE" --model "$MODEL" --audio "$FIXTURES/$item.wav" --language "$language" --stream \
        > "$RESULTS/$item.json" 2> "$RESULTS/$item.log"
done
xcrun swift "$PROJECT_DIR/Scripts/score-fixtures.swift" "$PROJECT_DIR/Tests/Fixtures/manifest.json" "$RESULTS" --language ja_jp --language fr_fr > "$RESULTS/accuracy.json"
shasum -a 256 "$PROBE" "$MODEL" "$FIXTURES"/{ja_jp-0,ja_jp-1,fr_fr-0,fr_fr-1}.wav > "$RESULTS/input-artifacts.sha256"
