//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Selection.swift
//
//  A text editor's selection: the cursor as a position, the selected span,
//  and selecting, clearing and deleting it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Selection

/// A normalized selection span: `start` is at or before `end`.
typealias SelectionSpan = (start: TextEditorPosition, end: TextEditorPosition)

extension TextEditorHandler {
    /// The cursor as a position value.
    var cursor: TextEditorPosition {
        get { TextEditorPosition(line: cursorLine, column: cursorColumn) }
        set {
            cursorLine = newValue.line
            cursorColumn = newValue.column
        }
    }

    /// The normalized selection span (start ≤ end), or nil when empty.
    var selectionRange: SelectionSpan? {
        guard let anchor = selectionAnchor, anchor != cursor else { return nil }
        return anchor < cursor ? (anchor, cursor) : (cursor, anchor)
    }

    /// Selects the whole document — Option-Ctrl-A.
    ///
    /// The empty guard mirrors `TextFieldHandler.selectAll()`, and it is
    /// load-bearing rather than tidy: `normalizeStaleState()` drops any anchor
    /// that sits on the cursor, so selecting "all" of an empty document would
    /// leave a phantom anchor behind for the next keystroke to trip over.
    func selectAll() {
        let lines = readLines()
        guard !(lines.count == 1 && lines[0].isEmpty) else { return }
        block = nil
        selectionAnchor = TextEditorPosition(line: 0, column: 0)
        cursorLine = lines.count - 1
        cursorColumn = lines[cursorLine].count
        syncDesiredColumn(lines)
    }

    /// Drops the selection, and a block, without moving the cursor.
    func clearSelection() {
        selectionAnchor = nil
        block = nil
    }

    /// Anchors a selection at `start` — a drag's press (``pressAnchor``) — or
    /// at the cursor if none exists (drag / Shift-click), leaving an existing
    /// anchor in place.
    func startOrExtendSelection(from start: TextEditorPosition? = nil) {
        guard selectionAnchor == nil else { return }
        guard let start else {
            selectionAnchor = cursor
            return
        }
        let lines = readLines()
        let line = min(max(0, start.line), lines.count - 1)
        selectionAnchor = TextEditorPosition(line: line, column: min(max(0, start.column), lines[line].count))
    }

    /// Positions the cursor at a clicked point, clamped into the text. Used by
    /// the mouse handler; leaves any selection anchor untouched (so a drag
    /// extends from it).
    func moveCursor(toLine line: Int, column: Int) {
        let lines = readLines()
        cursorLine = min(max(0, line), lines.count - 1)
        cursorColumn = min(max(0, column), lines[cursorLine].count)
        // Vertical motion after a click should keep the clicked column, so sync
        // the preferred column like the keyboard motion methods do.
        syncDesiredColumn()
    }

    /// The selected column range within `lineIndex` (whose length is
    /// `lineLength`), or nil if the line carries no selection. Interior lines of
    /// a multi-line selection return their whole width.
    func selectedColumns(inLine lineIndex: Int, lineLength: Int) -> Range<Int>? {
        guard let span = textDrag?.span ?? selectionRange, lineIndex >= span.start.line, lineIndex <= span.end.line
        else { return nil }
        let lo = lineIndex == span.start.line ? span.start.column : 0
        let hi = lineIndex == span.end.line ? span.end.column : lineLength
        let clampedLo = max(0, min(lo, lineLength))
        let clampedHi = max(0, min(hi, lineLength))
        return clampedLo < clampedHi ? clampedLo..<clampedHi : nil
    }

    /// `span` clamped into `lines`: each end on a real line, at a real column.
    /// A corrupt span's clamped columns can come out inverted on one line;
    /// the callers order them.
    func clamped(_ span: SelectionSpan, in lines: [[Character]]) -> SelectionSpan {
        let startLine = min(max(0, span.start.line), lines.count - 1)
        let endLine = min(max(0, span.end.line), lines.count - 1)
        return (
            TextEditorPosition(
                line: startLine, column: min(max(0, span.start.column), lines[startLine].count)),
            TextEditorPosition(
                line: endLine, column: min(max(0, span.end.column), lines[endLine].count))
        )
    }

    /// Removes the selected text, placing the cursor at the span's start and
    /// clearing the selection.
    func deleteSelection(_ span: SelectionSpan) {
        var lines = readLines()
        let (start, end) = clamped(span, in: lines)
        let startLine = start.line
        let endLine = end.line
        let startColumn = start.column
        let endColumn = end.column
        if startLine == endLine {
            // The per-line clamps can invert a corrupt span's columns once its
            // lines collapse together; an inverted range must not trap.
            lines[startLine].removeSubrange(min(startColumn, endColumn)..<max(startColumn, endColumn))
        } else {
            let head = Array(lines[startLine][..<startColumn])
            let tail = Array(lines[endLine][endColumn...])
            lines[startLine] = head + tail
            lines.removeSubrange((startLine + 1)...endLine)
        }
        cursorLine = startLine
        cursorColumn = startColumn
        // NOT `desiredColumn = startColumn`: that is a character index, and
        // the field is DISPLAY space. On a prefix holding a tab or a wide
        // character the two differ, so Backspace over a drag selection and
        // then Down / Page Down read the index as a screen column — "\tabc"
        // minus "ab" left the caret on screen column 4 and sent Down to
        // column 1. `lines` is already the post-delete array, and `startLine`
        // indexes it in both branches, so no re-read.
        syncDesiredColumn(lines)
        selectionAnchor = nil
        writeLines(lines)
    }
}
