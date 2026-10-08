//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextInputFocusHandler.swift
//
//  Created by Wade Tregaskis
//  License: MIT
/// A focus handler that consumes ordinary typed characters as CONTENT.
///
/// Adopting this is what puts a handler behind the input dispatcher's layer-0
/// gate: while one is focused, typed keys reach it BEFORE status-bar items and
/// `onKeyEvent` handlers, so typing "q" into a field cannot quit the app. The
/// gate used to test `is TextFieldHandler` literally — which is how
/// `TextEditor`, a separate class, shipped with its keystrokes stealable by
/// any lettered status item on the page. A new text-consuming handler adopts
/// this protocol; it does not extend a type test.
package protocol TextInputFocusHandler: AnyObject {
    /// Whether this control gives `event` up to an app's keyboard shortcut on
    /// the same chord.
    ///
    /// The input dispatcher asks before it offers the control the key. When
    /// the answer is yes and an app shortcut is registered on the chord, the
    /// control is not offered the key at all: the shortcut fires and the
    /// control does nothing. The answer must be the one the control's own key
    /// handling acts on, so each text control reads both from its
    /// `editingCommand(for:)`, and gives the rule
    /// (``TextEditingCommand/givesWayToKeyboardShortcuts(homeAndEndReachLineEnds:)``)
    /// the one fact about itself it depends on.
    func givesWayToKeyboardShortcut(_ event: KeyEvent) -> Bool
}
