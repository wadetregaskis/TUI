//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+FocusBreathing.swift
//
//  The app's half of `\.focusBreathes`; the user's is `TUI_BREATHING`
//  (`FocusBreathing.swift`, in TUIFoundation).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - The app's setting

extension Scene {
    /// Holds every focus indication still throughout the app — a TUI-specific
    /// setting, with no SwiftUI counterpart.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     @AppStorage("focusBreathing") var focusBreathing = true
    ///
    ///     var body: some Scene {
    ///         WindowGroup { ContentView() }
    ///             .focusBreathing(focusBreathing)
    ///     }
    /// }
    /// ```
    ///
    /// `false` turns ``EnvironmentValues/focusBreathes`` off for everything the
    /// scene draws: a focused control's breath, and its blink under
    /// `.selectionIndicatorStyle(.blink)`, sit still at their bright end,
    /// whatever a view's own `.selectionIndicatorStyle(_:)` says. It never
    /// turns the breath back on: `true` means the app does not ask for
    /// stillness, and a user who asked for it with `TUI_BREATHING=0` still
    /// gets it.
    ///
    /// Apart from ``Scene/reduceMotion(_:)``, which leaves the breath alone,
    /// and from the text cursor's blink. For one part of a screen, use
    /// `.selectionIndicatorStyle(.none)` on that view instead.
    ///
    /// - Parameter breathes: Whether focus indications may animate.
    /// - Returns: A scene whose focus indications are still if `breathes` is
    ///   `false`.
    public func focusBreathing(_ breathes: Bool) -> some Scene {
        transformEnvironment(\.focusBreathes) { current in
            current = current && breathes
        }
    }
}
