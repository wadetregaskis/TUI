#!/usr/bin/env bash
#
# The PTY half of the CI smoke test: drive both apps through a real terminal.
#
# `Stress --selfcheck` (run separately, on every CI lane including Windows)
# proves the render stack produces output, but it never opens a terminal. The
# crash classes that only appear in the interactive render loop — the
# 2026-07-17 debug-build stack overflow being the canonical one — are invisible
# to it and to the 3,000+ unit tests. This script is that net.
#
# POSIX only: tui_walk.py uses pty/termios/fcntl. A Windows equivalent needs
# ConPTY and does not exist yet, so the Windows lanes run --selfcheck alone.
#
# Usage: Tools/Smoke/ci-pty-smoke.sh [quick|full] [build-dir]
#
#   quick  (default) — a shallow walk, ~1 minute. Cheap enough to run on every
#                      CI lane, which is the point: an interactive-only crash
#                      that is specific to one Swift version or architecture
#                      still gets caught.
#   full             — every menu item, plus the persistence probe and the
#                      faded-palette sweep: ~11.5 minutes measured, of which the
#                      sweep is 7.25. One lane per OS runs this.
#
# The split exists because tui_walk settles 0.25s after every keystroke, so the
# walk is bounded by keystrokes rather than by anything the app does. It used to
# return the cursor to the top between items, which made that cost grow with the
# SQUARE of the item count (34 items ~1,100 keystrokes, six minutes); it now
# carries on from where the page was opened, which is linear (~70 keystrokes,
# two minutes). The quick/full split is kept anyway: `quick` is a minute on
# every lane, and nine lanes of `full` would still be twenty minutes of runner
# time for the same signal.

set -euo pipefail

DEPTH="${1:-quick}"
BUILD_DIR="${2:-.build/debug}"
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$REPO/$BUILD_DIR" ;; esac
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VENV="${TMPDIR:-/tmp}/tuikit-smoke-venv"

# `full` asks each app how many pages it has rather than carrying a literal.
# The literals drifted: Stress gained two scenarios and `STRESS_ITEMS` stayed at
# 19, so CI walked 19 of 21 and the `menus` and `kitchensink` pages went
# unsmoked for weeks. `quick` is a deliberately shallow walk, so its counts are
# literals on purpose.
case "$DEPTH" in
    quick) EXAMPLE_ITEMS=12; STRESS_ITEMS=6 ;;
    full)  EXAMPLE_ITEMS=""; STRESS_ITEMS="" ;;
    *)     echo "usage: $0 [quick|full] [build-dir]" >&2; exit 2 ;;
esac

# pyte is the screen reconstructor; use system python if available, else a venv
# (which keeps this working on distros that mark system Python externally-managed).
if python3 -c "import pyte" &>/dev/null; then
    PY="python3"
elif [ -x "$VENV/bin/python" ]; then
    PY="$VENV/bin/python"
else
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check pyte
    PY="$VENV/bin/python"
fi

# Never the developer's — or the runner's — real preferences.
export TUIKIT_CONFIG_DIR="${TUIKIT_CONFIG_DIR:-${TMPDIR:-/tmp}/tuikit-smoke-config}"

# Item counts are entries in each app's top-level menu. An empty count means
# "ask the app": `Example --pages` prints `DemoPage.allCases.count` and
# `Stress --help` lists its scenario ids, both from the registry that defines
# them, so neither can fall behind the menu it describes.
page_count() {
    local binary="$1"
    case "$binary" in
        Example) "$BUILD_DIR/Example" --pages ;;
        Stress)  "$BUILD_DIR/Stress" --help | tail -1 | tr ',' '\n' | grep -c . ;;
    esac
}

walk() {
    local binary="$1" count="$2"
    if [ ! -x "$BUILD_DIR/$binary" ]; then
        echo "error: $BUILD_DIR/$binary not built" >&2
        return 1
    fi
    if [ -z "$count" ]; then
        count="$(page_count "$binary")"
        # A derivation that silently yields nothing would walk zero items and
        # pass, which is the failure this replaced.
        case "$count" in
            ''|*[!0-9]*|0) echo "error: could not read $binary's page count" >&2; return 1 ;;
        esac
    fi
    echo "── PTY walk ($DEPTH): $binary, $count items ──"
    "$PY" "$HERE/tui_walk.py" "$BUILD_DIR/$binary" "$count" --settle 0.5
}

