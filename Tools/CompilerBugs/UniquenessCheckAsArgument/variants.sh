#!/bin/bash
# Compiles Crash.swift and a set of near-misses with each toolchain given, and
# prints one row per variant and one column per toolchain.
#
#   ./variants.sh                # `swiftc` from PATH
#   ./variants.sh TOOLCHAIN...   # each an .xctoolchain directory
#
# README.md's table is the output of:
#
#   tcs=~/Library/Developer/Toolchains
#   ./variants.sh /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
#       "$tcs/swift-6.2.4-RELEASE.xctoolchain"
#
# A column is headed with its compiler's version, "Xcode" for Xcode's build, and
# "+a" for a build with assertions. Each variant is compiled to an object at -O
# (the build that fails), unless its label says otherwise. The cells:
#   ABORTS   the verifier failure this directory is about
#   ok       compiled
#   error    failed some other way, which says nothing either way
# The `run` rows build a small program at -Onone and print what the check
# answered.
set -u
cd "$(dirname "$0")" || exit 2
failure='Load borrow invalidated by a local write'

compilers=()
if [ $# -eq 0 ]; then
    compilers=(swiftc)
else
    for toolchain in "$@"; do compilers+=("$toolchain/usr/bin/swiftc"); done
fi
sdk=$(xcrun --sdk macosx --show-sdk-path)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

print_line() { # $1 = line, printed without its trailing spaces
    local line="$1"
    printf '%s\n' "${line%"${line##*[! ]}"}"
}

heading() { # $1 = swiftc
    local version name
    version=$("$1" -version 2>&1)
    name=$(sed -n 's/.*Swift version \([^ ]*\).*/\1/p' <<<"$version" | head -n 1)
    case "$version" in *swiftlang-*) name="Xcode $name" ;; esac
    case "$version" in *+assertions*) name="$name +a" ;; esac
    printf '%s' "$name"
}

compile() { # $1 = swiftc, $2 = file, $3... = flags; prints one cell
    local swiftc="$1" file="$2" out status
    shift 2
    out=$(perl -e 'alarm 180; exec @ARGV' "$swiftc" "$@" -parse-as-library -sdk "$sdk" \
        -c -o /dev/null "$file" 2>&1)
    status=$?
    if grep -q "$failure" <<<"$out"; then
        echo "ABORTS"
    elif [ $status -eq 0 ]; then
        echo "ok"
    else
        echo "error"
    fi
}

run() { # $1 = swiftc, $2 = file; prints what the program printed
    if perl -e 'alarm 180; exec @ARGV' "$1" -Onone -sdk "$sdk" -o "$work/run" "$2" >/dev/null 2>&1; then
        "$work/run"
    else
        echo "error"
    fi
}

row() { # $1 = label, $2 = file, $3... = flags
    local label="$1" file="$2" line swiftc
    shift 2
    line=$(printf '%-48s' "$label")
    for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(compile "$swiftc" "$file" "$@")"); done
    print_line "$line"
}

variant() { # $1 = label, $2 = source, $3... = flags
    local label="$1"
    printf '%s\n' "$2" > "$work/variant.swift"
    shift 2
    row "$label" "$work/variant.swift" "${@:--O}"
}

run_row() { # $1 = label, $2 = source
    local line swiftc
    printf '%s\n' "$2" > "$work/program.swift"
    line=$(printf '%-48s' "$1")
    for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(run "$swiftc" "$work/program.swift")"); done
    print_line "$line"
}

box='final class Box {
    var name = ""
    func reset(_ unshared: Bool) {
        if unshared { name = "" }
    }
}'

line=$(printf '%-48s' "")
for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(heading "$swiftc")"); done
print_line "$line"

row "Crash.swift: the check as the argument" Crash.swift -O
row "Crash.swift, -Onone" Crash.swift -Onone
variant "WORKAROUND: the check asked first" "$box
func edit(_ box: Box, _ flag: Bool) {
    var before = box
    guard flag else { return }
    let unshared = isKnownUniquelyReferenced(&before)
    before.reset(unshared)
}"
variant "no guard between the var and the call" "$box
func edit(_ box: Box) {
    var before = box
    before.reset(isKnownUniquelyReferenced(&before))
}"
variant "the method stores an Int, not a String" 'final class Box {
    var count = 0
    func reset(_ unshared: Bool) {
        if unshared { count = 0 }
    }
}
func edit(_ box: Box, _ flag: Bool) {
    var before = box
    guard flag else { return }
    before.reset(isKnownUniquelyReferenced(&before))
}'
variant "the method stores an Array" 'final class Box {
    var lines: [Int] = []
    func reset(_ unshared: Bool) {
        if unshared { lines = [] }
    }
}
func edit(_ box: Box, _ flag: Bool) {
    var before = box
    guard flag else { return }
    before.reset(isKnownUniquelyReferenced(&before))
}'
variant "a free function given the var and the check" "$box
func reset(_ box: Box, _ unshared: Bool) { box.reset(unshared) }
func edit(_ box: Box, _ flag: Bool) {
    var before = box
    guard flag else { return }
    reset(before, isKnownUniquelyReferenced(&before))
}"
variant "TUI's shape: returns a new object" 'final class Layout {
    var lines: [Int] = []
    func laidOut(reusingStorage: Bool) -> Layout {
        if reusingStorage { lines = [] }
        return Layout()
    }
}
func edit(_ before: Layout, _ flag: Bool) -> Layout? {
    var before = before
    guard flag else { return nil }
    return before.laidOut(reusingStorage: isKnownUniquelyReferenced(&before))
}'
answering='final class Box {
    var name = ""
    func reset(_ unshared: Bool) -> Bool {
        if unshared { name = "" }
        return unshared
    }
}'
run_row "run: the check as the argument" "$answering
var before = Box()
print(before.reset(isKnownUniquelyReferenced(&before)))"
run_row "run: the check asked first" "$answering
var before = Box()
let unshared = isKnownUniquelyReferenced(&before)
print(before.reset(unshared))"
