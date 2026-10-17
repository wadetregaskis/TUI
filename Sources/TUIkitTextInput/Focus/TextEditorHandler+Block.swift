//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+Block.swift
//
//  A rectangular selection in a TextEditor — an Option-drag's: the same
//  columns of every row it spans, copied as those columns' text, row by row.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// A rectangular selection in a ``TextEditor``: the columns between two
/// corners, on every row between them.
///
/// In the editor's grid of rows: where it wraps, its rows (`WrappedRows`) and
/// the cells across each; where it scrolls sideways, its lines and their
/// display columns, unscrolled. The corners are between cells, as a caret is:
/// a drag from column 2 to column 5 takes columns 2, 3 and 4.
struct TextEditorBlock: Equatable {
    /// The corner that stays where it is.
    var anchor: CellPoint
    /// The corner the pointer moves.
    var head: CellPoint
    /// Whether Shift was held at the drag's last step: the corners swap roles
    /// each time it goes down or comes up, as a screen selection's do.
    var shiftHeld = false
    /// The moving corner's distance from the pointer, since the last swap.
    var pointerOffset = CellPoint.zero

    /// The rows it spans.
    var rows: ClosedRange<Int> { min(anchor.y, head.y)...max(anchor.y, head.y) }

    /// The columns it takes of each row; empty while both corners are in one
    /// column.
    var columns: Range<Int> { min(anchor.x, head.x)..<max(anchor.x, head.x) }
}

extension TextEditorHandler {
    /// The grid cell (``TextEditorBlock``) under a point of the editor,
    /// `row` and `column` counted from its top-left on screen.
    func gridPoint(atScreenRow row: Int, column: Int) -> CellPoint {
        if let rows = wrappedRows() {
            return CellPoint(x: max(0, column), y: min(max(0, topRow(in: rows) + row), max(0, rows.rowCount - 1)))
        }
        let lineCount = readLines().count
        return CellPoint(x: max(0, scrollColumn + column), y: min(max(0, scrollLine + row), lineCount - 1))
    }

    /// Starts a block at `point`, a grid cell, in place of any selection.
    func beginBlock(at point: CellPoint, shift: Bool) {
        clearSelection()
        block = TextEditorBlock(anchor: point, head: point, shiftHeld: shift)
    }

    /// Moves the block's moving corner to the grid cell under the pointer,
    /// `point` — swapping which corner that is when Shift has gone down or
    /// come up since the last step. The swap itself moves nothing: the corner
    /// the pointer takes over keeps its distance from it.
    func extendBlock(to point: CellPoint, shift: Bool) {
        guard var current = block else { return }
        if shift != current.shiftHeld {
            current.shiftHeld = shift
            swap(&current.anchor, &current.head)
            current.pointerOffset = CellPoint(x: current.head.x - point.x, y: current.head.y - point.y)
        }
        let lastRow = wrappedRows().map { max(0, $0.rowCount - 1) } ?? (readLines().count - 1)
        current.head = CellPoint(
            x: max(0, point.x + current.pointerOffset.x),
            y: min(max(0, point.y + current.pointerOffset.y), lastRow))
        block = current
    }

    /// Ends the drag making the block: one that took no column is a click,
    /// and selects nothing.
    func finishBlock() {
        if block?.columns.isEmpty == true { block = nil }
    }

    /// The cells of grid row `row` the block highlights, or `nil` where it
    /// highlights none.
    func blockCells(onRow row: Int) -> Range<Int>? {
        guard let block, block.rows.contains(row), !block.columns.isEmpty else { return nil }
        return block.columns
    }

    /// The characters of each row `block` spans that start inside its
    /// columns: the row's line, and the character offsets in it.
    func blockSpans(_ block: TextEditorBlock) -> [(line: Int, characters: Range<Int>)] {
        let columns = block.columns
        guard !columns.isEmpty else { return [] }
        if let rows = wrappedRows() {
            return block.rows.compactMap { row in
                guard row < rows.rowCount else { return nil }
                let (line, rowInLine) = rows.location(ofRow: row)
                let layout = rows.lines[line]
                let span = layout.rows[rowInLine]
                let inside = (span.start..<span.end).filter { columns.contains(layout.cells(inRow: rowInLine, before: $0)) }
                return (line, (inside.first ?? span.start)..<((inside.last ?? span.start - 1) + 1))
            }
        }
        let lines = readLines()
        return block.rows.compactMap { line in
            guard line < lines.count else { return nil }
            let characters = lines[line]
            let inside = characters.indices.filter {
                columns.contains(TabLayout.displayColumn(ofCharIndex: $0, in: characters, tabWidth: tabWidth))
            }
            return (line, (inside.first ?? 0)..<((inside.last ?? -1) + 1))
        }
    }

    /// The block's text: each row's characters inside its columns, the rows
    /// joined by line breaks.
    func blockText(_ block: TextEditorBlock) -> String {
        let lines = readLines()
        return blockSpans(block)
            .map { String(lines[$0.line][$0.characters]) }
            .joined(separator: "\n")
    }

    /// Takes the block's characters out of every row it spans, leaves the
    /// caret where its top-left corner was, and drops it.
    func deleteBlock(_ block: TextEditorBlock) {
        var lines = readLines()
        let spans = blockSpans(block)
        // Last first, so each removal leaves the offsets of the ones still to
        // make where they were: a wrapped line's rows come in order.
        for span in spans.reversed() where !span.characters.isEmpty {
            lines[span.line].removeSubrange(span.characters)
        }
        if let first = spans.first {
            cursorLine = first.line
            cursorColumn = min(first.characters.lowerBound, lines[first.line].count)
        }
        self.block = nil
        selectionAnchor = nil
        writeLines(lines)
        syncDesiredColumn(lines)
    }
}
