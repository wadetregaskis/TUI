//  🖥️ TUI — A Terminal UI framework for Swift
//  TestProcessColorDepth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStyling

/// Pins ``ColorDepth/current`` process-wide to 24-bit colour, which every test
/// then draws at unless it pins another for its own task with
/// `ColorDepth.withCurrent`.
///
/// Called once, by the constructor in CTestSupport.c, as the test bundle loads:
/// before any test has run or read the depth, so this write is the only one any
/// test sees (`ProcessWideState` explains why a write once tests are running is
/// another matter). Without it the depth was whatever the environment said the
/// first time something drew: no colour under a piped `swift test`, which sets
/// `NO_COLOR`, and what `COLORTERM` and `TERM` happened to say anywhere else.
@_cdecl("TUITestProcessPinColorDepth")
public func pinTestProcessColorDepth() {
    // swiftlint:disable:next process_wide_write_in_tests
    ColorDepth.current = .truecolor
}
