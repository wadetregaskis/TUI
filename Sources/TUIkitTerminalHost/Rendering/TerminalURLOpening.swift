//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalURLOpening.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Whether this process may launch a browser

/// Whether ``OpenURLAction`` may hand a URL to the system opener.
///
/// The render path and the activation path are not main-actor isolated and
/// cannot go asking a terminal anything, so the answer is published here and
/// read from there — the same shape as ``TerminalHyperlink/isSupported``.
package enum TerminalURLOpening {
    /// `false` unless something turned it on. See ``TerminalClient/urlOpeningSupport``.
    ///
    /// `nonisolated(unsafe)` for the reason `TerminalHyperlink.isSupported` is:
    /// written once at startup, before anything renders, and read from paths
    /// that have no actor.
    package nonisolated(unsafe) static var isEnabled = false

    /// The opener of the app this process is running, for an action no
    /// environment handed one: an ``OpenURLAction`` the app made itself
    /// (`OpenURLAction { … }`) and calls directly.
    ///
    /// SwiftUI's `systemAction` "asks the system to open the original URL",
    /// with no condition on where the action came from, and before the opener
    /// was injected such an action did launch one. An action read from an
    /// environment carries that environment's opener
    /// (``EnvironmentValues/urlOpener``); a hand-made one has none, and is
    /// called from wherever the app calls it — a button's action, a `Task`, a
    /// `DispatchQueue.main` block — so the one thing that reaches all of them
    /// is the process. Without this it would answer `false` and launch nothing
    /// in a running app with opening on: a silent no-op.
    ///
    /// The app's run loop publishes its context's opener as it starts, beside
    /// ``isEnabled``, and withdraws it when the run ends (`AppRunner.run()`).
    /// Nothing else writes it, so outside a running app it is `nil`, and a
    /// headless run, a snapshot or a test still launches nothing. Not a
    /// singleton: the framework creates nothing here; the value is the
    /// running context's own opener, published for the callers no context
    /// reaches. An action that carries an opener uses that one first.
    ///
    /// Behind a lock rather than `nonisolated(unsafe)` like ``isEnabled``: it
    /// holds a reference and is written twice, and a torn read of a
    /// reference is a crash rather than a stale answer. Read only when a
    /// deferral reaches the opener, never per frame.
    package static var runLoopOpener: (any URLOpenerBackend)? {
        get { runLoopOpenerStore.withLock { $0 } }
        set { runLoopOpenerStore.withLock { $0 = newValue } }
    }

    private static let runLoopOpenerStore = Lock<(any URLOpenerBackend)?>(initialState: nil)
}

// MARK: - This machine's opener

/// This machine's URL opener, as ``OpenURLAction`` reaches it when a handler
/// defers to the system (``OpenURLAction/Result/systemAction``) and
/// ``TerminalURLOpening/isEnabled`` lets it.
///
/// Declared here and implemented above: the app's run loop installs the one
/// that launches `open` or `xdg-open` (`SystemURLOpener`, a subprocess, which
/// belongs with the run loop's other POSIX code) into the ``TUIContext`` it
/// creates, and every other context — a headless run's, a snapshot's, a
/// test's — gets an ``InMemoryURLOpener``, so nothing but a running app ever
/// launches a browser. The environment carries the context's opener
/// (``EnvironmentValues/urlOpener``), and an action read from it carries it
/// on, so a URL opened from an event handler, long after the render, still
/// reaches the context that drew the link.
package protocol URLOpenerBackend: Sendable {
    /// Hands `url` to the opener, answering whether it took it.
    func open(_ url: URL) -> Bool
}

/// A URL opener that launches nothing and keeps what it was handed: what a
/// context gets unless the app's run loop installs this machine's
/// (``URLOpenerBackend``).
///
/// One per context, so two contexts in one process — a test suite — keep
/// their URLs apart.
package final class InMemoryURLOpener: URLOpenerBackend {
    private let urls = Lock<[URL]>(initialState: [])

    /// An opener that has been handed nothing. Spelled out because the
    /// implicit initializer is internal, and every context TUIkitFoundation
    /// makes holds one.
    package init() {}

    /// Every URL handed over, oldest first.
    var opened: [URL] { urls.withLock { $0 } }

    /// Keeps `url`, and answers that it was taken.
    package func open(_ url: URL) -> Bool {
        urls.withLock { $0.append(url) }
        return true
    }
}

