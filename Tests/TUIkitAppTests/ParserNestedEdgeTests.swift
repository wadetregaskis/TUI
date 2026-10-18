//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ParserNestedEdgeTests.swift
//
//  The input parser's edges one level further in than
//  `EscapeBeforeNonKeyTests`: an `ESC` in front of a meta prefix whose own
//  sequence is cut short, an Option chord on a UTF-8 lead that a sequence
//  cuts short, and a legacy mouse report whose coordinate a terminal wrapped
//  past 255 into an `ESC`. In each the parser settled on an Escape and then
//  put that `ESC` back in front of the next sequence, which read it as a meta
//  prefix: the arrow that followed arrived as Option+Up, a chord nobody
//  pressed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Input parser: nested meta prefixes and wrapped legacy coordinates")
struct ParserNestedEdgeTests {

    /// Reference box so the read closure and the test share one byte queue.
    private final class ByteBox { var bytes: [UInt8] = [] }

    /// A terminal reading whatever has been staged; returns it and a setter
    /// that stages more.
    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = ByteBox()
        terminal.readSource = { buffer in
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    /// Pumps `readEvent()` until it has returned nothing sixteen times running.
    private func events(_ terminal: Terminal) -> [TerminalInput] {
        var events: [TerminalInput] = []
        var quiet = 0
        var pumps = 0
        while quiet < 16, pumps < 10_000 {
            pumps += 1
            if let event = terminal.readEvent() {
                events.append(event)
                quiet = 0
            } else {
                quiet += 1
            }
        }
        return events
    }

    /// The events `bytes` decode to in a terminal of their own, whole and
    /// split at every byte: the second is checked against the first, so a
    /// case holds wherever a read boundary falls.
    private func decode(_ bytes: [UInt8], sourceLocation: SourceLocation = #_sourceLocation) -> [TerminalInput] {
        let (terminal, stage) = makeTerminal()
        stage(bytes)
        let whole = events(terminal)
        for split in 1..<bytes.count {
            let (splitTerminal, stageSplit) = makeTerminal()
            stageSplit(Array(bytes[..<split]))
            var seen = splitTerminal.readEvent().map { [$0] } ?? []
            stageSplit(Array(bytes[split...]))
            seen += events(splitTerminal)
            #expect(seen == whole, "split at \(split)", sourceLocation: sourceLocation)
        }
        return whole
    }

    private static let esc: [UInt8] = [0x1B]
    private static let up: [UInt8] = esc + Array("[A".utf8)
    private static let escape = TerminalInput.key(KeyEvent(key: .escape))
    private static let upKey = TerminalInput.key(KeyEvent(key: .up))

    /// `ESC ESC [1;2 ESC [A` is Escape and Up (the sequence after the meta
    /// prefix is cut short, so the prefix is the Escape key). One more `ESC`
    /// in front: the inner pair settled on Escape having dropped the
    /// sequence behind it, and the outer read put that Escape's `ESC` back in
    /// front of the Up, which took it as a meta prefix — Escape, Option+Up.
    @Test("An ESC before a meta prefix whose sequence is cut short leaves the arrow alone")
    func escapeBeforeCutShortMetaSequence() {
        let bytes = Self.esc + Self.esc + Self.esc + Array("[1;2".utf8) + Self.up
        #expect(decode(bytes) == [Self.escape, Self.escape, Self.upKey])
    }

    /// Option and a UTF-8 lead whose continuation a sequence cuts short: the
    /// lead is mis-framed and dropped, so the `ESC` has nothing to prefix and
    /// is the Escape key. It was put back in front of the sequence instead,
    /// and Up arrived as Option+Up.
    @Test("Option and a UTF-8 lead cut short by a sequence is Escape, then the sequence")
    func metaOnCutShortUTF8Lead() {
        #expect(decode(Self.esc + [0xC3] + Self.up) == [Self.escape, Self.upKey])
    }

    /// The same one level in: `ESC ESC 0xC3 ESC [A`.
    @Test("An ESC before Option and a cut-short UTF-8 lead leaves the arrow alone")
    func escapeBeforeMetaOnCutShortUTF8Lead() {
        #expect(decode(Self.esc + Self.esc + [0xC3] + Self.up) == [Self.escape, Self.escape, Self.upKey])
    }

    /// A UTF-8 lead dropped as mis-framed with plain text behind it is still
    /// an Option chord on that text: only an `ESC` left with nothing straight
    /// after it is the Escape key.
    @Test("Option and a mis-framed lead before a letter is Option and the letter")
    func metaOnMisframedLeadThenLetter() {
        let decoded = decode(Self.esc + [0xC3] + Array("x".utf8))
        #expect(decoded == [.key(KeyEvent(key: .character("x"), alt: true))])
    }

    // MARK: Legacy mouse coordinates past 223

    /// A legacy report spells a coordinate as one byte, 32 more than it, so
    /// none past 223 fits. xterm sends a 0 byte for a coordinate past the
    /// end; a terminal that let the byte wrap would send `ESC` at 251, 27
    /// more than 256 (a hypothesis: no measured terminal wraps). Either way
    /// the report is malformed and dropped, and nothing in it is typed: the
    /// `ESC` among its bytes is not a new sequence unless an introducer
    /// follows it. It was taken as one, and `ESC` and the row's byte arrived
    /// as an Option chord.
    @Test(
        "A legacy report with a coordinate past the end types nothing",
        arguments: [
            [0x20, 0x00, 0x25],  // column past the end, xterm's 0 byte
            [0x20, 0x25, 0x00],  // row past the end
            [0x20, 0x1B, 0x25],  // column 251 wrapped to ESC, row 5
            [0x20, 0x25, 0x1B],  // row 251 wrapped to ESC
            [0x20, 0x1B, 0x1B],  // both
        ] as [[UInt8]])
    func legacyReportPastTheEndTypesNothing(coordinates: [UInt8]) {
        let report = Self.esc + Array("[M".utf8) + coordinates
        #expect(decode(report + Array("q".utf8)) == [.key(KeyEvent(character: "q"))])
        #expect(decode(report + Self.up) == [Self.upKey])
    }

    /// An `ESC` among the three bytes that an introducer follows is still a
    /// new sequence cutting the report short (Option-[, `M`, then a paste,
    /// a report or an arrow), as `TerminalInputParsingTests` pins for the
    /// other spellings. A wrapped coordinate followed by a row byte of `[`
    /// (row 59) or `O` (row 47) reads the same way: the two cannot be told
    /// apart, and the cut-short reading is the one that types nothing.
    @Test("An ESC and an introducer among a legacy report's bytes still cuts it short")
    func legacyReportCutShortByASequence() {
        let cutShort = Self.esc + Array("[M ".utf8)
        #expect(decode(cutShort + Self.up) == [Self.upKey])
        #expect(decode(cutShort + Self.esc + Array("OP".utf8)) == [.key(KeyEvent(key: .f1))])
    }
}
