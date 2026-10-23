//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LargePasteTests.swift
//
//  A bracketed paste of any size. Until 2026-10-11 the parser gave up on a
//  paste past 1 MiB by leaving paste mode, and every later byte of it went to
//  the key parser: an 8 MiB paste of prose typed its letters as shortcuts, and
//  its `q` quit Stress. From then until 2026-10-12 a paste past 16 MiB stayed
//  open to its end marker and arrived as its first 16 MiB. Now there is no
//  limit: a paste arrives whole however long it is, and nothing in it is a
//  key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

#if canImport(Glibc)
import Glibc
#endif

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A paste of any size")
struct LargePasteTests {

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

    /// A terminal reading `bytes` in reads `Source` shapes.
    private static func makeTerminal(
        feeding bytes: [UInt8], readLimit: Int = .max, boundaries: [Int] = []
    ) -> (Terminal, Source) {
        let terminal = Terminal()
        let source = Source(bytes: bytes, readLimit: readLimit, boundaries: boundaries)
        terminal.readSource = { source.read(into: $0) }
        return (terminal, source)
    }

    /// Pumps `readEvent()` until the source is dry and nothing has been
    /// delivered for a while; returns the events.
    private func drain(_ terminal: Terminal, _ source: Source) -> [TerminalInput] {
        var events: [TerminalInput] = []
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
        }
        return events
    }

    nonisolated private static let esc: [UInt8] = [0x1B]
    nonisolated private static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }
    nonisolated private static let pasteStart = esc + bytes("[200~")
    nonisolated private static let pasteEnd = esc + bytes("[201~")

    /// The content a paste test feeds: whole repeats of a unit holding
    /// everything but the paste's own end marker, at least `count` bytes of
    /// it. Letters that are shortcuts, digits, the controls a chord could ride
    /// on, an arrow key's sequence and an SS3 one, a mouse report, a start
    /// marker, the end marker's first five bytes with something else after
    /// them, and characters of two, three and four bytes for a read to split.
    ///
    /// After `prefix`, when there is one, in the same array, with room left
    /// for an end marker: the measuring test below must not leave a freed
    /// block the size of the paste for the allocator to hand back.
    nonisolated private static func content(count: Int, after prefix: [UInt8] = []) -> [UInt8] {
        let unit = bytes(
            "quit q Q 0123456789 \u{03}\t\r\u{11}\u{1A}\u{7F}"
                + "\u{1B}[A\u{1B}OP\u{1B}[<0;5;5M\u{1B}[200~\u{1B}[201!é你🎉\n")
        var content = prefix
        content.reserveCapacity(prefix.count + count + unit.count + pasteEnd.count)
        while content.count - prefix.count < count { content += unit }
        return content
    }

    private static func paste(_ bytes: some Sequence<UInt8>) -> TerminalInput {
        .key(KeyEvent(key: .paste(String(bytes: Array(bytes), encoding: .utf8) ?? "(not UTF-8)")))
    }

    private static let typedX = TerminalInput.key(KeyEvent(character: "x"))

    /// The case that quit Stress, at a size that grows the buffer several
    /// times over, in reads of one byte, of a few, and of the parser's own
    /// size: a read of one byte splits every sequence and character in it.
    @Test("A paste arrives whole and types nothing, in reads of any size", arguments: [1, 7, 1000, 4096])
    func pasteArrivesWhole(readLimit: Int) {
        let content = Self.content(count: 100_000)
        let (terminal, source) = Self.makeTerminal(
            feeding: Self.pasteStart + content + Self.pasteEnd + Self.bytes("x"), readLimit: readLimit)

        let events = drain(terminal, source)
        #expect(events == [Self.paste(content), Self.typedX])
        #expect(terminal.input.capacity == Terminal.baselineCapacity, "the paste's room was not given back")
        #expect(
            terminal.input.bytesMoved <= 4 * content.count,
            "copying grew faster than the paste: \(terminal.input.bytesMoved) bytes moved")
    }

    /// Past the 16 MiB the parser kept until 2026-10-12, which a paste this
    /// size arrived cut to.
    @Test("A paste past 16 MiB arrives whole")
    func pastePastSixteenMiB() {
        let content = Self.content(count: (16 << 20) + 65_536)
        let (terminal, source) = Self.makeTerminal(
            feeding: Self.pasteStart + content + Self.pasteEnd + Self.bytes("x"))

        let events = drain(terminal, source)
        #expect(events.count == 2)
        guard case .key(let key) = events.first, case .paste(let text) = key.key else {
            Issue.record("no paste: \(events.first.map { String(describing: $0).prefix(80) } ?? "nothing")")
            return
        }
        #expect(text.utf8.count == content.count, "the paste arrived cut")
        // `memcmp` rather than `elementsEqual`, which walks 16 MiB a byte at a
        // time through generic code in a debug build.
        let same = text.utf8.withContiguousStorageIfAvailable { memcmp($0.baseAddress!, content, content.count) == 0 }
        #expect(same == true, "the paste arrived changed")
        #expect(events.last == Self.typedX)
        #expect(terminal.input.capacity == Terminal.baselineCapacity, "the paste's room was not given back")
    }

    /// A read boundary at each byte of the paste's tail: through the end
    /// marker, the characters of two, three and four bytes before it, and the
    /// fake start marker and five-byte false end marker before those. The
    /// boundary falls among reads of the parser's own size, at the end of a
    /// buffer the paste has already grown.
    @Test("A read boundary anywhere in a paste's tail splits nothing", arguments: -27...6)
    func readBoundaryInTheTail(offset: Int) {
        let content = Self.content(count: 20_000)
        let markerAt = Self.pasteStart.count + content.count
        let (terminal, source) = Self.makeTerminal(
            feeding: Self.pasteStart + content + Self.pasteEnd + Self.bytes("x"), boundaries: [markerAt + offset])

        #expect(drain(terminal, source) == [Self.paste(content), Self.typedX], "a boundary \(offset) from the marker")
    }

    /// A paste that is not UTF-8 arrives read a byte to a character: each
    /// byte its Latin-1 character, the control bytes and the high half
    /// included, and nothing dropped or doubled, however the reads split it.
    @Test("A paste that is not UTF-8 arrives as Latin-1", arguments: [1, 7, 4096])
    func latin1Paste(readLimit: Int) {
        // Every byte value but ESC, which could begin the end marker; 0xC0 and
        // 0xFF are never UTF-8, so the whole paste is not.
        let unit = (0...255).map(UInt8.init).filter { $0 != 0x1B }
        var content: [UInt8] = []
        while content.count < 20_000 { content += unit }
        let (terminal, source) = Self.makeTerminal(
            feeding: Self.pasteStart + content + Self.pasteEnd + Self.bytes("x"), readLimit: readLimit)
        let expected = String(String.UnicodeScalarView(content.map { Unicode.Scalar($0) }))
        #expect(drain(terminal, source) == [.key(KeyEvent(key: .paste(expected))), Self.typedX])
        #expect(expected.unicodeScalars.count == content.count)
        let decoded = content.withUnsafeBufferPointer { Terminal.latin1Text($0) }
        #expect(decoded.utf8.count == content.count + content.filter { $0 >= 0x80 }.count)
    }

    /// A paste whose end marker never comes still ends at the stall timeout,
    /// whole, and the keyboard is the app's again.
    @Test("A paste whose end never comes is delivered whole at the stall")
    func stalledPaste() {
        let content = Self.content(count: 100_000)
        let (terminal, source) = Self.makeTerminal(feeding: Self.pasteStart + content)

        var events: [TerminalInput] = []
        var pumps = 0
        while events.isEmpty, pumps < 10_000 {
            pumps += 1
            if let event = terminal.readEvent() { events.append(event) }
        }
        #expect(events == [Self.paste(content)])
        #expect(!terminal.hasPendingInput, "the stalled paste left the parser waiting")
        #expect(terminal.input.capacity == Terminal.baselineCapacity, "the paste's room was not given back")

        source.bytes += Self.bytes("x")
        #expect(terminal.readEvent() == Self.typedX)
    }

    /// What delivering a paste adds to the process: its string, made once
    /// from the buffer, and nothing else. Until 2026-10-12 the bytes were
    /// copied into an array on the way, and delivering a 16 MiB paste raised
    /// the footprint's peak by twice the paste over what the open paste held
    /// (measured, macOS: 2.0 times; 1.0 without the copy).
    ///
    /// An exit test, so that the peak is this paste's: the body runs in a
    /// child process of its own. The footprint, not the resident size: macOS
    /// hands a freed large block back as reusable, which leaves the footprint
    /// at once and the resident size only when the kernel reclaims it, so the
    /// resident size counts every size the buffer grew through. And no
    /// freed block as large as the paste on the way: the allocator would hand
    /// it to the copy, which would then cost the footprint nothing (it hid
    /// the copy from the first version of this test).
    #if canImport(Darwin)
    @Test("Delivering a paste costs the process its string and no copy besides")
    func deliveryCostsTheString() async {
        await #expect(processExitsWith: .success) {
            let size = 16 << 20
            let (delivered, raised) = await MainActor.run { () -> (Int?, Int) in
                let (terminal, source) = Self.makeTerminal(feeding: Self.content(count: size, after: Self.pasteStart))
                // The whole paste in the buffer, its end marker still to come.
                while !source.isDry { _ = terminal.readEvent() }
                let held = Self.footprint()
                source.bytes += Self.pasteEnd
                guard case .key(let key) = terminal.readEvent(), case .paste(let text) = key.key else { return (nil, 0) }
                return (text.utf8.count, Self.footprint(peak: true) - held)
            }
            #expect((delivered ?? 0) >= size, "no paste, or a cut one")
            #expect(raised < size * 3 / 2, "delivering the paste raised the peak by \(raised >> 20) MiB")
        }
    }

    /// The process's footprint now, or the most it has been.
    nonisolated private static func footprint(peak: Bool = false) -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        #expect(result == KERN_SUCCESS)
        return peak ? Int(info.ledger_phys_footprint_peak) : Int(info.phys_footprint)
    }
    #endif

    /// What decoding a paste that is not UTF-8 costs: every byte above 0x7F,
    /// so 16 MiB read becomes 32 MiB of text, and the process may grow by that
    /// and not much more. It grows by 32 MiB; the second spelling of the
    /// decode (``Terminal/latin1Text(_:)`` says what it was) grew it by 144 MiB
    /// (both measured 2026-10-11, macOS, Swift 6.2.4, debug).
    ///
    /// An exit test, so the peak resident size is this decode's: the body
    /// runs in a child process of its own, where no other test allocates.
    @Test("Decoding a paste that is not UTF-8 grows the process by the text, not a copy per byte")
    func latin1DecodePeak() async {
        await #expect(processExitsWith: .success) {
            let content = [UInt8](repeating: 0xE9, count: 16 << 20)
            let before = Self.peakResidentBytes()
            let text = content.withUnsafeBufferPointer { Terminal.latin1Text($0) }
            let grown = Self.peakResidentBytes() - before
            #expect(text.utf8.count == 2 * content.count)
            #expect(text.unicodeScalars.allSatisfy { $0 == "\u{E9}" })
            #expect(grown < 3 * content.count, "the decode grew the process by \(grown >> 20) MiB")
        }
    }

    /// The largest resident size this process has held, in bytes. Stress has
    /// the same as `ProcessMemory.peakResidentBytes()`, which a test cannot
    /// import; the unit of `ru_maxrss` is bytes on Darwin and KiB elsewhere,
    /// and Glibc types the `who` argument apart from its constant.
    nonisolated private static func peakResidentBytes() -> Int {
        #if canImport(Glibc)
        let who = __rusage_who_t(RUSAGE_SELF.rawValue)
        #else
        let who = RUSAGE_SELF
        #endif
        var usage = rusage()
        _ = getrusage(who, &usage)
        #if canImport(Darwin)
        return usage.ru_maxrss
        #else
        return usage.ru_maxrss * 1024
        #endif
    }
}
