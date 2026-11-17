//  🖥️ TUI — A Terminal UI framework for Swift
//  TextDropTests.swift
//
//  Dragged text dropped on a text control, as SwiftUI's take it (measured on
//  macOS 15.8.3, `Tools/SwiftUIProbes/Pasted line breaks and drops (1117)`):
//  a TextField or SecureField takes it only while focused, a TextEditor
//  focused or not, without taking the focus; each inserts a copy where it
//  was dropped, as one step to undo — and a drag carried from the keyboard
//  drops at the caret.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("Text dropped on a text field or editor")
struct TextDropTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
        var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// A draggable string on row 0, then a field, a secure field and an editor,
    /// one a row, each holding `abcd`.
    struct Page: View {
        let payload: String
        let field = Box("abcd"), secure = Box("abcd"), editor = Box("abcd")
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("DRAG").draggable(payload)
                TextField("Field", text: field.binding).focusID("field").frame(width: 20)
                SecureField("Secure", text: secure.binding).focusID("secure").frame(width: 20)
                TextEditor(text: editor.binding).focusID("editor").frame(width: 20, height: 3)
            }
        }
    }

    private static let undoKey = KeyEvent(key: .character("z"), ctrl: true)
    private static let pickUp = KeyEvent(key: .character("r"), ctrl: true)

    /// The cell of the third character, `c`, of the control drawn on `row`:
    /// the first of `glyph` on that row, two cells on.
    func cellOfC(row: Int, glyph: String = "a", in frame: FrameBuffer) throws -> (x: Int, y: Int) {
        let line = frame.lines[row].stripped
        let range = try #require(line.range(of: glyph))
        return (line.distance(from: line.startIndex, to: range.lowerBound) + 2, row)
    }

    /// A left drag from the draggable to `end`, a frame after each event.
    func drag(_ harness: InputChainHarness, _ page: Page, to end: (x: Int, y: Int)) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: end.x, y: end.y))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: end.x, y: end.y))
        harness.frame(page)
    }

    /// A harness drawing `page` twice, with `focus` focused.
    func setUp(_ page: Page, focus: String) -> InputChainHarness {
        let harness = InputChainHarness(width: 30, height: 8)
        harness.frame(page)
        harness.focusManager.focus(id: focus)
        harness.frame(page)
        return harness
    }

    @Test("A focused TextField inserts the dropped text at the cell dropped on, and selects it")
    func focusedFieldInserts() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "field")
        drag(harness, page, to: try cellOfC(row: 1, in: harness.frame(page)))
        #expect(page.field.value == "abxycd")
        #expect(harness.focusManager.currentFocusedID == "field")
        let handler = try #require(harness.focusManager.currentFocused as? TextFieldHandler)
        #expect(handler.selectionRange == 2..<4, "the dropped text is selected, as an NSTextView leaves it")
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    @Test("A TextField not focused takes no drop: the drag goes home")
    func unfocusedFieldRefuses() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "editor")
        drag(harness, page, to: try cellOfC(row: 1, in: harness.frame(page)))
        #expect(page.field.value == "abcd")
        #expect(page.editor.value == "abcd")
        #expect(harness.focusManager.currentFocusedID == "editor")
    }

    @Test("A focused SecureField inserts the dropped text at the cell dropped on")
    func focusedSecureFieldInserts() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "secure")
        let frame = harness.frame(page)
        drag(harness, page, to: try cellOfC(row: 2, glyph: String(TerminalSymbols.maskBullet), in: frame))
        #expect(page.secure.value == "abxycd")
    }

    @Test("A SecureField not focused takes no drop")
    func unfocusedSecureFieldRefuses() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "field")
        let frame = harness.frame(page)
        drag(harness, page, to: try cellOfC(row: 2, glyph: String(TerminalSymbols.maskBullet), in: frame))
        #expect(page.secure.value == "abcd")
        #expect(page.field.value == "abcd")
    }

    @Test("A TextEditor not focused takes the drop where it landed, and the focus stays where it was")
    func unfocusedEditorTakes() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "field")
        drag(harness, page, to: try cellOfC(row: 3, in: harness.frame(page)))
        #expect(page.editor.value == "abxycd")
        #expect(page.field.value == "abcd")
        #expect(harness.focusManager.currentFocusedID == "field")
    }

    @Test("A focused TextEditor takes the drop where it landed, as one step to undo")
    func focusedEditorUndoes() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "editor")
        drag(harness, page, to: try cellOfC(row: 3, in: harness.frame(page)))
        #expect(page.editor.value == "abxycd")
        harness.press(Self.undoKey)
        harness.frame(page)
        #expect(page.editor.value == "abcd")
    }

    @Test("A drop on a field is one step to undo")
    func fieldDropUndoes() throws {
        let page = Page(payload: "xyz")
        let harness = setUp(page, focus: "field")
        drag(harness, page, to: try cellOfC(row: 1, in: harness.frame(page)))
        #expect(page.field.value == "abxyzcd")
        harness.press(Self.undoKey)
        harness.frame(page)
        #expect(page.field.value == "abcd")
    }

    @Test("A drop is a copy: the badge says so")
    func dropIsACopy() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "field")
        let target = try cellOfC(row: 1, in: harness.frame(page))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: target.x, y: target.y))
        harness.frame(page)
        #expect(harness.tui.dragAndDropSession.proposedOperation == .copy)
    }

    @Test("A drag carried from the keyboard drops at the field's caret")
    func carriedDropAtCaret() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "field")
        // The caret after `ab`, put there by a click on `c`.
        let c = try cellOfC(row: 1, in: harness.frame(page))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: c.x, y: c.y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: c.x, y: c.y))
        harness.frame(page)
        let source = try #require(harness.focusManager.focusableIDs.first { $0.hasPrefix("draggable") })
        harness.focusManager.focus(id: source)
        let consumed = harness.play([Self.pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { page }
        #expect(consumed == [true, true, true])
        #expect(page.field.value == "abxycd")
        #expect(harness.focusManager.currentFocusedID == "field")
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    @Test("A drag carried from the keyboard drops at an editor's caret")
    func carriedDropAtEditorCaret() throws {
        let page = Page(payload: "xy")
        let harness = setUp(page, focus: "editor")
        let c = try cellOfC(row: 3, in: harness.frame(page))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: c.x, y: c.y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: c.x, y: c.y))
        harness.frame(page)
        let source = try #require(harness.focusManager.focusableIDs.first { $0.hasPrefix("draggable") })
        harness.focusManager.focus(id: source)
        // Back from the card, round the end, to the editor at the bottom.
        harness.play([Self.pickUp, KeyEvent(key: .tab, shift: true), KeyEvent(key: .enter)]) { page }
        #expect(page.editor.value == "abxycd")
        #expect(page.field.value == "abcd")
    }

    @Test("A dropped line break is stored as a pasted one is, in a field on one line")
    func lineBreakAsPasted() throws {
        let page = Page(payload: "p\r\nq")
        let harness = setUp(page, focus: "field")
        drag(harness, page, to: try cellOfC(row: 1, in: harness.frame(page)))
        let dropped = page.field.value

        let pasted = Page(payload: "")
        let other = setUp(pasted, focus: "field")
        let c = try cellOfC(row: 1, in: other.frame(pasted))
        other.mouse(MouseEvent(button: .left, phase: .pressed, x: c.x, y: c.y))
        other.mouse(MouseEvent(button: .left, phase: .released, x: c.x, y: c.y))
        other.frame(pasted)
        other.press(KeyEvent(key: .paste("p\r\nq")))
        other.frame(pasted)
        #expect(dropped == pasted.field.value)
        #expect(dropped != "abcd")
    }
}
