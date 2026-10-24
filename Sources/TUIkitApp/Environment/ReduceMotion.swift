//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReduceMotion.swift
//
//  Where `\.accessibilityReduceMotion` (declared in TUIkitView) comes from in a
//  terminal — the user's `TUIKIT_REDUCE_MOTION`, the operating system's own
//  setting where TUIkit is sure the user is at this machine
//  (`HostSettingsRefresher`), or the app's own `.reduceMotion()` on its
//  scene. The operating system's setting counts only there: the machine the app
//  runs on need not be the one the user sits at.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitFoundation
import TUIkitView

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
    /// does not ask for less motion, and a user who asked for it — with
    /// `TUIKIT_REDUCE_MOTION=1`, or with Reduce Motion on the machine they are
    /// at — still gets it: less motion is the direction to err in, and the
    /// user is the one who knows they need it.
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