cd "$REPO"
walk Example "$EXAMPLE_ITEMS"
walk Stress  "$STRESS_ITEMS"

# A program shipped as one file, without TUIkit's resource bundle beside it:
# SwiftPM's `Bundle.module` stopped every such program at launch, and every
# other check here runs the program beside its build's bundle. Stress copied
# out alone must run in English (asked for German, which is in the bundle), and
# beside a copy of the bundle, directly or through a symbolic link, in German.
# Headless, no pyte: three runs, a few seconds.
echo "── without its resource bundle: runs, in English ──"
"$PY" "$HERE/bundleless_smoke.py" "$BUILD_DIR"

# The arrows as a terminal left in application cursor-key mode sends them
# (`ESC O B`): a killed vim or less leaves DECCKM on, and the parser read only
# F1–F4 in that spelling, so the app's arrows were dead. A walk with dead arrows
# stops at its first item and calls it the end of the menu, which
# `--min-items` turns into a failure. Three items, about five seconds.
echo "── application-mode arrows (SS3) move the menu ──"
"$PY" "$HERE/tui_walk.py" "$BUILD_DIR/Example" 3 \
    --application-keys --min-items 3 --settle 0.5 --per-item ""

# Two checks on the terminal handshake, both cheap (a couple of seconds each)
# and both guarding ORDERING that no type can enforce: the host must be
# identified, and mode 2027 negotiated, before RenderLoop is built, because its
# FrameDiffWriter freezes the advance model at construction. A unit test cannot
# see that; only a live run can. They ran nowhere until now.
echo "── identity: detection reaches the compensation ──"
"$PY" "$HERE/identity_smoke.py" "$BUILD_DIR/Example"

echo "── mode 2027: pinned when needed, and only then ──"
"$PY" "$HERE/mode_pin_smoke.py" "$BUILD_DIR/Example"

# The kitty keyboard protocol: pushed only where the terminal answers its
# query, and popped on every way out — a quit, a suspend, SIGTERM, and an
# abort, SIGHUP or SIGUSR1, which run none of the teardown (a signal handler
# pays it, with the shell's termios). Its flags make every key an escape code,
# Return included, so a pop missed on any of those leaves a shell that cannot
# be typed at. Nine short runs, about forty-five seconds.
echo "── kitty keyboard protocol: pushed where spoken, popped on every exit ──"
"$PY" "$HERE/keyboard_protocol_smoke.py" "$BUILD_DIR/Example"

# The user's quit key, ⌃\: raw mode leaves it the one live signal character,
# so the driver turns it into SIGQUIT even when the app hangs, while ⌃C, ⌃Z, ⌃Y
# and ⌃T stay keys; and SIGQUIT is a quit, not a crash: the handler leaves the
# alternate screen and every mode as a quit does, puts the termios back
# exactly, and ends by the signal's default action, never through the Swift
# runtime's crash reporter (which printed a backtrace on the alternate screen
# and waited half a minute for a key). A user's `stty quit undef` is kept, and
# so is the quit key across a suspend. Against IdleProbe, the smallest app,
# whose `keys` mode shows each key and `hang` mode hangs. Five short runs,
# about fifteen seconds.
echo "── ⌃\\ and SIGQUIT: a quit, not a crash, even when hung ──"
"$PY" "$HERE/quit_key_smoke.py" "$BUILD_DIR/IdleProbe"

# The same class, for the colour exchange: the terminal's colours are asked
# once, with the request its host needs, and published before RenderLoop draws
# its first frame (under tmux the sixteen slots follow that frame, once, rather
# than hold it for tmux's half second), and an app whose grounds are clear
# clears frame one's rows on the terminal's own background (SGR 49) whether the
# terminal reported its page or not. Eight short runs, about half a minute
# (27.5 s measured).
echo "── colours: asked before the first frame ──"
"$PY" "$HERE/colour_query_smoke.py" "$BUILD_DIR/Example"

