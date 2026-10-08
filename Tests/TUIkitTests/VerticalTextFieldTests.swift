//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VerticalTextFieldTests.swift
//
//  `TextField(…, axis: .vertical)`: text that wraps over rows, a field that
//  grows with it within its line limit and then scrolls, and the keys that
//  differ from a field on one line.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

/// The text a field edits, and how often it was submitted.
@MainActor
private final class Model {
    var text: String
    var submits = 0
    init(_ text: String) { self.text = text }
    var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

/// The rows a buffer drew, without their escapes.
private func rows(_ buffer: FrameBuffer) -> [String] {
    buffer.lines.map(\.stripped)
}

private func key(_ character: Character, ctrl: Bool = false) -> KeyEvent {
    KeyEvent(key: .character(character), ctrl: ctrl)
}

@MainActor
@Suite("TextField on the vertical axis")
struct VerticalTextFieldTests {

    /// A plain vertical field over `model`, so its rows are its text alone.
    private func field(_ model: Model) -> some View {
        TextField("T", text: model.binding, axis: .vertical)
            .onSubmit { model.submits += 1 }
            .textFieldStyle(.plain)
    }

    // MARK: - Growing

    @Test("It grows a row at a time as its text wraps or breaks; a field on one line does not")
    func grows() {
        let harness = InputChainHarness(width: 12)
        let model = Model("")
        #expect(harness.frame(field(model)).height == 1)
        model.text = "one\ntwo"
        #expect(harness.frame(field(model)).height == 2)
        // Twelve cells, wrapping at eleven: "aaaa bbbb " then "cccc dddd".
        model.text = "aaaa bbbb cccc dddd"
        #expect(rows(harness.frame(field(model))).map { $0.trimmingTrailingSpaces } == ["aaaa bbbb", "cccc dddd"])
        let oneLine = TextField("T", text: model.binding, axis: .horizontal).textFieldStyle(.plain)
        #expect(harness.frame(oneLine).height == 1)
    }

    @Test("Its rows sit between the line limit's floor and cap")
    func lineLimits() {
        let harness = InputChainHarness(width: 12)
        let model = Model("1\n2\n3\n4\n5")
        #expect(harness.frame(field(model).lineLimit(3)).height == 3)
        #expect(harness.frame(field(model).lineLimit(2...4)).height == 4)
        #expect(harness.frame(field(model)).height == 5, "no limit: as tall as the text")
        model.text = "x"
        #expect(harness.frame(field(model).lineLimit(2...4)).height == 2)
        #expect(harness.frame(field(model).lineLimit(4, reservesSpace: true)).height == 4)
        #expect(harness.frame(field(model).lineLimit(3...)).height == 3)
    }

    @Test("Its measured height is the height it draws")
    func measureMatchesRender() {
        let model = Model("aaaa bbbb cccc dddd eeee")
        let view = VStack { field(model).lineLimit(1...5) }
        let context = makeRenderContext(width: 12, height: 20)
        let size = measureChild(view, proposal: ProposedSize(width: 12, height: nil), context: context)
        #expect(size.height == 3)
        #expect(renderToBuffer(view, context: context).height == size.height)
    }

    @Test("Each row is drawn between the style's caps")
    func capsOnEveryRow() {
        let harness = InputChainHarness(width: 12)
        let model = Model("one\ntwo")
        let drawn = rows(harness.frame(TextField("T", text: model.binding, axis: .vertical)))
        #expect(drawn.count == 2)
        #expect(drawn.allSatisfy { $0.hasPrefix("▐") && $0.hasSuffix("▌") }, "\(drawn)")
    }

    @Test("While empty it grows to show its whole prompt")
    func promptRows() {
        let harness = InputChainHarness(width: 12)
        let model = Model("")
        // Another field first takes the focus, so this one draws its prompt.
        let view = VStack {
            TextField("first", text: .constant(""))
            TextField("T", text: model.binding, prompt: Text("one two three four five six"), axis: .vertical)
                .textFieldStyle(.plain)
        }
        let drawn = rows(harness.frame(view)).dropFirst().map { $0.trimmingTrailingSpaces }
        #expect(Array(drawn) == ["one two", "three four", "five six"])
    }

    // MARK: - Keys

    @Test("Option-Return inserts a newline, and Return submits without one")
    func newlineAndSubmit() {
        let harness = InputChainHarness(width: 20)
        let model = Model("ab")
        harness.play([KeyEvent(key: .left), KeyEvent(key: .enter, alt: true), key("X")]) { field(model) }
        #expect(model.text == "a\nXb")
        harness.play([KeyEvent(key: .enter)]) { field(model) }
        #expect(model.text == "a\nXb")
        #expect(model.submits == 1)
    }

