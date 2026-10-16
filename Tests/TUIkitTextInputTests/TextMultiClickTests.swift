//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextMultiClickTests.swift
//
//  A double-click in a text input selects a word, a triple-click a paragraph,
//  and a drag after either extends by them — against what AppKit's field
//  editor and NSTextView select for the same text, measured on macOS 15.8.
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
@Suite("Text inputs: double- and triple-click")
struct TextMultiClickTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    /// The probe's field text, with a run of two blanks.
    static let fieldText = "hunter2 abc.def  ghi"
    /// The probe's text view text, with an empty paragraph.
    static let editorText = "one two\nthree.four  five\n\nsix"

    struct Field: View {
        let text: Box
        var secure = false
        @ViewBuilder var body: some View {
            let binding = Binding(get: { text.value }, set: { text.value = $0 })
            if secure {
                SecureField("Password", text: binding).frame(width: 30)
            } else {
                TextField("Name", text: binding).frame(width: 30)
            }
        }
    }

    struct Editor: View {
        let text: Box
        var body: some View {
            TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                .frame(width: 30, height: 6)
        }
    }

    /// A harness whose dispatcher reads the frame clock, so presses at one
    /// instant count up as a multi-click.
    func harness() -> InputChainHarness {
        let harness = InputChainHarness(width: 40, height: 10)
        harness.syncEventClock()
        return harness
    }

    /// `count` clicks at (`x`, `y`), a frame after each event. With `dragTo`,
    /// the last press drags there before it is released.
    func click(
        _ harness: InputChainHarness, _ view: some View, count: Int, x: Int, y: Int,
        dragTo: (x: Int, y: Int)? = nil
    ) {
        harness.now += 1_000_000_000
        for index in 0..<count {
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            harness.frame(view)
            var end = (x: x, y: y)
            if index == count - 1, let dragTo {
                harness.mouse(MouseEvent(button: .left, phase: .dragged, x: dragTo.x, y: dragTo.y))
                harness.frame(view)
                end = dragTo
            }
            harness.mouse(MouseEvent(button: .left, phase: .released, x: end.x, y: end.y))
            harness.frame(view)
        }
    }

    /// Where `fragment` is drawn: its first cell, on the row that shows it.
    func cell(of fragment: String, in frame: FrameBuffer) throws -> (x: Int, y: Int) {
        let rows = frame.lines.map(\.stripped)
        let y = try #require(rows.firstIndex { $0.contains(fragment) })
        let range = try #require(rows[y].range(of: fragment))
        return (rows[y].distance(from: rows[y].startIndex, to: range.lowerBound), y)
    }

    func fieldSelection(_ harness: InputChainHarness, _ text: Box) throws -> String {
        let handler = try #require(harness.focusManager.currentFocused as? TextFieldHandler)
        let range = try #require(handler.selectionRange)
        return String(Array(text.value)[range])
    }

    func editorSelection(_ harness: InputChainHarness) throws -> String {
        let handler = try #require(harness.focusManager.currentFocused as? TextEditorHandler)
        return handler.selectedText(try #require(handler.selectionRange))
    }

    @Test("A double-click in a field selects the run clicked: a word, the blanks, or the last word past the end")
    func fieldWord() throws {
        let harness = harness()
        let text = Box(Self.fieldText)
        let view = Field(text: text)
        let frame = harness.frame(view)
        let abc = try cell(of: "abc", in: frame)
        click(harness, view, count: 2, x: abc.x + 1, y: abc.y)
        #expect(try fieldSelection(harness, text) == "abc")
        let blanks = try cell(of: "  ghi", in: frame)
        click(harness, view, count: 2, x: blanks.x + 1, y: blanks.y)
        #expect(try fieldSelection(harness, text) == "  ")
        click(harness, view, count: 2, x: blanks.x + 8, y: blanks.y)
        #expect(try fieldSelection(harness, text) == "ghi")
    }

    @Test("A triple-click in a field selects its text; a double-click in a SecureField all of it")
    func fieldParagraphAndSecure() throws {
        let harness = harness()
        let text = Box(Self.fieldText)
        let view = Field(text: text)
        let abc = try cell(of: "abc", in: harness.frame(view))
        click(harness, view, count: 3, x: abc.x, y: abc.y)
        #expect(try fieldSelection(harness, text) == Self.fieldText)

        let secureHarness = self.harness()
        let secure = Field(text: text, secure: true)
        secureHarness.frame(secure)
        click(secureHarness, secure, count: 2, x: abc.x, y: abc.y)
        #expect(try fieldSelection(secureHarness, text) == Self.fieldText)
    }

    @Test("A drag after a double-click extends by words, keeping the word clicked")
    func fieldDragByWords() throws {
        let harness = harness()
        let text = Box(Self.fieldText)
        let view = Field(text: text)
        let frame = harness.frame(view)
        let abc = try cell(of: "abc", in: frame)
        let ghi = try cell(of: "ghi", in: frame)
        let hunter = try cell(of: "hunter2", in: frame)
        click(harness, view, count: 2, x: abc.x + 1, y: abc.y, dragTo: (ghi.x + 1, ghi.y))
        #expect(try fieldSelection(harness, text) == "abc.def  ghi")
        click(harness, view, count: 2, x: abc.x + 1, y: abc.y, dragTo: (hunter.x + 2, hunter.y))
        #expect(try fieldSelection(harness, text) == "hunter2 abc")
    }

    @Test("A double-click in an editor selects a word, or a line break at a line's end or on an empty line")
    func editorWord() throws {
        let harness = harness()
        let view = Editor(text: Box(Self.editorText))
        let frame = harness.frame(view)
        let four = try cell(of: "four", in: frame)
        click(harness, view, count: 2, x: four.x + 1, y: four.y)
        #expect(try editorSelection(harness) == "four")
        let two = try cell(of: "two", in: frame)
        click(harness, view, count: 2, x: two.x + 6, y: two.y)
        #expect(try editorSelection(harness) == "\n")
        click(harness, view, count: 2, x: 2, y: four.y + 1)
        #expect(try editorSelection(harness) == "\n")
        let six = try cell(of: "six", in: frame)
        click(harness, view, count: 2, x: six.x + 8, y: six.y)
        #expect(try editorSelection(harness) == "six")
    }

    @Test("A triple-click in an editor selects the line with its line break, and a drag extends by lines")
    func editorParagraph() throws {
        let harness = harness()
        let view = Editor(text: Box(Self.editorText))
        let frame = harness.frame(view)
        let three = try cell(of: "three", in: frame)
        click(harness, view, count: 3, x: three.x + 2, y: three.y)
        #expect(try editorSelection(harness) == "three.four  five\n")
        let six = try cell(of: "six", in: frame)
        click(harness, view, count: 3, x: six.x, y: six.y)
        #expect(try editorSelection(harness) == "six")
        let one = try cell(of: "one", in: frame)
        click(harness, view, count: 3, x: three.x, y: three.y, dragTo: (one.x, one.y))
        #expect(try editorSelection(harness) == "one two\nthree.four  five\n")
    }
}
