#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/PadScreen.app"
ICON_SOURCE="$ROOT/macOS/AppIcon.png"
ICONSET="$ROOT/.build/PadScreen.iconset"
ICNS="$ROOT/.build/PadScreen.icns"

cd "$ROOT"
swift build -c release --product PadScreenHost
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ROOT/.build/PadScreen.iconset" -o "$ROOT/.build/PadScreen.icns"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/PadScreenHost" "$APP/Contents/MacOS/PadScreenHost"
cp "$ROOT/macOS/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/.build/PadScreen.icns" "$APP/Contents/Resources/PadScreen.icns"
codesign --force --deep --sign - "$APP"
echo "$APP"