    @Test("Ctrl-O opens a line: the newline goes in front of the caret")
    func openLine() {
        let harness = InputChainHarness(width: 20)
        let model = Model("ab")
        harness.play([KeyEvent(key: .left), key("o", ctrl: true), key("X")]) { field(model) }
        #expect(model.text == "aX\nb")
    }

    @Test("Up and Down move a row, keeping the column, and leave the text from either end")
    func verticalMotion() {
        let harness = InputChainHarness(width: 20)
        let model = Model("abc\ndef")
        harness.play([KeyEvent(key: .up), key("X")]) { field(model) }
        #expect(model.text == "abcX\ndef")
        model.text = "abc\ndef"
        harness.play([KeyEvent(key: .end), KeyEvent(key: .up), KeyEvent(key: .up), key("X")]) { field(model) }
        #expect(model.text == "Xabc\ndef", "Up from the first row goes to the start")
        model.text = "abc\ndef"
        harness.play([KeyEvent(key: .home), KeyEvent(key: .down), KeyEvent(key: .down), key("X")]) { field(model) }
        #expect(model.text == "abc\ndefX", "Down from the last row goes to the end")
    }

    /// Upstream, the start of a wrapped row is drawn at the end of the row
    /// before it, so Down landing there drew the caret on the row it left, and
    /// the next Down came back to it.
    @Test("Upstream, Down moves a row at a time through wrapped rows")
    func upstreamDown() {
        let harness = InputChainHarness(width: 7)
        let model = Model("aaaa bbbb cccc")
        harness.play([KeyEvent(key: .home), KeyEvent(key: .down), KeyEvent(key: .down), key("X")]) {
            field(model).textSelectionAffinity(.upstream)
        }
        #expect(model.text == "aaaa bbbb cXccc")
    }

    @Test("A run of Up presses keeps the column it started from through a shorter row")
    func columnMemory() {
        let harness = InputChainHarness(width: 20)
        let model = Model("abcdef\nx\nabcdef")
        harness.play([KeyEvent(key: .end), KeyEvent(key: .up), KeyEvent(key: .up), key("X")]) { field(model) }
        #expect(model.text == "abcdefX\nx\nabcdef")
    }

    @Test("Up and Down move by the rows the text wrapped into, not by its lines")
    func wrappedRows() {
        let harness = InputChainHarness(width: 12)
        let model = Model("aaaa bbbb cccc dddd")
        // From the end of "cccc dddd" (row 1, column 9) up to row 0, column 9.
        harness.play([KeyEvent(key: .end), KeyEvent(key: .up), key("X")]) { field(model) }
        #expect(model.text == "aaaa bbbbX cccc dddd")
    }

    @Test("Shift-Up selects to the same column a row up")
    func shiftUp() {
        let harness = InputChainHarness(width: 20)
        let model = Model("abc\ndef")
        harness.play([KeyEvent(key: .end), KeyEvent(key: .up, shift: true), key("X")]) { field(model) }
        #expect(model.text == "abcX")
    }

    @Test("Ctrl-A, Ctrl-E and Ctrl-K act on the caret's line; Ctrl-K at its end takes the newline")
    func lineCommands() {
        let harness = InputChainHarness(width: 20)
        let model = Model("abc\ndef")
        harness.play([KeyEvent(key: .end), key("a", ctrl: true), key("X")]) { field(model) }
        #expect(model.text == "abc\nXdef")
        harness.play([key("e", ctrl: true), key("Y")]) { field(model) }
        #expect(model.text == "abc\nXdefY")
        model.text = "abc\ndef"
        harness.play([KeyEvent(key: .home), key("e", ctrl: true), key("k", ctrl: true)]) { field(model) }
        #expect(model.text == "abcdef")
        model.text = "abc\ndef"
        harness.play([KeyEvent(key: .home), KeyEvent(key: .right), key("k", ctrl: true)]) { field(model) }
        #expect(model.text == "a\ndef")
    }

    @Test("Ctrl-A keeps the key from an app's ⌘A, its only key for the start of a line; one line gives it up")
    func lineStartKeepsTheChord() {
        final class Fired { var fired = false }
        let shortcut = Fired()
        let model = Model("abc\ndef")
        func page(_ axis: Axis) -> some View {
            VStack {
                TextField("T", text: model.binding, axis: axis).textFieldStyle(.plain)
                Button("Select All") { shortcut.fired = true }.keyboardShortcut("a")
            }
        }
        InputChainHarness(width: 20).play([key("a", ctrl: true), key("X")]) { page(.vertical) }
        #expect(model.text == "abc\nXdef" && !shortcut.fired)
        model.text = "abc"
        InputChainHarness(width: 20).play([key("a", ctrl: true)]) { page(.horizontal) }
        #expect(shortcut.fired)
    }

