#!/bin/bash
set -euo pipefail
# Official whisper.cpp v1.9.5, commit d1be6fde11ac6e0407606b4e42fe72d34add8037.
# Its tagged release points to the official b5454 binary build.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Packages/CaptionCore/Frameworks/whisper.xcframework"
SHA256=e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b
URL=https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/livecaption-whisper.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
curl --fail --location --retry 3 "$URL" -o "$TEMP/whisper.zip"
ACTUAL="$(shasum -a 256 "$TEMP/whisper.zip" | awk '{print $1}')"
if [[ "$ACTUAL" != "$SHA256" ]]; then
    echo "Whisper framework checksum mismatch; refusing to install." >&2
    exit 1
fi
unzip -q "$TEMP/whisper.zip" -d "$TEMP/extracted"
test -f "$TEMP/extracted/build-apple/whisper.xcframework/Info.plist"
mkdir -p "$(dirname "$DEST")"
if [[ -d "$DEST" ]]; then
    mv "$DEST" "$TEMP/previous.xcframework"
fi
mv "$TEMP/extracted/build-apple/whisper.xcframework" "$DEST"
echo "Verified whisper.cpp v1.9.5 (b5454) installed in $DEST"
