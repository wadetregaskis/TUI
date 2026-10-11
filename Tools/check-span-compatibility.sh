#!/bin/bash
# check-span-compatibility.sh [FILE...]
#
# Fails if a TUIkit executable links `libswiftCompatibilitySpan.dylib` — a load
# command naming it (strong or weak), or a symbol imported from it — or if a
# module that a TUIkit library product ships refers to a symbol that library
# would provide. With no arguments it checks the release build: the Stress and
# Example executables, and the objects of every module of every library
# product (TUIkitAppKit's among them, which no executable here links). It
# builds nothing: run `swift build -c release` first. It asks `$SWIFT`
# (default `swift`, as CI's workflow sets it) where the build is and which
# modules the library products ship. A FILE argument ending in `.o` is checked
# as an object, anything else as an executable. macOS only: elsewhere it says
# so and passes.
#
#   Tools/check-span-compatibility.sh
#   Tools/check-span-compatibility.sh "$(swift build -c release --show-bin-path)/Stress"
#
# Run by CI's macOS release-build lane (.github/workflows/ci.yml, the step
# "Release executables and library modules link no Span back-deployment
# library", after "Release build").
#
# WHY. The standard library's Span family (`Span`, `RawSpan`, `MutableSpan`,
# `MutableRawSpan`, `OutputSpan`, `OutputRawSpan`) is in macOS's own Swift
# runtime from macOS 26. For an older deployment target the linker binds the
# few symbols that are not inlined into the client — each type's metadata and
# descriptor, and a few accessors — to `@rpath/libswiftCompatibilitySpan.dylib`
# instead: the SDK's `libswiftCore.tbd` says so with `$ld$previous` symbols for
# targets from 10.14 to 26.0. That library lives in the toolchain, not in macOS.
# A program run from `.build` finds it through an rpath into the toolchain
# that built it; the same program copied anywhere else, as a user receives it,
# does not, and on macOS 14 and 15 a strong load stops it at launch:
#
#   dyld: Library not loaded: @rpath/libswiftCompatibilitySpan.dylib
#
# Concrete, specialised code that uses a Span type needs none of those symbols:
# every method is inlined. Unspecialised generic code does, and so does anything
# that asks for a Span type's metadata (reflection, a cast, an existential). In
# TUIkit's case it was swift-collections' DequeModule, whose public generic
# entry points reference `OutputSpan`'s metadata accessor and are linked into
# every program that links DequeModule, called or not, because Swift never
# dead-strips a public symbol. Whether the load came out strong or weak was
# decided by the deployment target swift-collections was compiled for, not by
# TUIkit: Swift 6.2.4's SwiftPM compiled it for macOS 10.13, older than
# OutputSpan, so the reference was weak (and NULL below macOS 26); Swift 6.4's
# compiles it for macOS 12, so it was strong, and a copied-out app died at
# launch (measured 2026-10-10 on macOS 15.8 with Xcode 26.3's Swift 6.2.4 and
# swift.org's 6.4.0, swift-collections 1.5.1). TUIkit has used its own buffers
# since (Sources/TUIkitApp/Rendering/InputByteBuffer.swift).
#
# Weak is not good enough either: a weak import of a symbol the compiler
# believes is always there is called without a check, so it is a jump to NULL
# waiting for a code path that reaches it. Hence this fails on any load, weak
# or strong, and any import.
#
# WHY THE OBJECTS TOO. An executable shows only the modules it links, and
# TUIkitAppKit is a library product that no executable in this package links:
# a Span-family reference there would reach every app that links it — called
# or not, as DequeModule's did — and no executable here would show it. So the
# objects of every module a library product ships are read as well, for any
# undefined symbol of the six types above. With the macOS 26.2 SDK those
# types' symbols in `libswiftCore.tbd` are exactly the 33 that `$ld$previous`
# moves to libswiftCompatibilitySpan; matching the types rather than reading
# the list from an SDK keeps the check independent of which SDK `xcrun` finds
# (Command Line Tools' is older, and lists none).
#
# AN EMPTY ANSWER MUST MEAN "NONE", NOT "COULD NOT LOOK". `otool -L` prints
# "is not an object file" and exits 0 for a file it cannot read, so every
# executable must also show the libSystem load and the libSystem imports that
# every macOS program has; `nm` must succeed on every file; every module must
# have objects where SwiftPM puts them (`<bin>/<Module>.build/*.o` under the
# native build system, `<bin>/<Module>.o` under Swift Build). Anything else is
# exit 2: the check could not run, which is not a pass.
#
# READING A FAILURE. The symbols it prints say which Span-family type brought
# the library in (`swift demangle` them). Look for that type in unspecialised
# generic code, in a cast or existential, or in a dependency — swift-collections
# 1.4 and later reference OutputSpan from DequeModule. Use the type only where
# its uses specialise, or not at all. `@available(macOS 26, *)` does not help:
# the compiler treats the Span types as available on every target TUIkit
# supports (they back-deploy), so a reference from code marked macOS 26 is
# still strong (measured 2026-10-10, Swift 6.4.0, macOS 14 target: an
# `@available(macOS 26, *)` generic function appending to an `OutputSpan` gave
# the executable linking it a strong LC_LOAD_DYLIB of the library). Raising
# TUIkit's deployment target to macOS 26 would silence this, and would drop
# macOS 14 and 15.
set -u -o pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    echo "check-span-compatibility: macOS only (libswiftCompatibilitySpan is a macOS back-deployment library); nothing to check"
    exit 0
