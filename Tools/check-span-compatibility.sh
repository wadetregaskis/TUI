#!/bin/bash
# check-span-compatibility.sh [EXECUTABLE...]
#
# Fails if a TUIkit executable links `libswiftCompatibilitySpan.dylib`: a load
# command naming it (strong or weak), or a symbol imported from it. With no
# arguments it checks the release builds of Stress and Example, which must
# already exist (`swift build -c release`); it builds nothing, and asks
# `$SWIFT` (default `swift`, as CI's workflow sets it) where they are. macOS
# only: elsewhere it says so and passes.
#
#   Tools/check-span-compatibility.sh
#   Tools/check-span-compatibility.sh "$(swift build -c release --show-bin-path)/Stress"
#
# Run by CI's macOS release-build lane (.github/workflows/ci.yml, "Release
# build").
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
# READING A FAILURE. The symbols it prints say which Span-family type brought
# the library in (`swift demangle` them). Look for that type in unspecialised
# generic code, in a cast or existential, or in a dependency — swift-collections
# 1.4 and later reference OutputSpan from DequeModule. Use the type only where
# its uses specialise, or behind `@available(macOS 26, *)`, or not at all;
# raising TUIkit's deployment target to macOS 26 would also silence this, and
# would drop macOS 14 and 15.
set -u

if [[ "$(uname -s)" != Darwin ]]; then
    echo "check-span-compatibility: macOS only (libswiftCompatibilitySpan is a macOS back-deployment library); nothing to check"
    exit 0
fi

if [[ $# -eq 0 ]]; then
    # Unquoted on purpose: CI's $SWIFT is a command line (`xcrun --toolchain … swift`).
    bin=$(${SWIFT:-swift} build -c release --show-bin-path) || exit 2
    set -- "$bin/Stress" "$bin/Example"
fi

status=0
for executable in "$@"; do
    if [[ ! -f "$executable" ]]; then
        echo "check-span-compatibility: no executable at $executable (build it first: swift build -c release)" >&2
        status=2
        continue
    fi
    loads=$(otool -L "$executable" | grep -F libswiftCompatibilitySpan | sed 's/^[[:space:]]*//')
    imports=$(nm -m "$executable" | grep -F '(from libswiftCompatibilitySpan)')
    if [[ -z "$loads" && -z "$imports" ]]; then
        echo "check-span-compatibility: $executable loads no libswiftCompatibilitySpan"
        continue
    fi
    status=1
    echo "check-span-compatibility: FAIL: $executable links libswiftCompatibilitySpan.dylib," \
        "which macOS has only from 26: copied out of .build, a strong load stops it at launch on macOS 14" \
        "and 15, and a weak one leaves NULL where its symbols should be. Why, and how to read this: the" \
        "comment at the top of $0" >&2
    [[ -n "$loads" ]] && echo "  load command: ${loads}" >&2
    if [[ -n "$imports" ]]; then
        echo "  imports:" >&2
        echo "$imports" | sed 's/^/    /' >&2
    fi
done
exit $status
