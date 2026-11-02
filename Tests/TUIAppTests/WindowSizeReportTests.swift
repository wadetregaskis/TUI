//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowSizeReportTests.swift
//
//  The in-band resize report, which stands in for SIGWINCH in the browser demo.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation

@MainActor
@Suite("An in-band resize report")
struct WindowSizeReportTests {

    /// A terminal whose input is `bytes`.
    private func terminal(reading bytes: [UInt8]) -> Terminal {
        let terminal = Terminal()
        var remaining = bytes
        terminal.readSource = { buffer in
            let count = min(remaining.count, buffer.count)
            for index in 0..<count { buffer[index] = remaining[index] }
            remaining.removeFirst(count)
            return count
        }
        return terminal
    }

    @Test("It gives the size, is not an event, and hides nothing behind it")
    func report() {
        let terminal = terminal(reading: Array("\u{1B}[48;45;164;0;0tq".utf8))
        #expect(!terminal.consumeWindowSizeReport())
        let event = terminal.readEvent()
        guard case .key(let key)? = event else {
            Issue.record("expected the key behind the report, got \(String(describing: event))")
            return
        }
        #expect(key.key == .character("q"))
        #expect(terminal.getSize() == (164, 45))
        #expect(terminal.consumeWindowSizeReport())
        #expect(!terminal.consumeWindowSizeReport())
    }

    @Test("Only a whole report with positive cells is one")
    func parsing() {
        func parsed(_ text: String) -> (width: Int, height: Int)? { Terminal.windowSizeReport(Array(text.utf8)) }
        #expect(parsed("\u{1B}[48;24;80;0;0t")?.width == 80)
        #expect(parsed("\u{1B}[48;24;80t")?.height == 24)
        #expect(parsed("\u{1B}[8;24;80t") == nil)
        #expect(parsed("\u{1B}[48;0;80t") == nil)
        #expect(parsed("\u{1B}[48;x;80t") == nil)
        #expect(parsed("\u{1B}[48;24;80R") == nil)
        #expect(parsed("t") == nil)
    }
}
