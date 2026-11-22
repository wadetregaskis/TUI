//  🖥️ TUI — A Terminal UI framework for Swift
//  AmbiguousWidthProbeTests.swift
//
//  The startup probe that learns whether the terminal draws East Asian
//  Ambiguous characters wide (`TerminalAmbiguousWidthQuery`), and what the frame
//  writer does with a wide answer: whole rows only, because a span is written at
//  the column TUI counted, which on such a host is left of where its row was
//  drawn (WRITER-9).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@Suite("The ambiguous-width probe, and spans off where it answers wide")
@MainActor
struct AmbiguousWidthProbeTests {

    // MARK: - The request and its answer

    @Test("The probe leaves row 1 before it asks, writes two Ambiguous characters concealed, and erases them")
    func requestShape() throws {
        let request = TerminalAmbiguousWidthQuery.request
        let move = try #require(request.range(of: "\u{1B}[2;1H"))
        let report = try #require(request.range(of: "\u{1B}[6n"))
        let probe = try #require(request.range(of: TerminalAmbiguousWidthQuery.probe))
        let conceal = try #require(request.range(of: "\u{1B}[8m"))
        #expect(move.upperBound <= conceal.lowerBound && conceal.upperBound <= probe.lowerBound)
        #expect(probe.upperBound <= report.lowerBound)
        #expect(request.hasPrefix("\u{1B}7") && request.hasSuffix("\u{1B}[2;1H\u{1B}[K\u{1B}8"))
        #expect(TerminalAmbiguousWidthQuery.probe.unicodeScalars.allSatisfy { $0.loneTerminalWidth == 1 })
    }

    @Test(
        "A report of column 3 is narrow, 4 or 5 wide, anything else or nothing no answer",
        arguments: [
            ("\u{1B}[2;3R", false), ("\u{1B}[2;4R", true), ("\u{1B}[2;5R", true),
            ("\u{1B}[2;2R", nil), ("\u{1B}[2;6R", nil), ("", nil), ("\u{1B}[0n", nil),
        ] as [(String, Bool?)])
    func answer(reply: String, wide: Bool?) {
        #expect(TerminalAmbiguousWidthQuery.drawsWide(in: Array(reply.utf8)) == wide)
    }

    /// `CSI 1;m R` is a modified F3, so a row-1 report is never the probe's, and
    /// one that arrives late is typed as a key.
    @Test("A row-1 report is a key, not the probe's answer")
    func rowOneIsAKey() {
        #expect(TerminalAmbiguousWidthQuery.drawsWide(in: Array("\u{1B}[1;3R".utf8)) == nil)
        #expect(!TerminalAmbiguousWidthQuery.isReply(Array("\u{1B}[1;3R".utf8)[...]))
        #expect(TerminalAmbiguousWidthQuery.isReply(Array("\u{1B}[2;3R".utf8)[...]))
        #expect(KeyEvent.parse(Array("\u{1B}[1;3R".utf8))?.key == .f3)
    }

    @Test("The last report on the probe's row is its answer: a late one from an earlier exchange comes first")
    func lastReportCounts() {
        #expect(TerminalAmbiguousWidthQuery.drawsWide(in: Array("\u{1B}[2;3R\u{1B}[2;5R".utf8)) == true)
    }

    // MARK: - The writer, against a host that draws ambiguous characters wide

    private static let width = 24
    private static let page = "\u{1B}[48;5;235m"
    private static let reset = "\u{1B}[0m"

    /// A bordered row with Greek, a line and a bullet before its last word.
    private static func row(_ word: String) -> [String] {
        let inner = "α ─ ● " + word
        let padding = String(repeating: " ", count: width - 2 - inner.unicodeScalars.count)
        return ["│" + inner + padding + "│"]
    }

    /// What `frames` leave on a host that advances the Ambiguous blocks two
    /// cells, drawn by a writer that writes spans or does not.
    private func screen(after frames: [[String]], writesSpans: Bool) -> VTScreenModel {
        let writer = FrameDiffWriter(program: .unidentified)
        writer.scrollOutput = .off
        writer.writesSpans = writesSpans
        let terminal = MockTerminal()
        var screen = VTScreenModel(width: Self.width, height: 1, advance: VTScreenModel.ambiguousWide)
        for rows in frames {
            let lines = writer.buildOutputLines(
                buffer: FrameBuffer(lines: rows), terminalWidth: Self.width, terminalHeight: rows.count,
                bgCode: Self.page, reset: Self.reset)
            terminal.reset()
            writer.writeContentDiff(
                newLines: lines, terminal: terminal, startRow: 1, terminalWidth: Self.width,
                bgCode: Self.page, reset: Self.reset)
            screen.feed(terminal.allOutput)
        }
        return screen
    }

    /// The model is sensitive to the hazard: with spans on, the second frame's
    /// change lands left of where the first frame drew the word.
    @Test("With spans on, a span after Ambiguous characters lands left of where the row was drawn")
    func spansGarbleTheRow() {
        let frames = [Self.row("alpha"), Self.row("omega")]
        let fresh = screen(after: [frames[1]], writesSpans: true)
        let diffed = screen(after: frames, writesSpans: true)
        #expect(diffed.firstDifference(from: fresh) != nil)
    }

    /// What the run loop's writer is given where the probe answered wide
    /// (`makeRenderLoop`): whole rows only, so the row equals a fresh write.
    @Test("Where the probe answered wide, a row written whole and then changed equals a fresh whole write")
    func wholeRowsStayCoherent() {
        let frames = [Self.row("alpha"), Self.row("omega")]
        let terminal = Terminal()
        terminal.drawsAmbiguousWide = TerminalAmbiguousWidthQuery.drawsWide(in: Array("\u{1B}[2;5R".utf8))
        let writesSpans = terminal.drawsAmbiguousWide != true
        #expect(!writesSpans)
        let fresh = screen(after: [frames[1]], writesSpans: writesSpans)
        let diffed = screen(after: frames, writesSpans: writesSpans)
        #expect(diffed.firstDifference(from: fresh) == nil)
    }

    @Test("A new writer writes spans, as one built after a narrow answer or none is left")
    func spansStayOnByDefault() {
        #expect(FrameDiffWriter().writesSpans)
    }
}
