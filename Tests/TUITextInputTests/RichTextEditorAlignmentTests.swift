//  🖥️ TUI — A Terminal UI framework for Swift
//  RichTextEditorAlignmentTests.swift
//
//  An attributed `TextEditor`'s paragraph alignment (G3 L4, the owner's ruling
//  A-ATTRED-3 of 2026-11-17): a centred or right-aligned paragraph's rows are
//  drawn after blank cells, and the caret, a click and the vertical keys map
//  through them, wrapping or scrolling sideways. Each case runs through
//  SwiftUI's `alignment` where it exists (macOS 26 on a Mac) and TUI's
//  `paragraphAlignment` everywhere (the owner's ruling attralign, 2026-11-19).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("Text editor over an attributed string: paragraph alignment")
struct RichTextEditorAlignmentTests {
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    /// An editor 12 cells wide over `text`, rendered once: its handler, and a
    /// render's stripped rows.
    private func editor(
        _ text: Box<AttributedString>, wraps: Bool = true
    ) -> (handler: TextEditorHandler, render: () -> [String]) {
        let context = makeRenderContext(width: 12, height: 4)
        let view = TextEditor(text: text.binding).textEditorWrapsLines(wraps).frame(width: 12, height: 4)
        _ = renderToBuffer(view, context: context)
        let handler = context.environment.focusManager!.activeSection!.focusables
            .compactMap { $0 as? TextEditorHandler }.first!
        return (handler, { renderToBuffer(view, context: context).lines.map(\.stripped) })
    }

    /// "alpha" over "hi", the second paragraph aligned `side`.
    private func twoParagraphs(_ side: TextAlignment, _ spelling: ParagraphAlignmentSpelling) -> Box<AttributedString> {
        var string = AttributedString("alpha\nhi")
        spelling.align(&string, string.range(of: "hi")!, side)
        return Box(string)
    }

    @Test(
        "A centred or right-aligned paragraph's row is drawn after blank cells; the caret's margin is kept",
        arguments: ParagraphAlignmentSpelling.available)
    func drawn(_ spelling: ParagraphAlignmentSpelling) {
        // 12 cells, the last the caret's margin: "hi" centred in 11 starts at
        // (11 - 2) / 2 = 4, right-aligned at 9.
        let centred = editor(twoParagraphs(.center, spelling)).render()
        #expect(centred[0].hasPrefix("alpha "))
        #expect(centred[1].hasPrefix("    hi "), "'\(centred[1])'")
        let right = editor(twoParagraphs(.trailing, spelling)).render()
        #expect(right[1].hasPrefix("         hi "), "'\(right[1])'")
        let left = editor(twoParagraphs(.leading, spelling)).render()
        #expect(left[1].hasPrefix("hi "), "'\(left[1])'")
    }

    @Test(
        "The terminal's cursor parks on the caret's cell after the row's blank cells",
        arguments: ParagraphAlignmentSpelling.available)
    func caretCell(_ spelling: ParagraphAlignmentSpelling) {
        let drawn = editor(twoParagraphs(.center, spelling))
        drawn.handler.moveCursor(toLine: 1, column: 1)
        _ = drawn.render()
        #expect(drawn.handler.insertionPoint == CellPoint(x: 5, y: 1))
    }

    @Test(
        "A click lands on the character drawn under it, and one in the blank cells on the row's start",
        arguments: ParagraphAlignmentSpelling.available)
    func click(_ spelling: ParagraphAlignmentSpelling) throws {
        let drawn = editor(twoParagraphs(.center, spelling))
        let rows = try #require(drawn.handler.wrappedRows())
        // "hi" is drawn in cells 4 and 5.
        let columns = [5, 1, 9].map { drawn.handler.position(atScreenRow: 1, column: $0, in: rows) }
        #expect(columns.map(\.line) == [1, 1, 1])
        #expect(columns.map(\.column) == [1, 0, 2])
    }

    @Test("Up and Down keep the column across the screen, not in the row", arguments: ParagraphAlignmentSpelling.available)
    func verticalKeys(_ spelling: ParagraphAlignmentSpelling) {
        let drawn = editor(twoParagraphs(.center, spelling))
        // After "alph": column 4 across the screen, which is before "h" below.
        drawn.handler.moveCursor(toLine: 0, column: 4)
        _ = drawn.render()
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(drawn.handler.cursorLine == 1 && drawn.handler.cursorColumn == 0)
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .right))
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(drawn.handler.cursorLine == 0 && drawn.handler.cursorColumn == 5, "column 5 across: after \"alpha\"")
    }

    @Test(
        "Scrolling sideways, a line narrower than the editor is aligned, and a click and the keys map through it",
        arguments: ParagraphAlignmentSpelling.available)
    func sideways(_ spelling: ParagraphAlignmentSpelling) {
        let drawn = editor(twoParagraphs(.trailing, spelling), wraps: false)
        let rows = drawn.render()
        #expect(rows[1].hasPrefix("         hi"), "'\(rows[1])'")
        drawn.handler.moveCursor(toLine: 1, column: 0)
        _ = drawn.render()
        #expect(drawn.handler.insertionPoint == CellPoint(x: 9, y: 1))
        // Up from before "h" (column 9 across) goes to the end of "alpha".
        _ = drawn.handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(drawn.handler.cursorLine == 0 && drawn.handler.cursorColumn == 5)
    }

    @Test(
        "Typing into an aligned paragraph keeps it aligned, and a new paragraph split from it takes it",
        arguments: ParagraphAlignmentSpelling.available)
    func typing(_ spelling: ParagraphAlignmentSpelling) {
        let text = twoParagraphs(.center, spelling)
        let drawn = editor(text)
        drawn.handler.moveCursor(toLine: 1, column: 2)
        for key: Key in [.character("!"), .enter, .character("x")] {
            _ = drawn.handler.handleKeyEvent(KeyEvent(key: key))
        }
        #expect(String(text.value.characters) == "alpha\nhi!\nx")
        let rows = drawn.render()
        #expect(rows[1].hasPrefix("    hi! "), "'\(rows[1])'")
        #expect(rows[2].hasPrefix("     x "), "'\(rows[2])'")
    }
}
