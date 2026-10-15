//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EscapeBeforeNonKeyTests.swift
//
//  An `ESC` straight before another escape sequence is either the meta prefix
//  of a key (Option-Shift-Tab is `ESC ESC [ Z`) or the Escape key, pressed
//  just before the terminal sent something else. The parser put it on
//  whatever came next, so in front of anything that is not a key the Escape
//  was lost: before a terminal reply, a mouse or focus report, a paste — and
//  before a paste's start marker the paste itself was lost too, its text typed
//  out as keys. A meta prefix now rides only on a key that follows it
//  directly; in front of anything else the `ESC` is the Escape key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("An Escape before something that is not a key")
struct EscapeBeforeNonKeyTests {

    /// Reference box so the read closure and the test share one byte queue.
    private final class ByteBox { var bytes: [UInt8] = [] }

    /// A terminal reading whatever has been staged, as much as the parser
    /// asks for at a time (``Terminal/readChunk``); returns it and a setter
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

    /// The events `bytes` decode to on their own, in a terminal of their own.
    private func eventsAlone(_ bytes: [UInt8]) -> [TerminalInput] {
        let (terminal, stage) = makeTerminal()
        stage(bytes)
        return events(terminal)
    }

    private static let esc: [UInt8] = [0x1B]
    private static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }
    private static let escape = TerminalInput.key(KeyEvent(key: .escape))
    private static func key(_ character: Character) -> TerminalInput { .key(KeyEvent(character: character)) }
    private static let paste = esc + bytes("[200~quit") + esc + bytes("[201~")
    private static let pasted = TerminalInput.key(KeyEvent(key: .paste("quit")))

    /// The case that types a paste out: Escape and then a paste, close
    /// enough together to share a read (a slow frame queues both). It was
    /// Option+Escape, then `q`, `u`, `i`, `t` as keys.
    @Test("Escape then a paste in one read is Escape, then the paste")
    func escapeThenPaste() {
        #expect(eventsAlone(Self.esc + Self.paste) == [Self.escape, Self.pasted])
    }

    /// The same by the `pendingAltEsc` route: `ESC ESC` goes stale and is
    /// held as a chord, then the paste's tail arrives and the pair is put
    /// back in front of it.
    @Test("A deferred ESC ESC followed by a paste's tail is Escape, then the paste")
    func deferredEscapeThenPasteTail() {
        let (terminal, stage) = makeTerminal()
        stage(Self.esc + Self.esc)
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → held as a chord
        stage(Array(Self.paste.dropFirst()))
        #expect(events(terminal) == [Self.escape, Self.pasted])
    }

    /// A mouse report behind an Escape: SGR, and the legacy form at a row
    /// whose coordinate byte is `A`, which the key parser reads as Up. The
    /// pair was Option+Escape, and Option+Up.
    @Test("Escape then a mouse report in one read is Escape, then the report", arguments: ["[<0;5;3M", "[M !A"])
    func escapeThenMouseReport(report: String) {
        let alone = eventsAlone(Self.esc + Self.bytes(report))
        guard case .mouse = alone.first else {
            Issue.record("\(report.debugDescription) alone is not a mouse report: \(alone)")
            return
        }
        #expect(eventsAlone(Self.esc + Self.esc + Self.bytes(report)) == [Self.escape] + alone)
    }

    /// A reply swallowed whole, and a key after it: the Escape is the
    /// Escape key, and the key is itself. It was Option and the key.
    @Test("Escape, a reply and a key in one read are Escape and the key", arguments: ["]11;rgb:0000/0000/0000\u{07}", "_Gi=1;OK\u{1B}\\"])
    func escapeThenReplyThenKey(reply: String) {
        #expect(eventsAlone(Self.esc + Self.esc + Self.bytes(reply) + Self.bytes("a")) == [Self.escape, Self.key("a")])
    }

    /// A CSI that is not a key (a device-attributes answer) is told once it
    /// has ended. The pair was Option+Escape, as `KeyEvent.parse` reads an
    /// `ESC ESC` it cannot parse further.
    @Test("Escape then a device-attributes answer is Escape")
    func escapeThenDeviceAttributes() {
        #expect(eventsAlone(Self.esc + Self.esc + Self.bytes("[?62;22c") + Self.bytes("b")) == [Self.escape, Self.key("b")])
    }

    /// The review's case: Escape pressed, and before the parser has decided
    /// it is the Escape key, a clipboard answer longer than the parser waits
    /// for arrives, in reads of the parser's size. The Escape was never
    /// delivered: it went with the reply's skip.
    @Test("Escape then an over-long reply arriving in pieces is Escape")
    func escapeThenOverlongReply() {
        let (terminal, stage) = makeTerminal()
        stage(Self.esc)
        #expect(terminal.readEvent() == nil)  // within the Escape-or-sequence wait
        stage(Self.esc + Self.bytes("]52;c;") + Self.bytes(String(repeating: "QUJD", count: 1250)) + [0x07])
        var seen = events(terminal)
        stage(Self.bytes("b"))
        seen += events(terminal)
        #expect(seen == [Self.escape, Self.key("b")])
    }

    /// An over-long CSI behind an Escape, its end and a key arriving with
    /// it: no key is 4 KiB long, so the Escape is the Escape key, and the key
    /// after the skip is itself. It was Option and the key.
    @Test("Escape then an over-long CSI and a key is Escape and the key")
    func escapeThenOverlongCSIThenKey() {
        let overlong = Self.bytes("[") + Self.bytes(String(repeating: "1;", count: 2500)) + Self.bytes("m")
        #expect(eventsAlone(Self.esc + Self.esc + overlong + Self.bytes("b")) == [Self.escape, Self.key("b")])
    }

    /// A sequence straight after the `ESC` that a new one cuts short (a
    /// CSI's parameters, an SS3's modifier) is dropped, and leaves the `ESC`
    /// nothing to prefix: it is the Escape key, and the sequence that cut in
    /// parses on its own. The `ESC` was put back in front of that sequence,
    /// so `ESC ESC [1;2 ESC [A` was Option+Up (review round 2).
    @Test("Escape then a sequence cut short is Escape, then the sequence that cut it", arguments: ["[1;2", "O2"])
    func escapeThenCutShortSequence(cutShort: String) {
        let up = Self.esc + Self.bytes("[A")
        #expect(eventsAlone(Self.esc + Self.esc + Self.bytes(cutShort) + up) == [Self.escape] + eventsAlone(up))
    }

    /// The same for an over-long CSI whose skip ends in the reads that start
    /// it, with only the start of a sequence behind it: the `ESC` was put
    /// back in front of that start, and when the rest arrived the two were
    /// Option+Up, the Escape lost. Fewer passes than the dead-sequence wait
    /// before the rest is staged, so the start is still held.
    @Test("Escape, an over-long CSI and the start of a sequence is Escape, then the sequence")
    func escapeThenOverlongCSIThenSplitSequence() {
        let overlong = Self.bytes("[") + Self.bytes(String(repeating: "1;", count: 2500)) + Self.bytes("m")
        let (terminal, stage) = makeTerminal()
        stage(Self.esc + Self.esc + overlong + Self.esc + Self.bytes("["))
        var seen = (0..<4).compactMap { _ in terminal.readEvent() }
        stage(Self.bytes("A"))
        seen += events(terminal)
        #expect(seen == [Self.escape] + eventsAlone(Self.esc + Self.bytes("[A")))
    }

    /// And a meta prefix still rides on the key straight after it: CSI,
    /// SS3, and a plain byte.
    @Test("A meta prefix still makes an Option chord of the key after it", arguments: ["[Z", "[A", "[1;5C", "OP", "x"])
    func metaPrefixOnAKey(key: String) {
        let sequence = Self.esc + Self.esc + Self.bytes(key)
        guard let chord = KeyEvent.parse(sequence) else {
            Issue.record("\(key.debugDescription) behind ESC ESC is not a key")
            return
        }
        #expect(chord.alt)
        #expect(eventsAlone(sequence) == [.key(chord)])
    }
}
