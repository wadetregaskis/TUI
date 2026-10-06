//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AccessibilityReduceMotion.swift
//
//  `\.accessibilityReduceMotion`: whether to reduce motion. Where the answer
//  comes from in a terminal — the user's `TUIKIT_REDUCE_MOTION`, or the app's
//  own `.reduceMotion()` on its scene — is TUIkit's (`ReduceMotion.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

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
    public package(set) var accessibilityReduceMotion: Bool {
        get { self[AccessibilityReduceMotionKey.self] }
        set { self[AccessibilityReduceMotionKey.self] = newValue }
    }
}
