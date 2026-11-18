//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Alignment.swift
//
//  An attributed editor's paragraph alignment (G3 L4, the owner's ruling
//  A-ATTRED-3 of 2026-11-17): the blank cells a centred or right-aligned
//  paragraph puts in front of each of its rows, which the rows are drawn
//  after, and which the caret, a click, a drag, a block and the vertical keys
//  map through.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension TextEditorHandler {
    /// The alignment of `line`'s paragraph: the `alignment` of its first
    /// character, or of its newline where it is empty — the attribute is
    /// bounded by paragraphs, so every character of one states the same. `nil`
    /// for a `String` editor, a hidden text, and a paragraph that states none.
    /// Read once a line and kept with its styles until an edit changes it.
    func paragraphAlignment(ofLine line: Int) -> AttributedString.TextAlignment? {
        guard let source = attributedSource, !isSecure else { return nil }
        return lineStyleCache.alignment(ofLine: line) { line in
            let layout = layout()
            guard line < layout.characterStarts.count else { return nil }
            let value = source.value
            let start = layout.characterStarts[line]
            // Not `characters.count`, which may count them all.
            guard let index = value.characters.index(value.startIndex, offsetBy: start, limitedBy: value.endIndex),
                index < value.endIndex
            else { return nil }
            return value[index..<value.characters.index(after: index)].runs.first?.alignment
        }
    }

    /// The blank cells in front of `rowInLine` of `line` in a wrapping editor:
    /// its paragraph's alignment, within the cells a row's text may take (the
    /// width's last cell is the caret's margin), of the row's text less the
    /// spaces a wrap leaves hanging at its end.
    func alignmentCells(line: Int, rowInLine: Int, in rows: WrappedRows) -> Int {
        guard let alignment = paragraphAlignment(ofLine: line), alignment != .left else { return 0 }
        let layout = rows.lines[line]
        let span = layout.rows[rowInLine]
        var end = span.end
        if !span.endsParagraph {
            let characters = displayLayout().lines[line]
            while end > span.start, characters[end - 1] == " " || characters[end - 1] == "\t" { end -= 1 }
        }
        return alignment.leadingCells(lineWidth: layout.cells(inRow: rowInLine, before: end), in: rows.width - 1)
    }

    /// The blank cells in front of `row`, among all of a wrapping editor's
    /// rows; none past the last.
    func alignmentCells(ofRow row: Int, in rows: WrappedRows) -> Int {
        guard attributedSource != nil, row >= 0, row < rows.rowCount else { return 0 }
        let (line, rowInLine) = rows.location(ofRow: row)
        return alignmentCells(line: line, rowInLine: rowInLine, in: rows)
    }

    /// The blank cells in front of `line` in an editor that scrolls sideways:
    /// its paragraph's alignment within the editor's width less the caret's
    /// margin, where the line fits in that; none where it does not, which
    /// scrolls as any long line does.
    func alignmentCells(ofLine line: Int, characters: [Character]) -> Int {
        guard let width = sidewaysWidth, let alignment = paragraphAlignment(ofLine: line), alignment != .left
        else { return 0 }
        let cells = TabLayout.displayColumn(ofCharIndex: characters.count, in: characters, tabWidth: tabWidth)
        guard cells < width else { return 0 }
        return alignment.leadingCells(lineWidth: cells, in: width - 1)
    }

    /// The character of `line` of `lines` (as drawn) whose cells hold
    /// `column` across an editor that scrolls sideways, unscrolled: after the
    /// line's alignment, the column the vertical keys keep.
    func characterIndex(atColumn column: Int, inLine line: Int, of lines: [[Character]]) -> Int {
        let aligned = alignmentCells(ofLine: line, characters: lines[line])
        return TabLayout.charIndex(forDisplayColumn: max(0, column - aligned), in: lines[line], tabWidth: tabWidth)
    }

    /// ``alignmentCells(ofLine:characters:)`` of `line` as drawn.
    func sidewaysAlignmentCells(ofLine line: Int) -> Int {
        guard attributedSource != nil else { return 0 }
        let lines = displayLayout().lines
        return line < lines.count ? alignmentCells(ofLine: line, characters: lines[line]) : 0
    }

    /// The column the caret is drawn at across a wrapping editor: its column
    /// in its row, after the row's blank cells. What Up and Down keep.
    func caretScreenColumn(in rows: WrappedRows) -> Int {
        caretColumnInRow(in: rows) + alignmentCells(ofRow: caretRow(in: rows), in: rows)
    }
}