    @Test("A paste keeps its line breaks, each as one newline; a field on one line drops them")
    func pasteKeepsLineBreaks() {
        let harness = InputChainHarness(width: 20)
        let model = Model("")
        harness.play([KeyEvent(key: .paste("x\r\ny\rz"))]) { field(model) }
        #expect(model.text == "x\ny\nz")
        let oneLine = Model("")
        harness.play([KeyEvent(key: .paste("x\r\ny"))]) {
            TextField("T", text: oneLine.binding).textFieldStyle(.plain)
        }
        #expect(oneLine.text == "xy")
    }

    // MARK: - Scrolling and the pointer

    @Test("At its limit it scrolls to keep the caret's row in view; unfocused it shows its first rows")
    func scrolls() {
        let harness = InputChainHarness(width: 12)
        let model = Model("1\n2\n3\n4\n5")
        let view = { field(model).lineLimit(2) }
        harness.play([KeyEvent(key: .end)], view)
        #expect(rows(harness.frame(view())).map { $0.trimmingTrailingSpaces } == ["4", "5"])
        harness.play([KeyEvent(key: .up), KeyEvent(key: .up), KeyEvent(key: .up)], view)
        #expect(rows(harness.frame(view())).map { $0.trimmingTrailingSpaces } == ["2", "3"])

        // Another field first takes the focus.
        let unfocused = rows(
            InputChainHarness(width: 12).frame(
                VStack { TextField("first", text: .constant("")); field(model).lineLimit(2) }))
        #expect(unfocused.dropFirst().map { $0.trimmingTrailingSpaces } == ["1", "2"])
    }

    @Test("Where a row wrapped, the caret is drawn on the later row, or on the earlier one upstream")
    func caretAffinity() {
        let model = Model("hello world")
        let toTheWrap = [KeyEvent(key: .home)] + Array(repeating: KeyEvent(key: .right), count: 6)
        func caretRow(_ affinity: TextSelectionAffinity) -> Int? {
            let harness = InputChainHarness(width: 7)
            let view = { field(model).textSelectionAffinity(affinity) }
            harness.play(toTheWrap, view)
            return harness.frame(view()).animatedCells.first.map(\.offsetY)
        }
        #expect(caretRow(.automatic) == 1)
        #expect(caretRow(.upstream) == 0)
    }

