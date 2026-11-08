//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManagerPointerFocus.swift
//
//  Focus follows the pointer, the focus manager's half: which control a
//  pointer moving onto it may take the focus to, and which may keep it. The
//  dispatcher's half, which finds the control under the pointer, is
//  `MouseEventDispatcher+FocusFollowsPointer.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Moves the focus to the control answering to `focusID`, for a pointer
    /// that moved onto it while the focus follows the pointer
    /// (`Scene.focusFollowsPointer(_:)`, `TUI_FOCUS_FOLLOWS_POINTER=1`).
    ///
    /// Narrower than ``focus(id:)``, which a click and the app use:
    ///
    /// - **Only a control registered and focusable this pass.** An id that
    ///   matches nothing is not kept as a pending intent, as ``focus(id:)``
    ///   keeps it: a pointer crossing a disabled control, or the page under a
    ///   sheet, which draws into a manager of its own, moves nothing and asks
    ///   for no render.
    /// - **Not while a menu is open.** The menu follows the pointer itself.
    /// - **Not out of a modal surface.** While the active section is a sheet's,
    ///   an alert's or a popover's, the pointer moves the focus only within it,
    ///   as Tab does: the frontmost surface keeps the keyboard.
    /// - **Not away from an edit.** A text control that input has reached since
    ///   it took the focus — a key, a click or a wheel over it
    ///   (``noteInputToFocusedControl()``) — keeps it while the pointer
    ///   wanders: what is typed next goes where the typing was. A click or the
    ///   keyboard moves it on. One the pointer merely crossed gives it up again.
    ///
    /// - Returns: Whether the focus moved.
    @discardableResult
    package func focusFollowingPointer(id focusID: String) -> Bool {
        guard currentFocusedID != focusID, !activeSectionIsMenu else { return false }
        if let editing = currentFocusedID, editing == focusScopes.inputHeldID,
            currentFocused is any TextInputFocusHandler
        {
            return false
        }
        guard let section = sections.first(where: { section in
            section.focusables.contains { $0.focusID == focusID && $0.canBeFocused }
        }) else { return false }
        if activeSectionIsModal, section.id != activeSectionIdentifier { return false }
        focus(id: focusID)
        return true
    }
}
