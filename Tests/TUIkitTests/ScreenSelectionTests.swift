//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenSelectionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

// MARK: - Reading cells

@Suite("Screen selection: reading what is drawn")
struct ScreenSelectionReadingTests {
    typealias Point = ScreenSelection.Point
    typealias Rect = ScreenSelection.Rect

    static let lines = ["hello world   ", "second line", "third"]
    static let area = Rect(x: 0, y: 0, width: 14, height: 3)

    func text(
        _ anchor: Point, _ head: Point, in lines: [String] = lines, clip: Rect = area,
        shape: ScreenSelection.Shape = .stream, unit: ScreenSelection.Unit = .character
    ) -> String {
        ScreenSelection.text(
            of: ScreenSelection.Selection(
                anchor: anchor, head: head, clip: clip, shape: shape, unit: unit, text: ""),
            in: lines)
    }

    @Test("A line's cells: escapes skipped, a wide character's second cell empty, a picture blank")
    func cells() {
        #expect(ScreenSelection.cells(of: "a\u{1B}[31mb界c\u{1B}[0m") == ["a", "b", "界", nil, "c"])
        #expect(ScreenSelection.cells(of: "x\u{10EEEE}y") == ["x", " ", "y"])
    }

    @Test("A stream runs to the row's clip edge and on from the next row's, trailing blanks dropped")
    func stream() {
        #expect(text(Point(x: 6, y: 0), Point(x: 5, y: 1)) == "world\nsecond")
        // Backwards is the same selection.
        #expect(text(Point(x: 5, y: 1), Point(x: 6, y: 0)) == "world\nsecond")
    }

    @Test("A rectangle takes the same columns of every row")
    func rectangle() {
        #expect(text(Point(x: 1, y: 0), Point(x: 3, y: 2), shape: .rectangle) == "ell\neco\nhir")
    }

    @Test("A word, and a row")
    func units() {
        #expect(text(Point(x: 7, y: 0), Point(x: 7, y: 0), unit: .word) == "world")
        #expect(text(Point(x: 5, y: 0), Point(x: 5, y: 0), unit: .word).isEmpty)
        #expect(text(Point(x: 2, y: 1), Point(x: 2, y: 1), unit: .row) == "second line")
        // Dragging on by words.
        #expect(text(Point(x: 1, y: 0), Point(x: 8, y: 0), unit: .word) == "hello world")
    }

    @Test("A wide character is read once, whichever of its cells the selection touches")
    func wideCharacters() {
        let lines = ["a界b"]
        let clip = Rect(x: 0, y: 0, width: 4, height: 1)
        #expect(text(Point(x: 2, y: 0), Point(x: 2, y: 0), in: lines, clip: clip) == "界")
        #expect(text(Point(x: 1, y: 0), Point(x: 1, y: 0), in: lines, clip: clip) == "界")
        #expect(text(Point(x: 0, y: 0), Point(x: 3, y: 0), in: lines, clip: clip) == "a界b")
    }

    @Test("A selection keeps to its pane")
    func clip() {
        let pane = Rect(x: 0, y: 0, width: 5, height: 3)
        #expect(text(Point(x: 0, y: 0), Point(x: 4, y: 2), clip: pane) == "hello\nsecon\nthird")
    }
}

// MARK: - Making one