# A different class of check, and the only one that needs TWO processes: does a
# setting written in one launch come back in the next? The framework's storage
# layer has unit tests; what they cannot say is whether an app's own keys
# round-trip through a real exit. ~11 s, and `full` only — `quick` runs on
# every lane and is budgeted at about a minute.
#
# Its own config directory, NOT the exported one above: the probe's whole
# method is a fresh directory against a reused one, and it must not inherit a
# directory the walks have already written to.
if [ "$DEPTH" = "full" ]; then
    echo "── persistence: settings survive a relaunch ──"
    "$PY" "$HERE/persistence_probe.py" --binary "$BUILD_DIR/Example"
fi

# The same two-process shape for the language: `setLanguage(_:)` is the
# localization service's half (change, persist) and an extension beside the
# views that asks for the frame, put apart by the module split's R1. Switching
# on the Theme page must redraw the page and TUIkit's own status bar words at
# once, and the next launch must open in the choice. ~8 s, `full` only, on its
# own config directory for the persistence probe's reason.
if [ "$DEPTH" = "full" ]; then
    echo "── language: a switch redraws at once and is kept ──"
    "$PY" "$HERE/language_switch_smoke.py" --binary "$BUILD_DIR/Example"
fi

# A timeline rather than a screen: the caret's blink, timed from the bytes the
# app writes. The irregular blink the owner reported held 709, 43 and 369 ms in
# turn while every unit test of the timer passed (CursorBlinkRegularityTests
# checks the runs the loop replays, not the loop); only the live loop's
# timeline showed it. The Text Input page with Blink set (F2) moves nothing
# else, so each write is the caret turning on or off. It judges regularity, not
# length, so a slow runner does not fail it. About 7 s, `full` only.
#
# ADVISORY until it has run clean on every lane for a while, as the Windows
# steps were: an irregular or absent blink is a warning annotation, not a
# failure. To make it gate, drop the `if` and let the probe's status stand.
if [ "$DEPTH" = "full" ]; then
    echo "── caret blink: regular holds in the live loop (advisory) ──"
    if ! "$PY" "$HERE/raw_probe.py" "$BUILD_DIR/Example" \
        --args "--page textInput" --keys f2 --blink --watch 4; then
        echo "::warning title=Caret blink (advisory)::raw_probe.py --blink found the caret's holds irregular, or saw no blink; its timeline is in the log above"
    fi
fi

# Last, because it is far and away the most expensive thing here — 7 min 15 s of
# the 11 min 23 s `full` now measures, against about four for everything above,
# and everything above gives its signal in seconds.
#
# A different failure class again: a paint site that hands a TRANSLUCENT colour
# straight to the ANSI emitter trips the assertion in `Color+ANSICodes.swift`,
# which in a debug build is a trap. Six such sites shipped past the whole unit
# suite and past three re-counts of the ledger meant to list them, because every
# one of those re-read the same list (§68 of `Documentation/Colour and styling/Opacity as
# composition.md`). Only running the app finds the site nobody wrote down.
#
# NOT a walk, and that distinction is the whole reason this is a second script
# rather than `walk Example … ` with the fade exported. A walk was tried: with
# one of those six fixes reverted on purpose it reported every page alive, while
# the sweep trapped on six. `tui_walk.py` steps a menu, and a `Picker`'s selected
# marker is not painted until the pop-up is OPENED — a walk that only navigates
# cannot see a control that has to be opened, so under a fade it proves only that
# the pages draw at rest. The sweep pokes each page, and runs one process per
# page so that a trap (which kills the app) reports the whole inventory instead
# of only the first one.
#
# Run through the venv's interpreter for one interpreter across `Tools/Smoke`,
# though unlike the walk this one needs no `pyte` and would run under any
# `python3`.
if [ "$DEPTH" = "full" ]; then
    "$PY" "$HERE/faded_palette_sweep.py" "$BUILD_DIR"
fi

echo "PTY smoke ($DEPTH): both apps survived."
