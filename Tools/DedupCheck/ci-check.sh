#!/bin/bash
# ci-check.sh : TUIkit's programs linked, stripped and run as the README's "Shipping size" recipe ships them.
#
# The README offers app developers two link flags that change the whole program, `-Xlinker -deduplicate` and
# `-Xlinker -no_exported_symbols`. This keeps TUIkit correct under them:
#
#   1. Relinks Stress with both flags and `--disable-dead-strip`, so that every key path TUIkit's objects form is in
#      it (a dead-stripped Stress keeps 227 to 288 of 315), and runs dedup_check.py on it and the release objects.
#   2. Relinks Stress, Example and IdleProbe with both flags, as an app developer would, and strips them.
#   3. Runs `Stress --selfcheck`, with the render-memo verifier, and the quick PTY smoke (Tools/Smoke/ci-pty-smoke.sh:
#      the walks, the handshake, the kitty keyboard protocol, the quit key's SIGQUIT handler) on the stripped
#      programs.
#
# It compiles nothing: run `swift build -c release` first, and every step here is a link. It leaves the three
# programs deduplicated and stripped in the release directory. macOS only (both flags are ld64's). `$SWIFT` (default
# `swift`) is the toolchain, as CI's workflow sets it. Swift Build (6.4's default) warns, once per module, that
# OTHER_LDFLAGS should not carry -no_exported_symbols, and applies it all the same (measured with 6.4.0).
#
#   swift build -c release && Tools/DedupCheck/ci-check.sh
#
# Run by CI's "macOS 26 · Swift 6.4" lane (.github/workflows/ci.yml, the step "Deduplicated, stripped release
# programs pass the dedup check, selfcheck and PTY smoke"), after its release build.
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    echo "ci-check: macOS only (-deduplicate and -no_exported_symbols are ld64's); nothing to check"
    exit 0
fi
cd "$(dirname "$0")/../.."
# Unquoted on purpose: CI's $SWIFT is a command line (`xcrun --toolchain … swift`).
SWIFT=${SWIFT:-swift}
flags=(-Xlinker -deduplicate -Xlinker -no_exported_symbols)
bin=$($SWIFT build -c release --show-bin-path)

echo "── dedup check: Stress linked whole with ${flags[*]} ──"
$SWIFT build -c release --product Stress --disable-dead-strip "${flags[@]}"
python3 Tools/DedupCheck/dedup_check.py --binary "$bin/Stress" --objects .build --demangle "$SWIFT demangle"

products=(Stress Example IdleProbe)
for product in "${products[@]}"; do
    echo "── $product linked with ${flags[*]}, then stripped ──"
    $SWIFT build -c release --product "$product" "${flags[@]}"
    strip "$bin/$product"
done

echo "── stripped Stress --selfcheck, render memo verified ──"
TUIKIT_VERIFY_RENDER_MEMO=1 "$bin/Stress" --selfcheck

echo "── stripped programs in a real PTY ──"
Tools/Smoke/ci-pty-smoke.sh quick "${bin#"$PWD"/}"