    @Test("A press puts the caret on the row and column it landed on")
    func pointer() {
        let harness = InputChainHarness(width: 12)
        let model = Model("abc\ndefgh")
        harness.frame(field(model))
        harness.frame(field(model))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 2, y: 1))
        harness.play([key("X")]) { field(model) }
        #expect(model.text == "abc\ndeXfgh")
    }

    /// Upstream a caret cannot be on a wrapped row's first character, but a
    /// selection's end can: a drag from that cell takes the character.
    @Test("Upstream, a drag from a wrapped row's first cell selects its first character")
    func upstreamDragFromRowStart() {
        let harness = InputChainHarness(width: 7)
        let model = Model("aaaa bbbb cccc")
        let view = { field(model).textSelectionAffinity(.upstream) }
        harness.frame(view())
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 0, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 4, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 4, y: 1))
        harness.play([key("X")]) { view() }
        #expect(model.text == "aaaa X cccc")
    }

    /// A drag's head on a wrapped row's first character is on that row, not
    /// the row before (whose end the same offset is to an upstream caret):
    /// read there, a field at its line limit scrolled up a row under the
    /// pointer.
    @Test("Upstream, a drag head on the top row's first cell scrolls nothing")
    func upstreamHeadOnTopRowStart() {
        let harness = InputChainHarness(width: 7)
        let model = Model("aaaa bbbb cccc dddd")
        let view = { field(model).lineLimit(2).textSelectionAffinity(.upstream) }
        harness.play([KeyEvent(key: .end)], view)
        #expect(rows(harness.frame(view())).map { $0.trimmingTrailingSpaces } == ["cccc", "dddd"])
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 1))
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 0, y: 0))
        #expect(rows(harness.frame(view())).map { $0.trimmingTrailingSpaces } == ["cccc", "dddd"])
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        harness.play([key("X")]) { view() }
        #expect(model.text == "aaaa bbbb Xdd")
    }

    /// A selection's head left the end of no selection is a caret, read by
    /// the field's affinity like every caret. Review round 2 of the
    /// follow-ups: on a wrapped row's first character under `.upstream` it
    /// stayed drawn at that row's first cell — after a drag back onto its
    /// press, and after a key that ends the selection without moving the
    /// head (Backspace deleting a backward selection: the review named Left,
    /// which here steps off the head and so already ended it).
    @Test("Upstream, a selection's head left the end of no selection on a row's first cell is a caret")
    func upstreamCollapsedHeadIsACaret() throws {
        let harness = InputChainHarness(width: 7)
        let model = Model("aaaa bbbb cccc dddd")
        let view = { field(model).textSelectionAffinity(.upstream) }
        let firstTwo: [String] = Array(rows(harness.frame(view())).map { $0.trimmingTrailingSpaces }.prefix(2))
        try #require(firstTwo == ["aaaa", "bbbb"])
        func drag(from: Int, through xs: [Int]) {
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: from, y: 1))
            harness.frame(view())
            for x in xs {
                harness.mouse(MouseEvent(button: .left, phase: .dragged, x: x, y: 1))
                harness.frame(view())
            }
            harness.mouse(MouseEvent(button: .left, phase: .released, x: xs.last ?? from, y: 1))
            harness.frame(view())
        }
        // A drag back onto its press on "bbbb"'s first cell: where a click
        // there puts the caret, after the "b".
        drag(from: 0, through: [1, 0])
        let handler = try #require(harness.focusManager.currentFocused as? TextFieldHandler)
        #expect(!handler.hasSelection)
        #expect(handler.cursorPosition == 6)
        #expect(handler.rowStartHead == nil)
        // A backward drag onto it, then Backspace: the caret stays on the
        // head, read as any caret at that offset is.
        drag(from: 2, through: [0])
        try #require(handler.selectionRange == 5..<7)
        harness.play([KeyEvent(key: .backspace)], view)
        #expect(!handler.hasSelection)
        #expect(handler.cursorPosition == 5)
        #expect(handler.rowStartHead == nil)
        #expect(handler.caretAffinity == .upstream)
    }

    /// A press on the `▾` that closes the suggestions is the field's, and so
    /// is a drag from it: it anchors at the caret, as before there was a
    /// press anchor, not at the cell an earlier press landed on.
    @Test("A drag from the ▾ that closed the suggestions anchors at the caret")
    func dragFromClosingDisclosureAnchorsAtTheCaret() throws {
        let harness = InputChainHarness(width: 12)
        let model = Model("aaaa bbbb cccc")
        let view = { field(model).textInputSuggestions { Text("one") } }
        harness.frame(view())
        let first = rows(harness.frame(view()))[0]
        let arrow = try #require(first.firstIndex(of: "▾")).utf16Offset(in: first)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: 1))
        harness.play([KeyEvent(key: .end)], view)
        let caret = try #require(harness.focusManager.currentFocused as? TextFieldHandler).cursorPosition
        try #require(caret > 6, "precondition: the caret is past the first press's cell")
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: arrow, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: arrow, y: 0))
        try #require(!harness.frame(view()).overlays.isEmpty, "precondition: the ▾ opened the suggestions")
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: arrow, y: 0))
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 0, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        try #require(harness.frame(view()).overlays.isEmpty, "precondition: the ▾ closed them")
        harness.play([key("X")]) { view() }
        let expected: String = "X" + "aaaa bbbb cccc".dropFirst(caret)
        #expect(model.text == expected)
    }

    @Test("With suggestions, Down moves a row until the caret is on the last, and opens them there")
    func suggestionsOpenFromTheLastRow() {
        let harness = InputChainHarness(width: 20)
        let model = Model("abc\ndef")
        let view = {
            field(model).textInputSuggestions {
                Text("one")
                Text("two")
            }
        }
        harness.play([KeyEvent(key: .home), KeyEvent(key: .down)], view)
        #expect(harness.frame(view()).overlays.isEmpty, "Down from the first row moved the caret")
        harness.play([KeyEvent(key: .down)], view)
        #expect(!harness.frame(view()).overlays.isEmpty, "Down on the last row opened the suggestions")
    }

    @Test("A token suggestion it cannot take draws no ▾, and the measure makes no room for one")
    func untakeableTokenSuggestionMeasuresAsDrawn() {
        // A token outside any searchable: no field here can take it, so the
        // menu is never prepared and no `▾` is drawn. Eleven cells of text in
        // a field twelve wide is one row without the `▾` and two with it.
        struct Crop: Identifiable { let id: String }
        let model = Model("aaaaaaaaaaa")
        let view = VStack {
            field(model).textInputSuggestions { Text("Apple").searchCompletion(Crop(id: "Apple")) }
        }
        let context = makeRenderContext(width: 12, height: 20)
        let size = measureChild(view, proposal: ProposedSize(width: 12, height: nil), context: context)
        let drawn = renderToBuffer(view, context: context)
        #expect(rows(drawn).map { $0.trimmingTrailingSpaces } == ["aaaaaaaaaaa"], "no ▾, one row")
        #expect(size.height == drawn.height, "measured \(size.height) rows, drew \(drawn.height)")
    }
}

extension String {
    /// The string without the spaces a field pads its rows with.
    fileprivate var trimmingTrailingSpaces: String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}
