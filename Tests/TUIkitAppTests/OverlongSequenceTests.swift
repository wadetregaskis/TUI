//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlongSequenceTests.swift
//
//  An escape sequence longer than the parser waits for (`maxReplyBytes`): a
//  CSI with thousands of parameters, or an OSC, DCS, APC, PM or SOS whose
//  payload runs past 4 KiB, as a clipboard answer's can. The parser stops
//  holding such a sequence at the limit. Until 2026-10-11 it dropped the
//  first 4 KiB and read the rest as typing, so a long enough reply spelled its
//  payload out as keys; now the rest is skipped to the sequence's terminator.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("An over-long escape sequence is not typing")
struct OverlongSequenceTests {

    /// Bytes waiting to be read, at most `readLimit` of them per read and
    /// never across an offset in `boundaries`.
    private final class Source {
        var bytes: [UInt8] = []
        var offset = 0
        let readLimit: Int
        let boundaries: [Int]

        init(readLimit: Int, boundaries: [Int]) {
            self.readLimit = readLimit
            self.boundaries = boundaries
        }

        var isDry: Bool { offset == bytes.count }

        func read(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
            var count = min(bytes.count - offset, buffer.count, readLimit)
            if let next = boundaries.first(where: { $0 > offset }) { count = min(count, next - offset) }
            for index in 0..<count { buffer[index] = bytes[offset + index] }
            offset += count
            return count
        }
    }

    private func makeTerminal(readLimit: Int = .max, boundaries: [Int] = []) -> (Terminal, Source) {
        let terminal = Terminal()
        let source = Source(readLimit: readLimit, boundaries: boundaries)
        terminal.readSource = { source.read(into: $0) }
        return (terminal, source)
    }

    /// Pumps `readEvent()` until the source is dry and nothing is delivered
    /// for a while.
    private func drain(_ terminal: Terminal, _ source: Source) -> [TerminalInput] {
        var events: [TerminalInput] = []
        var quiet = 0
        var pumps = 0
        while quiet < 4 && pumps < 100_000 {
            pumps += 1
            if let event = terminal.readEvent() {
                events.append(event)
                quiet = 0
            } else if source.isDry {
                quiet += 1
            }
        }
        return events
    }

    private static let esc: [UInt8] = [0x1B]
    private static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }
    private static func key(_ character: Character) -> TerminalInput { .key(KeyEvent(character: character)) }

    /// A CSI of ten thousand parameter bytes: digits and `;`, each of them a
    /// key if it were read as one, and `m` to end it.
    private static let overlongCSI = esc + Self.bytes("[") + Self.bytes(String(repeating: "1;", count: 5000)) + Self.bytes("m")

    /// A string sequence's body: letters, digits and `=` (a clipboard
    /// answer's base64), longer than the parser waits for.
    private static let overlongPayload = Self.bytes(String(repeating: "QUJD=z09", count: 1000))

    @Test("An over-long CSI is skipped, and the keys either side of it arrive", arguments: [1, 7, 1000, 4096])
    func overlongCSIIsSkipped(readLimit: Int) {
        let (terminal, source) = makeTerminal(readLimit: readLimit)
        source.bytes = Self.bytes("a") + Self.overlongCSI + Self.bytes("b")
        #expect(drain(terminal, source) == [Self.key("a"), Self.key("b")])
    }

    /// Each string family, ended by BEL and by ST, with a read boundary
    /// between ST's two bytes: an `ESC` alone at the end of a read is the
    /// one moment the skip cannot tell a terminator from a new sequence.
    @Test(
        "An over-long string sequence is skipped to its terminator",
        arguments: ["]52;c;", "P1+r", "_Gi=1;", "^", "X"], [[0x07], [0x1B, 0x5C]])
    func overlongStringIsSkipped(introducer: String, terminator: [UInt8]) {
        let head = Self.bytes("a") + Self.esc + Self.bytes(introducer) + Self.overlongPayload
        let (terminal, source) = makeTerminal(boundaries: [head.count + 1])
        source.bytes = head + terminator + Self.bytes("b")
        #expect(
            drain(terminal, source) == [Self.key("a"), Self.key("b")],
            "\(introducer.debugDescription) ended by \(terminator)")
    }

    /// A new sequence before the terminator cuts the over-long one short, as
    /// it cuts a short one: the new one parses, from its own `ESC`.
    @Test("A new sequence cuts the skip short and parses")
    func newSequenceEndsTheSkip() {
        let up = TerminalInput.key(KeyEvent(key: .up))
        for overlong in [
            Self.esc + Self.bytes("[") + Self.bytes(String(repeating: "1;", count: 5000)),
            Self.esc + Self.bytes("]52;c;") + Self.overlongPayload,
        ] {
            let (terminal, source) = makeTerminal()
            source.bytes = overlong + Self.esc + Self.bytes("[A") + Self.bytes("b")
            #expect(drain(terminal, source) == [up, Self.key("b")])
        }
    }

    /// The rest arriving in a later read, after a few quiet frames: the skip
    /// waits for it rather than reading it as keys.
    @Test("The rest of an over-long sequence arriving later is still skipped")
    func restArrivingLaterIsSkipped() {
        for (overlong, rest) in [
            (Self.esc + Self.bytes("[") + Self.bytes(String(repeating: "1;", count: 2500)), Self.bytes("2;3m")),
            (Self.esc + Self.bytes("]52;c;") + Self.overlongPayload, Self.bytes("QUJD") + Self.esc + Self.bytes("\\")),
            // Behind a meta `ESC`, which goes with it rather than being put
            // back in front of the rest, where it would end the skip.
            (Self.esc + Self.esc + Self.bytes("[") + Self.bytes(String(repeating: "1;", count: 2500)), Self.bytes("2;3m")),
        ] {
            let (terminal, source) = makeTerminal()
            source.bytes = overlong
            var events: [TerminalInput] = []
            for _ in 0..<4 {
                if let event = terminal.readEvent() { events.append(event) }
            }
            source.bytes += rest + Self.bytes("b")
            events += drain(terminal, source)
            #expect(events == [Self.key("b")], "\(overlong.prefix(3))")
        }
    }

    /// A terminal that starts an over-long sequence and never ends it must
    /// not take the keyboard with it: the skip ends at the same wait an
    /// unfinished sequence gets, and the loop is kept polling until then.
    @Test("Silence ends the skip, and the keyboard is the app's again")
    func silenceEndsTheSkip() {
        for overlong in [
            Self.esc + Self.bytes("[") + Self.bytes(String(repeating: "1;", count: 2500)),
            Self.esc + Self.bytes("]52;c;") + Self.overlongPayload,
            Self.esc + Self.bytes("]52;c;") + Self.overlongPayload + Self.esc,
        ] {
            let (terminal, source) = makeTerminal()
            source.bytes = overlong
            #expect(terminal.readEvent() == nil)
            #expect(terminal.hasPendingInput, "the skip must keep the loop polling or its wait never ends")

            var events: [TerminalInput] = []
            var pumps = 0
            while terminal.hasPendingInput, pumps < 200 {
                pumps += 1
                if let event = terminal.readEvent() { events.append(event) }
            }
            #expect(!terminal.hasPendingInput, "the skip never ended")
            source.bytes += Self.bytes("b")
            if let event = terminal.readEvent() { events.append(event) }
            // An `ESC` left at the end is the Escape key by then, as a lone one is.
            let escape = overlong.last == 0x1B ? [TerminalInput.key(KeyEvent(key: .escape))] : []
            #expect(events == escape + [Self.key("b")], "\(overlong.suffix(2))")
        }
    }
}
