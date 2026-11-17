//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+CursorPlacement.swift
//
//  A cursor on no row. Under `.selectionFollowsCursor()` a list's cursor is
//  its selection, as a macOS list's is, so with nothing selected and nothing
//  having placed it, it is on none: no row is drawn as the cursor's, Down
//  selects the first row, Up the last, a typed letter the first row it names
//  (`Tools/SwiftUIProbes/Scroll to a row/firstkey.out`). It started on row 0,
//  so the first Down selected row 1 and the first row's letter skipped it.
//  What places it is on ``ItemListHandler/cursorIsPlaced``. The keys that act
//  on the cursor's row — Space, Return, Delete, a tree's Left and Right, the
//  row menu, the swipe and reorder keys — act on none from there, as a macOS
//  list's do with nothing selected: the row they would have acted on is not
//  drawn as the cursor's, and Delete took it away unseen.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension ItemListHandler {
    /// Whether the cursor is on no row: under `.selectionFollowsCursor()`,
    /// with nothing having placed it since the list began or since the app
    /// emptied the selection (``cursorIsPlaced``). Without the modifier the
    /// cursor is apart from the selection, and always on a row (V2).
    var cursorIsUnplaced: Bool { selectionFollowsCursor && !cursorIsPlaced }

    /// The cursor as a key finds it, for ``followCursor(from:)`` and type
    /// select: `nil` when it is on no row.
    var cursorBeforeKey: Int? { cursorIsUnplaced ? nil : focusedIndex }

    /// Up or Down from no row: comes into the list from outside it, Down from
    /// above onto the first row the cursor may land on and Up from below onto
    /// the last, and brings it into view — from wherever the wheel left the
    /// rows, as a macOS list scrolls back.
    func enterFromOutside(movingDown: Bool) {
        interruptGlide()
        let row = movingDown ? firstLandableRow(orElse: 0) : lastLandableRow(orElse: itemCount - 1)
        guard let row else { return }
        focusedIndex = row
        ensureFocusedItemVisible()
    }
}
