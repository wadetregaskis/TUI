//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Wheel.swift
//
//  The mouse wheel over a text editor: it scrolls the text and leaves the
//  caret where it is, as an NSTextView's does, until a key or a click brings
//  the view back to it (decisions B62).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TextEditorHandler {
    /// Scrolls the text `delta` rows (lines, where the editor scrolls
    /// sideways), down for a positive one, in a view `height` rows tall; the
    /// caret stays where it is, and the view stops following it
    /// (``isWheelScrolled``).
    ///
    /// - Returns: Whether the text moved. A tick that cannot — the text at
    ///   its end already, or no taller than the view — is not the editor's,
    ///   and goes on to a scroll view around it, as a list's does.
    func scrollByWheel(_ delta: Int, height: Int) -> Bool {
        if let rows = wrappedRows() {
            let top = topRow(in: rows)
            let moved = max(0, min(top + delta, rows.rowCount - height))
            guard moved != top else { return false }
            scroll(toRow: moved, in: rows)
        } else {
            let rows = sidewaysRows()
            let top = sidewaysTopRow(in: rows)
            let moved = max(0, min(top + delta, rows.rowCount - height))
            guard moved != top else { return false }
            scrollSideways(toRow: moved, in: rows)
        }
        isWheelScrolled = true
        return true
    }

    /// Keeps a wheel-scrolled top row in range — the text may have shrunk
    /// under it — without moving it to the caret.
    func clampWheelScroll(rowCount: Int, height: Int, in rows: WrappedRows?) {
        guard let rows else {
            let spaced = sidewaysRows()
            scrollSideways(toRow: max(0, min(sidewaysTopRow(in: spaced), rowCount - height)), in: spaced)
            return
        }
        let top = max(0, min(topRow(in: rows), rowCount - height))
        scroll(toRow: top, in: rows)
    }
}
