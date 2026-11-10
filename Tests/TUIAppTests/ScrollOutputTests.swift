//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollOutputTests.swift
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

/// A page of rows: a header and a footer that stay, a document that scrolls, and
/// optionally a side pane or a scroll bar beside it.
private struct Page {
    var width = 80
    var height = 24
    var document: [String]
    var offset = 0
    var selected: Int?
    var sidePane: [String]?
    var scrollBar = false

    private static let reset = "\u{1B}[0m"
    private static let page = "\u{1B}[48;5;235m"

    func rows() -> [String] {
        var rows: [String] = ["\u{1B}[1m" + fit("Header", width) + Self.reset]
        let body = height - 2
        for line in 0..<body {
            var row = ""
            if let sidePane { row += fit(sidePane[line % sidePane.count], 20) + "│" }
            let lineWidth = width - (sidePane == nil ? 0 : 21) - (scrollBar ? 1 : 0)
            let index = offset + line
            let text = fit(document[index % document.count], lineWidth)
            row += index == selected ? "\u{1B}[7m" + text + Self.reset : text
            if scrollBar {
                let thumb = offset * body / max(1, document.count)
                row += line == thumb ? "█" : "│"
            }
            rows.append(row)
        }
        rows.append(fit("Footer at \(offset)", width))
        return rows
    }

    private func fit(_ text: String, _ width: Int) -> String {
        let cut = String(text.prefix(width))
        return cut + String(repeating: " ", count: max(0, width - cut.strippedLength))
    }

    static func letters(rows: Int, width: Int, seed: UInt64) -> [String] {
        var state = seed
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return (0..<rows).map { _ in
            String((0..<width).map { _ in alphabet[Int(next() % UInt64(alphabet.count))] })
        }
    }

    static var pageCode: String { page }
    static var resetCode: String { reset }
}

/// A writer and the screen it has drawn, frame by frame.
@MainActor
private final class Drawn {
    let writer: FrameDiffWriter
    let terminal = MockTerminal()
    var screen: VTScreenModel
    var bytes = 0
    var lastFrame = ""

    init(level: ScrollOutput, program: TerminalClient.Program, width: Int, height: Int) {
        writer = FrameDiffWriter(program: program)
        writer.scrollOutput = level
        writer.framesAreHeld = true
        screen = VTScreenModel(width: width, height: height)
    }

    func draw(_ rows: [String], width: Int) {
        let lines = writer.buildOutputLines(
            buffer: FrameBuffer(lines: rows), terminalWidth: width, terminalHeight: rows.count,
            bgCode: Page.pageCode, reset: Page.resetCode)
        terminal.reset()
        writer.writeContentDiff(
            newLines: lines, terminal: terminal, startRow: 1, terminalWidth: width,
            bgCode: Page.pageCode, reset: Page.resetCode)
        lastFrame = terminal.allOutput
        bytes += lastFrame.utf8.count
        screen.feed(lastFrame)
    }
}

/// A whole repaint of `rows`: what the screen should show, from nothing.
@MainActor
private func repainted(_ rows: [String], width: Int) -> VTScreenModel {
    let fresh = Drawn(level: .off, program: .unidentified, width: width, height: rows.count)
    fresh.draw(rows, width: width)
    return fresh.screen
}

@Suite("Hardware scrolling in the frame writer")
@MainActor
struct ScrollOutputTests {
    private let document = Page.letters(rows: 200, width: 120, seed: 42)

    /// Draws `pages` at every level given, and holds each frame's screen to a
    /// whole repaint of it: the differential, in a model of the terminal.
    @discardableResult
    private func expectSameScreens(
        _ pages: [Page], level: ScrollOutput, program: TerminalClient.Program = .ghostty,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (scrolled: Drawn, plain: Drawn) {
        let width = pages[0].width
        let height = pages[0].height
        let scrolled = Drawn(level: level, program: program, width: width, height: height)
        let plain = Drawn(level: .off, program: program, width: width, height: height)
        for (index, page) in pages.enumerated() {
            let rows = page.rows()
            scrolled.draw(rows, width: width)
            plain.draw(rows, width: width)
            let expected = repainted(rows, width: width)
            #expect(
                scrolled.screen.firstDifference(from: expected) == nil,
                "frame \(index): \(scrolled.screen.firstDifference(from: expected) ?? "")",
                sourceLocation: sourceLocation)
            #expect(plain.screen.firstDifference(from: expected) == nil, sourceLocation: sourceLocation)
            #expect(scrolled.screen.regionIsReset, "frame \(index) left a region set", sourceLocation: sourceLocation)
        }
        return (scrolled, plain)
    }

    private func notches(_ page: Page, _ offsets: [Int]) -> [Page] {
        offsets.map {
            var moved = page
            moved.offset = $0
            return moved
        }
    }

    @Test("Exact is the default, and off is the way out")
    func parsesTheSwitch() {
        #expect(ScrollOutput.parse(nil) == .exact)
        #expect(ScrollOutput.parse("nonsense") == .exact)
        #expect(ScrollOutput.parse("exact") == .exact)
        #expect(ScrollOutput.parse("1") == .exact)
        #expect(ScrollOutput.parse("off") == .off)
        #expect(ScrollOutput.parse("0") == .off)
        #expect(ScrollOutput.parse("residue") == .residue)
        #expect(ScrollOutput.parse("margins") == .margins)
    }

