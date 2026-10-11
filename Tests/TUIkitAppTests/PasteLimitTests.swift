//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PasteLimitTests.swift
//
//  A bracketed paste longer than the parser keeps (`Terminal.maxPasteBytes`).
//  Until 2026-10-11 the parser gave up on such a paste by leaving paste mode,
//  and every later byte of it went to the key parser: an 8 MiB paste of prose
//  typed its letters as shortcuts, and its `q` quit Stress. Past the limit the
//  paste now stays open to its end marker; the app is given its first
//  bytes, and nothing in it is a key. These tests lower the limit through
//  `pasteByteLimit`, so that going past it costs kilobytes rather than
//  megabytes; the real limit is pinned by the last.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A paste longer than the parser keeps")
struct PasteLimitTests {

    /// Bytes to be read, and where each read must stop: after at most
    /// `readLimit` bytes, and never across an offset in `boundaries`.
    ///
    /// Reads from an offset rather than removing from the front, so feeding
    /// megabytes costs a pass, not a pass per read.
    private final class Source {
        var bytes: [UInt8]
        var offset = 0
        let readLimit: Int
        let boundaries: [Int]

        init(bytes: [UInt8], readLimit: Int, boundaries: [Int]) {
            self.bytes = bytes
            self.readLimit = readLimit
            self.boundaries = boundaries
        }

        var isDry: Bool { offset == bytes.count }

        func read(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
            var count = min(bytes.count - offset, buffer.count, readLimit)
            if let next = boundaries.first(where: { $0 > offset }) { count = min(count, next - offset) }
            guard count > 0, let destination = buffer.baseAddress else { return 0 }
            bytes.withUnsafeBufferPointer { source in
                // swiftlint:disable:next force_unwrapping
                destination.update(from: source.baseAddress! + offset, count: count)
            }
            offset += count
            return count
        }
    }

    /// A terminal that keeps at most `limit` bytes of a paste, reading
    /// `bytes` in reads `Source` shapes.
    private func makeTerminal(
        limit: Int?, feeding bytes: [UInt8], readLimit: Int = .max, boundaries: [Int] = []
    ) -> (Terminal, Source) {
        let terminal = Terminal()
        if let limit { terminal.pasteByteLimit = limit }
        let source = Source(bytes: bytes, readLimit: readLimit, boundaries: boundaries)
        terminal.readSource = { source.read(into: $0) }
        return (terminal, source)
    }

    /// Pumps `readEvent()` until the source is dry and nothing has been
    /// delivered for a while; returns the events, and the most bytes the
    /// buffer held between two pumps.
    private func drain(_ terminal: Terminal, _ source: Source) -> (events: [TerminalInput], peak: Int) {
        var events: [TerminalInput] = []
        var peak = 0
        var quiet = 0
        var pumps = 0
        while quiet < 8 && pumps < 1_000_000 {
            pumps += 1
            if let event = terminal.readEvent() {
                events.append(event)
                quiet = 0
            } else if source.isDry {
                quiet += 1
            }
            peak = max(peak, terminal.input.count)
        }
        return (events, peak)
    }

