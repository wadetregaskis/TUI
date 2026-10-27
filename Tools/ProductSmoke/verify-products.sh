#!/usr/bin/env bash
#
# verify-products.sh — build and run one tiny app per library product of
# TUI, each depending on that product ALONE, with TUI resolved by version
# as a client resolves it.
#
# Everything else CI builds is the package as itself, where every executable
# links the umbrella and so every module. That misses what only a client of ONE
# product sees:
#
#   - a module that uses a sibling it does not declare. In the package it can
#     compile by luck (SwiftPM's own build system finds any module already
#     built in the shared Modules directory) and link, because Example and
#     Stress link everything; a client of that module's product alone gets an
#     unresolved import or undefined symbols, and so does this script's app
#     for it. Swift Build, the default build system from Swift 6.4 on macOS,
#     scans every target's imports, and fails on an undeclared one, or warns
#     where that module happens to be built already, which this script fails
#     on too; which is why CI runs it on the swift.org 6.4 lane;
#   - a module whose re-exports do not give an importer what the docs say
#     they do: each app writes only the imports Choosing Products tells a
#     client of its product to write (its product's module; beside it, for
#     TUIAppKit, TUIFilePanelsAppKit and TUIMacros the module they extend), with
#     MemberImportVisibility on, and uses
#     a name from beneath its module where there is one. One or two names
#     each: a re-export no app happens to use goes unchecked;
#   - a product that does not resolve, or whose name has drifted from its
#     module's.
#
# It also checks that the fixture has an app for every library product the
# manifest declares and none for a product it does not, so a new product needs
# an app here before CI passes.
#
# No dynamic product in the fixture (Package.swift says why).
#
# Cost: one debug build of every TUI module, and 26 small apps. Measured on
# the shared development machine with swift.org 6.4.0 (2026-10-11): 47.9 s in
# all, 25.4 s of it the build. SwiftPM used a prebuilt swift-syntax for
# TUIMacros' plugin (in .build/prebuilts), so the macro app cost little.
#
# Usage:
#   Tools/ProductSmoke/verify-products.sh            # $SWIFT, else swift
#   Tools/ProductSmoke/verify-products.sh --keep     # keep the scratch directory
#
# Exit status: 0 if every app builds and runs.

set -euo pipefail
cd "$(dirname "$0")/../.."

# CI's macOS lanes set SWIFT to a command of several words
# (`xcrun --toolchain <id> swift`), so it is expanded unquoted below.
SWIFT="${SWIFT:-swift}"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

TEMP_DIR="$(mktemp -d)"
PACKAGE_REPO="$TEMP_DIR/TUI"
FIXTURE="$TEMP_DIR/Fixture"
if [ "$KEEP" -eq 1 ]; then
    echo "scratch: $TEMP_DIR"
else
    trap 'rm -rf "$TEMP_DIR"' EXIT
fi

printf '── Checking the fixture has one app per library product\n'
# The manifest's own list, against the fixture's apps and its products array.
declared=$($SWIFT package describe --type json | python3 -c '
import json, sys
package = json.load(sys.stdin)
print("\n".join(sorted(p["name"] for p in package["products"] if "library" in p["type"])))
')
apps=$(cd Tools/ProductSmoke/Sources && ls -d Uses* | sed 's/^Uses//' | sort)
if [ "$declared" != "$apps" ]; then
    echo "error: the library products and Tools/ProductSmoke's apps differ:" >&2
    # diff exits 1 when the lists differ, which they do here; under pipefail
    # that is the pipeline's status, and errexit would stop the script before
    # it says what to do.
    diff <(echo "$declared") <(echo "$apps") | sed 's/^</  product without an app:/; s/^>/  app without a product:/' | grep -v '^[0-9]' >&2 || true
    echo "Give each product an app, Tools/ProductSmoke/Sources/Uses<Product>/main.swift, and list it in" >&2
    echo "Tools/ProductSmoke/Package.swift's products." >&2
    exit 1
fi
for product in $declared; do
    grep -q "\"$product\"" Tools/ProductSmoke/Package.swift \
        || { echo "error: $product is missing from Tools/ProductSmoke/Package.swift's products" >&2; exit 1; }
done
echo "$(wc -w <<<"$declared" | tr -d ' ') products, each with its app"

printf '── Staging the working tree as a versioned package\n'
Tools/stage-versioned-package.sh "$PACKAGE_REPO" 1.0.0
# The fixture is copied out, so that its build and Package.resolved stay out of the tree.
mkdir -p "$FIXTURE"
cp -R Tools/ProductSmoke/Package.swift Tools/ProductSmoke/Sources "$FIXTURE/"
export TUI_PRODUCT_SMOKE_URL="file://$PACKAGE_REPO"

printf '── Building every app\n'
BUILD_LOG="$TEMP_DIR/build.log"
set +e
$SWIFT build --package-path "$FIXTURE" 2>&1 | tee "$BUILD_LOG"
status=${PIPESTATUS[0]}
set -e
[ "$status" -eq 0 ] || { echo "error: the fixture did not build (above)" >&2; exit 1; }
# Swift Build only WARNS when a module imports a sibling it does not declare
# and that sibling happens to be built already: "'TUIGrid' is missing a
# dependency on 'TUILists' because dependency scan of Swift module
# 'TUIGrid' discovered a dependency on 'TUILists'" (an import planted in
# the fixture's checkout, rebuilt, 2026-10-11; the app on that product alone
# then failed to link, undefined symbols). Failing on the warning makes the
# verdict independent of build order. A clean run prints no warning at all.
if grep -q "is missing a dependency on" "$BUILD_LOG"; then
    echo "error: a module imports a module it does not declare:" >&2
    grep "is missing a dependency on" "$BUILD_LOG" >&2
    exit 1
fi

printf '── Running every app\n'
bin=$($SWIFT build --package-path "$FIXTURE" --show-bin-path)
failed=0
for product in $declared; do
    if ! output=$("$bin/Uses$product" 2>&1); then
        echo "FAIL Uses$product: $output" >&2
        failed=$((failed + 1))
        continue
    fi
    echo "$output" | head -1 | cut -c1-160
done
if [ "$failed" -gt 0 ]; then
    echo "error: $failed of the apps failed to run" >&2
    exit 1
fi

printf '\nEvery library product builds and runs on its own\n'
