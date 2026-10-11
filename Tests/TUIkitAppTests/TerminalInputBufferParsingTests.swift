//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalInputBufferParsingTests.swift
//
//  The input parser over its own buffers (`InputByteBuffer`, `InputQueue`),
//  driven through `readSource` with reads of a size the test chooses: one byte
//  at a time, a few, exactly the parser's read size and one either side of it.
//  Where a read boundary lands, and where the buffer has to slide or grow under
//  a sequence still in flight, must not change what the app is told.
//  `InputSplitInvarianceTests` splits each sequence once, at every byte; this
//  feeds whole streams in pieces.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("The input parser over its buffer")
struct TerminalInputBufferParsingTests {

    /// Bytes waiting to be read, and the most one `read()` returns.
    private final class Source {
        var bytes: [UInt8] = []
        var readLimit: Int
        init(readLimit: Int) { self.readLimit = readLimit }
    }

    /// A terminal whose reads return at most `readLimit` of the staged bytes.
    private func makeTerminal(readLimit: Int = .max) -> (Terminal, Source) {
        let terminal = Terminal()
        let source = Source(readLimit: readLimit)
        terminal.readSource = { buffer in
            let count = min(source.bytes.count, buffer.count, source.readLimit)
            guard count > 0 else { return 0 }
            for index in 0..<count { buffer[index] = source.bytes[index] }
            source.bytes.removeFirst(count)
            return count
        }
        return (terminal, source)
    }

    /// Pumps `readEvent()` until the source is dry and nothing is delivered
    /// for a while; a paste fed a byte per read needs a pump per byte.
    private func drain(_ terminal: Terminal, _ source: Source) -> [TerminalInput] {
        var events: [TerminalInput] = []
        var quiet = 0
        var pumps = 0
        while quiet < 8 && pumps < 2_000_000 {
            pumps += 1
            if let event = terminal.readEvent() {
                events.append(event)
                quiet = 0
            } else if source.bytes.isEmpty {
                quiet += 1
            }
        }
        return events
    }

    private static let esc: [UInt8] = [0x1B]
    private static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    /// Keys, mouse reports, focus reports, typed UTF-8, Alt chords, a short
    /// paste and the replies a terminal volunteers, back to back. No bare
    /// `ESC`: whether one is the Escape key depends on the time between reads,
    /// which this does not model.
    private static let stream: [UInt8] =
        bytes("a") + esc + bytes("[A") + bytes("é") + esc + bytes("[<0;10;5M") + esc + bytes("[<0;10;5m")
        + bytes("你") + esc + bytes("[1;5D") + esc + bytes("b") + esc + bytes("[I") + bytes("🎉")
        + esc + bytes("]11;rgb:2828/2c2c/3434") + esc + bytes("\\") + bytes("c")
        + esc + bytes("[?63;1;2;4;6;9;15;16;18;21;22;28;29c") + bytes("d")
        + esc + bytes("_Gi=1;OK") + esc + bytes("\\") + esc + esc + bytes("[Z")
        + esc + bytes("[200~pasted text") + esc + bytes("[201~") + esc + bytes("OP") + esc + bytes("[O") + bytes("z")

    @Test("A stream fed in reads of any size decodes as it does in one", arguments: [1, 2, 3, 5, 7, 64])
    func streamInPiecesDecodesAsWhole(readLimit: Int) {
        let (wholeTerminal, wholeSource) = makeTerminal()
        wholeSource.bytes = Self.stream
        let whole = drain(wholeTerminal, wholeSource)
        #expect(whole.count == 17, "the corpus itself decodes to its seventeen events: \(whole)")

        let (terminal, source) = makeTerminal(readLimit: readLimit)
        source.bytes = Self.stream
        #expect(drain(terminal, source) == whole)
        #expect(terminal.input.isEmpty)
    }

    /// The parser reads 4,096 bytes at a time. A stream of single-byte keys
    /// whose length puts a sequence across that boundary has its head in one
    /// read and its tail in the next, with the buffer making room for the
    /// second read under the unparsed head.
    @Test("A sequence across the parser's read boundary decodes", arguments: [4093, 4094, 4095, 4096, 4097])
    func sequenceAcrossTheReadBoundary(lead: Int) {
        let (terminal, source) = makeTerminal()
        source.bytes = [UInt8](repeating: 0x61, count: lead) + Self.esc + Self.bytes("[<35;120;40M") + Self.bytes("x")
        let events = drain(terminal, source)
        #expect(events.count == lead + 2)
        #expect(events.prefix(lead).allSatisfy { $0 == .key(KeyEvent(character: "a")) })
        guard case .mouse = events.dropFirst(lead).first else {
            Issue.record("the report across the boundary did not decode: \(events.dropFirst(lead))")
            return
        }
        #expect(events.last == .key(KeyEvent(character: "x")))
    }

