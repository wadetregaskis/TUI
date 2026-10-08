//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClient+ReduceMotion.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

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
