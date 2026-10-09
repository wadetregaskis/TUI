//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ActionHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A reusable focus handler for action-triggering views.
///
/// `ActionHandler` consolidates the common focus handling logic shared by
/// simple interactive views like `Button` and `Toggle`. It handles:
/// - Focus registration with the focus manager
/// - Key event handling (Enter/Space triggers the action)
/// - Disabled state (prevents focus when disabled)
///
/// ## Usage
///
/// ```swift
/// // In Button's renderToBuffer:
/// let handler = ActionHandler(
///     focusID: focusID,
///     action: action,
///     canBeFocused: !isDisabled
/// )
/// focusManager.register(handler, inSection: sectionID)
///
/// // In Toggle's renderToBuffer:
/// let handler = ActionHandler(
///     focusID: focusID,
///     action: { isOn.wrappedValue.toggle() },
///     canBeFocused: !isDisabled
/// )
/// focusManager.register(handler, inSection: sectionID)
/// ```
///
/// ## Trigger Keys
///
/// By default, the action is triggered on Enter or Space. You can customize
/// this by providing a different set of trigger keys:
///
/// ```swift
/// let handler = ActionHandler(
///     focusID: "custom",
///     action: { ... },
///     triggerKeys: [.enter]  // Only Enter, not Space
/// )
/// ```
package final class ActionHandler: Focusable {
    /// The unique identifier for this focusable element.
    package let focusID: String

    /// The action to execute when triggered.
    let action: () -> Void

    /// Whether this element can currently receive focus.
    package var canBeFocused: Bool { get { _canBeFocused } set { _canBeFocused = newValue } }

    /// ``canBeFocused``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _canBeFocused: Bool

    /// The keys that trigger the action.
    let triggerKeys: Set<Key>

    /// Extra keys an enclosing control wants answered while this button has
    /// focus — a disclosure's Left and Right. See ``ButtonKeyExtras``.
    let extras: ButtonKeyExtras?

    /// Whether a held trigger key's repeats run the action again. A repeat is
    /// told from a press only where the terminal speaks the kitty keyboard
    /// protocol; in a legacy encoding every repeat arrives as a press and
    /// runs it whatever this says.
    let repeats: Bool

    /// Creates an action handler.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - action: The action to execute when triggered.
    ///   - canBeFocused: Whether this element can receive focus. Defaults to `true`.
    ///   - triggerKeys: The keys that trigger the action. Defaults to Enter and Space.
    ///   - extras: Extra keys supplied by an enclosing control, if any.
    ///   - repeats: Whether a held trigger key's repeats run the action again.
    package init(
        focusID: String,
        action: @escaping () -> Void,
        canBeFocused: Bool = true,
        triggerKeys: Set<Key> = [.enter, .space],
        extras: ButtonKeyExtras? = nil,
        repeats: Bool = true
    ) {
        self.focusID = focusID
        self.action = action
        self._canBeFocused = canBeFocused
        self.triggerKeys = triggerKeys
        self.extras = extras
        self.repeats = repeats
    }
}

// MARK: - Key Event Handling

extension ActionHandler {
    package func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // Extras first, and only for keys they claimed: a control that composes
        // a button is more specific than the button, and this is the one place
        // that can tell the difference. They never see Return or Space unless
        // they asked for them.
        if let extras, extras.keys.contains(event.key), extras.handle(event) {
            return true
        }
        guard triggerKeys.contains(event.key) else { return false }
        // A repeat that does not act is still taken: a held Return must not
        // fall through to the default button once the focused one declines.
        if event.phase == .repeat, !repeats { return true }
        action()
        return true
    }
}
