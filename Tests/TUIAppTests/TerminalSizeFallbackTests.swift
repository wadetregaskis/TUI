//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalSizeFallbackTests.swift
//
//  `Terminal.getSize()` reads the `COLUMNS` / `LINES` environment variables
//  ahead of `TIOCGWINSZ`. Those are ordinary environment variables — a shell's
//  `checkwinsize`, a multiplexer, a CI runner, or a stale export from a
//  since-resized window can all set them — and `Int("0")` parses fine, so an
//  unvalidated read would hand back a zero-row terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Terminal size environment fallback")
struct TerminalSizeFallbackTests {

    @Test(
        "Only a positive value is a size",
        arguments: [
            ("40", 40),          // ordinary
            ("1", 1),            // degenerate but real
            ("0", nil),          // parses as Int — must NOT become a size
            ("-1", nil),         // ditto
            ("-100", nil),
            ("", nil),           // unset-ish
            ("abc", nil),        // garbage
            ("40x100", nil),     // wrong shape
            (" 40", nil),        // Int(" 40") is nil — no silent trimming
        ] as [(String, Int?)])
    func onlyPositiveValuesAreSizes(raw: String, expected: Int?) {
        let terminal = Terminal()
        #expect(terminal.terminalDimension(fromEnvironment: "LINES", in: ["LINES": raw]) == expected)
    }

    @Test("An unset variable is not a size")
    func unsetIsNil() {
        let terminal = Terminal()
        #expect(terminal.terminalDimension(fromEnvironment: "LINES", in: ["COLUMNS": "40"]) == nil)
    }

    /// The tests above pose the parse on a dictionary, so they would all still
    /// pass if the fallback stopped reading the real environment. This one sets
    /// the variable for real — in a process of its own, since the environment
    /// is the whole process's — and asks with the default.
    @Test("With no dictionary given, the process environment is what is read")
    func defaultReadsTheProcessEnvironment() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("LINES", to: "37")
                #expect(Terminal().terminalDimension(fromEnvironment: "LINES") == 37)
            }
        }
    }

    /// The whole of it through the real `getSize()`, whatever this process's stdout
    /// is: a terminal under `swift test`, or nothing under the parallel runner.
    @Test("COLUMNS and LINES are what getSize() says, until a report comes in")
    func getSizeReadsThemFirst() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("COLUMNS", to: "123")
                ProcessWideState.setEnvironment("LINES", to: "45")
                let terminal = Terminal()
                #expect(terminal.getSize() == (123, 45))
                terminal.reportedWindowSize = (164, 50)
                #expect(terminal.getSize() == (164, 50))
                #expect(terminal.windowGrid() == (164, 50))
            }
        }
    }
}