    @Test("Off sets no region and scrolls nothing")
    func offIsOff() {
        let pages = notches(Page(document: document), [0, 3, 6, 9])
        let drawn = expectSameScreens(pages, level: .off)
        #expect(drawn.scrolled.screen.scrolls == 0)
        #expect(drawn.scrolled.bytes == drawn.plain.bytes)
    }

    @Test("A wheel notch over dissimilar rows moves the band and writes what it exposes")
    func wheelNotch() {
        let pages = notches(Page(document: document), [0, 3, 6, 3, 0, 1, 2, 17])
        let drawn = expectSameScreens(pages, level: .exact)
        #expect(drawn.scrolled.screen.scrolls >= 6)
        // The first frame is the same whole repaint either way.
        let first = repainted(pages[0].rows(), width: 80).width * 24
        #expect(drawn.scrolled.bytes - first < (drawn.plain.bytes - first) / 2)
    }

    @Test("The region stops at the footer and the header")
    func fixedRowsStayOut() {
        let drawn = Drawn(level: .exact, program: .ghostty, width: 80, height: 24)
        drawn.draw(Page(document: document).rows(), width: 80)
        var moved = Page(document: document)
        moved.offset = 3
        drawn.draw(moved.rows(), width: 80)
        #expect(drawn.lastFrame.contains("\u{1B}[2;23r\u{1B}[3S\u{1B}[r"))
        #expect(!drawn.lastFrame.contains("?69h"))
    }

    @Test("A region is stated in the screen's rows, wherever the frame starts")
    func startRow() {
        let plan = ScrollPlan(top: 1, bottom: 22, by: -2, columns: 10..<40, saving: 0)
        #expect(plan.sequences(startRow: 3) == "\u{1B}[?69h\u{1B}[11;40s\u{1B}[4;25r\u{1B}[2T\u{1B}[r\u{1B}[?69l")
    }

    @Test("A highlight moving with the rows, and a scroll bar, are repaired on the moved screen")
    func residue() {
        var page = Page(document: document)
        page.scrollBar = true
        var pages: [Page] = []
        for offset in 0..<30 {
            page.offset = offset
            page.selected = offset + 5 + offset % 3
            pages.append(page)
        }
        let drawn = expectSameScreens(pages, level: .exact)
        #expect(drawn.scrolled.screen.scrolls > 20)
        #expect(drawn.scrolled.bytes < drawn.plain.bytes / 2)
    }

    @Test("A side pane hides the shift from whole-row comparison, not from its columns")
    func sidePane() {
        var page = Page(document: document)
        page.sidePane = Page.letters(rows: 22, width: 20, seed: 7)
        let pages = notches(page, [0, 3, 6, 9, 12, 9])
        let exact = expectSameScreens(pages, level: .exact)
        #expect(exact.scrolled.screen.scrolls == 0)
        let margins = expectSameScreens(pages, level: .margins)
        #expect(margins.scrolled.screen.scrolls == 5)
        #expect(margins.scrolled.lastFrame.contains("\u{1B}[?69h\u{1B}[22;80s"))
        #expect(margins.scrolled.bytes * 2 < margins.plain.bytes)
    }

    @Test("Moving the whole width and repairing a dissimilar side pane is priced, and declined when it does not pay")
    func residuePriced() {
        var page = Page(document: Page.letters(rows: 200, width: 12, seed: 5))
        page.sidePane = Page.letters(rows: 22, width: 20, seed: 7)
        page.width = 34  // a narrow document beside a wider pane, which would all come back
        let pages = notches(page, [0, 3, 6, 9])
        let residue = expectSameScreens(pages, level: .residue)
        #expect(residue.scrolled.bytes <= residue.plain.bytes)
    }

    /// The study's table: what a wheel notch costs at each level, on the three
    /// shapes that decide it (`Documentation/Performance/Scroll regions for output.md`).
    @Test("A wheel notch at each level, on a full-width list, a list beside a pane, and rows that look alike")
    func notchTable() {
        func perNotch(_ page: Page, _ level: ScrollOutput) -> Int {
            let drawn = Drawn(level: level, program: .ghostty, width: page.width, height: page.height)
            var moved = page
            drawn.draw(moved.rows(), width: page.width)
            let opening = drawn.bytes
            for notch in 1...10 {
                moved.offset = notch * 3
                drawn.draw(moved.rows(), width: page.width)
            }
            return (drawn.bytes - opening) / 10
        }
        var alone = Page(document: document)
        (alone.width, alone.height) = (120, 40)
        var beside = alone
        beside.sidePane = Page.letters(rows: 38, width: 20, seed: 7)
        var alike = alone
        alike.document = (0..<200).map { "Row \($0 + 1000) some text that is the same on every row" }
        for (name, page) in [("full width", alone), ("beside a pane", beside), ("rows alike", alike)] {
            let levels = [ScrollOutput.off, .exact, .residue, .margins].map { perNotch(page, $0) }
            print("notch table: \(name): off \(levels[0]), exact \(levels[1]), residue \(levels[2]), margins \(levels[3])")
            #expect(levels[1] <= levels[0] && levels[3] <= levels[0])
        }
    }

