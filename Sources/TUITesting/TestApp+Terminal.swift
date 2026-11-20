//  🖥️ TUI — A Terminal UI framework for Swift
//  TestApp+Terminal.swift
//
//  What a test can say about the terminal around the app: its window losing
//  and gaining the focus, and what the terminal can do; and what the app sent
//  the terminal beyond its cells: its progress bar and desktop notifications.
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

    /// The progress the app last sent for the terminal to show on its tab or
    /// window, which its views state with `.terminalProgress(_:)`, or `nil`
    /// while none states one.
    ///
    /// It is not on the ``screen``: a terminal draws it beside the app's
    /// cells. A running app sends it only to a terminal that draws a progress
    /// bar; this is what it would send to one, whatever
    /// ``terminalCapabilities`` says.
    ///
    /// ```swift
    /// app.press(.character("s"), modifiers: .control)     // starts a scan
    /// #expect(app.terminalProgress == .indeterminate)
    /// ```
    public var terminalProgress: TerminalProgress? {
        start()
        drawAskedFrames()
        return headless.terminalProgress
    }

    /// The messages the app has posted on the desktop, oldest first: each
    /// toast posted with a `desktop:` delivery that applied when the frame
    /// after the post drew it.
    ///
    /// Nothing reaches the desktop of the machine the test runs on. A running
    /// app posts these through the terminal where it posts notifications, and
    /// otherwise through the machine's own; a message lands here either way.
    /// A toast that asks for `.whenInactive` is posted only while the window
    /// is in the background, as ``reportFocus(_:)`` puts it:
    ///
    /// ```swift
    /// app.reportFocus(false)
    /// app.press(.character("s"), modifiers: .control)     // posts "Scan finished"
    /// #expect(app.desktopNotifications == ["Scan finished"])
    /// ```
    ///
    /// A toast is sent by the frame that first draws it, so one posted through
    /// `NotificationService.current`, which no `TestApp` draws, is not here.
    /// Nor is a `\.requestAttention` call: a `TestApp`'s terminal is not taken
    /// to post notifications, so that one rings the bell instead.
    public var desktopNotifications: [String] {
        start()
        drawAskedFrames()
        return headless.desktopNotificationsPosted
    }
}
