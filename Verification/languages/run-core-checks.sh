#!/bin/bash
# Development-only; models/audio are external, never embedded into this script.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ $# -ne 4 ]]; then
    echo "Usage: bash Verification/languages/run-core-checks.sh /path/CaptionProbe /path/models /path/fixtures /path/results" >&2
    exit 2
fi
PROBE="$1"
MODELS="$2"
FIXTURES="$3"
RESULTS="$4"
for model in tiny base; do
    for mode in direct stream; do
        output="$RESULTS/$model/$mode"
        mkdir -p "$output"
        for item in en_us-0 en_us-1 cmn_hans_cn-0 cmn_hans_cn-1; do
            case "$item" in en_*) language=en ;; *) language=zh ;; esac
            if [[ "$mode" == stream ]]; then extra=(--stream); else extra=(); fi
            "$PROBE" --model "$MODELS/ggml-$model.bin" --audio "$FIXTURES/$item.wav" \
                --language "$language" "${extra[@]}" > "$output/$item.json" 2> "$output/$item.log"
        done
        xcrun swift "$PROJECT_DIR/Scripts/score-fixtures.swift" "$PROJECT_DIR/Tests/Fixtures/manifest.json" \
            "$output" --language en_us --language cmn_hans_cn > "$output/accuracy.json"
    done
done
shasum -a 256 "$PROBE" "$MODELS"/ggml-{tiny,base}.bin \
    "$FIXTURES"/{en_us-0,en_us-1,cmn_hans_cn-0,cmn_hans_cn-1}.wav > "$RESULTS/input-artifacts.sha256"
