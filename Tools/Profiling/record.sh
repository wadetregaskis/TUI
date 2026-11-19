#!/usr/bin/env bash
#
# Record an Instruments Time Profiler trace of Example while a
# scripted scenario drives it, then print the hot functions.
#
# This is the end-to-end ("Mode B") profiling flow: it profiles the real
# app the way a user exercises it (input -> dispatch -> render -> diff ->
# write). For deterministic micro-profiling of the render pipeline alone,
# see the headless harness (`RenderHarness`) in README.md.
#
# Usage:
#   Tools/Profiling/record.sh [scenario] [seconds] [rows] [cols]
#
# Examples:
#   Tools/Profiling/record.sh              # tour, 15s, 50x160
#   Tools/Profiling/record.sh emoji 20     # hammer the emoji list for 20s
#   Tools/Profiling/record.sh idle 12      # steady-state per-frame cost
#
# PROFILE_PRODUCT names another executable product to build and drive in
# Example's place: Stress, booted straight into a scenario by its own
# variables, which the driven app inherits, and left alone (`still`):
#   PROFILE_PRODUCT=Stress TUI_STRESS_SCENARIO=fanout Tools/Profiling/record.sh still 12 24 80
# Stress runs under its autopilot (TUI_STRESS_AUTOPILOT=1) unless the caller
# says otherwise: see below. A page that draws its own frames is profiled with
# it off, so the profile is the page's loop alone:
#   PROFILE_PRODUCT=Stress TUI_STRESS_AUTOPILOT=0 TUI_STRESS_SCENARIO=app-shapes \
#       TUI_STRESS_VARIANT=game-loop Tools/Profiling/record.sh still 12 24 80
#
# PROFILE_SWIFT names the `swift` to build with; by default it is Xcode's
# (see below), not PATH's. DEVELOPER_DIR, if set, names the Xcode.
#
# Requires: Xcode (for `xcrun xctrace`, Instruments) and python3. Run from
# the repository root.
set -euo pipefail

SCENARIO="${1:-tour}"
SECS="${2:-15}"
ROWS="${3:-50}"
COLS="${4:-160}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

PRODUCT="${PROFILE_PRODUCT:-Example}"

# Stress's interactive shell shows a scenario at rest: nothing on a static page
# changes between steps, so under `still` (no input at all) it draws its first
# frame and then sleeps, and the Time Profiler had nothing of the app's to
# sample — 4 ms in the Stress module over 12 s of `fanout` (2026-11-17), the
# rest kernel wake-ups. Its autopilot bumps the frame counter every 33 ms, so a
# frame is drawn ~30 times a second: the scenarios that read the counter churn
# their content, and the rest redraw the footer that shows it through the whole
# pipeline. Example needs nothing of the kind: its pages breathe a focus ring.
# A caller's own value is kept: 0 for a page that animates by itself.
if [ "$PRODUCT" = "Stress" ]; then
    export TUI_STRESS_AUTOPILOT="${TUI_STRESS_AUTOPILOT:-1}"
fi

# Which Xcode, and with it which `swift` and which `xctrace`. NOT whatever is
# first on PATH: there that is often swiftly's toolchain, which may not build
# main at all, and a build with one compiler after another's flips the whole
# .build between them. Nor `xcode-select -p` taken as it is: it may name the
# Command Line Tools, which have no `xctrace` ("unable to find utility").
# A caller's DEVELOPER_DIR wins; else the selected developer directory if it
# is an Xcode; else /Applications/Xcode.app; else any /Applications/Xcode*.app.
# Exported, so drive.py's `xcrun xctrace record` and analyze_timeprofile.py's
# `xcrun xctrace export` find the same Instruments.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${DEVELOPER_DIR:-}" ]; then
    selected="$(xcode-select -p 2>/dev/null || true)"
    case "$selected" in
        *.app/Contents/Developer) DEVELOPER_DIR="$selected" ;;
        *)
            for app in /Applications/Xcode.app /Applications/Xcode*.app; do
                if [ -d "$app/Contents/Developer" ]; then
                    DEVELOPER_DIR="$app/Contents/Developer"
                    break
                fi
            done
            ;;
    esac
    if [ -n "${DEVELOPER_DIR:-}" ]; then
        export DEVELOPER_DIR
    else
        echo "warning: no Xcode found; xctrace needs one (set DEVELOPER_DIR)" >&2
    fi
fi

# PROFILE_SWIFT names the `swift` to build with, overriding the choice below:
# the developer directory's (`xcrun --find swift`) on macOS, PATH's elsewhere.
if [ -n "${PROFILE_SWIFT:-}" ]; then
    SWIFT="$PROFILE_SWIFT"
elif [ "$(uname -s)" = "Darwin" ] && SWIFT="$(xcrun --find swift 2>/dev/null)"; then
    :
else
    SWIFT="swift"
fi

echo "==> Building $PRODUCT (release, with debug symbols) with ${SWIFT}…"
"$SWIFT" build -c release --product "$PRODUCT" -Xswiftc -g
BIN="$("$SWIFT" build -c release --product "$PRODUCT" --show-bin-path)/$PRODUCT"
[ -x "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }

OUTDIR="$REPO_ROOT/profiling-traces"
mkdir -p "$OUTDIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
TRACE="$OUTDIR/${SCENARIO}-${STAMP}.trace"

echo "==> Recording '$SCENARIO' for ${SECS}s at ${COLS}x${ROWS} → $TRACE"
python3 "$REPO_ROOT/Tools/Profiling/drive.py" "$BIN" \
    --scenario "$SCENARIO" --rows "$ROWS" --cols "$COLS" \
    --trace "$TRACE" --time-limit "$((SECS * 1000))"

echo "==> Analyzing…"
python3 "$REPO_ROOT/Tools/Profiling/analyze_timeprofile.py" "$TRACE" --top 25

echo
echo "Trace saved at: $TRACE"
echo "Re-analyze any time with:"
echo "  python3 Tools/Profiling/analyze_timeprofile.py \"$TRACE\" --thread main --top 40"
