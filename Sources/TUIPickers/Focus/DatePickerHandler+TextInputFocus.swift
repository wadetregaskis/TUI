//  🖥️ TUI — A Terminal UI framework for Swift
//  DatePickerHandler+TextInputFocus.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// Typed digits are the date picker's CONTENT (`typeDigit`); a lettered or
// digit-bound status item stole them the same way it stole an editor's
// letters. Everything the handler declines — letters, Tab, Escape — still
// falls through to the ordinary layers, so only its digits are protected.
extension DatePickerHandler: TextInputFocusHandler {
    /// Never: the date picker binds no editing chord.
    func givesWayToKeyboardShortcut(_ event: KeyEvent) -> Bool { false }

    /// Never: the date picker binds no editing chord.
    func editsWith(_ event: KeyEvent) -> Bool { false }
}
