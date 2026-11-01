//  🖥️ TUI — A Terminal UI framework for Swift
//  ButtonKeyExtras.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// Keys the focused button should answer beyond Return and Space, supplied by
/// whatever built a control out of it.
///
/// A disclosure header is a `Button` — the triangle and the label are one
/// control, as they are on macOS — and it also answers Left and Right, which
/// *set* the disclosure closed and open rather than toggling it. A button knows
/// nothing about disclosure, and a disclosure has no way to reach a focused
/// button's key handling from the outside, so the keys travel down the
/// environment and the button hands them to its focus handler along with its
/// own.
///
/// Focus-gating comes free: a `Focusable`'s `handleKeyEvent` is only ever
/// called for the element that has focus, so every other disclosure on the page
/// ignores the same keystroke without anyone testing for it.
///
/// ## Scope
///
/// The environment reaches everything below the write, so attach it to the
/// button and not to a subtree containing one. Both callers here wrap exactly
/// the header button, whose label is text. A `Button` nested inside another
/// button's *label* would inherit these keys; there is no such thing in this
/// framework, and the alternative — a mechanism that could name one button —
/// would need an identity the composing view does not have.
///
/// ## Comparing it
///
/// An object the modifier keeps in `@State` and refreshes with the keys and the
/// handler each time its body runs, compared by identity — the shape
/// ``MenuOpenAction`` takes, for its reason: an environment value that cannot
/// be compared turns every memo off beneath it, and the handler is a closure.
/// The button reads the object at registration and asks it at the keystroke,
/// so a registration replayed from a memo asks the keys and the handler as they
/// stand now, not as they stood when the memo stored it.
///
/// Not `Sendable`, as ``DepartureStore`` is not: the closure is built during a
/// render pass and called from key dispatch, both of which run on the single
/// run loop.
package final class ButtonKeyExtras: Equatable {
    /// The keys to intercept. Anything outside this set is not offered.
    var keys: Set<Key>

    /// Handles one of ``keys``. Returning `false` lets the key fall through to
    /// the button's own triggers and then out of the control entirely, which is
    /// how "Left on an already-closed group" reaches whatever is outside it.
    var handle: (KeyEvent) -> Bool

    init(keys: Set<Key> = [], handle: @escaping (KeyEvent) -> Bool = { _ in false }) {
        self.keys = keys
        self.handle = handle
    }

    nonisolated package static func == (lhs: ButtonKeyExtras, rhs: ButtonKeyExtras) -> Bool { lhs === rhs }
}

private struct ButtonKeyExtrasKey: EnvironmentKey {
    static var defaultValue: ButtonKeyExtras? { nil }
}

extension EnvironmentValues {
    /// Extra keys the button below this write should answer. See
    /// ``ButtonKeyExtras``.
    var buttonKeyExtras: ButtonKeyExtras? {
        get { self[ButtonKeyExtrasKey.self] }
        set { self[ButtonKeyExtrasKey.self] = newValue }
    }
}

extension View {
    /// Gives the button in this view extra keys to answer while it is focused.
    ///
    /// - Parameters:
    ///   - keys: Which keys to intercept.
    ///   - handle: What to do with one. `false` lets it fall through.
    /// - Returns: A view whose button answers those keys too.
    package func buttonKeyExtras(
        keys: Set<Key>, handle: @escaping (KeyEvent) -> Bool
    ) -> some View {
        _ButtonKeyExtrasModifier(content: self, keys: keys, handle: handle)
    }
}

/// ``View/buttonKeyExtras(keys:handle:)``: the keys and their handler, handed to
/// the button through one ``ButtonKeyExtras`` for the modifier's life.
private struct _ButtonKeyExtrasModifier<Content: View>: View {
    let content: Content
    let keys: Set<Key>
    let handle: (KeyEvent) -> Bool

    /// The object the button asks, refreshed below.
    @State private var extras = ButtonKeyExtras()

    var body: some View {
        // Written into the object, not the state: the environment holds the
        // object it compared equal last frame, which now answers as this body
        // says.
        extras.keys = keys
        extras.handle = handle
        return content.environment(\.buttonKeyExtras, extras)
    }
}
