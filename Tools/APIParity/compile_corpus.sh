#!/bin/sh
#  🖥️ TUI — A Terminal UI framework for Swift
#  compile_corpus.sh
#
#  Type-checks CompileCorpus.swift against the built TUI modules. Nothing is
#  run and nothing is linked: a clean exit IS the assertion, because every
#  snippet in that file is SwiftUI source that must bind to something here.
#
#  Usage:  swift build && Tools/APIParity/compile_corpus.sh [debug|release]
#
#  Created by Wade Tregaskis
#  License: MIT
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
configuration=${1:-debug}
modules="$repo/.build/$configuration/Modules"

if [ ! -d "$modules" ]; then
    echo "no modules at $modules — run 'swift build' first" >&2
    exit 1
fi

swiftc -typecheck -I "$modules" "$here/CompileCorpus.swift"
# On its own, never beside the file above: that one imports AppKit for the
# bridges, and within one compilation an import in one file loads its module
# for all of them — which is the very leak this one proves is gone.
swiftc -typecheck -I "$modules" "$here/CompileCorpusTUIOnly.swift"
echo "compile corpus: every SwiftUI snippet type-checks against TUI"
# The other way round: SwiftUI code that TUI refuses, each line stating the error
# it must get. `-verify` fails on a missing error, an extra one, or a wrong message.
swiftc -typecheck -I "$modules" -Xfrontend -verify "$here/UnavailableCorpus.swift"
echo "compile corpus: every refused SwiftUI spelling gets its own error"
