//  🖥️ TUI — A Terminal UI framework for Swift
//  HandOffTerminalActionTests.swift
//
//  The action's own rules, with a handler that stands in for a run loop's:
//  the closure runs inside the hand-off, its value or error comes out after
//  it, and a call inside one runs as it is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation

@MainActor
@Suite("HandOffTerminalAction")
struct HandOffTerminalActionTests {
    private struct Refused: Error, Equatable {}

    /// A hand-off whose handler logs its way out and back around the closure.
    private func handOff(logging log: Log) -> TerminalHandOff {
        let handOff = TerminalHandOff()
        handOff.handler = { body in
            log.lines.append("out")
            body()
            log.lines.append("back")
        }
        return handOff
    }

    private final class Log {
        var lines: [String] = []
    }

    @Test("Outside a running app the closure just runs, and its value comes back")
    func noHandler() {
        let action = HandOffTerminalAction(handOff: TerminalHandOff())
        #expect(action { 42 } == 42)
        #expect(HandOffTerminalAction(handOff: nil) { "nothing to hand" } == "nothing to hand")
        #expect(EnvironmentValues().handOffTerminal { 7 } == 7, "the environment's default is such an action")
    }

    @Test("The closure runs between the hand-off and the taking back, and its value comes back")
    func valueComesBack() {
        let log = Log()
        let action = HandOffTerminalAction(handOff: handOff(logging: log))
        let value = action {
            log.lines.append("body")
            return "edited"
        }
        #expect(value == "edited")
        #expect(log.lines == ["out", "body", "back"])
    }

    @Test("What the closure throws comes out after the terminal is taken back")
    func errorIsRethrown() {
        let log = Log()
        let handOff = handOff(logging: log)
        let action = HandOffTerminalAction(handOff: handOff)
        #expect(throws: Refused()) {
            try action { () throws(Refused) -> Int in
                log.lines.append("body")
                throw Refused()
            }
        }
        #expect(log.lines == ["out", "body", "back"])
        #expect(!handOff.isHandedOff, "and the hand-off is over")
    }

    @Test("A call inside the closure runs its own closure as it is, with no second hand-off")
    func nestedCallRunsInline() {
        let log = Log()
        let handOff = handOff(logging: log)
        let action = HandOffTerminalAction(handOff: handOff)
        let value = action {
            log.lines.append("outer")
            return action {
                log.lines.append("inner")
                return handOff.isHandedOff
            }
        }
        #expect(value, "the inner closure ran while the outer hand-off was under way")
        #expect(log.lines == ["out", "outer", "inner", "back"])
        // And the next call hands the terminal over again.
        action { log.lines.append("again") }
        #expect(log.lines.suffix(3) == ["out", "again", "back"])
    }

    @Test("A handler that never runs the closure still has it run, once")
    func handlerThatDropsTheBody() {
        let handOff = TerminalHandOff()
        handOff.handler = { _ in }
        var runs = 0
        let value = HandOffTerminalAction(handOff: handOff) {
            runs += 1
            return runs
        }
        #expect(value == 1)
        #expect(runs == 1)
    }
}
