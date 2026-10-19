//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeysAfterFrame.swift
//
//  Keys to press once the frame being drawn is on the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Keys to press once the frame being drawn is on the screen, through the
/// whole input chain, as if typed then — and the app's quit, asked for then.
///
/// How a menu item does exactly what a key does where the key acts on what has
/// the focus: the menu bar's Copy is ⌘C to the focused view (TUIkitCommands).
/// While a menu is open it holds the focus and the keyboard, so the key cannot
/// be sent from its item's action; the frame that closes the menu hands the
/// focus back to the page, and the key goes after it.
///
/// The menu bar's Quit is NOT the quit key pressed: a key through the whole
/// chain reaches the focused view first, and a focused text field typed the
/// `q` instead of quitting. It is the quit itself (``quit()``), which the run
/// loop asks for as the quit key does where nothing else takes the key.
///
/// One per ``TUIContext``. The run loop drains it after each frame
/// (``take()``), handing each key to the input chain, and draws again when
/// anything was owed. `@unchecked Sendable` as ``TerminalBell`` is: pressed
/// from event handlers and drained by the run loop, all on the main actor.
package final class KeysAfterFrame: @unchecked Sendable {
    /// What is owed once the frame is on the screen.
    package enum Owed {
        /// A key, through the whole input chain, as if typed then.
        case key(KeyEvent)

        /// The app's quit, as the quit key asks for it where nothing else
        /// takes the key: through the status bar, which may ask first (a
        /// top-level dismissal confirmation) or refuse
        /// (`StatusBarState.isQuitAllowed`). No key goes anywhere.
        case quit
    }

    /// What is owed, in the order asked for.
    private var owed: [Owed] = []

    /// Asks the run loop for a frame, so a key pressed with nothing else to
    /// draw still goes.
    private let requestFrame: @Sendable () -> Void

    package init(requestFrame: @escaping @Sendable () -> Void) {
        self.requestFrame = requestFrame
    }

    /// Presses `event` once the next frame is on the screen.
    package func press(_ event: KeyEvent) {
        owed.append(.key(event))
        requestFrame()
    }

    /// Asks for the app's quit once the next frame is on the screen.
    package func quit() {
        owed.append(.quit)
        requestFrame()
    }

    /// What is owed, in order, forgetting it.
    package func take() -> [Owed] {
        guard !owed.isEmpty else { return [] }
        defer { owed.removeAll() }
        return owed
    }
}

private struct KeysAfterFrameKey: EnvironmentKey {
    static let defaultValue: KeysAfterFrame? = nil
}

extension EnvironmentValues {
    /// The running app's keys to press after the frame — its context's,
    /// handed down each frame (`applyRuntimeServices(from:)`) — or `nil` where
    /// no context's services reached, and no key could go anywhere.
    package var keysAfterFrame: KeysAfterFrame? {
        get { self[KeysAfterFrameKey.self] }
        set { self[KeysAfterFrameKey.self] = newValue }
    }
}
