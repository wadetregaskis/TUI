//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+CursorRow.swift
//
//  The focus cursor of a `List` or `Table` stays on its row when the rows
//  change under it. The cursor is a row INDEX, so a row inserted above it, one
//  removed above it, a sort or a branch opened above it left the index where it
//  was and the cursor on another row — the one Space, Return and Delete then
//  acted on. In SwiftUI the cursor is the selection, which an id names, so it
//  never leaves its row; here it follows its row by id the same way.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension ItemListHandler {
    /// Puts the cursor back on the row it stood on last frame, found by its id,
    /// when the rows changed under it. Render pass only, after ``holdTopRow()``
    /// (which shifts the cursor by as much as the top row moved, right for a
    /// change above the screen and wrong for one between the top row and the
    /// cursor, or for a sort) and before the anchor, whose Bottom follow may
    /// carry the cursor on to a newer row.
    ///
    /// Left alone:
    /// - a cursor the user, or the list itself, moved since the last frame
    ///   (`cursorBefore`, read before the hold, is not where it was drawn): the
    ///   move put it where it is meant to be;
    /// - a move of the list's own still on its way to the data
    ///   (`ownMovePending`): the cursor is already where the moved row will be;
    /// - a row that is gone — deleted, or its id changed — whose place the row
    ///   after it takes, as it did before.
    ///
    /// Costs one id read on a frame whose rows did not change under the cursor
    /// (``rememberCursorRow(checked:)`` reuses it), and on one whose did, a
    /// search outward from the cursor (``index(of:near:)``).
    ///
    /// - Parameters:
    ///   - cursorBefore: ``focusedIndex`` as this frame began, before the hold.
    ///   - ownMovePending: Whether a move of the list's own was awaited as this
    ///     frame began (``movedRowsPendingFrames``, before the hold spent it).
    /// - Returns: The index and id this read, for ``rememberCursorRow(checked:)``.
    func followCursorRow(from cursorBefore: Int, ownMovePending: Bool) -> (index: Int, id: SelectionValue?) {
        let current = id(at: focusedIndex)
        guard let remembered = cursorRowID, cursorBefore == cursorRowOrdinal, !ownMovePending,
            current != remembered, let found = index(of: remembered, near: focusedIndex)
        else { return (focusedIndex, current) }
        // The Bottom follow tells its own cursor from one the user moved by its
        // index: it moves with the row it named.
        if bottomFollowCursor == focusedIndex { bottomFollowCursor = found }
        focusedIndex = found
        return (found, remembered)
    }

    /// Remembers the cursor's row for the next frame's
    /// ``followCursorRow(from:ownMovePending:)``, after everything this frame
    /// does to the cursor. Reads no id when the cursor is still where
    /// `checked` read it.
    func rememberCursorRow(checked: (index: Int, id: SelectionValue?)) {
        cursorRowOrdinal = focusedIndex
        guard movedRowsPendingFrames == 0 else {
            // The rows the list moved have not reached the data: the cursor
            // stands where its row will be, on another row until then.
            cursorRowID = nil
            return
        }
        cursorRowID = focusedIndex == checked.index ? checked.id : id(at: focusedIndex)
    }
}
