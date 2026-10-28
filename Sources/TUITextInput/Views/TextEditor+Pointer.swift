//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+Pointer.swift
//
//  Where the pointer is in a TextEditor's text: a buffer-local cell mapped
//  through the scroll offsets in effect for the frame drawn, for the editor's
//  mouse handler.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

/// Maps the pointer's cell in a ``TextEditor``'s drawn frame to its text.
///
/// The trailing scrollbar column (when present) clamps into the last content
/// column. The click lands in DISPLAY space; the handler's cursor is a
/// character index, so it is translated through the clicked line's tab layout
/// (a click anywhere in a tab's span puts the caret on the tab).
@MainActor
struct EditorPointer {
    let handler: TextEditorHandler
    let contentWidth: Int
    let height: Int
    let tabWidth: TabWidth

    /// The grid cell under the pointer, for a block: on a drawn row, and up
    /// to the column after the last drawn one.
    func gridPoint(_ event: MouseEvent) -> CellPoint {
        handler.gridPoint(atScreenRow: max(0, min(event.y, height - 1)), column: max(0, min(event.x, contentWidth)))
    }

    /// Puts the caret where `event` landed.
    ///
    /// `asSelectionEnd`: the event ends a selection — a drag's head, a
    /// Shift-click — whose end may be a wrapped row's first character under
    /// `.upstream`, where a caret cannot be.
    func placeCursor(at event: MouseEvent, asSelectionEnd: Bool = false) {
        let row = max(0, min(event.y, height - 1))
        handler.rowStartHead = nil
        // Wrapping, a click lands in a ROW: on the character whose cells
        // hold it, or past the row's text on its last caret position.
        if let rows = handler.wrappedRows() {
            let column = max(0, min(event.x, contentWidth - 1))
            if asSelectionEnd {
                handler.placeSelectionHead(atScreenRow: row, column: column, in: rows)
            } else {
                let position = handler.position(atScreenRow: row, column: column, in: rows)
                handler.moveCursor(toLine: position.line, column: position.column)
            }
            return
        }
        // Valid content columns are 0..<contentWidth: clamping to
        // `contentWidth` put a scrollbar-column click one display column
        // PAST the window's right edge, so on a long line the caret
        // landed on the first off-screen character and followCursor
        // immediately scrolled the text one column right — a scrollbar
        // click that horizontally scrolled the editor.
        let displayColumn =
            handler.scrollColumn + max(0, min(event.x, contentWidth - 1))
        let line = handler.scrollLine + row
        let allLines = handler.readLines()
        let lineChars = allLines.indices.contains(line) ? allLines[line] : []
        let column = TabLayout.charIndex(
            forDisplayColumn: displayColumn, in: lineChars, tabWidth: tabWidth)
        handler.moveCursor(toLine: line, column: column)
    }

    /// What a plain left press at `event` does to the caret and the
    /// selection: an Option-press starts a block, a Shift-press extends the
    /// selection, a double- or triple-click selects a word or a line, and any
    /// other press puts the caret down and drops the selection.
    func press(_ event: MouseEvent) {
        if event.meta {
            // Option-drag (⌘-drag in iTerm2): a block, from here.
            placeCursor(at: event)
            handler.beginBlock(at: gridPoint(event), shift: event.shift)
        } else if event.shift {
            handler.pressAnchor = nil
            handler.startOrExtendSelection()
            placeCursor(at: event, asSelectionEnd: true)
        } else if let granularity = TextSelectionGranularity(clickCount: event.clickCount) {
            // A double-click selects the word clicked, a triple-click
            // the line; a drag after either extends by them.
            placeCursor(at: event)
            handler.selectRun(granularity, around: handler.cursor)
        } else {
            // Plain click: place the caret and drop any selection. Do
            // NOT anchor here — a collapsed anchor (anchor == cursor)
            // shows no highlight but survives into a phantom one-char
            // selection on the next arrow key. A drag anchors itself on
            // its first .dragged event (startOrExtendSelection below),
            // where the press landed as a selection's end: wrapping,
            // that can be a row's first character the caret is not on.
            placeCursor(at: event)
            handler.clearSelection()
            handler.pressAnchor = handler.wrappedRows().map { rows in
                handler.selectionPosition(
                    atScreenRow: max(0, min(event.y, height - 1)),
                    column: max(0, min(event.x, contentWidth - 1)), in: rows)
            }
        }
    }
}
