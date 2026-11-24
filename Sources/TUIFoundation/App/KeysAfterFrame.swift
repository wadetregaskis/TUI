//  🖥️ TUI — A Terminal UI framework for Swift
//  KeysAfterFrame.swift
//
//  Keys to press once the frame being drawn is on the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Keys to press once the frame being drawn is on the screen, through the
/// whole input chain, as if typed then — and the app's quit, asked for then.
///
/// It is also where an app's posted keys wait (``PostKeyEventAction``, the
/// owner's ruling A-POSTKEY-1, 2026-11-20): delivered here rather than at
/// once, so a key posted from inside a key handler waits for the current key
/// to finish, and for the next frame, instead of running the chain from
/// inside itself. A key posted while the owed keys are being pressed is owed
/// to the frame after, as ``take()`` hands over only what was owed before.
///
/// How a menu item does exactly what a key does where the key acts on what has
/// the focus: the menu bar's Copy is ⌘C to the focused view (TUICommands).
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
/// anything was owed. Not `Sendable`, as ``TerminalBell`` is not: it is pressed
/// from event handlers and drained by the run loop, all on the main actor.
package final class KeysAfterFrame {
    /// What is owed once the frame is on the screen.
    package enum Owed {
        /// A key, through the whole input chain, as if typed then.
        case key(KeyEvent)

        /// A key the app posted (``PostKeyEventAction``), through the whole
        /// input chain as the keyboard's: noted as the keyboard's input, as
        /// the run loop notes a typed key, so a menu it opens opens with a
        /// row highlighted. A menu item's ``key(_:)`` is not noted: it is
        /// pressed under the input that chose the item.
        case posted(KeyEvent)

        /// The app's quit, as the quit key asks for it where nothing else
        /// takes the key: through the status bar, which may ask first (a
        /// top-level dismissal confirmation) or refuse
        /// (`StatusBarState.isQuitAllowed`). No key goes anywhere.
        case quit

        /// The list of keyboard shortcuts, as F1 asks for it where nothing else
        /// takes the key, of the frame with the menu closed. No key goes
        /// anywhere: an app's own F1 is not what the Help menu's item means.
        case keyboardShortcutOverlay

        /// The whole screen written again by the next frame, as the redraw
        /// key asks for it (View ▸ Redraw). No key goes anywhere: an app's own
        /// F5 is not what the View menu's item means.
        case redraw
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

    /// Posts `event` for the next frame: delivered once that frame is on the
    /// screen, through the whole input chain, as the keyboard's.
    package func post(_ event: KeyEvent) {
        owed.append(.posted(event))
        requestFrame()
    }

    /// Asks for the app's quit once the next frame is on the screen.
    package func quit() {
        owed.append(.quit)
        requestFrame()
    }

    /// Asks for the list of keyboard shortcuts once the next frame is on the
    /// screen.
    package func showKeyboardShortcutOverlay() {
        owed.append(.keyboardShortcutOverlay)
        requestFrame()
    }

    /// Asks for the whole screen to be written again once the next frame
    /// is on the screen.
    package func redraw() {
        owed.append(.redraw)
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
    static var defaultValue: KeysAfterFrame? { nil }
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
