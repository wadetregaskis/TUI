#!/bin/bash
# Builds probe.swift into an app bundle under $TMPDIR, with this folder's
# Info.plist and .lproj tables, and runs it; compare with probe.out.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="${TMPDIR:-/tmp}/locale-scripts-probe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/Info.plist" "$app/Contents/Info.plist"
cp -R "$here/Resources/." "$app/Contents/Resources/"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcrun swiftc -target arm64-apple-macos15.0 "$here/probe.swift" -o "$app/Contents/MacOS/probe"
"$app/Contents/MacOS/probe"