extension TerminalClient {

    /// Whether TUIkit may open a URL by launching a browser on **this**
    /// machine. `nil` (the default) means no.
    ///
    /// ## Why the default is no
    ///
    /// `OpenURLAction`'s system opener runs `/usr/bin/open` or
    /// `/usr/bin/xdg-open` **on the machine the application is running on**.
    /// Locally that is the user's own browser and is exactly right. Over ssh it
    /// is the server's — and a server is either headless, where `xdg-open`
    /// ships in a desktop package most server images do not carry and the
    /// launch is a silent no-op, or it is somebody's desktop, where the URL
    /// lands in a browser in front of a person who did not ask for it and stays
    /// in their history.
    ///
    /// **And the framework cannot tell which it is.** `SSH_CONNECTION`,
    /// `SSH_TTY` and `SSH_CLIENT` are reliable when PRESENT and prove nothing
    /// when absent: they are gone under `sudo` and `su`, and a tmux, screen or
    /// zellij session started before the hop — or reattached after it — carries
    /// the environment of whenever it began rather than of the client now
    /// looking at it. There is no query that asks a terminal which machine it
    /// is on. So "am I local?" has no answer this framework can trust, and the
    /// cost of the two wrong answers is not symmetric: guessing local when
    /// remote sends somebody's URL to a machine they are not at, and guessing
    /// remote when local costs a copy and paste.
    ///
    /// A `Link` is not silent as a result — that is what makes this bearable.
    /// It carries an OSC 8 hyperlink where the terminal honours one, so the
    /// terminal (which IS on the user's machine) can open it; and activating
    /// one raises a popover with the destination to read and copy. See
    /// ``LinkDisplay``.
    ///
    /// ## Turning it on
    ///
    /// `true` for a tool that knows it is local — a local-only developer
    /// utility, an app whose own launcher guarantees it. `TUIKIT_OPEN_URLS=1`
    /// in the environment does the same, which is how a USER answers for their
    /// own session without the application knowing anything about it, and
    /// `TUIKIT_OPEN_URLS=0` forces it off against an app that turned it on.
    ///
    /// An app that wants to open URLs its own way needs none of this: an
    /// `OpenURLAction` handler that does the work and returns
    /// ``OpenURLAction/Result/handled`` is untouched by this setting. What is
    /// gated is only the framework launching a process on the user's behalf.
    @MainActor public static var urlOpeningSupport: Bool? {
        didSet {
            guard urlOpeningSupport != oldValue else { return }
            applyURLOpeningSupport()
        }
    }

    /// Whether a URL handed to the system opener would actually be launched —
    /// the environment's kill switch, then the override, then the environment's
    /// opt-in, then `false`.
    @MainActor public static var urlOpeningEnabled: Bool {
        urlOpeningEnabled(override: urlOpeningSupport, environment: ProcessInfo.processInfo.environment)
    }

    /// The ladder behind ``urlOpeningEnabled``, posed on its inputs — the shape
    /// `ColorDepth.detect(environment:)` has — so it can be asked without
    /// setting anything a whole process reads.
    static func urlOpeningEnabled(override: Bool?, environment: [String: String]) -> Bool {
        let environment = environment["TUIKIT_OPEN_URLS"]
        // `=0` FIRST, ahead of the app's own answer. A user who exported it is
        // saying "not on this machine", and the app cannot know better: it is
        // the one party here that does not know where it is running. (This
        // arm used to sit BEHIND the override, where it could never fire.)
        if environment == "0" { return false }
        if let override { return override }
        // `=1` answers for the user only where the app has not answered: an
        // app that said `false` had a reason, and opening a browser is the
        // one direction to err away from.
        return environment == "1"
    }

    /// Publishes ``urlOpeningEnabled`` to the flag the activation path reads.
    ///
    /// Called once at startup — before anything can be activated — and again
    /// from the setter, whose whole point is changing it.
    @MainActor
    public static func applyURLOpeningSupport() {
        TerminalURLOpening.isEnabled = urlOpeningEnabled
    }
}
