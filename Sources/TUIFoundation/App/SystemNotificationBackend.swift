//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemNotificationBackend.swift
//
//  The operating system's own notifications, as a context reaches them: the
//  app's run loop installs this machine's, and every other context keeps what
//  it is handed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization

/// The operating system's own notifications, for a toast posted to the desktop
/// that the terminal cannot carry: what ``TUIContext/systemNotifier`` holds.
///
/// The app's run loop installs this machine's (`SystemNotifier`, TUIApp:
/// `osascript` or `notify-send`, only where the person is at this machine);
/// every other context — a headless run's, a test's — gets an
/// ``InMemorySystemNotifier``, so nothing but a running app posts a real
/// notification.
package protocol SystemNotificationBackend: Sendable {
    /// Posts `message` where this backend can and should, here and now,
    /// without making the caller wait: the run loop calls it from a frame.
    func post(_ message: String)
}

/// A system notifier that posts nothing and keeps what it was handed: what a
/// context gets unless the app's run loop installs this machine's
/// (``SystemNotificationBackend``). One per context, so two contexts in one
/// process — a test suite — keep their messages apart.
package final class InMemorySystemNotifier: SystemNotificationBackend {
    private let messages = Mutex<[String]>([])

    /// A notifier that has been handed nothing. Spelled out because the
    /// implicit initializer is internal, and every context TUIFoundation makes
    /// holds one.
    package init() {}

    /// Every message handed over, oldest first.
    package var posted: [String] { messages.withLock { $0 } }

    /// Keeps `message`.
    package func post(_ message: String) {
        messages.withLock { $0.append(message) }
    }
}
