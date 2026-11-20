#!/bin/sh
#  Type-checks SwiftUI's and TUI's spellings of a paragraph's alignment against
#  a stand-in for TUIFoundation's declarations (StandIn.swift), in each shape,
#  SDK and deployment target the attralign question weighed. Prints one line a
#  case: ok, or the first error. Nothing is run, so it needs no macOS 26.
#
#  Usage:  sh probe.sh [sdk26|sdk15|all]     (default all)
#
#  sdk26: Xcode's swiftc and SDK (26.2 when recorded).
#  sdk15: the Command Line Tools' macOS 15.5 SDK, which tuitree builds against,
#         with the same swiftc.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d)
which=${1:-all}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
swiftc="xcrun swiftc"
sdk15=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk

$swiftc --version 2>&1 | head -1

# case <label> <sdk-args> <target> <standin-flags> <client-flags> <client file>
run_case() {
    label=$1 sdkargs=$2 target=$3 sflags=$4 cflags=$5 client=$6
    dir="$out/$(echo "$label" | tr -c 'A-Za-z0-9' _)"
    mkdir -p "$dir"
    # shellcheck disable=SC2086
    if ! $swiftc $sdkargs -target "arm64-apple-macos$target" -parse-as-library -module-name StandIn \
        -emit-module -emit-module-path "$dir/StandIn.swiftmodule" $sflags "$here/StandIn.swift" \
        >"$dir/standin.log" 2>&1; then
        printf '%-70s standin FAILED: %s\n' "$label" "$(grep -m1 error: "$dir/standin.log")"
        return
    fi
    # shellcheck disable=SC2086
    if $swiftc $sdkargs -target "arm64-apple-macos$target" -typecheck -I "$dir" $cflags "$here/$client" \
        >"$dir/client.log" 2>&1; then
        printf '%-70s ok\n' "$label"
    else
        printf '%-70s %s\n' "$label" "$(grep -m1 error: "$dir/client.log" | sed 's/.*error: /error: /')"
    fi
}

matrix() {
    sdk=$1 sdkargs=$2
    echo "== $sdk"
    for shape in "ruling:" "same-named:-D SAME_NAMED" "ruling, no re-export:-D NO_CORETEXT_REEXPORT"; do
        name=${shape%%:*} sflags=${shape#*:}
        for target in 15.0 26.0; do
            for imports in "TUI:" "TUI+AppKit:-D WITH_APPKIT" "TUI, MemberImportVisibility:-enable-upcoming-feature MemberImportVisibility"; do
                iname=${imports%%:*} cflags=${imports#*:}
                for client in ClientGuarded.swift ClientUnguarded.swift ClientFallback.swift; do
                    run_case "$sdk $name macOS$target $iname ${client%.swift}" "$sdkargs" "$target" \
                        "$sflags" "$cflags" "$client"
                done
            done
        done
    done
    # SwiftUI itself, for reference: what a SwiftUI program gets.
    for target in 15.0 26.0; do
        for imports in "SwiftUI:-D WITH_SWIFTUI" \
            "SwiftUI, MemberImportVisibility:-D WITH_SWIFTUI -enable-upcoming-feature MemberImportVisibility"; do
            iname=${imports%%:*} cflags=${imports#*:}
            for client in ClientGuarded.swift ClientUnguarded.swift; do
                run_case "$sdk SwiftUI itself macOS$target $iname ${client%.swift}" "$sdkargs" "$target" \
                    "" "$cflags" "$client"
            done
        done
    done
}

line_height() {
    echo "== sdk26 line height"
    if $swiftc -target arm64-apple-macos15.0 -typecheck "$here/LineHeightReading.swift" >"$out/lh.log" 2>&1; then
        echo "LineHeightReading (==, Codable, Mirror) type-checks"
    else
        grep -m1 error: "$out/lh.log"
    fi
}

case "$which" in
    sdk26) matrix sdk26 "" && line_height ;;
    sdk15) matrix sdk15 "-sdk $sdk15" ;;
    *) matrix sdk26 "" && line_height && matrix sdk15 "-sdk $sdk15" ;;
esac
