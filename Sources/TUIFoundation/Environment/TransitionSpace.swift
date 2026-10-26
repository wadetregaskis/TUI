//  🖥️ TUI — A Terminal UI framework for Swift
//  TransitionSpace.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// What happens to the room a view took in a stack while its removal plays.
///
/// TUI-specific: SwiftUI has no choice here. Its stack gives the room back at
/// once, and the views around the one leaving glide into it while it plays its
/// removal where it was — which is ``released``, the default, and what a
/// TUI stack does too. ``held`` keeps the room until the removal has played
/// out, then gives it back at once: the views around stand still while the
/// view leaves, and close up after.
///
/// Set it with ``View/transitionSpace(_:)``.
public enum TransitionSpace: Hashable, Sendable {
    /// The room is given back at once, as SwiftUI's stack gives it: under an
    /// animation, the views after the one leaving glide into it while it plays
    /// its removal over or under them.
    case released

    /// The room is kept until the removal has played out, then given back at
    /// once.
    case held
}

private struct TransitionSpaceKey: EnvironmentKey {
    static let defaultValue = TransitionSpace.released
}

extension EnvironmentValues {
    /// What happens to the room a view took in a stack while its removal
    /// plays — see ``TransitionSpace``.
    package var transitionSpace: TransitionSpace {
        get { self[TransitionSpaceKey.self] }
        set { self[TransitionSpaceKey.self] = newValue }
    }
}

extension View {
    /// Sets what happens to the room a view in a stack inside this one took,
    /// while that view's removal transition plays.
    ///
    /// ```swift
    /// VStack {
    ///     if showsBanner {
    ///         Banner().transition(.opacity)
    ///     }
    ///     Content()
    /// }
    /// .transitionSpace(.held)
    /// ```
    ///
    /// By default (``TransitionSpace/released``) a stack gives the room back on
    /// the frame the view is removed, as SwiftUI's does: inside
    /// ``withAnimation(_:_:)`` the views after it glide up into the room while
    /// the banner fades where it was. With ``TransitionSpace/held`` the room is
    /// kept while the banner fades, and the stack closes up once it has gone —
    /// the content stands still under the fade and then moves up at once.
    ///
    /// TUI-specific; SwiftUI has no equivalent. It reaches every eager stack
    /// below it, as the environment does. A lazy stack keeps the room while a
    /// removal plays either way. The room held is a view's an `if` takes out,
    /// whose `nil` keeps a slot: a branch an `if`/`else` leaves, a `switch`'s
    /// case and a `ForEach`'s row are no longer children of the stack, which
    /// closes up and fades them where they were (decisions B-TRANSITIONS2-3).
    ///
    /// - Parameter space: What happens to the room.
    /// - Returns: A view whose stacks treat a removal's room that way.
    public func transitionSpace(_ space: TransitionSpace) -> some View {
        environment(\.transitionSpace, space)
    }
}
