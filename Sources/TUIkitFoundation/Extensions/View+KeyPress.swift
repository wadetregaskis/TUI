//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+KeyPress.swift
//
//  SwiftUI's five onKeyPress modifiers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - onKeyPress

/// SwiftUI's `onKeyPress`: an action that hears a key press **while the focus
/// is on this view or inside it**, as SwiftUI's does.
///
/// - **Focus decides who hears.** A handler on a view that holds no focus and
///   contains none never runs, so `Text("x").onKeyPress { … }` needs a
///   `.focusable()` to hear anything, exactly as under SwiftUI. To bind a key
///   whatever holds the focus, use the TUI-specific ``View/onKeyEvent(_:)``.
/// - **Outermost first.** The handlers on the path to the focused view are
///   asked from the outside in, until one returns ``KeyPress/Result/handled``;
///   that is the order SwiftUI asks them in (measured on macOS 15).
/// - **Before the focused control.** They are asked before the focused
///   control sees the key — a `TextField` included, so a `.handled` letter is
///   never typed, and a `.handled` Tab does not move the focus — and before
///   the app's keyboard shortcuts.
/// - **Phases.** All three where the terminal speaks the kitty keyboard
///   protocol; presses only in its legacy encodings. See ``KeyPress``.
extension View {
    /// Performs an action when the given key is pressed while this view has
    /// the focus, or contains it.
    ///
    /// The action runs for a press and for each auto-repeat of a held key.
    /// Return ``KeyPress/Result/handled`` to consume the press, or
    /// ``KeyPress/Result/ignored`` to let the next handler, and then the
    /// focused control, have it.
    ///
    /// ```swift
    /// List(selection: $selection) { … }
    ///     .onKeyPress(.space) {
    ///         togglePlayback()
    ///         return .handled
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - key: The key to match. Case matters: `"a"` does not match Shift-A.
    ///   - action: The action to perform.
    /// - Returns: A view that handles the key while it holds the focus.
    public func onKeyPress(
        _ key: KeyEquivalent, action: @escaping () -> KeyPress.Result
    ) -> some View {
        onKeyPress(keys: [key], phases: [.down, .repeat]) { _ in action() }
    }

    /// Performs an action when the given key is pressed in one of `phases`
    /// while this view has the focus, or contains it.
    ///
    /// - Parameters:
    ///   - key: The key to match.
    ///   - phases: The phases to match. A terminal in its legacy encodings
    ///     reports every press as ``KeyPress/Phases/down`` and no release;
    ///     see ``KeyPress``.
    ///   - action: The action to perform, given the press.
    /// - Returns: A view that handles the key while it holds the focus.
    public func onKeyPress(
        _ key: KeyEquivalent, phases: KeyPress.Phases,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        onKeyPress(keys: [key], phases: phases, action: action)
    }

    /// Performs an action when any of `keys` is pressed while this view has
    /// the focus, or contains it.
    ///
    /// ```swift
    /// .onKeyPress(keys: [.upArrow, .downArrow]) { press in
    ///     move(press.key == .upArrow ? -1 : 1)
    ///     return .handled
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - keys: The keys to match.
    ///   - phases: The phases to match; a press and its repeats by default.
    ///   - action: The action to perform, given the press.
    /// - Returns: A view that handles the keys while it holds the focus.
    public func onKeyPress(
        keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        onKeyPress(phases: phases, where: { keys.contains($0.key) }, action: action)
    }

    /// Performs an action when a key whose characters are all in `characters`
    /// is pressed while this view has the focus, or contains it.
    ///
    /// The characters are the press's ``KeyPress/characters`` — the key's own,
    /// with Shift but no other modifier applied, so Control-A matches
    /// `.letters` as A does.
    ///
    /// - Parameters:
    ///   - characters: The characters to match.
    ///   - phases: The phases to match; a press and its repeats by default.
    ///   - action: The action to perform, given the press.
    /// - Returns: A view that handles the keys while it holds the focus.
    public func onKeyPress(
        characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        // A set of characters asks for what is typed, not for chords:
        // Control is not looked at, so `.decimalDigits` would claim ⌃4 and
        // `.punctuationCharacters` ⌃\. It declares no keys, as the
        // catch-all declares none, so a field that takes digits does not
        // mask the user's quit key (the coordinator's ruling, round 6).
        onKeyPress(
            phases: phases,
            where: { !$0.characters.isEmpty && $0.characters.unicodeScalars.allSatisfy(characters.contains) },
            declared: false, action: action)
    }

    /// Performs an action when any key is pressed while this view has the
    /// focus, or contains it.
    ///
    /// ```swift
    /// .onKeyPress { press in
    ///     lastKey = press.characters
    ///     return .ignored
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - phases: The phases to match; a press and its repeats by default.
    ///   - action: The action to perform, given the press.
    /// - Returns: A view that handles key presses while it holds the focus.
    public func onKeyPress(
        phases: KeyPress.Phases = [.down, .repeat], action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        onKeyPress(phases: phases, where: { _ in true }, declared: false, action: action)
    }

    /// The focus-path modifier every `onKeyPress` is: a handler on the
    /// key-press stage that hears a press `matches` accepts, in `phases`.
    ///
    /// Whether a press may be a repeat is the terminal's to say
    /// (``KeyboardReporting/reportsRepeats``), read where the handler is made:
    /// the environment is out of reach by the time a key arrives.
    ///
    /// - Parameter declared: Whether `matches` is the handler's declaration —
    ///   its keys — so the framework may ask it which keys the handler is
    ///   for without running `action`. Not for the catch-all, which declares
    ///   none (only the action says which keys it takes), nor for a set of
    ///   characters, which asks for typed text, not chords. What asks is the
    ///   user's quit key (`Terminal.maskQuitKey(for:)`).
    ///
    ///   A key declares a Control chord only where it names one
    ///   (``KeyEquivalent/namesControlChord``): `onKeyPress("\\")` declares
    ///   ⌃\\, but `onKeyPress("4")` does not declare ⌃4, though it hears it —
    ///   a press matches on its key alone, and `KeyPress(⌃4).key` is `"4"`.
    ///   Declared, a PIN field's digits would mask the user's quit key, whose
    ///   byte some terminals send for ⌃4, and be offered ⌃\\ again as ⌃4,
    ///   typing a 4 for it (the coordinator's ruling, 2026-10-06).
    private func onKeyPress(
        phases: KeyPress.Phases, where matches: @escaping (KeyPress) -> Bool, declared: Bool = true,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> FocusPathModifier<Self> {
        let declares: ((KeyEvent) -> Bool)? =
            declared
            ? { event in
                phases.hears(event.phase, repeatsReported: false)
                    && KeyPress(event).map { matches($0) && (!event.ctrl || $0.key.namesControlChord) } == true
            }
            : nil
        return FocusPathModifier(content: self, stage: .keyPress, declares: declares) { context in
            let repeatsReported = context.environment.keyboardReporting.reportsRepeats
            return { event in
                guard phases.hears(event.phase, repeatsReported: repeatsReported),
                    let press = KeyPress(event), matches(press)
                else { return false }
                return action(press) == .handled
            }
        }
    }
}
