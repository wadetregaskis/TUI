#!/bin/bash
#
#  🖥️ TUIkit — Terminal UI Kit for Swift
#  generate.sh
#
#  Created by Wade Tregaskis
#  License: MIT
#
#  Regenerates Sources/TUIkitImage/ImageGlyphCalibration.generated.swift by
#  rasterising the reference monospace font (SF Mono Regular 11) and measuring
#  glyph ink coverage. macOS only (CoreText). See README.md and
#  main.swift.
#
#  Usage:  Tools/GenerateImageGlyphs/generate.sh
#
#  Run from the repository root (the output path is repo-relative).
#
#  The table is one array literal, and CI's type-check budget counts it like
#  any expression: 1,157 solver scopes for its 165 glyphs on Swift 6.2.4 and
#  6.4.0 alike, under the "macOS 26 · Swift 6.4" lane's cap of 1,500 (measured
#  2026-10-08). A regeneration that takes it past a lane's cap raises that cap
#  in the same commit; the "Type-check budget" step in
#  .github/workflows/ci.yml says how.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

source_file="Tools/GenerateImageGlyphs/main.swift"
# Compile the framework's own sampling geometry INTO the tool, so the tool and
# the runtime share one definition of the circle centres / radius / spiral and
# cannot drift apart.
shared_file="Sources/TUIkitImage/ShapeSampling.swift"
binary="$(mktemp -t generate-image-glyphs)"
trap 'rm -f "$binary"' EXIT

swiftc -O \
    -framework AppKit -framework CoreText -framework CoreGraphics -framework Foundation \
    -o "$binary" "$shared_file" "$source_file"

"$binary" "$@"