@MainActor
@Suite("Screen selection: a drag no control uses")
struct ScreenSelectionGestureTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    struct Page: View {
        let first: Box
        var body: some View {
            VStack(alignment: .leading) {
                Text(first.value)
                Text("second row text")
                Button("Press") {}
            }
        }
    }

    /// A harness whose writer copies to `log`, with the page drawn twice.
    func harness(_ page: Page, log: SystemClipboardLog = SystemClipboardLog()) -> InputChainHarness {
        let harness = InputChainHarness(width: 40, height: 8)
        harness.tui.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log)
        harness.frame(page)
        harness.frame(page)
        return harness
    }

    /// Where `needle` is drawn: its first cell.
    func find(_ needle: String, in harness: InputChainHarness, _ page: Page) throws -> (x: Int, y: Int) {
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains(needle) })
        let prefix = try #require(lines[row].range(of: needle)).lowerBound
        return (lines[row][..<prefix].count, row)
    }

    func left(_ harness: InputChainHarness, _ phase: MousePhase, _ x: Int, _ y: Int, meta: Bool = false) {
        harness.mouse(MouseEvent(button: .left, phase: phase, x: x, y: y, meta: meta))
    }

    func drag(_ harness: InputChainHarness, from: (x: Int, y: Int), to: (x: Int, y: Int), page: Page) {
        left(harness, .pressed, from.x, from.y)
        harness.frame(page)
        left(harness, .dragged, to.x, to.y)
        harness.frame(page)
        left(harness, .released, to.x, to.y)
        harness.frame(page)
    }

    @Test("A drag over the page's text selects it, and Ctrl-C copies it")
    func dragSelectsAndCopies() throws {
        let log = SystemClipboardLog()
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page, log: log)
        let alpha = try find("alpha", in: harness, page)
        drag(harness, from: alpha, to: (alpha.x + 9, alpha.y), page: page)
        #expect(harness.tui.screenSelection.current?.text == "alpha beta")
        // Nothing is copied until asked.
        #expect(log.writes.isEmpty)
        #expect(harness.press(KeyEvent(key: .character("c"), ctrl: true)))
        #expect(log.writes == ["alpha beta"])
        // A Mac keeps the selection after a copy.
        #expect(harness.tui.screenSelection.hasSelection)
    }

    @Test("The selection is drawn in the text inputs' selection colours")
    func highlight() throws {
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page)
        let alpha = try find("alpha", in: harness, page)
        let before = harness.frame(page).lines[alpha.y]
        drag(harness, from: alpha, to: (alpha.x + 4, alpha.y), page: page)
        let after = harness.frame(page).lines[alpha.y]
        let palette = harness.context.environment.palette
        let colors = TextFieldContentRenderer.selectionColors(palette: palette, background: nil)
            .resolved(with: palette)
        // The field's parameters, wherever the sequence that states them begins.
        let field = String(
            ANSIRenderer.backgroundCode(for: colors.isReversed ? colors.foreground : colors.background)
                .dropFirst(2).dropLast())
        #expect(!before.contains(field))
        #expect(after.contains(field))
        // The text is the same; only its colours changed.
        #expect(after.stripped == before.stripped)
    }

    @Test("A click selects nothing, and clears what was selected")
    func clickClears() throws {
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page)
        let alpha = try find("alpha", in: harness, page)
        left(harness, .pressed, alpha.x, alpha.y)
        left(harness, .released, alpha.x, alpha.y)
        #expect(!harness.tui.screenSelection.hasSelection)
        drag(harness, from: alpha, to: (alpha.x + 3, alpha.y), page: page)
        #expect(harness.tui.screenSelection.hasSelection)
        left(harness, .pressed, alpha.x + 20, alpha.y + 1)
        #expect(!harness.tui.screenSelection.hasSelection)
    }

    @Test("Escape clears the selection, and only then is it the selection's")
    func escapeClears() throws {
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page)
        let alpha = try find("alpha", in: harness, page)
        drag(harness, from: alpha, to: (alpha.x + 3, alpha.y), page: page)
        #expect(harness.tui.screenSelection.handleKey(KeyEvent(key: .escape)) == true)
        #expect(!harness.tui.screenSelection.hasSelection)
        #expect(harness.tui.screenSelection.handleKey(KeyEvent(key: .escape)) == nil)
    }

    @Test("A double-click selects a word, a triple-click the row")
    func multiClick() throws {
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page)
        let beta = try find("beta", in: harness, page)
        for clicks in 1...2 {
            left(harness, .pressed, beta.x + 1, beta.y)
            left(harness, .released, beta.x + 1, beta.y)
            if clicks == 2 { #expect(harness.tui.screenSelection.current?.text == "beta") }
        }
        left(harness, .pressed, beta.x + 1, beta.y)
        left(harness, .released, beta.x + 1, beta.y)
        #expect(harness.tui.screenSelection.current?.text == "alpha beta gamma")
    }

    @Test("Option-drag selects a rectangle")
    func rectangle() throws {
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page)
        let alpha = try find("alpha", in: harness, page)
        left(harness, .pressed, alpha.x + 1, alpha.y, meta: true)
        left(harness, .dragged, alpha.x + 3, alpha.y + 1, meta: true)
        #expect(harness.tui.screenSelection.current?.text == "lph\neco")
    }

    @Test("A drag that starts on a control is the control's")
    func controlsKeepTheirDrags() throws {
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page)
        let button = try find("Press", in: harness, page)
        left(harness, .pressed, button.x, button.y)
        left(harness, .dragged, button.x - 3, button.y - 2)
        left(harness, .released, button.x - 3, button.y - 2)
        #expect(!harness.tui.screenSelection.hasSelection)
    }

    /// An invisible selection must not take the keys ahead of every layer: a
    /// Ctrl-C meant for the focused view copied the text no longer drawn, and
    /// the first Escape was eaten.
    @Test("When the cells change, the highlight goes, and with it the selection's keys")
    func highlightDropsOnChange() throws {
        let log = SystemClipboardLog()
        let first = Box("alpha beta gamma")
        let page = Page(first: first)
        let harness = harness(page, log: log)
        let alpha = try find("alpha", in: harness, page)
        drag(harness, from: alpha, to: (alpha.x + 4, alpha.y), page: page)
        first.value = "omega beta gamma"
        harness.frame(page)
        #expect(harness.tui.screenSelection.current?.isHighlighted != true)
        #expect(harness.tui.screenSelection.handleKey(KeyEvent(key: .character("c"), ctrl: true)) == nil)
        #expect(harness.tui.screenSelection.handleKey(KeyEvent(key: .escape)) == nil)
        harness.press(KeyEvent(key: .character("c"), ctrl: true))
        #expect(log.writes.isEmpty)
    }

    /// The cells changed under the selection, the page did not move: the
    /// highlight is gone for good, and an equal text drawn there later is not
    /// the selection come back. Reviving it took Ctrl-C and Escape ahead of
    /// every layer again.
    @Test("When the cells change under it, the highlight and its keys are gone for good")
    func highlightGoesForGood() throws {
        let log = SystemClipboardLog()
        let first = Box("alpha beta gamma")
        let page = Page(first: first)
        let harness = harness(page, log: log)
        let alpha = try find("alpha", in: harness, page)
        drag(harness, from: alpha, to: (alpha.x + 4, alpha.y), page: page)
        first.value = "omega beta gamma"
        harness.frame(page)
        // Dropped, so no later frame pays to read its cells (the follow-ups'
        // review: a dead selection read them every frame until a press).
        #expect(harness.tui.screenSelection.current == nil)
        first.value = "alpha beta gamma"
        harness.frame(page)
        #expect(harness.tui.screenSelection.current?.isHighlighted != true)
        #expect(harness.tui.screenSelection.handleKey(KeyEvent(key: .character("c"), ctrl: true)) == nil)
        #expect(log.writes.isEmpty)
    }

    /// With the selection's own menu open over it, it is kept when its
    /// cells change, so the menu's Copy copies what was selected.
    @Test("A selection whose cells change under its open menu keeps its text")
    func goneUnderItsMenuKeepsItsText() throws {
        let first = Box("alpha beta gamma")
        let page = Page(first: first)
        let harness = harness(page, log: SystemClipboardLog())
        let alpha = try find("alpha", in: harness, page)
        drag(harness, from: alpha, to: (alpha.x + 4, alpha.y), page: page)
        let selection = harness.tui.screenSelection
        let text = try #require(selection.current?.text)
        try #require(text.hasPrefix("alph"))
        try #require(selection.openMenu(at: ScreenSelection.Point(x: alpha.x + 1, y: alpha.y)))
        first.value = "omega beta gamma"
        harness.frame(page)
        #expect(selection.current?.text == text)
        #expect(selection.current?.isHighlighted == false)
        harness.frame(page)
        #expect(selection.current?.text == text)
    }

    struct Log: View {
        let lines: Box
        var body: some View {
            VStack(alignment: .leading) {
                ForEach(Array(lines.value.split(separator: "\n").enumerated()), id: \.offset) { entry in
                    Text(String(entry.element))
                }
            }
        }
    }

    /// The review's log: a line selected, the log scrolling on, and another
    /// "OK" landing on the same cells two lines later.
    @Test("An equal line scrolling onto a selection's cells does not bring it back")
    func scrollingLogDoesNotRevive() throws {
        let entries = (0..<12).map { $0.isMultiple(of: 2) ? "OK" : "step \($0)" }
        let lines = Box(entries[0..<6].joined(separator: "\n"))
        let page = Log(lines: lines)
        let harness = InputChainHarness(width: 40, height: 8)
        harness.frame(page)
        let rows = harness.frame(page).lines.map(\.stripped)
        let row = try #require(rows.firstIndex { $0.hasPrefix("OK") })
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 0, y: row))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 1, y: row))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: row))
        harness.frame(page)
        let selection = harness.tui.screenSelection
        try #require(selection.current?.text == "OK")
        var highlighted: [Bool] = []
        for shift in 1...4 {
            lines.value = entries[shift..<(shift + 6)].joined(separator: "\n")
            let drawn = harness.frame(page).lines.map(\.stripped)
            try #require(drawn[row].hasPrefix(shift.isMultiple(of: 2) ? "OK" : "step"))
            highlighted.append(selection.current?.isHighlighted ?? false)
        }
        #expect(highlighted == [false, false, false, false])
        #expect(selection.handleKey(KeyEvent(key: .escape)) == nil)
    }

    struct SpinnerPage: View {
        var body: some View {
            VStack(alignment: .leading) {
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 0.25)) { context in
                    Text(
                        ["|", "/", "-", "\\"][Int(context.date.timeIntervalSinceReferenceDate * 4) % 4]
                            + " Building")
                }
                Button("Press") {}
            }
        }
    }

    /// The review's spinner: a line that comes back to the selected text every
    /// fourth tick. The highlight blinked with it, and Ctrl-C went to the
    /// selection on those ticks and to the focused control on the others.
    @Test("Over a cycling line the highlight goes once, and the keys stay the app's")
    func cyclingLineDoesNotStrobe() throws {
        let page = SpinnerPage()
        let harness = InputChainHarness(width: 40, height: 8)
        var seconds = 1_000.0
        func frame() -> [String] {
            harness.tui.renderCache.frameDate = Date(timeIntervalSinceReferenceDate: seconds)
            return harness.frame(page).lines.map(\.stripped)
        }
        _ = frame()
        let rows = frame()
        let row = try #require(rows.firstIndex { $0.contains("| Building") })
        let x = rows[row].distance(from: rows[row].startIndex, to: try #require(rows[row].firstIndex(of: "|")))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
        _ = frame()
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: x + 9, y: row))
        _ = frame()
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x + 9, y: row))
        _ = frame()
        let selection = harness.tui.screenSelection
        try #require(selection.current?.text == "| Building")
        var highlighted: [Bool] = []
        var owned: [Bool] = []
        for _ in 0..<8 {
            seconds += 0.25
            _ = frame()
            highlighted.append(selection.current?.isHighlighted ?? false)
            owned.append(selection.handleKey(KeyEvent(key: .character("c"), ctrl: true)) != nil)
        }
        try #require(frame()[row].contains("| Building"), "precondition: the line came back round")
        #expect(highlighted == Array(repeating: false, count: 8))
        #expect(owned == Array(repeating: false, count: 8))
    }

    struct CopyablePage: View {
        let first: Box
        var body: some View {
            VStack(alignment: .leading) {
                Text(first.value)
                Button("Rows") {}
                    .copyable(["the rows"])
            }
        }
    }

    @Test("Once the highlight is gone, Ctrl-C copies what holds the focus")
    func hiddenSelectionLetsTheFocusCopy() throws {
        let log = SystemClipboardLog()
        let first = Box("alpha beta gamma")
        let page = CopyablePage(first: first)
        let writer = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log)
        let harness = InputChainHarness(width: 40, height: 8) { $0.clipboardAccess = ClipboardAccess(writer: writer) }
        harness.tui.clipboardWriter = writer
        harness.frame(page)
        harness.frame(page)
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains("alpha") })
        let x = lines[row][..<(try #require(lines[row].range(of: "alpha")).lowerBound)].count
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: x + 4, y: row))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x + 4, y: row))
        harness.frame(page)
        #expect(harness.tui.screenSelection.current?.text == "alpha")
        first.value = "omega beta gamma"
        harness.frame(page)
        #expect(harness.press(KeyEvent(key: .character("c"), ctrl: true)))
        #expect(log.writes == ["the rows"])
    }

    @Test("With copy-on-release, the release copies")
    func copyOnRelease() throws {
        let log = SystemClipboardLog()
        let page = Page(first: Box("alpha beta gamma"))
        let harness = harness(page, log: log)
        harness.tui.screenSelection.copiesOnRelease = true
        let alpha = try find("alpha", in: harness, page)
        drag(harness, from: alpha, to: (alpha.x + 4, alpha.y), page: page)
        #expect(log.writes == ["alpha"])
    }

    struct FieldPage: View {
        let text: Box
        var body: some View {
            VStack {
                TextField("Field", text: Binding(get: { text.value }, set: { text.value = $0 }))
                Text("plain words here")
            }
        }
    }

    /// The newest selection is the one Ctrl-C copies: a screen drag after a
    /// field's selection, and a field's key after a screen drag.
    @Test("Ctrl-C copies the newest selection")
    func newestWins() throws {
        let log = SystemClipboardLog()
        let board = FakeClipboard()
        let harness = InputChainHarness(width: 40, height: 8) { $0.clipboardAccess = board.access }
        harness.tui.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log)
        let page = FieldPage(text: Box("field text"))
        harness.frame(page)
        harness.frame(page)
        // The field's selection: its last four characters.
        for _ in 0..<4 { harness.press(KeyEvent(key: .left, shift: true)) }
        harness.frame(page)
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains("plain") })
        let column = lines[row][..<(try #require(lines[row].range(of: "plain")).lowerBound)].count
        left(harness, .pressed, column, row)
        left(harness, .dragged, column + 4, row)
        left(harness, .released, column + 4, row)
        harness.press(KeyEvent(key: .character("c"), ctrl: true))
        #expect(log.writes == ["plain"])
        #expect(board.writes.isEmpty)
        // A key the field takes makes the field's selection the newest again.
        harness.press(KeyEvent(key: .left, shift: true))
        #expect(!harness.tui.screenSelection.hasSelection)
        harness.press(KeyEvent(key: .character("c"), ctrl: true))
        #expect(board.writes.count == 1)
    }
}

