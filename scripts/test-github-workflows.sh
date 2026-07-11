#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI="$ROOT/.github/workflows/ci.yml"
RELEASE="$ROOT/.github/workflows/release.yml"
ANDROID_ICON_TEST="$ROOT/scripts/test-android-app-icon.sh"

require_text() {
    local file="$1"
    local text="$2"
    grep -Fq -- "$text" "$file" || {
        echo "$file must contain: $text" >&2
        exit 1
    }
}

[[ -f "$CI" ]] || { echo "missing CI workflow" >&2; exit 1; }
[[ -f "$RELEASE" ]] || { echo "missing release workflow" >&2; exit 1; }

require_text "$CI" "pull_request:"
require_text "$CI" "runs-on: macos-15"
require_text "$CI" "swift test"
require_text "$CI" "runProtocolTests assembleDebug"
require_text "$CI" "test-github-workflows.sh"
require_text "$CI" "actions/checkout@v7"
require_text "$CI" "gradle/actions/setup-gradle@v6"

require_text "$RELEASE" "tags:"
require_text "$RELEASE" "- 'v*'"
require_text "$RELEASE" "contents: write"
require_text "$RELEASE" "runs-on: macos-15"
require_text "$RELEASE" "PadScreen-macOS-arm64.zip"
require_text "$RELEASE" "PadScreen-Android-debug.apk"
require_text "$RELEASE" "actions/upload-artifact@v7"
require_text "$RELEASE" "actions/download-artifact@v8"
require_text "$RELEASE" "softprops/action-gh-release@v3"
require_text "$RELEASE" "SHA256SUMS.txt"

[[ "$(head -n 1 "$ANDROID_ICON_TEST")" == "#!/usr/bin/env bash" ]] || {
    echo "Android icon test must use a portable Bash shebang" >&2
    exit 1
}

echo "GitHub Actions workflow checks passed"
