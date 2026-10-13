#!/bin/bash
# May be sourced by build scripts or used as a command wrapper.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '%s\n' 'Keyboard Shortcutter requires macOS and full Xcode.' >&2
    exit 1
fi

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    shortcutter_developer_dir="$DEVELOPER_DIR"
else
    shortcutter_developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
    if [[ ! -d "$shortcutter_developer_dir/Platforms/MacOSX.platform" ]]; then
        shortcutter_developer_dir='/Applications/Xcode.app/Contents/Developer'
    fi
fi

# xcrun also accepts an Xcode.app path; normalize it before checking the SDK.
if [[ "$shortcutter_developer_dir" == *.app ]]; then
    shortcutter_developer_dir="$shortcutter_developer_dir/Contents/Developer"
fi
if [[ ! -d "$shortcutter_developer_dir/Platforms/MacOSX.platform" ||
      ! -x "$shortcutter_developer_dir/usr/bin/xcodebuild" ]]; then
    printf '%s\n' 'Full Xcode is required for SwiftUI macro plugins and XCTest.' >&2
    printf '%s\n' 'Install Xcode, or set DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer.' >&2
    exit 1
fi
export DEVELOPER_DIR="$shortcutter_developer_dir"
unset shortcutter_developer_dir

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        printf '%s\n' 'Usage: scripts/swift-env.sh <command> [arguments...]' >&2
        exit 1
    fi
    exec "$@"
fi
