//  🖥️ TUI — A Terminal UI framework for Swift
//  AppTextEditSelectionTests.swift
//
//  The selection a field or an editor keeps when the app edits the text bound
//  to it: moved as NSTextView moves its own (owner ruling O-28 (a),
//  2026-11-22), each row of the measurement
//  (`Documentation/SwiftUI parity/SELECTION-REPLACE/`, Parts 1 and 1b) a case.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

/// One measured row: the selection in "abcdefghij", the text the app writes,
/// and the selection `NSTextView` was left with, as character offsets.
struct AppEditRow: CustomTestStringConvertible, Sendable {
    let label: String
    let selection: Range<Int>
    let new: String
    let expected: Range<Int>

    var testDescription: String { label }

    init(_ label: String, _ new: String, _ expected: Range<Int>, from selection: Range<Int> = 2..<7) {
        (self.label, self.selection, self.new, self.expected) = (label, selection, new, expected)
    }

    static let original = "abcdefghij"

    /// Part 1 of `probe.out`, then Part 1b of `probe-edges.out`: the
    /// selection `{location,length}` there is `location..<location+length`
    /// here.
    static let measured: [Self] = [
        Self("(a) string = same length", "0123456789", 10..<10),
        Self("(a') string = shorter than the selection's end", "0123", 4..<4),
        Self("(a'') string = longer", "0123456789ABCDEF", 16..<16),
        Self("(b) insert before", "XYabcdefghij", 4..<9),
        Self("(b') insert just before", "aXYbcdefghij", 4..<9),
        Self("(c) inside, shrinks", "abcZfghij", 4..<4),
        Self("(c') inside, grows", "abcZZZZfghij", 7..<7),
        Self("(c'') straddles the start", "aQefghij", 2..<2),
        Self("(c''') straddles the end", "abcdefQj", 7..<7),
        Self("(d) append", "abcdefghijXYZ", 2..<7),
        Self("(e') whole, shorter", "012", 3..<3),
        Self("insert at the selection's start", "abXYcdefghij", 4..<9),
        Self("insert at the selection's end", "abcdefgXYhij", 2..<7),
        Self("replace ending at the start", "Qcdefghij", 1..<6),
        Self("replace starting at the end", "abcdefgQj", 2..<7),
        Self("delete ending at the start", "cdefghij", 0..<5),
        Self("delete starting at the end", "abcdefgj", 2..<7),
        Self("delete inside", "abcfghij", 3..<3),
        Self("insert inside", "abcdXYefghij", 6..<6),
        Self("delete the selection exactly", "abhij", 2..<2),
        Self("insert at a caret", "abcdeXYfghij", 7..<7, from: 5..<5),
        Self("replace starting at a caret", "abcdeQhij", 6..<6, from: 5..<5),
        Self("replace ending at a caret", "abcQfghij", 4..<4, from: 5..<5),
        Self("replace across a caret", "abcdQghij", 5..<5, from: 5..<5),
        Self("append at a caret at the end", "abcdefghijXY", 12..<12, from: 10..<10),
        Self("insert at 0, caret at 0", "XYabcdefghij", 2..<2, from: 0..<0),
    ]
}

@MainActor
@Suite("The selection through the app's edit of the text")
struct AppTextEditSelectionTests {

    // MARK: - NSTextView's table

