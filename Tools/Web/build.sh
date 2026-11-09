#!/bin/bash
#
# 🖥️ TUI — A Terminal UI framework for Swift
# build.sh — builds the Example app, or your own, for the browser.
#
#   Tools/Web/build.sh [--debug] [--no-opt] [--product NAME] [--package-path DIR]
#                      [--scratch-path DIR]
#
# Produces `Tools/Web/site/`: the wasm module, the resource bundles SwiftPM
# built, and a manifest saying which guest path each of those files has to
# appear at. Serve it with `Tools/Web/serve.py`.
#
#   --product NAME       the executable to build: `Example` unless named. The
#                        module is `NAME.wasm`, and the page starts it as NAME.
#   --package-path DIR   the package it is in: this repository unless named.
#                        Your own app's package, which depends on TUI, builds
#                        here as well: `--package-path ~/MyApp --product MyApp`.
#   --scratch-path DIR   SwiftPM's build directory: the package's `.build`
#                        unless named. Name one to keep this toolchain's build
#                        apart from your usual compiler's, which shares `.build`
#                        otherwise: two compilers in one build directory
#                        confuse each other's incremental state.
#
# For the Example alone, the manifest also lists its pages and its languages,
# read from its source, for the page's start-page and language pickers.
#
# Prerequisites, and why they are not the toolchain you build the rest with:
#
#   * a swift.org toolchain, not Xcode's. Xcode's compiler is built without the
#     WebAssembly LLVM target and stops at "No available targets are compatible
#     with triple wasm32-unknown-wasip1".
#   * 6.3 or newer. On 6.2.4 the compiler asserts on `TupleView`'s
#     pack-expansion conformance (SILGenPoly, `isPreconcurrency`) — see
#     CONTRIBUTING.md.
#   * the matching WebAssembly SDK. The SDK must be the *same version* as the
#     toolchain or the module files will not load.
#
#       swiftly install 6.3.3
#       swift sdk install \
#         https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
#         --checksum <the one swift.org publishes>
#
set -euo pipefail

