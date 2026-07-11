#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"

grep -q 'android:icon="@mipmap/ic_launcher"' "$MANIFEST" || {
    echo "AndroidManifest.xml must declare @mipmap/ic_launcher" >&2
    exit 1
}

grep -q 'android:roundIcon="@mipmap/ic_launcher_round"' "$MANIFEST" || {
    echo "AndroidManifest.xml must declare @mipmap/ic_launcher_round" >&2
    exit 1
}

for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    icon="$ROOT/android/app/src/main/res/mipmap-$density/ic_launcher.png"
    round_icon="$ROOT/android/app/src/main/res/mipmap-$density/ic_launcher_round.png"
    [[ -f "$icon" ]] || { echo "missing $icon" >&2; exit 1; }
    [[ -f "$round_icon" ]] || { echo "missing $round_icon" >&2; exit 1; }
done

for adaptive_icon in ic_launcher ic_launcher_round; do
    xml="$ROOT/android/app/src/main/res/mipmap-anydpi-v26/$adaptive_icon.xml"
    [[ -f "$xml" ]] || { echo "missing $xml" >&2; exit 1; }
    grep -q '<adaptive-icon' "$xml" || { echo "$xml must be adaptive" >&2; exit 1; }
    grep -q '@color/padscreen_icon_background' "$xml" || { echo "$xml must declare icon background" >&2; exit 1; }
    grep -q '@drawable/padscreen_icon_foreground' "$xml" || { echo "$xml must declare icon foreground" >&2; exit 1; }
done

[[ -f "$ROOT/android/app/src/main/res/drawable-nodpi/padscreen_icon_foreground.png" ]] || {
    echo "missing adaptive foreground artwork" >&2
    exit 1
}

echo "Android app icon packaging checks passed"
