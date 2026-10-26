#!/bin/bash
#
#  🖥️ TUI — A Terminal UI framework for Swift
#  generate.sh
#
#  Created by LAYERED.work
#  License: MIT
#
#  Regenerates Sources/TUIStrings/SFSymbols/SFSymbolTable.generated.swift from the
#  installed SF Symbols app. macOS only; requires the SF Symbols app (Beta or
#  release) in /Applications, unless the mapping comes from a pairs file. See
#  README.md and GenerateSFSymbols.swift.
#
#  Usage:  Tools/GenerateSFSymbols/generate.sh ["/path/to/SF Symbols.app"]
#          Tools/GenerateSFSymbols/generate.sh --pairs FILE   (name<TAB>hex codepoint lines)
#
#  Runs from any directory: a relative app path or FILE is taken from the
#  directory it is run in, and the table is written into the repository the
#  script belongs to.

set -euo pipefail

# Make relative path arguments absolute before the cd below, which the
# generator needs (it writes the table to a repo-relative path).
arguments=()
for argument in "$@"; do
    case "$argument" in
        -* | /*) arguments+=("$argument") ;;
        *) arguments+=("$PWD/$argument") ;;
    esac
done

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

source_file="Tools/GenerateSFSymbols/GenerateSFSymbols.swift"
binary="$(mktemp -t generate-sfsymbols)"
trap 'rm -f "$binary"' EXIT

# `-undefined dynamic_lookup` lets the @_silgen_name binding to the private
# CoreGlyphsLib.Crypton decryptor link; it is resolved at run time by the
# dlopen() calls in the program.
swiftc -O \
    -framework CoreText -framework Foundation \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    -o "$binary" "$source_file"

# `${arguments[@]+…}`, not `"${arguments[@]}"`: under `set -u`, macOS's bash 3.2
# calls an empty array unbound, so a run with no arguments would stop here.
"$binary" ${arguments[@]+"${arguments[@]}"}