    @Test("A field's selection moves through the app's edit as NSTextView's does", arguments: AppEditRow.measured)
    func fieldRow(_ row: AppEditRow) {
        var text = AppEditRow.original
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "field", text: binding, cursorPosition: row.selection.upperBound)
        if !row.selection.isEmpty { handler.selectionAnchor = row.selection.lowerBound }
        text = row.new
        handler.clampCursorPosition()
        #expect(handler.selectionOffsets == row.expected)
    }

    @Test("An editor's selection moves through the app's edit as NSTextView's does", arguments: AppEditRow.measured)
    func editorRow(_ row: AppEditRow) {
        var text = AppEditRow.original
        let handler = TextEditorHandler(focusID: "editor", text: Binding(get: { text }, set: { text = $0 }))
        select(row.selection, in: handler)
        text = row.new
        handler.clampCursor()
        #expect(handler.selectionOffsets == row.expected)
    }

    @Test("A selection made backwards keeps its direction where the edit shifts it")
    func directionKept() {
        var text = AppEditRow.original
        let binding = Binding(get: { text }, set: { text = $0 })
        let field = TextFieldHandler(focusID: "field", text: binding, cursorPosition: 2)
        field.selectionAnchor = 7
        let editor = TextEditorHandler(focusID: "editor", text: binding)
        editor.selectionAnchor = TextEditorPosition(line: 0, column: 7)
        editor.cursor = TextEditorPosition(line: 0, column: 2)
        text = "XY" + text
        field.clampCursorPosition()
        editor.clampCursor()
        #expect(field.cursorPosition == 4 && field.selectionAnchor == 9)
        #expect(editor.cursor == TextEditorPosition(line: 0, column: 4))
        #expect(editor.selectionAnchor == TextEditorPosition(line: 0, column: 9))
    }

    // MARK: - A log

    @Test("A selection in a log stays as lines are appended below it, and moves down with lines put in above it")
    func logLines() {
        var text = "line 1\nline 2\nline 3\n"
        let handler = TextEditorHandler(focusID: "editor", text: Binding(get: { text }, set: { text = $0 }))
        select(7..<13, in: handler)
        text += "line 4\nline 5\n"
        handler.clampCursor()
        #expect(handler.selectionOffsets == 7..<13, "appended below: kept")
        text = "line 0\n" + text
        handler.clampCursor()
        #expect(handler.selectionOffsets == 14..<20, "put in above: moved down a line")
        #expect(handler.selectionAnchor == TextEditorPosition(line: 2, column: 0))
        #expect(handler.cursor == TextEditorPosition(line: 2, column: 6))
    }

    @Test("A line put in above the first line selected moves it down, though its text starts like the new line's")
    func lineAboveSharingItsStart() {
        // "L0\n" + "L1…" reads, byte by byte, as "0\nL" put in after the first
        // "L" — inside the selection — unless placed where it leaves it be.
        var text = "L1\nL2\n"
        let handler = TextEditorHandler(focusID: "editor", text: Binding(get: { text }, set: { text = $0 }))
        select(0..<2, in: handler)
        text = "L0\n" + text
        handler.clampCursor()
        #expect(handler.selectionOffsets == 3..<5)
    }

    @Test("A caret at the end of a log follows the lines appended to it")
    func caretAtEndFollows() {
        var text = "line 1\n"
        let handler = TextEditorHandler(focusID: "editor", text: Binding(get: { text }, set: { text = $0 }))
        select(7..<7, in: handler)
        text += "line 2\n"
        handler.clampCursor()
        #expect(handler.cursor == TextEditorPosition(line: 2, column: 0))
    }

    // MARK: - A block

    @Test("A block stays as text is appended below it, moves down with lines put in above it, and goes when an edit reaches it")
    func block() {
        var text = "a\nbbbb\ncccc\nd"
        let handler = TextEditorHandler(focusID: "editor", text: Binding(get: { text }, set: { text = $0 }))
        let block = TextEditorBlock(anchor: CellPoint(x: 1, y: 1), head: CellPoint(x: 3, y: 2))
        handler.block = block
        text += "\ne"
        handler.clampCursor()
        #expect(handler.block == block, "appended below: kept")
        text = "z\nz\n" + text
        handler.clampCursor()
        #expect(handler.block?.rows == 3...4, "two lines put in above: moved down two rows")
        #expect(handler.block?.columns == 1..<3)
        text = text.replacingOccurrences(of: "cccc", with: "cXcc")
        handler.clampCursor()
        #expect(handler.block == nil, "an edit in its lines: gone")
        #expect(handler.cursor == TextEditorPosition(line: 4, column: 2), "a caret at the end of what the edit put in")
    }

    // MARK: - The editor's own edits

    @Test("A binding that formats what is typed leaves the caret after the character typed")
    func formattingBinding() {
        var digits = "123"
        let binding = Binding(
            get: { digits.count > 3 ? digits.prefix(3) + "-" + digits.dropFirst(3) : digits },
            set: { digits = $0.filter(\.isNumber) })
        let handler = TextFieldHandler(focusID: "field", text: binding)
        handler.insertCharacter("4")
        handler.clampCursorPosition()
        #expect(binding.wrappedValue == "123-4")
        #expect(handler.cursorPosition == 5, "after the 4, not between the hyphen and it")
    }

    @Test("Typing into an editor carries nothing: its own writes are not the app's")
    func typingIsNotAnAppEdit() {
        var text = "abc"
        let handler = TextEditorHandler(focusID: "editor", text: Binding(get: { text }, set: { text = $0 }))
        select(1..<1, in: handler)
        _ = handler.handleKeyEvent(KeyEvent(key: .character("X")))
        handler.clampCursor()
        #expect(text == "aXbc")
        #expect(handler.selectionOffsets == 2..<2)
        #expect(handler.selectionText == text)
    }

    // MARK: - Helpers

    private func select(_ range: Range<Int>, in handler: TextEditorHandler) {
        let layout = handler.layout()
        handler.selectionAnchor = range.isEmpty ? nil : layout.position(ofCharacter: range.lowerBound)
        handler.cursor = layout.position(ofCharacter: range.upperBound)
    }
}
