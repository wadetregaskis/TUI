//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+KeyNotation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - The app's setting

extension Scene {
    /// Writes keys with their names spelled out throughout the app — a
    /// TUI-specific setting, SwiftUI drawing keys with the system's own font.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .keyNotation(.spelledOut)   // Ctrl-Shift-Z rather than ⌃⇧Z
    /// ```
    ///
    /// ``KeyNotation/spelledOut`` sets ``EnvironmentValues/keyNotation`` for
    /// everything the scene draws, the status bar included. It never turns the
    /// symbols back on: ``KeyNotation/symbols`` means the app does not ask for
    /// the names, and a user who asked for them with `TUIKIT_KEY_SYMBOLS=0`
    /// still gets them — it is the user who knows what their font can draw.
    ///
    /// - Parameter notation: How to write keys.
    /// - Returns: A scene whose environment writes keys that way, or as the
    ///   user asked.
    public func keyNotation(_ notation: KeyNotation) -> some Scene {
        transformEnvironment(\.keyNotation) { current in
            if notation == .spelledOut { current = .spelledOut }
        }
    }
}
