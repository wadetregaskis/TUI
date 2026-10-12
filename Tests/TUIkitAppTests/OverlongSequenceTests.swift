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

    /// A sequence arriving a byte a read, a CSI and a string sequence: after
    /// each pass the next walk is to start at the end of what has arrived,
    /// not at the sequence's start, so walking it stays linear in its length.
    /// (Until 2026-10-12 every walk began at the start: a sequence of n bytes
    /// arriving a byte a read cost n²/2 byte checks.) And it still parses:
    /// nothing in it is typed, and the key after it is.
    @Test("A sequence arriving a byte a read is walked on from where the last walk stopped", arguments: ["[", "]52;c;"])
    func walkResumesWhereItStopped(introducer: String) {
        let (terminal, source) = makeTerminal(readLimit: 1)
        let end = introducer == "[" ? Self.bytes("m") : [0x07]
        source.bytes =
            Self.esc + Self.bytes(introducer) + Self.bytes(String(repeating: "1;", count: 500)) + end + Self.bytes("b")

        var events: [TerminalInput] = []
        var resumes: [(next: Int, arrived: Int)] = []
        while !source.isDry {
            if let event = terminal.readEvent() { events.append(event) }
            if terminal.input.count > 2, terminal.input[0] == 0x1B {
                resumes.append((terminal.sequenceWalkStart(2), terminal.input.count))
            }
        }
        events += drain(terminal, source)

        #expect(resumes.count > 400, "the sequence was not walked a few bytes at a time")
        let restart = resumes.first { $0.next != $0.arrived }
        #expect(restart == nil, "a walk would start over: \(restart.map { "\($0)" } ?? "")")
        #expect(events == [Self.key("b")])
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
            // Behind an `ESC`, which is the Escape key (no key runs to 4 KiB)
            // and is delivered first, not put back in front of the rest, where
            // it would end the skip.
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
            let escape = overlong[1] == 0x1B ? [TerminalInput.key(KeyEvent(key: .escape))] : []
            #expect(events == escape + [Self.key("b")], "\(overlong.prefix(3))")
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

    // MARK: - Typing during a skip, and during the wait within the cap

    // The two waits are the same length and are counted differently: the
    // skip's starts again from each byte it consumes, while an unfinished
    // sequence's within the cap counts only the passes on which nothing
    // arrives. These pin what decisions-PASTE B-PASTE-2 says of each, which
    // its first version got wrong.

    /// Every other pass a `j`, as a key held to auto-repeat is read.
    private func typeWhileWaiting(_ terminal: Terminal, _ source: Source, passes: Int) -> [TerminalInput] {
        var events: [TerminalInput] = []
        for pass in 0..<passes {
            if pass.isMultiple(of: 2) { source.bytes += Self.bytes("j") }
            if let event = terminal.readEvent() { events.append(event) }
        }
        return events
    }

    /// Pumps `readEvent()` until the parser holds nothing, then reads one `b`.
    private func waitOutThenType(_ terminal: Terminal, _ source: Source) -> [TerminalInput] {
        var events: [TerminalInput] = []
        var pumps = 0
        while terminal.hasPendingInput, pumps < 200 {
            pumps += 1
            if let event = terminal.readEvent() { events.append(event) }
        }
        source.bytes += Self.bytes("b")
        if let event = terminal.readEvent() { events.append(event) }
        return events
    }

    /// In a string sequence's skip a typed letter cannot be told from the
    /// payload, and each one starts the wait again: a held key is skipped
    /// for as long as it repeats, and the key after a pause is the app's.
    @Test("Typing during a skip is skipped, and starts its wait again")
    func typingDuringSkipStartsItsWaitAgain() {
        let (terminal, source) = makeTerminal()
        source.bytes = Self.esc + Self.bytes("]52;c;") + Self.overlongPayload
        #expect(typeWhileWaiting(terminal, source, passes: 64).isEmpty)
        #expect(terminal.hasPendingInput, "the skip ended while bytes kept arriving")
        #expect(waitOutThenType(terminal, source) == [Self.key("b")])
    }

    /// Within the cap, typing joins an unfinished string sequence too, but
    /// cannot make its wait longer: after eight quiet passes in all it is
    /// dropped with what joined it, and every repeat after that is a key.
    /// The eight are the first pass (a pass whose bytes all came in the read
    /// that starts it, into an empty buffer, counts as quiet) and the odd
    /// ones to the thirteenth, so the `j`s of passes 14 to 62 arrive.
    @Test("Typing after an unfinished sequence within the cap does not lengthen its wait")
    func typingDoesNotLengthenTheWaitWithinTheCap() {
        let (terminal, source) = makeTerminal()
        source.bytes = Self.esc + Self.bytes("]52;c;QUJD")
        #expect(typeWhileWaiting(terminal, source, passes: 64) == Array(repeating: Self.key("j"), count: 25))
    }

    /// The Escape key during a string sequence's skip may be the first byte
    /// of its `ST`, so it waits out the skip's eight passes from the last
    /// byte the skip consumed, and then the three a lone `ESC` takes: eleven
    /// in all, about 275 ms at the run loop's 25 ms poll. A key typed in that
    /// time joins it as an Option chord.
    @Test("The Escape key during a string's skip arrives eleven passes after the skip's last byte")
    func escapeDuringStringSkipIsLate() {
        let (terminal, source) = makeTerminal()
        source.bytes = Self.esc + Self.bytes("]52;c;") + Self.overlongPayload + Self.esc
        var events: [TerminalInput] = []
        // The pass that reads the last bytes skips them too, so the wait
        // starts with it.
        repeat {
            if let event = terminal.readEvent() { events.append(event) }
        } while !source.isDry
        var late = 0
        while events.isEmpty, late < 100 {
            late += 1
            if let event = terminal.readEvent() { events.append(event) }
        }
        #expect(events == [.key(KeyEvent(key: .escape))])
        #expect(late == 11)

        let (chord, chordSource) = makeTerminal()
        chordSource.bytes = Self.esc + Self.bytes("]52;c;") + Self.overlongPayload + Self.esc
        repeat { _ = chord.readEvent() } while !chordSource.isDry
        chordSource.bytes += Self.bytes("j")
        guard let optionJ = KeyEvent.parse(Self.esc + Self.bytes("j")), optionJ.alt else {
            Issue.record("ESC j is not an Option chord")
            return
        }
        #expect(drain(chord, chordSource) == [.key(optionJ)])
    }

    /// Within the cap, a lone `ESC` at the end of an unfinished string
    /// sequence is dropped with it when its wait runs out: the Escape is lost
    /// rather than late.
    @Test("The Escape key after an unfinished string within the cap is dropped with it")
    func escapeAfterUnfinishedStringWithinTheCapIsLost() {
        let (terminal, source) = makeTerminal()
        source.bytes = Self.esc + Self.bytes("]52;c;QUJD") + Self.esc
        #expect(terminal.readEvent() == nil)
        #expect(waitOutThenType(terminal, source) == [Self.key("b")])
    }
}
