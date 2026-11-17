//  🖥️ TUI — A Terminal UI framework for Swift
//  TestApp+Terminal.swift
//
//  What a test can say about the terminal around the app: its window losing
//  and gaining the focus, and what the terminal can do.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
import TUIFoundation

extension TestApp {
    /// What the terminal can do, feature by feature, as the app reads it from
    /// `\.terminalCapabilities`.
    ///
    /// Every feature is undetermined until a test says otherwise, as for a
    /// terminal TUI has asked nothing. Set it to test a path that depends on
    /// the terminal. Set before the app's first frame, it is the terminal the
    /// app starts in, as a running app learns its terminal before its first
    /// frame, so `.onAppear` reads it; set later, it changes as a terminal
    /// attached under tmux changes it, and the frames that causes are drawn.
    ///
    /// ```swift
    /// let app = TestApp { Game() }
    /// app.terminalCapabilities = TerminalCapabilities(supported: .keyReleases, unsupported: [])
    /// app.press(.left)                                            // held from here…
    /// app.press(KeyEvent(key: .left, phase: .release))            // …to here
    /// ```
    ///
    /// The keyboard's features (``TerminalCapabilities/Feature/keyReleases``,
    /// ``TerminalCapabilities/Feature/keyRepeats`` and the rest the kitty
    /// keyboard protocol negotiates) also set what the terminal is taken to
    /// report, as the protocol's negotiation does in a running app: a supported
    /// one is reported, an unsupported or undetermined one is not. The events
    /// themselves are the test's to send, with ``press(_:times:)``.
    public var terminalCapabilities: TerminalCapabilities {
        get { headless.terminalCapabilities }
        set {
            headless.terminalCapabilities = newValue
            headless.keyboardReporting = KeyboardReporting(newValue)
            if headless.framesDrawn > 0, headless.takeFrameRequest() { drawFrames() }
        }
    }

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