    /// A paste big enough to grow the buffer several times over, in reads of
    /// the parser's size and of an odd size, with multi-byte characters
    /// throughout so that a read boundary splits some of them.
    @Test("A large paste arrives whole, the key behind it too, and the buffer gives its room back",
          arguments: [4096, 1000])
    func largePaste(readLimit: Int) {
        let line = "Paste line with é, 你 and 🎉 in it.\n"
        let text = String(repeating: line, count: 300_000 / line.utf8.count)
        let (terminal, source) = makeTerminal(readLimit: readLimit)
        source.bytes = Self.esc + Self.bytes("[200~") + Self.bytes(text) + Self.esc + Self.bytes("[201~") + Self.bytes("q")

        let events = drain(terminal, source)
        #expect(events.count == 2)
        #expect(events.first == .key(KeyEvent(key: .paste(text))), "the paste arrived cut or garbled")
        #expect(events.last == .key(KeyEvent(character: "q")))
        #expect(terminal.input.capacity == Terminal.baselineCapacity, "the paste's room was not given back")
        #expect(
            terminal.input.bytesMoved <= 4 * Self.bytes(text).count,
            "copying grew faster than the paste: \(terminal.input.bytesMoved) bytes moved")
    }

    /// The replies the parser siphons off: an OSC colour answer is kept for
    /// the run loop whatever pieces it arrived in, and the keys either side of
    /// every reply arrive as keys.
    @Test("Replies fed in small reads are taken, and the keys around them arrive", arguments: [1, 2, 3])
    func repliesInSmallReads(readLimit: Int) {
        let colourReply = Self.esc + Self.bytes("]11;rgb:2828/2c2c/3434") + Self.esc + Self.bytes("\\")
        let (terminal, source) = makeTerminal(readLimit: readLimit)
        source.bytes = Self.bytes("a") + colourReply + Self.bytes("b")
            + Self.esc + Self.bytes("[?62;22c") + Self.bytes("c")
            + Self.esc + Self.bytes("_Gi=7;OK") + Self.esc + Self.bytes("\\") + Self.bytes("d")
        #expect(drain(terminal, source) == ["a", "b", "c", "d"].map { .key(KeyEvent(character: $0)) })
        #expect(terminal.takeVolunteeredColorReplies() == colourReply)
    }

    /// The buffer holds a read beside any partial sequence the parser waits
    /// for, so neither a read boundary through a sequence nor an Escape key
    /// (held a round as a lone `ESC`) reallocates it. With room for one read
    /// only, each grew the buffer by half, and the next `consume` shrank it
    /// back.
    @Test("Split sequences and an Escape key leave the buffer's allocation alone")
    func partialSequencesDoNotReallocate() {
        let (terminal, source) = makeTerminal()
        var capacities: Set<Int> = [terminal.input.capacity]
        var events: [TerminalInput] = []
        func pump(_ times: Int) {
            for _ in 0..<times {
                if let event = terminal.readEvent() { events.append(event) }
                capacities.insert(terminal.input.capacity)
            }
        }

        // Thirteen-byte motion reports: 4,096-byte reads end inside one.
        let report = Self.esc + Self.bytes("[<35;120;40M")
        source.bytes = Array([[UInt8]](repeating: report, count: 1000).joined())
        pump(1100)
        #expect(events.count == 1000)
        #expect(events.allSatisfy { if case .mouse = $0 { true } else { false } })

        source.bytes = Self.esc
        pump(12)
        source.bytes = Self.bytes("a")
        pump(4)
        #expect(events.dropFirst(1000) == [.key(KeyEvent(key: .escape)), .key(KeyEvent(character: "a"))])
        #expect(capacities == [Terminal.baselineCapacity], "the buffer was reallocated: \(capacities.sorted())")
    }

    /// What an exchange reads but does not own goes back AFTER whatever was
    /// already buffered, because that was read first — here behind a key
    /// still waiting and the head of a sequence still in flight, so the bytes
    /// handed back land behind both, with the buffer's front no longer at its
    /// first byte.
    @Test("Bytes an exchange hands back follow the ones already buffered")
    func handedBackBytesFollowTheBuffer() {
        let (terminal, source) = makeTerminal()
        source.bytes = Self.bytes("ab") + Self.esc + Self.bytes("[")
        #expect(terminal.readEvent() == .key(KeyEvent(character: "a")))
        terminal.enqueue(input: Self.bytes("B") + Self.bytes(String(repeating: "k", count: 5000)))
        let events = drain(terminal, source)
        #expect(events.count == 5002)
        #expect(events.prefix(2) == [.key(KeyEvent(character: "b")), .key(KeyEvent(key: .down))])
        #expect(events.dropFirst(2).allSatisfy { $0 == .key(KeyEvent(character: "k")) })
    }

    /// The events one sequence decodes to beyond the first wait in the queue
    /// and come out, in order, before anything still in the byte buffer.
    @Test("Queued events come out first, in order")
    func queuedEventsComeOutFirst() {
        let (terminal, source) = makeTerminal()
        terminal.queuedInputs.append(contentsOf: [.focusChanged(isFocused: true), .focusChanged(isFocused: false)])
        source.bytes = Self.bytes("x")
        #expect(drain(terminal, source) == [
            .focusChanged(isFocused: true), .focusChanged(isFocused: false), .key(KeyEvent(character: "x")),
        ])
        #expect(terminal.queuedInputs.isEmpty)
    }
}
