//  🖥️ TUI — A Terminal UI framework for Swift
//  ClipboardWriteSizeTests.swift
//
//  A terminal that drops an OSC 52 write over a size (Windows Terminal and
//  conhost): a copy too large for it goes to this machine's clipboard where
//  that is the user's, and is otherwise reported as not copied, never sent to
//  be lost.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITerminalHost

extension ClipboardWriter {
    /// A writer whose terminal takes OSC 52 writes of at most `largestWrite`
    /// bytes, its locality and helper the test's.
    static func stated(
        terminal: TerminalClient.ClipboardWriteSupport, largestWrite: Int, isLocal: Bool, hasHelper: Bool = true,
        log: SystemClipboardLog = SystemClipboardLog(), mime: Bool = false
    ) -> ClipboardWriter {
        ClipboardWriter(
            terminal: { TerminalClient.ClipboardDelivery(terminal, largestWrite: largestWrite) },
            isLocal: { isLocal }, mimeSupport: { mime },
            system: StatedClipboard(isAvailable: hasHelper, helperWorks: true, log: log),
            nowNanos: { 0 }, requestFrame: {})
    }
}

@Suite("Clipboard routes: a write too large for the terminal")
struct ClipboardRouteSizeTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let terminal: TerminalClient.ClipboardWriteSupport
        let hasHelper: Bool
        let isLocal: Bool
        let expected: ClipboardRoute
        var testDescription: String { "\(terminal), helper \(hasHelper), local \(isLocal)" }
    }

    static let rows: [Row] = [
        // At the desk this machine's clipboard takes what the terminal would drop.
        Row(terminal: .honoured, hasHelper: true, isLocal: true, expected: .system),
        Row(terminal: .unconfirmed, hasHelper: true, isLocal: true, expected: .system),
        // Away from it, or with no helper, nothing does: too large, not sent.
        Row(terminal: .honoured, hasHelper: true, isLocal: false, expected: .tooLarge),
        Row(terminal: .honoured, hasHelper: false, isLocal: true, expected: .tooLarge),
        Row(terminal: .unconfirmed, hasHelper: true, isLocal: false, expected: .tooLarge),
        // A terminal that takes no write at all is no-clipboard, as ever.
        Row(terminal: .unsupported, hasHelper: true, isLocal: false, expected: .none),
    ]

    @Test("The rule, for a write that does not fit", arguments: rows)
    func rule(_ row: Row) {
        #expect(
            ClipboardRoute.choose(
                terminal: row.terminal, fits: false, hasSystemHelper: row.hasHelper, isLocal: { row.isLocal })
                == row.expected)
    }
}

@MainActor
@Suite("Clipboard writer: a write too large for the terminal")
struct ClipboardWriterSizeTests {
    /// The bytes of the OSC 52 write of `text`.
    private func writeBytes(_ text: String) -> Int {
        ClipboardSequence.write(text)?.utf8.count ?? 0
    }

    @Test("A write of exactly the largest size is sent")
    func exactlyTheLargest() {
        let text = String(repeating: "x", count: 300)
        let writer = ClipboardWriter.stated(terminal: .honoured, largestWrite: writeBytes(text), isLocal: false)
        #expect(writer.write(text, announcingSuccess: false) == .copied)
        #expect(writer.takePendingSequences() == ClipboardSequence.write(text))
    }

    @Test("At the desk, one byte over goes to this machine's clipboard")
    func overAtTheDesk() {
        let text = String(repeating: "x", count: 300)
        let log = SystemClipboardLog()
        let writer = ClipboardWriter.stated(
            terminal: .honoured, largestWrite: writeBytes(text) - 1, isLocal: true, log: log)
        #expect(writer.write(text, announcingSuccess: false) == .copied)
        #expect(log.writes == [text])
        #expect(writer.takePendingSequences().isEmpty)
    }

    @Test("Away from the desk, one over is not sent, and the status bar says why")
    func overAway() {
        let text = String(repeating: "x", count: 300)
        let log = SystemClipboardLog()
        let writer = ClipboardWriter.stated(
            terminal: .honoured, largestWrite: writeBytes(text) - 1, isLocal: false, log: log)
        #expect(writer.write(text, announcingSuccess: false) == .tooLarge)
        #expect(log.writes.isEmpty)
        #expect(writer.takePendingSequences().isEmpty)
        #expect(writer.statusNote(atNanos: 0)?.text == ClipboardWriteResult.tooLarge.statusLine)
        // Still the app's own copy, for a paste chord.
        #expect(writer.lastCopiedText == text)
    }

    @Test("A write in OSC 5522's packets is not held to an OSC 52 write's size")
    func typesGoInPackets() {
        let text = String(repeating: "x", count: 300)
        let writer = ClipboardWriter.stated(terminal: .honoured, largestWrite: 64, isLocal: false, mime: true)
        #expect(writer.write(text, announcingSuccess: false) == .copied)
        #expect(writer.takePendingSequences().contains("\u{1B}]5522;"))
    }

    @Test("The status line has words")
    func statusLine() {
        #expect(ClipboardWriteResult.tooLarge.statusKey == .notCopiedTooLarge)
        #expect(ClipboardWriteResult.tooLarge.statusLine?.isEmpty == false)
    }
}

@Suite("Clipboard ladder: the terminals that drop a large write")
struct ClipboardLargestWriteTests {
    @Test("Windows Terminal and conhost have a largest write, and the others none")
    func whichTerminals() {
        for program in TerminalClient.Program.allCases {
            let largest = TerminalClient.largestClipboardWrite(of: program)
            if program == .windowsTerminal || program == .windowsConsole {
                #expect(largest == TerminalClient.windowsClipboardWriteBytes, "\(program)")
            } else {
                #expect(largest == nil, "\(program)")
            }
        }
    }

    @Test("The ladder carries it, TUI_OSC52=1 too, but not through GNU screen's passthrough")
    func ladderCarriesIt() {
        let plain = TerminalClient.clipboardDelivery(
            environment: [:], program: .windowsTerminal, primaryDeviceAttributes: nil, tmuxSetClipboard: nil)
        #expect(plain.largestWrite == TerminalClient.windowsClipboardWriteBytes)
        let forced = TerminalClient.clipboardDelivery(
            environment: ["TUI_OSC52": "1"], program: .windowsConsole, primaryDeviceAttributes: nil,
            tmuxSetClipboard: nil)
        #expect(forced.largestWrite == TerminalClient.windowsClipboardWriteBytes)
        let screen = TerminalClient.clipboardDelivery(
            environment: ["TUI_OSC52": "1", "STY": "4242.pts-0.desk"], program: .windowsTerminal,
            primaryDeviceAttributes: nil, tmuxSetClipboard: nil)
        #expect(screen.passthrough == .screen)
        #expect(screen.largestWrite == nil)
    }
}