    private static let esc: [UInt8] = [0x1B]
    private static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }
    private static let pasteStart = esc + bytes("[200~")
    private static let pasteEnd = esc + bytes("[201~")

    /// Paste content holding everything but its own end marker: letters that
    /// are shortcuts, digits, the controls a chord could ride on, an arrow
    /// key's sequence and an SS3 one, a mouse report, a start marker, and the
    /// end marker's first five bytes with something else after them.
    private static func content(count: Int) -> [UInt8] {
        let unit = bytes(
            "quit q Q 0123456789 \u{03}\t\r\u{11}\u{1A}\u{7F}"
                + "\u{1B}[A\u{1B}OP\u{1B}[<0;5;5M\u{1B}[200~\u{1B}[201!\n")
        var content: [UInt8] = []
        content.reserveCapacity(count + unit.count)
        while content.count < count { content += unit }
        return Array(content.prefix(count))
    }

    private static func paste(_ bytes: some Sequence<UInt8>) -> TerminalInput {
        .key(KeyEvent(key: .paste(String(bytes: Array(bytes), encoding: .utf8) ?? "(not UTF-8)")))
    }

    private static let typedX = TerminalInput.key(KeyEvent(character: "x"))

    /// The case that quit Stress, at a size a test can afford: five times the
    /// limit, in reads of one byte, of a few, and of the parser's own size.
    @Test("A paste past the limit types nothing, and arrives cut to the limit", arguments: [1, 7, 1000, 4096])
    func overLimitPasteTypesNothing(readLimit: Int) {
        let limit = 20_000
        let content = Self.content(count: 5 * limit + 17)
        let (terminal, source) = makeTerminal(
            limit: limit, feeding: Self.pasteStart + content + Self.pasteEnd + Self.bytes("x"), readLimit: readLimit)

        let (events, peak) = drain(terminal, source)
        #expect(events == [Self.paste(content.prefix(limit)), Self.typedX])
        // What it holds is bounded by the limit, not by the paste: the limit,
        // the read that took it past, and a possible marker's first bytes.
        #expect(peak <= limit + Terminal.readChunk + 5, "the buffer held \(peak) bytes")
        #expect(terminal.input.capacity == Terminal.baselineCapacity, "the paste's room was not given back")
    }

    /// The end marker across the limit, with a read boundary at the limit
    /// too: content from six bytes short of it to six past. Up to the limit
    /// the paste arrives whole; past it, cut to it.
    @Test("An end marker at the limit ends the paste there", arguments: -6...6)
    func endMarkerAtTheLimit(offset: Int) {
        let limit = 10_000
        let content = Self.content(count: limit + offset)
        let (terminal, source) = makeTerminal(
            limit: limit, feeding: Self.pasteStart + content + Self.pasteEnd + Self.bytes("x"),
            boundaries: [Self.pasteStart.count + limit])

        let (events, _) = drain(terminal, source)
        #expect(events == [Self.paste(content.prefix(limit)), Self.typedX], "content \(offset) from the limit")
    }

    /// A paste of exactly the limit is not cut, its last character included;
    /// one byte more is, and it loses that byte and nothing else.
    @Test("A paste of exactly the limit arrives whole")
    func pasteOfExactlyTheLimit() {
        let limit = 10_000
        let exact = String(repeating: "é", count: limit / 2)
        for (text, expected) in [(exact, exact), (exact + "a", exact)] {
            let (terminal, source) = makeTerminal(
                limit: limit, feeding: Self.pasteStart + Self.bytes(text) + Self.pasteEnd + Self.bytes("x"))
            let (events, _) = drain(terminal, source)
            #expect(events == [.key(KeyEvent(key: .paste(expected))), Self.typedX], "\(text.utf8.count) bytes")
        }
    }

    /// The limit falling at each byte of a two-byte and a four-byte
    /// character. Cut there, the paste would not be UTF-8 and would arrive read a byte
    /// to a character, every é and 🎉 in it garbled.
    @Test("The limit never cuts a character in two", arguments: 0...5)
    func limitInsideACharacter(phase: Int) {
        let limit = 10_001
        let text = String(repeating: "a", count: phase) + String(repeating: "é🎉", count: limit / 2)
        var expected = ""
        for character in text {
            guard expected.utf8.count + String(character).utf8.count <= limit else { break }
            expected.append(character)
        }
        #expect(expected.utf8.count > limit - 4)

        let (terminal, source) = makeTerminal(
            limit: limit, feeding: Self.pasteStart + Self.bytes(text) + Self.pasteEnd + Self.bytes("x"))
        let (events, _) = drain(terminal, source)
        #expect(events == [.key(KeyEvent(key: .paste(expected))), Self.typedX])
    }

    /// A paste past the limit whose end marker never comes still ends at the
    /// stall timeout, as the kept part, and the keyboard is the app's again.
    @Test("A paste past the limit whose end never comes is delivered at the stall")
    func stalledOverLimitPaste() {
        let limit = 10_000
        let content = Self.content(count: 3 * limit)
        let (terminal, source) = makeTerminal(limit: limit, feeding: Self.pasteStart + content)

        var events: [TerminalInput] = []
        var pumps = 0
        while events.isEmpty, pumps < 10_000 {
            pumps += 1
            if let event = terminal.readEvent() { events.append(event) }
        }
        #expect(events == [Self.paste(content.prefix(limit))])
        #expect(!terminal.hasPendingInput, "the stalled paste left the parser waiting")

        source.bytes += Self.bytes("x")
        #expect(terminal.readEvent() == Self.typedX)
    }

    /// The limit as specified: twice the 8 MiB paste that quit Stress, so a
    /// paste of that size arrives whole (decisions-PASTE, B-PASTE-1), and the
    /// limit a terminal applies unless a test lowers it. Feeding 8 MiB through
    /// the parser takes seconds in a debug build, so the size is pinned here
    /// and the behaviour at the limit is tested at a lowered one above.
    @Test("The limit is 16 MiB, twice the paste that quit Stress")
    func limitIsSpecified() {
        #expect(Terminal.maxPasteBytes == 16 << 20)
        #expect(Terminal().pasteByteLimit == Terminal.maxPasteBytes)
    }
}
