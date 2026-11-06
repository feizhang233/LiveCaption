#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CAPTION_BUILD_PATH="${CAPTION_BUILD_DIR:-$PROJECT_DIR/DerivedData-Build}"
CAPTION_BUILD_CONFIGURATION="${CAPTION_CONFIGURATION:-Debug}"
MODE="${1:-all}"

case "$MODE" in
    mac|ipad-simulator|ipad-device|all) ;;
    -h|--help)
        echo "Usage: bash Scripts/build.sh [mac|ipad-simulator|ipad-device|all]"
        echo "Optional: CAPTION_BUILD_DIR=/path CAPTION_CONFIGURATION=Debug|Release"
        echo "Builds unsigned for verification only; does not install or publish."
        exit 0
        ;;
    *) echo "Unknown build target: $MODE. Use --help." >&2; exit 2 ;;
esac

if [[ ! -f "$PROJECT_DIR/Packages/CaptionCore/Frameworks/whisper.xcframework/Info.plist" ]]; then
    echo "Missing pinned Whisper XCFramework. Run: bash Scripts/fetch-whisper.sh" >&2
    exit 1
fi
if [[ ! -d "$PROJECT_DIR/LiveCaption.xcodeproj" ]]; then
    echo "LiveCaption.xcodeproj is missing from this checkout." >&2
    exit 1
fi

build_target() {
    local scheme="$1"
    local sdk="$2"
    local destination="$3"
    xcodebuild -quiet -project "$PROJECT_DIR/LiveCaption.xcodeproj" \
        -scheme "$scheme" -configuration "$CAPTION_BUILD_CONFIGURATION" \
        -sdk "$sdk" -destination "$destination" \
        -derivedDataPath "$CAPTION_BUILD_PATH" \
        CODE_SIGNING_ALLOWED=NO build
    echo "Build passed: $scheme ($sdk), unsigned verification only."
}

case "$MODE" in
    mac) build_target LiveCaptionMac macosx 'generic/platform=macOS' ;;
    ipad-simulator) build_target LiveCaptioniPad iphonesimulator 'generic/platform=iOS Simulator' ;;
    ipad-device) build_target LiveCaptioniPad iphoneos 'generic/platform=iOS' ;;
    all)
        build_target LiveCaptionMac macosx 'generic/platform=macOS'
        build_target LiveCaptioniPad iphonesimulator 'generic/platform=iOS Simulator'
        ;;
esac
echo "Build products: $CAPTION_BUILD_PATH/Build/Products"
