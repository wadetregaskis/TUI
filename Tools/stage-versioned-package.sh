#!/usr/bin/env bash
#
# stage-versioned-package.sh DEST TAG — copy the working tree into a fresh git
# repository at DEST and tag it TAG, so that a package can depend on THIS tree
# by version, `.package(url: "file://DEST", exact: "TAG")`, the way a client
# depends on a release. SwiftPM then resolves it through the version machinery
# rather than treating it as a local checkout, and builds it as somebody
# else's dependency.
#
# The tree under test, not a published tag: a gate that only examines what is
# already released tells you about a mistake you have already made.
#
# Used by Tools/verify-versioned-consumer.sh and
# Tools/ProductSmoke/verify-products.sh. Bash 3.2 compatible.

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 DEST TAG" >&2
    exit 2
fi
DEST="$1"
TAG="$2"
cd "$(dirname "$0")/.."

mkdir -p "$DEST"

# The WHOLE tree, not just Sources/ and the manifests.
#
# SwiftPM validates every target's path when it loads a manifest, including
# targets the consumer will never build. Ours declares four outside Sources/ —
# Tools/EmojiBugScanner, Tools/EmojiBenchmark, Tools/Profiling/RenderHarness,
# Benchmarks/TUIBenchmarks — so a staging area holding only Sources/ fails
# resolution with "invalid custom path", which says nothing about whether the
# package is consumable. (It said exactly that on the consumer gate's first
# run.)
#
# A consumer clones the repository, so copying the tree is also the faithful
# thing. It costs nothing at build time: the consumer builds the products it
# names and only what they need, so Tests/ and the harnesses are never
# compiled.
#
# Excludes are the artefacts a clone would not carry. `.build` in particular
# holds the host's own build products, which would be both enormous and wrong.
tar -cf - --exclude=./.git --exclude=./.build --exclude=./.swiftpm -C "$PWD" . \
    | tar -xf - -C "$DEST"

git -C "$DEST" init --quiet
git -C "$DEST" config user.name "TUI consumer gate"
git -C "$DEST" config user.email "consumer-gate@localhost"
git -C "$DEST" add .
git -C "$DEST" commit --quiet -m "Working tree under test"
# The version is arbitrary: what matters is that the consumer asks for it
# EXACTLY, so SwiftPM resolves through the version machinery rather than
# treating the dependency as a local checkout.
git -C "$DEST" tag "$TAG"
