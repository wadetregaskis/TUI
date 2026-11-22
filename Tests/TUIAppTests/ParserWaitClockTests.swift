//  🖥️ TUI — A Terminal UI framework for Swift
//  ParserWaitClockTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation

/// The input parser's three waits, for a lone `ESC`, an unfinished sequence
/// and a paste that has stopped, are timed on the clock, from when what is
/// waited on arrived. They were counts of `readEvent()` calls, and the run
/// loop's passes are not paced: any wake buys one, so a burst of wakes ran a
/// wait out in microseconds, and a sequence split across two reads became
/// Escape and typing (hunt H-21: APPRUN-1, CORE2-2, CORE2-7).
@MainActor
@Suite("The input parser's waits are timed on the clock")
struct ParserWaitClockTests {
    /// What the next read returns, and the instant the parser reads.
    private final class Script {
        var bytes: [UInt8] = []
        var now: UInt64 = 1_000_000_000

        func advance(milliseconds: UInt64) { now += milliseconds * 1_000_000 }
    }

    private func makeTerminal() -> (Terminal, Script) {
        let terminal = Terminal()
        let script = Script()
        unsafe terminal.readSource = { buffer in
            guard !script.bytes.isEmpty else { return 0 }
            let count = min(script.bytes.count, buffer.count)
            for index in 0..<count { unsafe buffer[index] = script.bytes[index] }
            script.bytes.removeFirst(count)
            return count
        }
        terminal.nowNanos = { script.now }
        return (terminal, script)
    }

    /// Every event `reads` calls of `readEvent()` give, at the script's instant.
    private func read(_ terminal: Terminal, _ reads: Int) -> [TerminalInput] {
        (0..<reads).compactMap { _ in terminal.readEvent() }
    }

    @Test("A lone ESC read three times at one instant still joins its arrow's tail")
    func loneEscapeAtOneInstant() {
        let (terminal, script) = makeTerminal()
        script.bytes = [0x1B]
        var events = read(terminal, 3)
        script.bytes += Array("[A".utf8)
        events += read(terminal, 2)
        #expect(events == [.key(KeyEvent(key: .up))])
    }

    @Test("A lone ESC is the Escape key once 50 ms have passed, on the read after")
    func loneEscapeCommitsAtItsDeadline() {
        let (terminal, script) = makeTerminal()
        script.bytes = [0x1B]
        #expect(read(terminal, 1).isEmpty)
        script.advance(milliseconds: 49)
        #expect(read(terminal, 4).isEmpty, "inside the wait")
        script.advance(milliseconds: 1)
        #expect(read(terminal, 1).isEmpty, "the wait is up: held one read for its tail")
        #expect(read(terminal, 1) == [.key(KeyEvent(key: .escape))])
    }

    @Test("A paste read forty times in 10 ms is not ended by a stall")
    func pasteReadOftenIsNotStalled() {
        let (terminal, script) = makeTerminal()
        script.bytes = Array("\u{1B}[200~abc".utf8)
        var events = read(terminal, 1)
        for _ in 0..<40 {
            events += read(terminal, 1)
            script.now += 250_000
        }
        script.bytes += Array("def\u{1B}[201~".utf8)
        events += read(terminal, 2)
        #expect(events == [.key(KeyEvent(key: .paste("abcdef")))])
    }

    @Test("A paste is ended a second after its last byte, and not before")
    func pasteStallsAfterASecond() {
        let (terminal, script) = makeTerminal()
        script.bytes = Array("\u{1B}[200~ab".utf8)
        #expect(read(terminal, 1).isEmpty)
        script.advance(milliseconds: 600)
        script.bytes = Array("c".utf8)
        #expect(read(terminal, 1).isEmpty, "a byte starts the wait again")
        script.advance(milliseconds: 999)
        #expect(read(terminal, 3).isEmpty)
        script.advance(milliseconds: 1)
        #expect(read(terminal, 1) == [.key(KeyEvent(key: .paste("abc")))])
    }

    @Test("An unfinished sequence read eight times at one instant still completes")
    func unfinishedSequenceAtOneInstant() {
        let (terminal, script) = makeTerminal()
        script.bytes = Array("\u{1B}[<3".utf8)
        var events = read(terminal, 8)
        script.bytes += Array("5;10;20M".utf8)
        events += read(terminal, 2)
        #expect(events.count == 1)
        guard case .mouse = events.first else {
            Issue.record("expected one mouse report, got \(events)")
            return
        }
    }

    @Test("An unfinished sequence is dropped 200 ms after it arrived, and not before")
    func unfinishedSequenceDropsAtItsDeadline() {
        let (terminal, script) = makeTerminal()
        script.bytes = Array("\u{1B}[".utf8)
        #expect(read(terminal, 1).isEmpty)
        script.advance(milliseconds: 199)
        #expect(read(terminal, 3).isEmpty)
        script.advance(milliseconds: 1)
        #expect(read(terminal, 1).isEmpty, "dropped")
        script.bytes = Array("x".utf8)
        #expect(read(terminal, 1) == [.key(KeyEvent(character: "x"))], "not the final byte of the dropped sequence")
    }

    /// CORE2-7: the wait a sequence cut short had run up went to the
    /// sequence that cut it short, and dropped that one early.
    @Test("A sequence that cuts a dead one short waits its own wait")
    func cuttingSequenceWaitsItsOwnWait() {
        let (terminal, script) = makeTerminal()
        script.bytes = Array("\u{1B}[".utf8)
        var events = read(terminal, 1)
        for _ in 0..<6 {
            script.advance(milliseconds: 25)
            events += read(terminal, 1)
        }
        script.bytes = Array("\u{1B}[<".utf8)
        events += read(terminal, 1)
        script.advance(milliseconds: 50)
        events += read(terminal, 1)
        script.bytes = Array("35;10;20M".utf8)
        events += read(terminal, 2)
        #expect(events.count == 1)
        guard case .mouse = events.first else {
            Issue.record("expected one mouse report, got \(events)")
            return
        }
    }

    /// CORE2-7, also: once the cut-short prefix was dropped, the read answered
    /// nothing with a whole sequence at the head of the buffer, left for the
    /// next poll.
    @Test("A whole sequence behind a dropped prefix is read at once")
    func sequenceBehindADroppedPrefixIsReadAtOnce() {
        let (terminal, script) = makeTerminal()
        script.bytes = Array("\u{1B}[\u{1B}[A".utf8)
        #expect(terminal.readEvent() == .key(KeyEvent(key: .up)))
    }
}