fi

# A mangled symbol of one of the six types: `$ss` (the standard library), the
# type's length-prefixed name, `V` (a struct). Global symbols carry a leading `_`.
span_symbol='^_\$ss(4Span|7RawSpan|11MutableSpan|14MutableRawSpan|10OutputSpan|13OutputRawSpan)V'

status=0

# Records that the check could not run on $1, and why ($2).
could_not_check() {
    echo "check-span-compatibility: cannot check $1: $2" >&2
    [[ $status -eq 1 ]] || status=2
}

check_executable() {
    local executable=$1 loads imports
    if ! loads=$(otool -L "$executable" 2>&1) || ! grep -qF /usr/lib/libSystem.B.dylib <<<"$loads"; then
        could_not_check "$executable" "otool -L did not list its load commands: ${loads:-no output}"
        return
    fi
    if ! imports=$(nm -m "$executable" 2>&1) || ! grep -qF '(from libSystem)' <<<"$imports"; then
        could_not_check "$executable" "nm -m did not list its imports: $(head -3 <<<"$imports")"
        return
    fi
    loads=$(grep -F libswiftCompatibilitySpan <<<"$loads" | sed 's/^[[:space:]]*//')
    imports=$(grep -F '(from libswiftCompatibilitySpan)' <<<"$imports")
    if [[ -z "$loads" && -z "$imports" ]]; then
        echo "check-span-compatibility: $executable loads no libswiftCompatibilitySpan"
        return
    fi
    status=1
    echo "check-span-compatibility: FAIL: $executable links libswiftCompatibilitySpan.dylib," \
        "which macOS has only from 26: copied out of .build, a strong load stops it at launch on macOS 14" \
        "and 15, and a weak one leaves NULL where its symbols should be. Why, and how to read this: the" \
        "comment at the top of $0" >&2
    [[ -n "$loads" ]] && echo "  load command: ${loads}" >&2
    if [[ -n "$imports" ]]; then
        echo "  imports:" >&2
        sed 's/^/    /' <<<"$imports" >&2
    fi
}

# Returns 0 if `$1` refers to no Span-family symbol, 1 otherwise.
check_object() {
    local object=$1 undefined references
    if ! undefined=$(nm -u -j "$object" 2>&1); then
        could_not_check "$object" "nm -u failed: $(head -3 <<<"$undefined")"
        return 1
    fi
    references=$(grep -E "$span_symbol" <<<"$undefined")
    [[ -z "$references" ]] && return 0
    status=1
    echo "check-span-compatibility: FAIL: $object refers to Span-family symbols that libswiftCompatibilitySpan.dylib" \
        "provides below macOS 26, so every program that links its module links that library. Why, and how to" \
        "read this: the comment at the top of $0" >&2
    sed 's/^/    /' <<<"$references" >&2
    return 1
}

if [[ $# -gt 0 ]]; then
    for file in "$@"; do
        if [[ ! -f "$file" ]]; then
            could_not_check "$file" "no such file"
        elif [[ "$file" == *.o ]]; then
            check_object "$file" && echo "check-span-compatibility: $file refers to no Span-family symbol"
        else
            check_executable "$file"
        fi
    done
    exit $status
fi

# Unquoted on purpose: CI's $SWIFT is a command line (`xcrun --toolchain … swift`).
bin=$(${SWIFT:-swift} build -c release --show-bin-path) || exit 2
for executable in Stress Example; do
    if [[ -f "$bin/$executable" ]]; then
        check_executable "$bin/$executable"
    else
        could_not_check "$bin/$executable" "no such file (build it first: swift build -c release)"
    fi
done

# Every library target that some library product ships, directly or through
# another target: `product_memberships` is transitive. Not the macro plugin (a
# host tool, run by the compiler and never linked into an app), nor targets
# only executables or tests use.
modules=$(${SWIFT:-swift} package describe --type json | python3 -c '
import json, sys
package = json.load(sys.stdin)
libraries = {p["name"] for p in package["products"] if "library" in p["type"]}
for target in package["targets"]:
    if target["type"] == "library" and libraries & set(target.get("product_memberships") or []):
        print(target["name"])
') || { echo "check-span-compatibility: could not list the package's library modules" >&2; exit 2; }
if [[ -z "$modules" ]]; then
    echo "check-span-compatibility: the package describes no module of a library product" >&2
    exit 2
fi

checked=0
for module in $modules; do
    if [[ -f "$bin/$module.o" ]]; then
        objects=("$bin/$module.o")
    else
        objects=("$bin/$module.build"/*.o)
        [[ -f "${objects[0]}" ]] || objects=()
    fi
    if [[ ${#objects[@]} -eq 0 ]]; then
        could_not_check "module $module" \
            "no objects at $bin/$module.o or $bin/$module.build/*.o (build it first: swift build -c release)"
        continue
    fi
    for object in "${objects[@]}"; do
        check_object "$object"
        checked=$((checked + 1))
    done
done
echo "check-span-compatibility: $checked objects of $(wc -w <<<"$modules" | tr -d ' ') library modules" \
    "read; $( [[ $status -eq 0 ]] && echo "none refers to a Span-family symbol" || echo "see above")"
exit $status
