//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReduceMotion.swift
//
//  `\.accessibilityReduceMotion`: whether to reduce motion, and where the
//  answer comes from in a terminal — the user's `TUIKIT_REDUCE_MOTION`, or the
//  app's own `.reduceMotion()` on its scene. Not the operating system's
//  setting: the machine the app runs on need not be the one the user sits at.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitView

// MARK: - The environment value

private struct AccessibilityReduceMotionKey: EnvironmentKey {
    // `false`, and not read from the process environment: a key's default
    // must not depend on where a test runs. The render loop writes the
    // user's answer at the root.
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether to reduce motion — mirrors SwiftUI's `accessibilityReduceMotion`.
    ///
    /// If it is `true`, a view should avoid large animations. TUIkit's own
    /// transitions follow it: one that has motion (see
    /// ``TransitionProperties/hasMotion``) plays as `.opacity` instead, as
    /// SwiftUI's does.
    ///
    /// SwiftUI reads the system's Reduce Motion preference. TUIkit does not,
    /// because the machine an app runs on need not be the one its user sits at
    /// — over ssh, the preference would be the server's. Instead it is `true`
    /// when the user set `TUIKIT_REDUCE_MOTION=1` in the environment the app
    /// runs in (``TerminalClient/reduceMotionRequested``), or the app asked for
    /// it with the TUI-specific `Scene.reduceMotion(_:)`. Read-only, as
    /// SwiftUI's is.
    public internal(set) var accessibilityReduceMotion: Bool {
        get { self[AccessibilityReduceMotionKey.self] }
        set { self[AccessibilityReduceMotionKey.self] = newValue }
    }
}

// MARK: - The app's setting

extension Scene {
    /// Asks for less motion throughout the app — a TUI-specific setting with
    /// no SwiftUI counterpart, SwiftUI taking the answer from the system.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     @AppStorage("reduceMotion") var reduceMotion = false
    ///
    ///     var body: some Scene {
    ///         WindowGroup { ContentView() }
    ///             .reduceMotion(reduceMotion)
    ///     }
    /// }
    /// ```
    ///
    /// It turns ``EnvironmentValues/accessibilityReduceMotion`` on for
    /// everything the scene draws. It never turns it off: `false` means the app
    /// does not ask for less motion, and a user who asked for it with
    /// `TUIKIT_REDUCE_MOTION=1` still gets it — less motion is the direction to
    /// err in, and the user is the one who knows they need it.
    ///
    /// - Parameter reduces: Whether to reduce motion. `true` by default.
    /// - Returns: A scene whose environment reduces motion if `reduces` is
    ///   `true`.
    public func reduceMotion(_ reduces: Bool = true) -> some Scene {
        transformEnvironment(\.accessibilityReduceMotion) { reduced in
            reduced = reduced || reduces
        }
    }
}

// MARK: - The user's setting

extension TerminalClient {
    /// Whether the user asked for less motion: `TUIKIT_REDUCE_MOTION=1` in
    /// the environment the app was started in. Read once, at first use.
    ///
    /// The app runner hands it to its render loop, which writes it into the
    /// root of every frame's environment, as
    /// ``EnvironmentValues/accessibilityReduceMotion``, before the scene's own
    /// `.reduceMotion(_:)`. Only the app runner reads it: a headless app's
    /// loop, and every test's, draws as if it were unset.
    public static let reduceMotionRequested: Bool =
        reduceMotionRequested(environment: ProcessInfo.processInfo.environment)

    /// The rule behind ``reduceMotionRequested``, posed on its input so it can
    /// be asked without changing what a whole process reads.
    static func reduceMotionRequested(environment: [String: String]) -> Bool {
        environment["TUIKIT_REDUCE_MOTION"] == "1"
    }
}
