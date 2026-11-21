//  🖥️ TUI — A Terminal UI framework for Swift
//  PostKeyEventAction.swift
//
//  Sending a key into the app's input chain from something that is not the
//  terminal: a gamepad, a remote, a script.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Post Key Event Action

/// An action that sends a key event through the app's whole input chain, as
/// if the terminal had just reported it.
///
/// For another input device whose presses stand for keys — a gamepad's
/// buttons, a remote, a foot pedal — so that each goes where the key it
/// stands for goes, by the rules the keys already follow: the `onKeyPress`
/// handlers round the focused view, outermost first; the focused control; the
/// status bar's items; the app's `.keyboardShortcut`s and the menu bar's; and
/// TUI's own keys last (F1's list, the quit key). A modal holds a posted key
/// as it holds a typed one, a disabled control does not hear it, and a press
/// nothing takes rings the bell.
///
/// ```swift
/// @Environment(\.postKeyEvent) private var postKeyEvent
///
/// var body: some View {
///     Game()
///         .task {
///             for await button in gamepad.buttons {
///                 postKeyEvent(KeyEvent(key: button.key, phase: button.isDown ? .press : .release))
///             }
///         }
/// }
/// ```
///
/// **Phases are delivered as posted.** A ``KeyEvent/Phase/release`` reaches
/// the `onKeyPress(phases:)` handlers that ask for ``KeyPress/Phases/up``, and
/// a ``KeyEvent/Phase/repeat`` those that ask for repeats, whether or not the
/// terminal itself reports releases and repeats: a device that says when its
/// button comes up can hold a key down where the keyboard cannot. As with a
/// typed key, nothing but a key-press handler acts on a release.
///
/// **Queued, never nested.** A posted key is not handled while the call
/// returns. It is delivered once the frame being drawn is on the screen, in
/// the order posted, each as a key typed then, and the frame after shows what
/// it did. So it acts on the focus and the views the person can see, and a key
/// posted from inside a key handler — an `onKeyPress` that turns one key into
/// another, or a posted key's own handler — waits for the current key to
/// finish and for the next frame, rather than running the chain again from
/// inside itself. A handler that posts a key every time it hears one posts
/// one key a frame, never a loop that does not return. The cost is up to a
/// frame of latency (about 17 ms at the default rate) over a key typed at the
/// same instant.
///
/// Not ``FocusManager/dispatchKeyEvent(_:)``, which is one layer of the chain,
/// the focus system's, and reaches no `onKeyPress` handler, status-bar item or
/// shortcut. Not ``KeyboardShortcut``: a posted key is a key, which a
/// shortcut on that key then fires on, as it would for the keyboard.
///
/// Outside a running app — a snapshot, a view rendered on its own — there is
/// no chain, and posting does nothing. A `TestApp` has one: a key posted there
/// is delivered after the next frame the test draws, by its next event,
/// `advance(by:)` or a read of its screen.
///
/// TUI-specific: SwiftUI has no way to post a key event, and AppKit's
/// `NSApplication.postEvent(_:atStart:)` is not SwiftUI.
public struct PostKeyEventAction {
    /// Where a posted key waits for the frame to be on the screen: the
    /// running app's keys after the frame, or `nil` outside a running app,
    /// where no chain could take it.
    private let keys: KeysAfterFrame?

    /// The action that posts into `keys`.
    package init(keys: KeysAfterFrame?) {
        self.keys = keys
    }

    /// Sends `event` through the app's whole input chain, once the frame being
    /// drawn is on the screen.
    ///
    /// - Parameter event: The key, its modifiers and its phase, as the
    ///   terminal would report them.
    @MainActor
    public func callAsFunction(_ event: KeyEvent) {
        keys?.post(event)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// An action that sends a key event through the app's whole input chain,
    /// as if the terminal had reported it — see ``PostKeyEventAction``.
    ///
    /// Read-only: the running app's own, which reaches every view it draws.
    /// Outside a running app it does nothing.
    public var postKeyEvent: PostKeyEventAction {
        PostKeyEventAction(keys: keysAfterFrame)
    }
}
