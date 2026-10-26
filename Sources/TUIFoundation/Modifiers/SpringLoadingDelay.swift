//  🖥️ TUI — A Terminal UI framework for Swift
//  SpringLoadingDelay.swift
//
//  How long a paused drag rests on a spring-loaded control before it
//  activates it (owner ruling B82): the user's spring-loading delay where
//  TUI can read it, half a second where it cannot, and a TUI-specific
//  modifier for an app's own.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

private struct SpringLoadingDelayKey: EnvironmentKey {
    // Not the user's: what a view draws and a test sees must not depend on
    // the machine it runs on. The render loop writes the user's at the root.
    static let defaultValue = Duration.milliseconds(500)
}

extension EnvironmentValues {
    /// How long a paused drag must rest on a spring-loaded control before it
    /// activates it — a TUI-specific value, set with
    /// ``View/springLoadingDelay(_:)``.
    ///
    /// SwiftUI has no such value: macOS reads the user's spring-loading delay
    /// (System Settings ▸ Accessibility ▸ Pointer Control, its
    /// `com.apple.springing.delay`). An app run in a terminal reads it the
    /// same way where TUI is sure the user is at the machine the app runs
    /// on, and otherwise takes macOS's default, half a second; the user's
    /// `TUIKIT_SPRING_LOADING_DELAY` (in seconds) overrides either. That is
    /// what the root of every frame holds, and this value's default outside
    /// an app's run loop is half a second.
    public var springLoadingDelay: Duration {
        get { self[SpringLoadingDelayKey.self] }
        set { self[SpringLoadingDelayKey.self] = newValue }
    }
}

extension View {
    /// Sets how long a paused drag must rest on a spring-loaded control in
    /// this view before it activates it (``View/springLoadingBehavior(_:)``)
    /// — a TUI-specific modifier, with no SwiftUI counterpart: on macOS the
    /// delay is the user's setting alone.
    ///
    /// By default it is the user's spring-loading delay where TUI can read
    /// it, and half a second otherwise (``EnvironmentValues/springLoadingDelay``).
    /// This overrides that for the subtree, as an environment value does: use
    /// it for a control whose pause should be shorter or longer than the
    /// user's, and leave the user's elsewhere. `.zero` activates a control the
    /// moment a drag rests on it.
    ///
    /// - Parameter delay: How long the pause lasts. A negative duration is zero.
    /// - Returns: A view whose spring-loaded controls wait `delay`.
    public func springLoadingDelay(_ delay: Duration) -> some View {
        environment(\.springLoadingDelay, delay)
    }
}

// MARK: - The user's setting

extension TerminalClient {
    /// The spring-loading delay the user asked for with
    /// `TUIKIT_SPRING_LOADING_DELAY` — in seconds, `0.3` or `1` — in the
    /// environment the app was started in, or `nil` where it is unset or no
    /// duration of zero or more. Read once, at first use.
    ///
    /// It overrides the host's own delay. The app runner hands it to its render
    /// loop, which writes it into the root of every frame's environment, as
    /// ``EnvironmentValues/springLoadingDelay``. Only the app runner reads it.
    package static let springLoadingDelayRequested: Duration? =
        springLoadingDelayRequested(environment: ProcessInfo.processInfo.environment)

    /// The rule behind ``springLoadingDelayRequested``, posed on its input.
    package static func springLoadingDelayRequested(environment: [String: String]) -> Duration? {
        guard let text = environment["TUIKIT_SPRING_LOADING_DELAY"],
            let seconds = Double(text.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0
        else { return nil }
        return .milliseconds(Int64((seconds * 1000).rounded()))
    }
}
