//  🖥️ TUI — A Terminal UI framework for Swift
//  ClipboardPassthroughTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

/// The write wrapped for a session keeper's passthrough, as
/// `Tools/TerminalProbes/keeper_passthrough_probe.py` measured screen 4.00.03
/// and tmux 3.7c passing it on (owner ruling D4X-LOCALITY).
@Suite("OSC 52 through a keeper's passthrough")
struct ClipboardPassthroughTests {
    @Test("Through tmux: ESC P tmux;, the write with its ESCs doubled, ESC \\")
    func tmux() {
        #expect(ClipboardSequence.write("hi", through: .tmux) == "\u{1B}Ptmux;\u{1B}\u{1B}]52;c;aGk=\u{1B}\u{1B}\\\u{1B}\\")
    }

    @Test("Through screen, short: one DCS around the BEL-terminated write")
    func screenShort() {
        #expect(ClipboardSequence.write("hi", through: .screen) == "\u{1B}P\u{1B}]52;c;aGk=\u{07}\u{1B}\\")
    }

    @Test("Through screen, long: DCS strings of at most 256 bytes that make one write again")
    func screenLong() throws {
        let text = String(repeating: "Größe 😀 ありがとう\n", count: 300)
        let wrapped = try #require(ClipboardSequence.write(text, through: .screen))
        let strings = wrapped.components(separatedBy: "\u{1B}\\").dropLast()
        #expect(strings.count > 10)
        #expect(strings.allSatisfy { $0.hasPrefix("\u{1B}P") && $0.utf8.count + 2 <= ClipboardSequence.screenStringBytes })
        let joined = strings.map { String($0.dropFirst(2)) }.joined()
        let bare = try #require(ClipboardSequence.write(text))
        #expect(joined == String(bare.dropLast(2)) + "\u{07}")
    }

    @Test("An empty copy sends nothing, through either")
    func emptySendsNothing() {
        #expect(ClipboardSequence.write("", through: .screen) == nil)
        #expect(ClipboardSequence.write("", through: .tmux) == nil)
    }

    @MainActor
    @Test("The writer wraps a copy for the keeper, sends its text alone, and calls it sent")
    func writerWraps() {
        let writer = ClipboardWriter.stated(terminal: .unconfirmed, passthrough: .screen, isLocal: false, mime: true)
        let result = writer.write(
            "hi", representations: [ClipboardRepresentation(type: "text/html", text: "<b>hi</b>")],
            announcingSuccess: true)
        #expect(result == .sentToTerminal)
        #expect(writer.takePendingSequences() == ClipboardSequence.write("hi", through: .screen))
        let picture = writer.write(
            "", representations: [ClipboardRepresentation(type: "image/png", data: Data([1, 2, 3]))],
            announcingSuccess: true)
        #expect(picture == .unavailable)
        #expect(writer.takePendingSequences().isEmpty)
    }
}
