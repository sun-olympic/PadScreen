#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE_ICON="$ROOT/macOS/AppIcon.png"

[[ -f "$SOURCE_ICON" ]] || { echo "missing macOS/AppIcon.png" >&2; exit 1; }

WIDTH=$(sips -g pixelWidth "$SOURCE_ICON" | awk '/pixelWidth/ {print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE_ICON" | awk '/pixelHeight/ {print $2}')
[[ "$WIDTH" -ge 1024 && "$HEIGHT" -ge 1024 ]] || {
    echo "AppIcon.png must be at least 1024x1024" >&2
    exit 1
}

ICON_NAME=$(plutil -extract CFBundleIconFile raw "$ROOT/macOS/Info.plist" 2>/dev/null || true)
[[ "$ICON_NAME" == "PadScreen.icns" ]] || {
    echo "Info.plist must declare PadScreen.icns" >&2
    exit 1
}

grep -q 'iconutil.*PadScreen.iconset' "$ROOT/scripts/build-macos-app.sh" || {
    echo "build script must generate PadScreen.icns" >&2
    exit 1
}

grep -q 'PadScreen.icns.*Contents/Resources' "$ROOT/scripts/build-macos-app.sh" || {
    echo "build script must copy PadScreen.icns into app resources" >&2
    exit 1
}

echo "macOS app icon packaging checks passed"
