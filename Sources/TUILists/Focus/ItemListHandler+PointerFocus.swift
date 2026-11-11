//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+PointerFocus.swift
//
//  A list's cursor row following the pointer, while the focus follows it: the
//  part `List` and `Table` share. Each finds the row under the pointer its own
//  way and files the follower with the dispatcher
//  (`MouseEventDispatcher.filePointerFocusFollower(for:in:_:)`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension ItemListHandler {
    /// Puts the cursor on `row`, the row the pointer moved onto while the
    /// focus follows it and the list holds the focus, so the keys act where
    /// the pointer is (owner ruling HOVER-FOCUS b). Never the selection, and
    /// nothing scrolls: the row is on screen, under the pointer. `nil` — a
    /// section's header or footer, a scroll indicator, the border — and a row
    /// the cursor may not land on (`.selectionDisabled()`, ``isLandable(_:)``)
    /// move nothing, as the arrows pass them by.
    ///
    /// - Parameter drawing: The list's pictures, dropped when the cursor
    ///   moves, as for any input that moves a handler between frames.
    /// - Returns: Whether the cursor moved, and so a frame is wanted.
    package func followPointer(toRow row: Int?, drawing: HandlerDrawing) -> Bool {
        guard let row, row != focusedIndex, isLandable(row) else { return false }
        focusedIndex = row
        drawing.changed()
        return true
    }
}
