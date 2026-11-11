//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+CursorRow.swift
//
//  The focus cursor of a `List` or `Table` stays on its row when the rows
//  change under it. The cursor is a row INDEX, so a row inserted above it, one
//  removed above it, a sort or a branch opened above it left the index where it
//  was and the cursor on another row — the one Space, Return and Delete then
//  acted on. In SwiftUI the cursor is the selection, which an id names, so it
//  never leaves its row; here it follows its row by id the same way. So does
//  the anchor a Shift-arrow or Shift-click range is measured from.
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

    /// Brings a cursor left past the last row back onto the rows: the rows
    /// under it went (the data shrank from outside, not by a delete of the
    /// list's own, which places the cursor itself), and with no row there,
    /// Space, Return and Delete did nothing and no row showed the focus. It
    /// lands on the last row the cursor can stand on, where a delete of the
    /// last row puts it. Render pass only, after
    /// ``followCursorRow(from:ownMovePending:)``.
    func keepCursorOnTheRows() {
        guard itemCount > 0, focusedIndex >= itemCount else { return }
        focusedIndex = min(itemCount - 1, lastLandingRow(orElse: itemCount - 1))
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

    /// Puts the range anchor (``selectionAnchor``) back on the row it stood on
    /// last frame, found by its id, when the rows changed under it — what
    /// ``followCursorRow(from:ownMovePending:)`` does for the cursor. The anchor
    /// is an index too, so a row arriving above it, or a sort, left it on
    /// another row, and the next Shift-Down selected a span from a row the user
    /// never chose. It runs on its own rather than off the cursor's check: a
    /// row inserted between the cursor and an anchor below it moves only the
    /// anchor's row.
    ///
    /// Left alone, as the cursor is: an anchor set since the last frame, a move
    /// of the list's own still on its way to the data, and a row that is gone,
    /// whose place the row after it takes.
    ///
    /// Costs nothing without an anchor, and one id read on a frame with one
    /// (``rememberAnchorRow(checked:)`` reuses it).
    ///
    /// - Parameter ownMovePending: Whether a move of the list's own was
    ///   awaited as this frame began.
    /// - Returns: The anchor and the id this read, for
    ///   ``rememberAnchorRow(checked:)``; `nil` with no anchor.
    func followAnchorRow(ownMovePending: Bool) -> (index: Int, id: SelectionValue?)? {
        guard let anchor = selectionAnchor else { return nil }
        let current = id(at: anchor)
        guard let remembered = anchorRowID, anchor == anchorRowOrdinal, !ownMovePending,
            current != remembered, let found = index(of: remembered, near: anchor)
        else { return (anchor, current) }
        selectionAnchor = found
        return (found, remembered)
    }

    /// Remembers the anchor's row for the next frame's
    /// ``followAnchorRow(ownMovePending:)``. Reads no id when the anchor is
    /// still where `checked` read it.
    func rememberAnchorRow(checked: (index: Int, id: SelectionValue?)?) {
        anchorRowOrdinal = selectionAnchor
        guard let anchor = selectionAnchor, movedRowsPendingFrames == 0 else {
            anchorRowID = nil
            return
        }
        anchorRowID = anchor == checked?.index ? checked?.id : id(at: anchor)
    }
}
