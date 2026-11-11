//  🖥️ TUI — A Terminal UI framework for Swift
//  RadioButtonGroupHandler+PointerFocus.swift
//
//  A radio group's and a segmented picker's cursor following the pointer,
//  while the focus follows it: the part the two share, as they share the
//  handler. Each finds the option under the pointer its own way and files the
//  follower with the dispatcher
//  (`MouseEventDispatcher.filePointerFocusFollower(for:in:_:)`), as a list's
//  cursor row does (`ItemListHandler+PointerFocus.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension RadioButtonGroupHandler {
    /// Puts the cursor on `option`, the option or segment the pointer moved
    /// onto while the focus follows it and the control holds the focus, so the
    /// keys act where the pointer is (owner ruling SEGMENT-CURSOR b). Never the
    /// selection: Space or Return chooses, or a click. `nil` — a rule between
    /// two segments — and an option that cannot be chosen
    /// (``RadioButtonItem/disabled(_:)``) move nothing, as the arrows pass
    /// them by.
    ///
    /// - Parameter drawing: The control's pictures, dropped when the cursor
    ///   moves, as for any input that moves a handler between frames.
    /// - Returns: Whether the cursor moved, and so a frame is wanted.
    func followPointer(toOption option: Int?, drawing: HandlerDrawing) -> Bool {
        guard let option, option != focusedIndex, itemValues.indices.contains(option),
            !disabledIndices.contains(option)
        else { return false }
        focusedIndex = option
        drawing.changed()
        return true
    }
}
