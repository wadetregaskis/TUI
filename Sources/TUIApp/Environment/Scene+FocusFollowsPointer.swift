//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+FocusFollowsPointer.swift
//
//  The app's half of whether the focus follows the pointer; the user's is
//  `TUI_FOCUS_FOLLOWS_POINTER` (`FocusFollowsPointer.swift`, in TUIFoundation).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - The app's setting

extension Scene {
    /// Moves the focus to whatever focusable control the mouse pointer moves
    /// onto, rather than only highlighting it — a TUI-specific setting, with no
    /// SwiftUI counterpart.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     @AppStorage("focusFollowsPointer") var focusFollowsPointer = false
    ///
    ///     var body: some Scene {
    ///         WindowGroup { ContentView() }
    ///             .focusFollowsPointer(focusFollowsPointer)
    ///     }
    /// }
    /// ```
    ///
    /// Off unless this or the user's `TUI_FOCUS_FOLLOWS_POINTER=1` turns it on;
    /// what the scene says wins over the variable. While it is on, the terminal
    /// reports every move of the mouse, as it does for `.onHover`, wherever it
    /// reports clicks at all: under `.mouseSupport(.disabled)` or `.scrollOnly`
    /// nothing changes.
    ///
    /// A move onto another cell over a control focuses it, as a click there
    /// would, without pressing it. A pointer at rest takes nothing back from the
    /// keyboard: Tab moves the focus as ever, and the pointer's next move moves
    /// it again. A text field you have typed in keeps the focus while the
    /// pointer wanders, until a click or the keyboard moves it on; one the
    /// pointer merely crossed gives it up again. While a sheet, an alert or a
    /// popover is up, the pointer moves the focus only within it, and while a
    /// menu is open, not at all: the menu follows the pointer itself.
    ///
    /// - Parameter follows: Whether the focus follows the pointer.
    /// - Returns: A scene whose focus follows the pointer, or not.
    public func focusFollowsPointer(_ follows: Bool = true) -> some Scene {
        transformEnvironment(\.focusFollowsPointer) { $0 = follows }
    }
}