    @Test("Frames that change every row and move none are written as they were")
    func noShift() {
        let drawn = Drawn(level: .margins, program: .ghostty, width: 80, height: 24)
        let plain = Drawn(level: .off, program: .ghostty, width: 80, height: 24)
        for seed in 0..<6 {
            let rows = Page(document: Page.letters(rows: 24, width: 80, seed: UInt64(seed))).rows()
            drawn.draw(rows, width: 80)
            plain.draw(rows, width: 80)
        }
        #expect(drawn.screen.scrolls == 0)
        #expect(drawn.bytes == plain.bytes)
    }

    @Test("A row of similar text gains nothing from a scroll, so none is sent")
    func similarRows() {
        // Numbered rows: the cell diff already sends only the digits.
        let lines = (0..<200).map { "Row \($0 + 1000) some text that is the same on every row" }
        let pages = notches(Page(document: lines), [0, 3, 6, 9])
        let drawn = expectSameScreens(pages, level: .exact)
        #expect(drawn.scrolled.bytes <= drawn.plain.bytes)
    }

    @Test("Rows carrying more than cells do not ride")
    func linksStayOut() {
        let link = "\u{1B}]8;;https://example.com\u{1B}\\here\u{1B}]8;;\u{1B}\\"
        var lines = document
        for index in stride(from: 0, to: lines.count, by: 2) { lines[index] = link + String(lines[index].prefix(40)) }
        let pages = notches(Page(document: lines), [0, 3, 6])
        let drawn = Drawn(level: .margins, program: .ghostty, width: 80, height: 24)
        for page in pages { drawn.draw(page.rows(), width: 80) }
        #expect(drawn.screen.scrolls == 0)
    }

    @Test("The host decides how far a level goes")
    func hosts() {
        #expect(ScrollOutput.level(.margins, on: .ghostty, holds: true) == .margins)
        #expect(ScrollOutput.level(.margins, on: .iTerm2, holds: true) == .margins)
        #expect(ScrollOutput.level(.margins, on: .warp, holds: true) == .residue)
        #expect(ScrollOutput.level(.margins, on: .appleTerminal, holds: true) == .exact)
        #expect(ScrollOutput.level(.margins, on: .tmux, holds: true) == .off)
        #expect(ScrollOutput.level(.margins, on: .tmux, holds: false) == .exact)
        #expect(ScrollOutput.level(.off, on: .ghostty, holds: true) == .off)
    }

    @Test("Under tmux, with holds on, nothing moves: tmux repaints the pane regardless")
    func tmuxHeld() {
        let drawn = Drawn(level: .margins, program: .tmux, width: 80, height: 24)
        for page in notches(Page(document: document), [0, 3, 6]) { drawn.draw(page.rows(), width: 80) }
        #expect(drawn.screen.scrolls == 0)
    }

    @Test("Random frames paint what a whole repaint paints", arguments: [ScrollOutput.exact, .residue, .margins])
    func randomFrames(level: ScrollOutput) {
        var seed: UInt64 = 0x1234_5678 &+ UInt64(level.rawValue)
        func next(_ bound: Int) -> Int {
            seed = seed &* 0x5851_F42D_4C95_7F2D &+ 0x14_0576
            return Int((seed >> 33) % UInt64(bound))
        }
        for program in [TerminalClient.Program.ghostty, .iTerm2, .appleTerminal, .unidentified] {
            for layout in 0..<4 {
                var page = Page(document: document)
                page.height = 12 + next(20)
                page.width = 50 + next(50)
                if layout & 1 == 1 { page.sidePane = Page.letters(rows: 9, width: 20, seed: UInt64(layout)) }
                if layout & 2 == 2 { page.scrollBar = true }
                var pages: [Page] = []
                var offset = 50
                for _ in 0..<40 {
                    switch next(5) {
                    case 0: offset += 1 + next(4)
                    case 1: offset = max(0, offset - 1 - next(4))
                    case 2: page.selected = offset + next(page.height)
                    case 3: offset += page.height - 3
                    default:
                        let edited = "edited \(next(1000)) " + String(repeating: "x", count: next(30))
                        page.document[(offset + next(page.height)) % page.document.count] = edited
                    }
                    page.offset = offset
                    pages.append(page)
                }
                expectSameScreens(pages, level: level, program: program)
            }
        }
    }

    @Test("What a signal owes puts the region and margins back, and keeps the cursor")
    func signalDebtShape() {
        var screen = VTScreenModel(width: 40, height: 10)
        screen.feed("\u{1B}[?69h\u{1B}[5;30s\u{1B}[2;8r\u{1B}[3;7H")
        let (row, column) = (screen.row, screen.column)
        screen.feed(Terminal.scrollRegionReset)
        #expect(screen.regionIsReset)
        #expect(screen.row == row && screen.column == column)
    }
}
