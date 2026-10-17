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

    /// The cell the insertion point is on, as the control last drew it: in the
    /// coordinates of the control's own hit-test region, the one that carries
    /// its focus id; `nil` where it is scrolled out of the control's view, or
    /// the control keeps none.
    ///
    /// The run loop parks the terminal's hidden cursor there after each frame
    /// (`RenderLoop.parkCursor`). A terminal draws what an input method is
    /// composing at its cursor — Apple Terminal's pending accent after ⌥E,
    /// say — so that is where the composition appears: on the caret, as in any
    /// text control, instead of wherever the frame's last write ended.
    var insertionPoint: CellPoint? { get }
}

extension TextInputFocusHandler {
    /// None: the control's input has no insertion point to show.
    package var insertionPoint: CellPoint? { nil }
}
