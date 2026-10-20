//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+Wheel.swift
//
//  The mouse wheel over a text editor: it scrolls the text and leaves the
//  caret where it is, as an NSTextView's does, until a key or a click brings
//  the view back to it (decisions B62).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

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
            (scrollLine, scrollRowInLine) = rows.location(ofRow: moved)
        } else {
            let moved = max(0, min(scrollLine + delta, readLines().count - height))
            guard moved != scrollLine else { return false }
            scrollLine = moved
        }
        isWheelScrolled = true
        return true
    }

    /// Keeps a wheel-scrolled top row in range — the text may have shrunk
    /// under it — without moving it to the caret.
    func clampWheelScroll(rowCount: Int, height: Int, in rows: WrappedRows?) {
        guard let rows else {
            scrollLine = max(0, min(scrollLine, rowCount - height))
            return
        }
        let top = max(0, min(topRow(in: rows), rowCount - height))
        (scrollLine, scrollRowInLine) = rows.location(ofRow: top)
    }
}
