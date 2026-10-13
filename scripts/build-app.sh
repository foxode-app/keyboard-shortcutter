#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

source "$project_dir/scripts/swift-env.sh"

/usr/bin/xcrun swift build --configuration release --arch arm64
binary_dir="$(/usr/bin/xcrun swift build --configuration release --arch arm64 --show-bin-path)"
app_path="$project_dir/build/Keyboard Shortcutter.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
install -m 755 "$binary_dir/KeyboardShortcutter" "$app_path/Contents/MacOS/KeyboardShortcutter"
install -m 644 "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
install -m 644 "$project_dir/Resources/KeyboardShortcutter.icns" "$app_path/Contents/Resources/KeyboardShortcutter.icns"

/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
signing_identity="${SIGNING_IDENTITY:--}"
signing_arguments=(--force --sign "$signing_identity" --identifier com.foxode.keyboardshortcutter.app)
if [[ "$signing_identity" != "-" ]]; then
    signing_arguments+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${signing_arguments[@]}" "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf '\nBuilt: %s\n' "$app_path"
if [[ "$signing_identity" == "-" ]]; then
    printf '%s\n' 'Local ad-hoc build. Use Developer ID signing and notarization before distribution.'
else
    printf '%s\n' 'Signed with hardened runtime. Notarize and staple the release before distribution.'
fi
