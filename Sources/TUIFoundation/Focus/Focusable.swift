//  🖥️ TUI — A Terminal UI framework for Swift
//  Focusable.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Focusable Protocol

/// A protocol for views that can receive focus.
///
/// Focusable views can receive keyboard input when focused.
/// The focus system manages which view currently has focus and
/// routes keyboard events accordingly.
public protocol Focusable: AnyObject {
    /// The unique identifier for this focusable element.
    var focusID: String { get }

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool { get }

    /// Called when this element receives focus.
    func onFocusReceived()

    /// Called when this element loses focus.
    func onFocusLost()

    /// Handles a key event when focused.
    ///
    /// - Parameter event: The key event to handle.
    /// - Returns: True if the event was consumed, false to propagate.
    @MainActor func handleKeyEvent(_ event: KeyEvent) -> Bool
}

/// Defaults so a conformer only writes what it actually needs.
///
/// ``Focusable/handleKeyEvent(_:)`` has no default and must be implemented —
/// it is the whole reason to be focusable. Everything else is optional.
extension Focusable {
    /// Whether this handler will accept focus. `true` by default.
    ///
    /// Override — or set the stored property where the type has one — to drop
    /// out of the Tab ring dynamically: a disabled control, or a `ScrollView`
    /// whose content does not overflow, is a stop that can do nothing and so
    /// is only an obstacle. The focus manager reads this each pass, so the
    /// answer may change from frame to frame.
    public var canBeFocused: Bool { true }

    /// Called when this handler takes focus. Does nothing by default.
    ///
    /// The hook for focus-time side effects — a list scrolling its cursor row
    /// back into view, a field seeding its draft text. It runs during the
    /// render pass that assigns focus, so anything it changes must also be
    /// reflected by that same frame.
    public func onFocusReceived() {}

    /// Called when this handler loses focus. Does nothing by default.
    ///
    /// The counterpart to ``onFocusReceived()``: commit a pending edit, close
    /// a dropdown, stop a caret blinking.
    public func onFocusLost() {}
}

/// A ``Focusable`` that is kept in `StateStorage` and so outlives the frame
/// that built it.
///
/// Its ``Focusable/focusID`` can be repointed for exactly one reason. A control
/// re-resolves its declared id every frame — `.focusID(_:)` is an ordinary
/// modifier and its argument may be computed from state — while a persisted
/// handler is built ONCE, inside a `storage(for:default:)` autoclosure, from
/// whatever id was in force the first time the control drew. The focus ring
/// files a control under `handler.focusID` and nothing else, so from the second
/// frame on the ring knew it by its old name while the view drew and queried
/// focus under the new one, and the two could never agree again.
///
/// Handlers rebuilt every frame (``ActionHandler``) already agree with the
/// declaration by construction, and deliberately do not conform.
///
/// `package`, since handlers in other modules conform to it (TUIColorPicker's
/// grids since module split step B4, and TUINavigation's, TUIPresentation's,
/// TUILists', TUITabs', TUITextInput's, TUIPickers' and TUINumericControls'), and NOT
/// `@usableFromInline`
/// (step A3): the `@inlinable`
/// `FocusRegistration.register(context:handler:focusID:)` reaches it only through
/// the out-of-line `FocusRegistration.repointPersistedHandler(_:to:)`, which says why.
///
/// A method, not a settable `focusID` requirement: a settable requirement of a
/// protocol other modules can see hands every conformer's stored `focusID` to
/// callers the whole-module optimiser cannot see, which keeps a run-time
/// exclusivity check in each conformer's `focusID` witnesses, the getter the
/// ring reads every frame included (CONTRIBUTING.md, "Crossing a module
/// boundary"). A method writes the property inside the conformer's own module.
package protocol PersistedFocusable: Focusable {
    /// Answers to `focusID` from now on: the id the control declares this frame.
    func repoint(focusID: String)
}

/// A control whose focus shows only in what it draws ITSELF, never in the
/// content below it.
///
/// A focus move drops the cached buffers at both ends of it (see
/// `FocusManager.invalidateCachedRender(of:)`). For most controls that has to
/// include everything below the control's identity, because that is where the
/// control draws itself: a core view renders its own label, or tells it how to
/// look. A `ScrollView`'s focus shows only in its scrollbar, which its core
/// draws after the content, and it passes the content nothing focus-dependent.
/// A focusable view INSIDE the content registers and clears for itself. So
/// only the scroll view's own identity and the buffers containing it are
/// dropped. Before this, tabbing onto a scroll view, or away from it, dropped
/// every row it held, and the next frame measured and drew them all again:
/// 6.8 ms for a 200-message chat.
///
/// Conform only when that is true of everything the control will ever put
/// below itself, including through the environment. A `List` does not qualify:
/// its rows draw the selection differently while it holds the focus.
package protocol FocusDrawnOnlyAtItself: Focusable {}

/// A control the focus manager gives the focus to of its own accord only when
/// nothing else can take it: not as the first control of a window or a section
/// that nothing has focused while another control follows it. A key, a click,
/// `.focused(_:)`, `.defaultFocus(_:_:)` or a neighbour leaving still focuses
/// it.
///
/// A `.searchable`'s field is one, as macOS's search field in a window's
/// toolbar is (measured with SwiftUI on macOS 15.8, `Tools/SwiftUIProbes/Search
/// field focus and Escape/`): a window whose content is a `List` or a `Table`
/// opens with the focus there, never in the search field. ⌃F puts it there, as
/// ⌘F does on macOS. Where the content has nothing to focus, macOS opens with
/// no view focused, to be clicked; a terminal has no pointer to count on, so
/// the field takes the focus then, rather than leave the keys going nowhere.
///
/// A class's stored property, set as the control renders
/// (``EnvironmentValues/declinesAutomaticFocus``), so a registration a memo
/// replays carries it too.
package protocol AutomaticFocusDeclining: Focusable {
    /// Whether the focus manager leaves this control alone when it chooses
    /// the focus by itself.
    var declinesAutomaticFocus: Bool { get }
}

extension Focusable {
    /// Whether the focus manager may give this control the focus by itself:
    /// not an ``AutomaticFocusDeclining`` control that declines it.
    var takesAutomaticFocus: Bool {
        (self as? any AutomaticFocusDeclining)?.declinesAutomaticFocus != true
    }
}

private struct DeclinesAutomaticFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a text field in this subtree is left alone when the focus
    /// manager chooses the focus by itself (``AutomaticFocusDeclining``).
    /// A `.searchable` sets it on its own field, and on nothing else.
    package var declinesAutomaticFocus: Bool {
        get { self[DeclinesAutomaticFocusKey.self] }
        set { self[DeclinesAutomaticFocusKey.self] = newValue }
    }
}
