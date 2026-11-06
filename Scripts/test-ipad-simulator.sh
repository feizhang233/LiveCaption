#!/bin/bash
# Development-only, hosted real-inference tests. Does not change model selection
# or user defaults, erase a simulator, or download any model/audio files.
set -euo pipefail
if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: bash Scripts/test-ipad-simulator.sh SIMULATOR_UDID VERIFIED_TINY_BIN FIXTURE_DIRECTORY [RESULT_DIRECTORY]" >&2
    exit 2
fi
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="$1"
MODEL_FILE="$2"
FIXTURE_DIR="$3"
RESULT_DIR="${4:-/tmp/live-caption-ipad-tests.$(date -u +%Y%m%dT%H%M%SZ)}"
MODEL_HASH="be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"

verify_hash() {
    if [[ ! -f "$1" ]]; then echo "Missing fixture: $1" >&2; exit 1; fi
    local actual
    actual="$(shasum -a 256 "$1" | awk '{print $1}')"
    if [[ "$actual" != "$2" ]]; then echo "SHA-256 mismatch: $1" >&2; exit 1; fi
}
seed_if_missing() {
    if [[ -e "$2" ]]; then
        if ! cmp -s "$1" "$2"; then
            echo "Existing simulator file differs; refusing to overwrite: $2" >&2
            exit 1
        fi
    else
        cp "$1" "$2"
    fi
}

verify_hash "$MODEL_FILE" "$MODEL_HASH"
verify_hash "$FIXTURE_DIR/ja_jp-0.wav" "bd1b9533cfa176b8c2a71ecb4821a02bc86fa368d096373efe8d8dceafb35634"
verify_hash "$FIXTURE_DIR/fr_fr-0.wav" "c834367fd212902124bdd0e0f6c1f16b5561af6386600f145e5aec50008b298d"
verify_hash "$FIXTURE_DIR/en_us-0.wav" "33aca50159ec2e3cbcc894eb26faa916d6badb1b49fb75994973561540a7f012"
verify_hash "$FIXTURE_DIR/cmn_hans_cn-0.wav" "a72c0b59fdba80850552af7991de07f9f4940846d2d70f0890eeb153c40f164b"
if [[ ! -f "$FIXTURE_DIR/fr-native-video.mp4" ]]; then
    echo "Missing derived video. Run bash Scripts/make-video-fixture.sh first." >&2
    exit 1
fi
if [[ -e "$RESULT_DIR" ]]; then
    echo "Result directory already exists; choose a new path: $RESULT_DIR" >&2
    exit 1
fi
mkdir -p "$RESULT_DIR"
RESULT_DIR="$(cd "$RESULT_DIR" && pwd)"
DERIVED_DIR="$RESULT_DIR/DerivedData"
cd "$PROJECT_DIR"

xcrun simctl bootstatus "$DEVICE_ID" -b
xcodebuild -project LiveCaption.xcodeproj -scheme LiveCaptioniPad -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$DERIVED_DIR" \
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO build-for-testing \
    > "$RESULT_DIR/build.log" 2>&1
APP_DIR="$DERIVED_DIR/Build/Products/Debug-iphonesimulator/LiveCaption.app"
xcrun simctl install "$DEVICE_ID" "$APP_DIR"
APP_DATA="$(xcrun simctl get_app_container "$DEVICE_ID" com.example.livecaption.ipad data)"
mkdir -p "$APP_DATA/Library/Application Support/LiveCaption/Models" "$APP_DATA/Documents"
seed_if_missing "$MODEL_FILE" "$APP_DATA/Library/Application Support/LiveCaption/Models/ggml-tiny.bin"
for fixture in ja_jp-0.wav fr_fr-0.wav fr-native-video.mp4 en_us-0.wav cmn_hans_cn-0.wav; do
    seed_if_missing "$FIXTURE_DIR/$fixture" "$APP_DATA/Documents/$fixture"
done

TEST_STATUS=0
xcodebuild -project LiveCaption.xcodeproj -scheme LiveCaptioniPad -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$DERIVED_DIR" \
    -resultBundlePath "$RESULT_DIR/Integration.xcresult" -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO test-without-building > "$RESULT_DIR/test.log" 2>&1 || TEST_STATUS=$?
xcrun xcresulttool get test-results summary --path "$RESULT_DIR/Integration.xcresult" > "$RESULT_DIR/test-summary.json"
xcrun xcresulttool get test-results tests --path "$RESULT_DIR/Integration.xcresult" > "$RESULT_DIR/test-results.json"
xcrun xcresulttool export attachments --path "$RESULT_DIR/Integration.xcresult" --output-path "$RESULT_DIR/attachments"
PASSED="$(plutil -extract passedTests raw -o - "$RESULT_DIR/test-summary.json")"
SKIPPED="$(plutil -extract skippedTests raw -o - "$RESULT_DIR/test-summary.json")"
FAILED="$(plutil -extract failedTests raw -o - "$RESULT_DIR/test-summary.json")"
TOTAL="$(plutil -extract totalTestCount raw -o - "$RESULT_DIR/test-summary.json")"
if [[ "$TEST_STATUS" != 0 || "$PASSED" != 6 || "$SKIPPED" != 0 || "$FAILED" != 0 || "$TOTAL" != 6 ]]; then
    echo "Integration acceptance failed: total=$TOTAL passed=$PASSED skipped=$SKIPPED failed=$FAILED. See $RESULT_DIR" >&2
    exit 1
fi
echo "PASS: 6 real-inference iPad simulator tests; 0 failures; 0 skipped. Evidence: $RESULT_DIR"
