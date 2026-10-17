//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+Wrapping.swift
//
//  A wrapping editor's caret and scroll, by row: its document's lines are
//  paragraphs, each laid out in rows (`WrappedRows`), and the vertical keys
//  move between rows as an NSTextView's do.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension TextEditorHandler {
    /// The document's rows at the width the editor last drew at, or `nil`
    /// where it scrolls sideways (``View/textEditorWrapsLines(_:)``).
    func wrappedRows() -> WrappedRows? {
        guard let wrapWidth else { return nil }
        return layout().wrapped(width: wrapWidth, tabWidth: tabWidth)
    }

    /// The row the caret is drawn on, among all of them, by its affinity.
    func caretRow(in rows: WrappedRows) -> Int {
        rows.row(ofLine: cursorLine, column: cursorColumn, affinity: caretAffinity)
    }

    /// The affinity the caret's row is read by: the editor's, except for a
    /// selection's head the pointer put on a wrapped row's first character
    /// (``rowStartHead``), which is read on that row.
    var caretAffinity: TextSelectionAffinity {
        rowStartHead == cursor ? .downstream : selectionAffinity
    }

    /// The caret's column in its row: what Up and Down keep.
    func caretColumnInRow(in rows: WrappedRows) -> Int {
        let (line, rowInLine) = rows.location(ofRow: caretRow(in: rows))
        return rows.lines[line].column(of: cursorColumn, inRow: rowInLine)
    }

    /// Ends ``rowStartHead``'s reading once a key has moved the head off
    /// the row start the pointer put it on, or left it the end of no
    /// selection: an offset the keys come back to is read by the caret rule,
    /// and so is a plain caret, by the editor's affinity like every other.
    /// (The editor has no keyboard selection, so after any key this ends it.)
    func forgetMovedRowStartHead() {
        if rowStartHead != cursor || selectionRange == nil { rowStartHead = nil }
    }

    /// The top row on screen, among all of them.
    func topRow(in rows: WrappedRows) -> Int {
        rows.row(line: scrollLine, rowInLine: scrollRowInLine)
    }

    /// Moves the caret `delta` rows, keeping the column it was asked to keep
    /// through short rows, as an `NSTextView` does (measured on macOS 15.8):
    /// Up from the first row goes to the start of the text, Down from the last
    /// to its end. The caret lands on an offset the editor's affinity draws on
    /// the row it moved to (``SoftWrapLayout/offset(inRow:atColumn:affinity:)``):
    /// downstream, a row that wrapped keeps it before its last character,
    /// whose end is drawn on the next row; upstream, a row that continues a
    /// paragraph keeps it after its first, whose start is drawn on the row
    /// before.
    ///
    /// - Parameter pastTheEnds: Whether a motion past the first or last row
    ///   goes to the text's start or end — the arrows' and Ctrl-P's and N's,
    ///   not a page's, which stops at the first or last row.
    func moveByRows(_ delta: Int, in rows: WrappedRows, pastTheEnds: Bool) {
        let target = caretRow(in: rows) + delta
        guard target >= 0, target < rows.rowCount else {
            guard pastTheEnds else {
                moveToRow(min(max(0, target), rows.rowCount - 1), in: rows)
                return
            }
            let lines = readLines()
            cursorLine = target < 0 ? 0 : lines.count - 1
            cursorColumn = target < 0 ? 0 : lines[cursorLine].count
            syncDesiredColumn(lines)
            return
        }
        moveToRow(target, in: rows)
    }

    /// Puts the caret on `row`, at the column it keeps — an offset whose caret
    /// the editor's affinity draws on that row, which ``caretRow(in:)`` reads
    /// back by the same affinity.
    private func moveToRow(_ row: Int, in rows: WrappedRows) {
        let (line, rowInLine) = rows.location(ofRow: row)
        cursorLine = line
        cursorColumn = rows.lines[line].offset(
            inRow: rowInLine, atColumn: desiredColumn, affinity: selectionAffinity)
    }

    /// Keeps the caret's row on screen, moving the top row as little as it
    /// must, and never past the last screenful.
    ///
    /// The top is kept as a line and a row within it, not as a row, so a
    /// change of width — a resize, the scroll bar's column arriving — keeps the
    /// top paragraph where it was rather than the row number.
    func followCaretRow(in rows: WrappedRows, height: Int) {
        var top = topRow(in: rows)
        let caret = caretRow(in: rows)
        if caret < top {
            top = caret
        } else if caret >= top + height {
            top = caret - height + 1
        }
        top = max(0, min(top, max(0, rows.rowCount - height)))
        (scrollLine, scrollRowInLine) = rows.location(ofRow: top)
        scrollColumn = 0
    }

    /// The caret position a click at `column` of the on-screen `row` lands
    /// on: before the character whose cells hold the column, or the row's last
    /// caret offset past its text.
    func position(atScreenRow row: Int, column: Int, in rows: WrappedRows) -> (line: Int, column: Int) {
        let (line, rowInLine) = rows.location(ofRow: topRow(in: rows) + row)
        return (line, rows.lines[line].offset(inRow: rowInLine, atColumn: column, affinity: selectionAffinity))
    }

    /// The position a selection's end takes at `column` of the on-screen
    /// `row` — a drag's start and its head, a Shift-click's end: as
    /// ``position(atScreenRow:column:in:)``, but a wrapped row's first
    /// character is reachable under `.upstream` too
    /// (``SoftWrapLayout/selectionOffset(inRow:atColumn:affinity:)``).
    func selectionPosition(atScreenRow row: Int, column: Int, in rows: WrappedRows) -> TextEditorPosition {
        let (line, rowInLine) = rows.location(ofRow: topRow(in: rows) + row)
        let offset = rows.lines[line].selectionOffset(inRow: rowInLine, atColumn: column, affinity: selectionAffinity)
        return TextEditorPosition(line: line, column: offset)
    }

    /// Moves a selection's head — a drag's, a Shift-click's end — to
    /// ``selectionPosition(atScreenRow:column:in:)``, and reads it on the row
    /// the pointer put it on. Under `.upstream` that can be a wrapped row's
    /// first character, which the caret rule reads on the row before: the
    /// head is kept as ``rowStartHead`` while it stays there.
    func placeSelectionHead(atScreenRow row: Int, column: Int, in rows: WrappedRows) {
        let position = selectionPosition(atScreenRow: row, column: column, in: rows)
        rowStartHead = nil
        moveCursor(toLine: position.line, column: position.column)
        let onScreen = topRow(in: rows) + row
        guard rows.row(ofLine: cursorLine, column: cursorColumn, affinity: selectionAffinity) != onScreen,
            rows.row(ofLine: cursorLine, column: cursorColumn, affinity: .downstream) == onScreen
        else { return }
        rowStartHead = cursor
        syncDesiredColumn()
    }

    /// The cell the caret is on in the window a frame draws, whether or not a
    /// caret is drawn there, or `nil` where it is scrolled out of view — for
    /// the run loop to park the terminal's cursor on
    /// (``TextInputFocusHandler/insertionPoint``).
    ///
    /// - Parameters:
    ///   - column: The caret's display column: in its row where the
    ///     editor wraps (`rows`), in its line where it scrolls sideways.
    ///   - rows: The wrapped rows, or `nil` where the editor scrolls sideways.
    ///   - width: The columns the text is drawn in, a scroll bar's left out.
    ///   - height: The rows drawn.
    func drawnInsertionPoint(column: Int, rows: WrappedRows?, width: Int, height: Int) -> CellPoint? {
        let point =
            rows.map { CellPoint(x: column, y: caretRow(in: $0) - topRow(in: $0)) }
            ?? CellPoint(x: column - scrollColumn, y: cursorLine - scrollLine)
        guard (0..<width).contains(point.x), (0..<height).contains(point.y) else { return nil }
        return point
    }
}
