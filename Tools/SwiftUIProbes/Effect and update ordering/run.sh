#!/bin/zsh
# Builds ordering.swift with Xcode's toolchain and runs each case in its own process, writing <case>.out here.
# SwiftUI's runtime warnings reach stderr through OS_ACTIVITY_DT_MODE; their date, process and thread prefix is cut.
# PROBE_STACKS prints, once each, the stack that led to a few events; the symbols in them are demangled here.
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
here=${0:A:h}
bin=${TMPDIR:-/tmp}/effect-ordering-probe
xcrun swiftc -target arm64-apple-macos15.0 "$here/ordering.swift" -o "$bin"
cases=(appear change chain selfloop prefloop geofeedback geocount geoscroll geolist bodywrite)
(( $# )) && cases=($@)
for c in $cases; do
  PROBE_STACKS=1 OS_ACTIVITY_DT_MODE=YES "$bin" $c 2>&1 | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+[-+][0-9]{4} [^[]+\[[0-9a-f:]+\] /[runtime] /' | xcrun swift-demangle --simplified | c++filt -n > "$here/$c.out"
done
