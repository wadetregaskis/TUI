//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorRightDragTests.swift
//
//  A right-button drag is never the editor's selection drag. The D4X lane's
//  second review found a fast right-drag on the screen selection's highlight
//  over a `TextEditor` moving the editor's selection: the drags came in the
//  same read as the press that opened the highlight's menu, before a frame
//  had drawn it, so they were hit-tested against the page, and the editor's
//  `.dragged` arm took any button's drag.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

@MainActor
@Suite("TextEditor: a right-button drag is not a selection drag")
struct TextEditorRightDragTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    struct Page: View {
        let text: Box
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("alpha beta gamma")
                TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                    .frame(width: 30, height: 4)
            }
        }
    }

    /// Where `fragment` is drawn: its first cell, on the row that shows it.
    func cell(of fragment: String, in frame: FrameBuffer) throws -> (x: Int, y: Int) {
        let rows = frame.lines.map(\.stripped)
        let y = try #require(rows.firstIndex { $0.contains(fragment) })
        let range = try #require(rows[y].range(of: fragment))
        return (rows[y].distance(from: rows[y].startIndex, to: range.lowerBound), y)
    }

    /// A left drag from `start` to `end`, a frame after each event.
    func leftDrag(_ harness: InputChainHarness, _ view: Page, from start: (x: Int, y: Int), to end: (x: Int, y: Int)) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: start.x, y: start.y))
        harness.frame(view)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: end.x, y: end.y))
        harness.frame(view)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: end.x, y: end.y))
        harness.frame(view)
    }

    func editorSelection(_ harness: InputChainHarness) -> String? {
        guard let handler = harness.focusManager.currentFocused as? TextEditorHandler,
            let range = handler.selectionRange
        else { return nil }
        return handler.selectedText(range)
    }

    /// The editor with `two` selected and the screen selection on `alpha`.
    func selectedBoth(_ harness: InputChainHarness, _ view: Page) throws -> FrameBuffer {
        var frame = harness.frame(view)
        let two = try cell(of: "two", in: frame)
        leftDrag(harness, view, from: two, to: (two.x + 3, two.y))
        #expect(editorSelection(harness) == "two")
        frame = harness.frame(view)
        let alpha = try cell(of: "alpha", in: frame)
        leftDrag(harness, view, from: alpha, to: (alpha.x + 4, alpha.y))
        #expect(harness.tui.screenSelection.current?.text == "alpha")
        #expect(editorSelection(harness) == "two")
        return harness.frame(view)
    }

    /// The review's case: a right press on the highlight opens its menu, and
    /// the drags and release in the same read cross the editor's text.
    @Test("A fast right-drag from the highlight across the editor leaves the editor's selection")
    func fastRightDragFromTheHighlight() throws {
        let harness = InputChainHarness(width: 40, height: 10)
        let view = Page(text: Box("one two three\nfour five"))
        let frame = try selectedBoth(harness, view)
        let alpha = try cell(of: "alpha", in: frame)
        let four = try cell(of: "four", in: frame)
        harness.mouse(MouseEvent(button: .right, phase: .pressed, x: alpha.x + 1, y: alpha.y))
        for column in 0..<4 {
            harness.mouse(MouseEvent(button: .right, phase: .dragged, x: four.x + column, y: four.y))
        }
        harness.mouse(MouseEvent(button: .right, phase: .released, x: four.x + 3, y: four.y))
        harness.frame(view)
        #expect(editorSelection(harness) == "two")
    }

    /// The editor's own arm: a drag of any button but the left is not its
    /// selection's, wherever the dispatcher routes it from. Handed straight
    /// to the editor's handler, a right drag extended the selection.
    @Test("The editor's handler ignores a right-button drag")
    func handlerIgnoresARightDrag() throws {
        let harness = InputChainHarness(width: 40, height: 10)
        let view = Page(text: Box("one two three\nfour five"))
        let frame = try selectedBoth(harness, view)
        let region = try #require(frame.hitTestRegions.last { $0.focusID?.hasPrefix("texteditor") == true })
        let handler = try #require(harness.tui.mouseEventDispatcher.handler(for: region.handlerID))
        let four = try cell(of: "four", in: frame)
        let consumed = handler(
            MouseEvent(button: .right, phase: .dragged, x: four.x - region.localOriginX + 3, y: four.y - region.localOriginY))
        #expect(!consumed)
        #expect(editorSelection(harness) == "two")
    }
}

@MainActor
@Suite("TextField: a right-button drag is not a selection drag")
struct TextFieldRightDragTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    struct Field: View {
        let text: Box
        var body: some View {
            TextField("Name", text: Binding(get: { text.value }, set: { text.value = $0 })).frame(width: 30)
        }
    }

    /// The editor's twin: handed straight to the field's handler, a right
    /// drag extended the field's selection.
    @Test("The field's handler ignores a right-button drag")
    func handlerIgnoresARightDrag() throws {
        let harness = InputChainHarness(width: 40, height: 4)
        let text = Box("one two three")
        let view = Field(text: text)
        let frame = harness.frame(view)
        let region = try #require(frame.hitTestRegions.last { $0.focusID?.hasPrefix("textfield") == true })
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))
        harness.frame(view)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: region.offsetX, y: region.offsetY))
        harness.frame(view)
        let field = try #require(harness.focusManager.currentFocused as? TextFieldHandler)
        #expect(field.selectionRange == nil)
        let handler = try #require(harness.tui.mouseEventDispatcher.handler(for: region.handlerID))
        #expect(!handler(MouseEvent(button: .right, phase: .dragged, x: 5, y: 0)))
        #expect(field.selectionRange == nil)
    }
}