// MARK: - Under a status-bar tooltip

@MainActor
@Suite("Screen selection: a status-bar tooltip")
struct ScreenSelectionTooltipTests {
    struct Page: App {
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Text("alpha beta gamma")
                    Text("explained").help("about it")
                }
            }
            .mouseSupport(.full)
        }
    }

    /// A status-bar tooltip adds a row above the bar's items, a row taken from
    /// the page, which a WindowGroup re-centres: the selected cells move for as
    /// long as the tooltip shows. The highlight used to go for good.
    @Test("A selection the tooltip's row moved is highlighted again when the tooltip goes")
    func tooltipMovesThePageAndBack() throws {
        // Eleven rows: the page is centred in what the bar leaves, and at this
        // height one row less moves it (at ten, it would not).
        let app = HeadlessApp(Page(), width: 40, height: 11)
        var now: Int64 = 16_666_667
        func frame(after nanos: Int64 = 16_666_667) {
            now += nanos
            app.frame(atNanos: now)
        }
        func position(of text: String) throws -> (x: Int, y: Int) {
            let lines = app.screen.map(\.stripped)
            let row = try #require(lines.firstIndex { $0.contains(text) })
            return (lines[row][..<(try #require(lines[row].range(of: text)).lowerBound)].count, row)
        }
        frame()
        frame()
        let alpha = try position(of: "alpha")
        app.send(MouseEvent(button: .left, phase: .pressed, x: alpha.x, y: alpha.y))
        frame()
        app.send(MouseEvent(button: .left, phase: .dragged, x: alpha.x + 4, y: alpha.y))
        frame()
        app.send(MouseEvent(button: .left, phase: .released, x: alpha.x + 4, y: alpha.y))
        frame()
        let selection = app.services.screenSelection
        try #require(selection.current?.text == "alpha")
        let explained = try position(of: "explained")
        app.send(MouseEvent(button: .none, phase: .moved, x: explained.x + 1, y: explained.y))
        frame()
        frame(after: 700_000_000)
        try #require(app.screen.contains { $0.stripped.contains("about it") }, "precondition: the tooltip shows")
        try #require(
            (try position(of: "alpha")).y != alpha.y, "precondition: the tooltip's row moved the page")
        #expect(selection.current?.isHighlighted == false)
        app.send(MouseEvent(button: .none, phase: .moved, x: 39, y: 0))
        frame()
        frame()
        try #require(!app.screen.contains { $0.stripped.contains("about it") }, "precondition: the tooltip went")
        #expect(selection.current?.isHighlighted == true)
        #expect(selection.handleKey(KeyEvent(key: .character("c"), ctrl: true)) == true)
    }
}
