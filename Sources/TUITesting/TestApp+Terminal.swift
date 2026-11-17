//  🖥️ TUI — A Terminal UI framework for Swift
//  TestApp+Terminal.swift
//
//  What a test can say about the terminal around the app: its window losing
//  and gaining the focus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
import TUIFoundation

extension TestApp {
    /// Reports the terminal's window losing or gaining the focus, as a
    /// terminal does when the person switches to another window and back, and
    /// draws the frames that causes.
    ///
    /// Losing it moves `\.scenePhase` to `.inactive` and `\.appearsActive` to
    /// `false`; gaining it moves them back to `.active` and `true`, as a running
    /// app moves them on the terminal's focus reports. So a game that pauses
    /// when its window goes to the back can be tested:
    ///
    /// ```swift
    /// let app = TestApp { Game() }
    /// app.reportFocus(false)
    /// #expect(app.screen.contains("Paused"))
    /// ```
    ///
    /// As in a running app, the pointer leaves with the focus: a view it hovered
    /// hears it exit, and the help it showed goes. A report of the focus the
    /// window already has changes nothing. The window starts focused.
    ///
    /// - Parameter isFocused: Whether the terminal's window has the focus now.
    public func reportFocus(_ isFocused: Bool) {
        start()
        headless.reportFocus(isFocused)
        if headless.takeFrameRequest() { drawFrames() }
    }
}