TOOLCHAIN_VERSION="${TUI_WASM_TOOLCHAIN:-6.3.3}"
SDK_NAME="${TUI_WASM_SDK:-swift-${TOOLCHAIN_VERSION}-RELEASE_wasm}"
CONFIGURATION="release"
RUN_WASM_OPT=1
PRODUCT="Example"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SITE="$ROOT/Tools/Web/site"
PACKAGE="$ROOT"
SCRATCH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --debug) CONFIGURATION="debug" ;;
        --no-opt) RUN_WASM_OPT=0 ;;
        --product)
            [ $# -ge 2 ] || { echo "--product needs a name" >&2; exit 2; }
            PRODUCT="$2"; shift ;;
        --package-path)
            [ $# -ge 2 ] || { echo "--package-path needs a directory" >&2; exit 2; }
            PACKAGE="$(cd "$2" && pwd)"; shift ;;
        --scratch-path)
            [ $# -ge 2 ] || { echo "--scratch-path needs a directory" >&2; exit 2; }
            SCRATCH="$2"; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Which `swift`. On macOS the plain `swift` is usually Xcode's, which cannot
# target wasm (see above), so it is the swift.org toolchain swiftly installs,
# by path. Elsewhere there is no Xcode to dodge, and the `swift` on PATH is a
# swift.org toolchain already — the Pages workflow builds in CI's
# `swift:6.3.3-noble` container. `TUI_WASM_SWIFT` overrides both.
if [ -n "${TUI_WASM_SWIFT:-}" ]; then
    SWIFT="$TUI_WASM_SWIFT"
elif [ "$(uname -s)" = Darwin ]; then
    SWIFT="$HOME/Library/Developer/Toolchains/swift-${TOOLCHAIN_VERSION}-RELEASE.xctoolchain/usr/bin/swift"
else
    SWIFT="$(command -v swift || true)"
fi

if [ -z "$SWIFT" ] || [ ! -x "$SWIFT" ]; then
    echo "no swift.org toolchain at ${SWIFT:-(none on PATH)}" >&2
    echo "install one with: swiftly install ${TOOLCHAIN_VERSION}" >&2
    exit 1
fi
if ! "$SWIFT" sdk list 2>/dev/null | grep -qx "$SDK_NAME"; then
    echo "no Swift SDK named '$SDK_NAME' (see the header of this script)" >&2
    echo "installed SDKs:" >&2
    "$SWIFT" sdk list >&2 || true
    exit 1
fi

# The stack size is a real requirement, not a precaution. A view tree is
# rendered by recursion, and wasm's default 64 KB of linear-memory stack runs
# out inside the Example's deeper pages; 16 MB matches what the native builds
# get from the main thread.
# What every `swift build` below shares. Never empty, which matters: bash 3.2,
# macOS's, calls an empty array unbound under `set -u`.
PACKAGE_OPTIONS=(--package-path "$PACKAGE" -c "$CONFIGURATION" --swift-sdk "$SDK_NAME")
[ -z "$SCRATCH" ] || PACKAGE_OPTIONS+=(--scratch-path "$SCRATCH")

echo "── building $PRODUCT.wasm ($CONFIGURATION, SDK $SDK_NAME, package $PACKAGE)"
"$SWIFT" build \
    "${PACKAGE_OPTIONS[@]}" \
    --static-swift-stdlib \
    --product "$PRODUCT" \
    -Xlinker -z -Xlinker stack-size=16777216 \
    -Xlinker --strip-debug

BIN="$("$SWIFT" build "${PACKAGE_OPTIONS[@]}" --show-bin-path)"
MODULE="$BIN/$PRODUCT.wasm"
[ -f "$MODULE" ] || { echo "no module at $MODULE" >&2; exit 1; }

mkdir -p "$SITE/resources"
rm -rf "$SITE/resources"/*
# The previous build's module, whichever product it was: the manifest names
# only the new one, and a stale module beside it is tens of megabytes.
rm -f "$SITE"/*.wasm

if [ "$RUN_WASM_OPT" = "1" ] && command -v wasm-opt >/dev/null 2>&1; then
    echo "── wasm-opt -Os"
    wasm-opt -Os --strip-debug --strip-dwarf "$MODULE" -o "$SITE/$PRODUCT.wasm"
else
    [ "$RUN_WASM_OPT" = "1" ] && echo "── wasm-opt not found; shipping the linker's output"
    cp "$MODULE" "$SITE/$PRODUCT.wasm"
fi

# The resource bundles, and the manifest that says where the guest expects to
# find each file. SwiftPM compiles the bundle's location into the binary as an
# absolute host path, so the page serves the files under exactly that path —
# there is no way to ask the module to look somewhere else.
echo "── collecting resource bundles"
python3 - "$BIN" "$SITE" "$PRODUCT" <<'PYTHON'
import json, os, shutil, sys

build_dir, site, product = sys.argv[1], sys.argv[2], sys.argv[3]
resources = os.path.join(site, "resources")
files, directories = [], set()

for bundle in sorted(os.listdir(build_dir)):
    if not bundle.endswith(".resources"):
        continue
    source = os.path.join(build_dir, bundle)
    for base, _, names in os.walk(source):
        for name in names:
            host = os.path.join(base, name)
            guest = os.path.join(build_dir, bundle, os.path.relpath(host, source))
            served = os.path.relpath(host, build_dir)
            target = os.path.join(resources, served)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(host, target)
            files.append({"path": guest, "url": "./resources/" + served.replace(os.sep, "/")})
            directories.add(os.path.dirname(guest))

manifest = {
    "wasm": f"./{product}.wasm",
    "argv0": product,
    "files": files,
    "directories": sorted(directories | {"/config"}),
}
with open(os.path.join(site, "manifest.json"), "w") as handle:
    json.dump(manifest, handle, indent=2)
print(f"   {len(files)} resource file(s)")
PYTHON

# The Example's pages and languages, for the page's pickers: read from the
# source each build, so a page added to `DemoPage` is offered without anyone
# remembering this file. Another product gets neither picker.
if [ "$PRODUCT" = Example ] && [ "$PACKAGE" = "$ROOT" ]; then
    echo "── listing the Example's pages and languages"
    python3 "$ROOT/Tools/Web/example_gallery.py" "$ROOT/Sources/Example" "$SITE/manifest.json"
fi

# The width probe's inputs: the shared corpus, TUI's own widths, and the
# records the Python probes wrote for real terminals. Copied rather than
# fetched from the repo because the demo server serves one directory.
echo "── collecting probe data"
mkdir -p "$SITE/probe-data"
cp "$ROOT/Tools/TerminalProbes/data/"*.json "$SITE/probe-data/"
cp "$ROOT/Tools/Web/glyph-probe.html" "$SITE/glyph-probe.html"

SIZE=$(du -h "$SITE/$PRODUCT.wasm" | cut -f1)
echo "── done: $SITE/$PRODUCT.wasm ($SIZE)"
echo "   serve it with: Tools/Web/serve.py"
