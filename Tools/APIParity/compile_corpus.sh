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
# The native build system's modules directory, or Swift Build's products
# directory, where the `.swiftmodule`s sit beside the binaries.
modules="$repo/.build/$configuration/Modules"
if [ ! -d "$modules" ]; then
    case "$configuration" in debug) product=Debug ;; *) product=Release ;; esac
    modules="$repo/.build/out/Products/$product"
fi
if [ ! -d "$modules" ]; then
    echo "no modules at $repo/.build/$configuration/Modules or $modules — run 'swift build' first" >&2
    exit 1
fi

# The package's C modules (`CSTBImage`, ...): a Swift module that imports one
# needs its headers to be loaded, and SwiftPM passes them only to its own
# compilations. Xcode's compiler, because the corpus names Foundation's macros
# (`#Predicate`), whose plugin a swift.org macOS toolchain does not ship, and
# because the modules are the build's: one compiler for both.
c_includes=""
for include in "$repo"/Sources/C*/include; do
    [ -d "$include" ] && c_includes="$c_includes -Xcc -I -Xcc $include"
done
swiftc="xcrun swiftc"

$swiftc -typecheck -I "$modules" $c_includes "$here/CompileCorpus.swift"
# On its own, never beside the file above: that one imports AppKit for the
# bridges, and within one compilation an import in one file loads its module
# for all of them — which is the very leak this one proves is gone.
$swiftc -typecheck -I "$modules" $c_includes "$here/CompileCorpusTUIOnly.swift"
echo "compile corpus: every SwiftUI snippet type-checks against TUI"
# The other way round: SwiftUI code that TUI refuses, each line stating the error
# it must get. `-verify` fails on a missing error, an extra one, or a wrong message.
$swiftc -typecheck -I "$modules" $c_includes -Xfrontend -verify "$here/UnavailableCorpus.swift"
echo "compile corpus: every refused SwiftUI spelling gets its own error"
