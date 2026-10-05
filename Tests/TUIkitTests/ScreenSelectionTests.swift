//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenSelectionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

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
        #expect(harness.tui.screenSelection.current?.isHighlighted == false)
        #expect(harness.tui.screenSelection.handleKey(KeyEvent(key: .character("c"), ctrl: true)) == nil)
        #expect(harness.tui.screenSelection.handleKey(KeyEvent(key: .escape)) == nil)
        harness.press(KeyEvent(key: .character("c"), ctrl: true))
        #expect(log.writes.isEmpty)
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
