//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeysAfterFrame.swift
//
//  Keys to press once the frame being drawn is on the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Keys to press once the frame being drawn is on the screen, through the
/// whole input chain, as if typed then.
///
/// How a menu item does exactly what a key does where the key acts on what has
/// the focus: the menu bar's Copy is ⌘C to the focused view, its Quit the app's
/// quit key (TUIkitCommands). While a menu is open it holds the focus and the
/// keyboard, so the key cannot be sent from its item's action; the frame that
/// closes the menu hands the focus back to the page, and the key goes after it.
///
/// One per ``TUIContext``. The run loop drains it after each frame
/// (``take()``), handing each key to the input chain, and draws again when one
/// was. `@unchecked Sendable` as ``TerminalBell`` is: pressed from event
/// handlers and drained by the run loop, all on the main actor.
package final class KeysAfterFrame: @unchecked Sendable {
    /// The keys owed, in the order pressed.
    private var owed: [KeyEvent] = []

    /// Asks the run loop for a frame, so a key pressed with nothing else to
    /// draw still goes.
    private let requestFrame: @Sendable () -> Void

    package init(requestFrame: @escaping @Sendable () -> Void = { AppState.shared.setNeedsRender() }) {
        self.requestFrame = requestFrame
    }

    /// Presses `event` once the next frame is on the screen.
    package func press(_ event: KeyEvent) {
        owed.append(event)
        requestFrame()
    }

    /// The keys owed, in order, forgetting them.
    package func take() -> [KeyEvent] {
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
