//  🖥️ TUI — A Terminal UI framework for Swift
//  MouseEventDispatcher+FocusFollowsPointer.swift
//
//  Focus follows the pointer, the dispatcher's half: the focusable control
//  under a pointer that moved. Which of them may take the focus is the focus
//  manager's (`FocusManagerPointerFocus.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

extension MouseEventDispatcher {
    /// Offers the focus to the focusable control under a bare pointer move,
    /// while the focus follows the pointer (``pointerFocusManager``).
    ///
    /// Only a move onto another cell counts: a report from the cell the pointer
    /// was already on moves nothing, so a pointer at rest never takes the focus
    /// back from the keyboard. The next move does — over the same control too,
    /// as long as it reaches another cell of it.
    ///
    /// The control is the innermost region under the pointer that carries a
    /// focus id: a `Button`'s, a `TextField`'s, a `List`'s, whatever a click
    /// there would focus. A region with none — a label, a backdrop — is looked
    /// through to the one behind it, which the focus manager then judges.
    /// Never while a drag is under way: a held button's moves arrive as drags,
    /// not here, and a drag the keyboard carries is steered by the keys.
    ///
    /// - Returns: Whether the focus moved, and so a frame is wanted.
    func focusFollowingPointer(_ event: MouseEvent, movedCell: Bool) -> Bool {
        guard movedCell, let focusManager = pointerFocusManager else { return false }
        if let session = dragAndDropSession, session.carry != nil || session.active != nil { return false }
        guard let focusID = matchingRegions(at: event.x, y: event.y).lazy.compactMap(\.focusID).first else {
            return false
        }
        return focusManager.focusFollowingPointer(id: focusID)
    }
}
