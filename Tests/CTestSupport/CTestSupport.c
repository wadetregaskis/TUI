//  🖥️ TUI — A Terminal UI framework for Swift
//  CTestSupport.c
//
//  The header's structs need no code; SwiftPM builds a C target only from a
//  source file. What code there is runs once, as the test bundle loads.
//
//  Created by Wade Tregaskis
//  License: MIT

#include "CTestSupport.h"

/// Defined in Swift, by TUITestProcess's `TestProcessColorDepth.swift`, which
/// depends on this target. Every test target but TUITestingTests links that one
/// (Package.swift says why); one that linked this without it would not link.
extern void TUITestProcessPinColorDepth(void);

/// Pins the colour depth every test draws at to 24-bit, before any test runs.
///
/// The depth a process draws at is detected from its environment the first time
/// anything reads it, and kept. `swift test` sets `NO_COLOR` whenever its output
/// is not a terminal, and `COLORTERM` and `TERM` are whatever the shell had, so
/// the same test drew in colour in one run and without it in the next. Here,
/// as the bundle loads, no test has read it yet and none is running, so the one
/// write reaches every test alike and no test can see it change. A test that
/// wants another depth pins it for its own task (`ColorDepth.withCurrent`), and
/// detection itself is tested on dictionaries (`ColorDepth.detect(environment:)`).
///
/// A constructor, because Swift Testing has no hook that runs before every test
/// of every suite, and a trait on each suite is one a new suite can forget.
__attribute__((constructor)) static void pinTestProcessColorDepth(void) {
    TUITestProcessPinColorDepth();
}
