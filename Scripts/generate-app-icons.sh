#!/bin/bash
# Mechanical size exports only. Artwork is maintained in Design/AppIcon.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SOURCES="$PROJECT_DIR/Design/AppIcon"
ICON_CATALOG="$PROJECT_DIR/App/Resources/Assets.xcassets"
ICON_SET="$ICON_CATALOG/AppIcon.appiconset"

for source in "$ICON_SOURCES/live-caption-ipad-1024.png" "$ICON_SOURCES/live-caption-mac-1024.png"; do
    if [[ ! -f "$source" ]]; then
        echo "Missing icon artwork: $source" >&2
        exit 1
    fi
done
mkdir -p "$ICON_SET"
cp "$ICON_SOURCES/live-caption-ipad-1024.png" "$ICON_SET/ipad-1024.png"
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((points * scale))
        filename="mac-${points}.png"
        if [[ "$scale" == 2 ]]; then filename="mac-${points}@2x.png"; fi
        sips --resampleHeightWidth "$pixels" "$pixels" \
            "$ICON_SOURCES/live-caption-mac-1024.png" --out "$ICON_SET/$filename" >/dev/null
    done
done
cat > "$ICON_CATALOG/Contents.json" <<'JSON'
{
  "info": { "author": "xcode", "version": 1 }
}
JSON
cat > "$ICON_SET/Contents.json" <<'JSON'
{
  "images": [
    { "filename": "ipad-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" },
    { "filename": "mac-16.png", "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "filename": "mac-16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "filename": "mac-32.png", "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "filename": "mac-32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "filename": "mac-128.png", "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "mac-128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "mac-256.png", "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "mac-256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "mac-512.png", "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "mac-512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
JSON
echo "Exported iPad master and 10 macOS app icon slots."
