#!/usr/bin/env bash
#
# validate-test-boundaries.sh — enforce per-module unit-test isolation.
#
# TUI's tests are split into per-module test targets (see Package.swift):
# each links only the modules its tests need, so an edit to a module rebuilds
# only the tests that can see it. This script is the fast, human-readable guard
# for that property: it flags a test file importing a module its target does
# not depend on BEFORE a full build would, with a clear message.
#
# - TUI{Core,Styling,View,Image}Tests, the low modules' own unit tests, may
#   import their module and what it depends on (the table below).
# - Every other per-module target (TUIFoundationTests, TUIAppTests,
#   TUIListsTests, ... and the support targets TUITestSupport,
#   TUIAppTestSupport, TUIListsTestSupport, ...) may import what its
#   entry in Package.swift lists in `dependencies:`. So a stray `import TUI`
#   (the umbrella) there fails here: only TUIIntegrationTests depends on it.
# - TUIIntegrationTests, ExampleTests and TUIMacrosTests are unrestricted.
#
# `swift test` already builds every target, so SPM enforces this at compile
# time too; this script exists so the rule is explicit, documented, and catches
# a stray `import TUI` in a module test the moment it lands (CI + pre-commit),
# not only when the offending symbol happens to be referenced.
#
# It also checks that every file of a support target (Tests/*TestSupport), a
# plain target, is wrapped in its guard. `swift build -c release`
# builds that target without testability, so a file outside the guard builds
# in debug and fails CI's release builds (Package.swift says why).
#
# Exit status: 0 if all module test targets stay within their layer and every
# support file is guarded, 1 otherwise.

set -euo pipefail
cd "$(dirname "$0")/.."

# Allowed framework imports per module test target = the module + its transitive
# framework dependencies. (Foundation / Testing / Dispatch etc. are never flagged
# — only TUI* modules are checked.) A `case` keeps this portable to macOS's
# stock bash 3.2 (no associative arrays).
#
# This table is a copy of the library targets' `dependencies:` in Package.swift
# and must be edited with them. TUIView has depended on TUIStyling since
# `Color: View` moved into the module that owns `View` (see the comment on that
# target), so a TUIView test may name a `Color`. TUIWidthCorpus is data
# with no dependencies (the width corpus), so any layer's tests may read it.
# Every other target's row is its `dependencies:` in Package.swift.
allowed_for() {
    case "$1" in
        TUICoreTests) echo "TUICore TUIWidthCorpus" ;;
        TUIStylingTests) echo "TUIStyling" ;;
        TUIViewTests) echo "TUIView TUICore TUIStyling" ;;
        TUIImageTests) echo "TUIImage TUIStyling" ;;
        *)
            # Its entry's `dependencies: [...]` in Package.swift, a test target's or a
            # support target's: the quoted names from its `name:` line to the list's `]`.
            awk -v name="name: \"$1\"," '
                index($0, name) { found = 1; next }
                found && /dependencies:/ { listing = 1 }
                listing { line = $0; gsub(/umbrellaTestDependencies/, "", line)
                          while (match(line, /"[A-Za-z]+"/)) {
                              printf "%s ", substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH) } }
                listing && /\]/ { exit }' Package.swift ;;
    esac
}

violations=0

for dir in Tests/*Tests Tests/*TestSupport; do
    target="${dir#Tests/}"
    case "$target" in
        TUIIntegrationTests | ExampleTests | TUIMacrosTests | CTestSupport) continue ;;
    esac
    [ -d "$dir" ] || continue
    if [ -z "$(allowed_for "$target" | tr -d ' ')" ]; then
        echo "✘ $target has no entry in this script's table, nor dependencies in Package.swift."
        violations=$((violations + 1))
        continue
    fi
    allowed=" $(allowed_for "$target") $target "

    # Every `import TUI<Module>` (optionally @testable) in the target's files.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        file="${line%%:*}"
        rest="${line#*:}"
        lineno="${rest%%:*}"
        module=$(printf '%s\n' "${rest#*:}" | sed -E 's/^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+//' \
            | grep -oE '^TUI[A-Za-z]*' | head -1 || true)
        # Only TUI* modules are governed here.
        case "$module" in TUI*) ;; *) continue ;; esac
        if [[ "$allowed" != *" $module "* ]]; then
            echo "✘ $file:$lineno imports '$module', which is outside $target's layer."
            echo "    Allowed: $(allowed_for "$target"). Move this test to the target of the highest"
            echo "    module it needs (CONTRIBUTING.md says which), or drop the cross-module dependency."
            violations=$((violations + 1))
        fi
    done < <(grep -rnE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+TUI' "$dir" 2>/dev/null || true)
done

# The guard opens the file's code, after its header comment and the comment
# above the guard, and the file's last line is its `#endif`.
guard='#if TUIKIT_TEST_SUPPORT && canImport(Testing)'
while IFS= read -r file; do
    first=$(grep -m 1 -vE '^[[:space:]]*(//.*)?$' "$file" || true)
    last=$(grep -vE '^[[:space:]]*$' "$file" | tail -1)
    if [ "$first" != "$guard" ] || [ "$last" != "#endif" ]; then
        echo "✘ $file is not wrapped in '$guard' ... '#endif'."
        echo "    A release build compiles a support target without testability. Copy the guard,"
        echo "    and the comment above it, from another file there."
        violations=$((violations + 1))
    fi
done < <(find Tests/*TestSupport -name '*.swift' -not -path '*/__*' -not -path 'Tests/CTestSupport/*' 2>/dev/null \
    | sort)

if [ "$violations" -gt 0 ]; then
    echo ""
    echo "✘ $violations test-boundary violation(s). Per-module test targets must import only what they depend on,"
    echo "  and every support-target file must be guarded."
    exit 1
fi

echo "✓ Test module boundaries intact (every per-module test target imports only what it depends on;"
echo "  every support-target file is guarded)."
