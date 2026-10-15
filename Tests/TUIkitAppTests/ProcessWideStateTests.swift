//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProcessWideStateTests.swift
//
//  Cut from ProcessWideState.swift, which holds the helper it tests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitStyling
@testable import TUIkitTestSupport

/// The door's own check.
@Suite("Process-wide state is written only in a process of its own")
struct ProcessWideStateTests {

    /// Here, in the shared process, a write is refused and recorded, and
    /// nothing any other test reads moves.
    @Test("A write from outside an exit test is refused and recorded")
    func writeOutsideAnExitTestIsRefused() {
        let before = TerminalColors.generation
        withKnownIssue("refused: this is the shared test process") {
            ProcessWideState.colours = TerminalColors(prefersDark: true)
        }
        #expect(TerminalColors.current == .unknown)
        #expect(TerminalColors.generation == before)
    }
}
