#!/usr/bin/env bash
#
# validate-test-boundaries.sh — enforce per-module unit-test isolation.
#
# TUIkit's unit tests are split into per-module test targets (see Package.swift):
# each links ONLY its module, so a test that reaches across a module boundary
# fails to compile. This script is the fast, human-readable guard for that
# property: it flags a module test target importing a module outside its
# dependency closure BEFORE a full build would, with a clear message. The
# umbrella suite's four test targets (TUIkitTests, TUIkitCollectionTests,
# TUIkitControlTests, TUIkitAppTests) and their TUIkitTestSupport are
# unrestricted (integration tests live there).
#
# `swift test` already builds every target, so SPM enforces this at compile
# time too; this script exists so the rule is explicit, documented, and catches
# a stray `import TUIkit` in a module test the moment it lands (CI + pre-commit),
# not only when the offending symbol happens to be referenced.
#
# It also checks that every file of TUIkitTestSupport, the umbrella suite's
# plain support target, is wrapped in its guard. `swift build -c release`
# builds that target without testability, so a file outside the guard builds
# in debug and fails CI's release builds (Package.swift says why).
#
# Exit status: 0 if all module test targets stay within their layer and every
# support file is guarded, 1 otherwise.

set -euo pipefail
cd "$(dirname "$0")/.."

# Allowed framework imports per module test target = the module + its transitive
# framework dependencies. (Foundation / Testing / Dispatch etc. are never flagged
# — only TUIkit* modules are checked.) A `case` keeps this portable to macOS's
# stock bash 3.2 (no associative arrays).
#
# This table is a copy of the library targets' `dependencies:` in Package.swift
# and must be edited with them. TUIkitView has depended on TUIkitStyling since
# `Color: View` moved into the module that owns `View` (see the comment on that
# target), so a TUIkitView test may name a `Color`. TUIkitWidthCorpus is data
# with no dependencies (the width corpus), so any layer's tests may read it.
# TUIkitFoundation (the substrate, under the TUIkit umbrella) has no row: it has
# no test target of its own, and its tests are the umbrella suite's, which this script
# leaves unrestricted. Nor have the modules carved out of it, TUIkitStrings and
# TUIkitTerminalHost (step B2), TUIkitApp (step B3), TUIkitColorPicker (step
# B4), TUIkitNavigation (step B5), TUIkitLists (step B6), TUIkitChrome,
# TUIkitEffects and TUIkitMenus (step B5b), TUIkitBitmaps (step B5c) and
# TUIkitTextInput (step B7), and TUIkitPresentation, peeled out of
# TUIkitNavigation (step C1), TUIkitTables, TUIkitTabs and TUIkitGrid, peeled
# out of TUIkitLists (steps C2 to C4), and TUIkitForms, TUIkitSearch,
# TUIkitPickers and TUIkitNumericControls, peeled out of TUIkitTextInput
# (steps C5 to C8), and TUIkitCurveEditors, peeled out of TUIkitColorPicker
# (C9b): their tests stayed in the umbrella suite, which
# `@testable import`s them. A module that gets a test target of its own gets a
# row here, and joins the loop below.
allowed_for() {
    case "$1" in
        TUIkitCoreTests) echo "TUIkitCore TUIkitWidthCorpus" ;;
        TUIkitStylingTests) echo "TUIkitStyling" ;;
        TUIkitViewTests) echo "TUIkitView TUIkitCore TUIkitStyling" ;;
        TUIkitImageTests) echo "TUIkitImage TUIkitStyling" ;;
    esac
}

violations=0

for target in TUIkitCoreTests TUIkitStylingTests TUIkitViewTests TUIkitImageTests; do
    dir="Tests/$target"
    [ -d "$dir" ] || continue
    allowed=" $(allowed_for "$target") "

    # Every `import TUIkit<Module>` (optionally @testable) in the target's files.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        file="${line%%:*}"
        rest="${line#*:}"
        lineno="${rest%%:*}"
        module=$(printf '%s\n' "$rest" | grep -oE 'TUIkit[A-Za-z]*' | head -1)
        # Only TUIkit* modules are governed here.
        case "$module" in TUIkit*) ;; *) continue ;; esac
        if [[ "$allowed" != *" $module "* ]]; then
            echo "✘ $file:$lineno imports '$module', which is outside $target's layer."
            echo "    Allowed: $(allowed_for "$target"). Move this test to one of the umbrella suite's"
            echo "    four targets (Tests/TUIkitTests, TUIkitCollectionTests, TUIkitControlTests,"
            echo "    TUIkitAppTests; CONTRIBUTING.md says which) or drop the cross-module dependency."
            violations=$((violations + 1))
        fi
    done < <(grep -rnE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+TUIkit' "$dir" 2>/dev/null || true)
done

# The guard opens the file's code, after its header comment and the comment
# above the guard, and the file's last line is its `#endif`.
guard='#if TUIKIT_TEST_SUPPORT && canImport(Testing)'
while IFS= read -r file; do
    first=$(grep -vE '^[[:space:]]*(//.*)?$' "$file" | head -1)
    last=$(grep -vE '^[[:space:]]*$' "$file" | tail -1)
    if [ "$first" != "$guard" ] || [ "$last" != "#endif" ]; then
        echo "✘ $file is not wrapped in '$guard' ... '#endif'."
        echo "    A release build compiles TUIkitTestSupport without testability. Copy the guard,"
        echo "    and the comment above it, from another file there."
        violations=$((violations + 1))
    fi
done < <(find Tests/TUIkitTestSupport -name '*.swift' -not -path '*/__*' 2>/dev/null | sort)

if [ "$violations" -gt 0 ]; then
    echo ""
    echo "✘ $violations test-boundary violation(s). Per-module test targets must stay within their module's layer,"
    echo "  and every TUIkitTestSupport file must be guarded."
    exit 1
fi

echo "✓ Test module boundaries intact (TUIkit{Core,Styling,View,Image}Tests each stay within their layer;"
echo "  every TUIkitTestSupport file is guarded)."
