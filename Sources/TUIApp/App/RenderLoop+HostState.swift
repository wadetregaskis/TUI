//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderLoop+HostState.swift
//
//  The terminal's window title, from the window in front, and its progress
//  bar, from the views drawn: what each frame asks of the terminal's ledger,
//  and writes of them, and what handing the terminal back gives back. And the
//  person's attention, as the app asked for it: a notification, or the bell.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension RenderLoop {
    /// The title the terminal's window, or tab, shows while the window in
    /// front is drawn, or `nil` for the terminal's own.
    ///
    /// A root `.navigationTitle` that no top bar shows, as the A28 design
    /// study decided (§9: a title alone creates no top bar, and sets the
    /// terminal's window title); else the window scene's own title —
    /// `WindowGroup("Notes") { … }`, `Window("Inspector", id: …)` — as on macOS,
    /// where a window's title is its navigation title, or its scene's.
    /// Decisions O9, B-O9-13.
    var terminalWindowTitle: String? {
        let chrome = windowChrome
        if !chrome.title.isEmpty, !chrome.topBarShowsTitle { return chrome.title }
        let title = scenes.front.flatMap { scenes.entry(of: $0) }?.window.windowTitle?.content
        return title?.isEmpty == false ? title : nil
    }

    /// The progress the views drawn this frame state (`.terminalProgress(_:)`):
    /// the last one drawn's, or `nil` where none states one. Read after the
    /// walk, from the preferences it collected at the root.
    var terminalProgress: TerminalProgress? {
        tuiContext.preferences.current[TerminalProgressKey.self]
    }

    /// The ledger of what the app has set on the terminal this loop draws on
    /// beyond its screen (``HostStateKeeping``): the terminal's, which the
    /// frames tell what they want, read here.
    var hostState: TerminalHostState { terminal.hostState }

    /// What this frame, drawn at `now` on the monotonic clock, writes to the
    /// terminal beyond its cells: the window title, where it changed since the
    /// last frame wrote it; and, to a terminal that takes one
    /// (``sendsProgressReports``), the progress bar, where it changed, or
    /// where it is due to be sent again. Each is asked of the terminal's
    /// ledger, which keeps what was sent and what that owes.
    ///
    /// Under tmux the bar is sent whether or not a client attached draws it:
    /// tmux keeps it for the pane and hands it to a client that can when one
    /// attaches (measured), so the app does not have to be told.
    func hostStateWrites(atNanos now: Int64) -> String {
        let wantedTitle = terminalWindowTitle
        let title = terminal.hostState.show(title: wantedTitle)
        guard sendsProgressReports else { return title }
        let wantedProgress = terminalProgress
        return title + terminal.hostState.show(progress: wantedProgress, atNanos: now)
            + terminal.hostState.keepAlive(atNanos: now)
    }

    /// Publishes, to `\.terminalFeatures`, whether the person sees the
    /// progress bar the frames send: where it is sent at all
    /// (``sendsProgressReports``), and under tmux only where every client
    /// attached draws the bar tmux passes on (`capabilities`, the tmux clients'
    /// answer, push-refreshed as they attach and detach). A change takes a
    /// frame: the render loop's `EnvironmentSnapshot` holds the value, so a
    /// memoized view that read it draws again.
    ///
    /// And the same answer to `\.terminalCapabilities`, as
    /// ``TerminalCapabilities/Feature/progressReports``: supported where the
    /// bar shows, else what ``progressAbsence`` says its absence means. Two
    /// bit tests a frame, and a write only on a change.
    func publishTerminalFeatures(_ capabilities: ClientCapabilities) {
        let showsProgress = sendsProgressReports && (!isTmux || capabilities.drawsProgressBars)
        let progressStatus: TerminalCapabilities.Status = showsProgress ? .supported : progressAbsence
        let known = tuiContext.terminalCapabilities
        if known.status(of: .progressReports) != progressStatus {
            tuiContext.terminalCapabilities = known.settling(.progressReports, as: progressStatus)
        }
        let features = tuiContext.terminalFeatures
        guard features.showsProgress != showsProgress else { return }
        tuiContext.terminalFeatures = features.withProgress(
            showsProgress: showsProgress, postsNotifications: features.postsNotifications)
    }

    /// Sends the progress bar again where it is due at `now` on the monotonic
    /// clock (``TerminalHostState/keepAlive(atNanos:)``), straight to the
    /// terminal: the run loop's write between frames, which draws nothing.
    func keepHostStateAlive(atNanos now: Int64) {
        let resend = terminal.hostState.keepAlive(atNanos: now)
        if !resend.isEmpty { terminal.write(resend) }
    }

    /// What this frame writes to get the person's attention: a notification
    /// for each message the app asked with (`requestAttention(_:)`), where the
    /// terminal posts one (``TerminalFeatures/postsNotifications``); and the
    /// bell — once, however often it was asked for — for input a control
    /// turned away, and for attention where no notification is posted or its
    /// message leaves nothing to say. Each half empty where nothing is owed.
    func attentionWrites() -> (notifications: String, bell: String) {
        let owed = tuiContext.terminalBell
        var rings = !owed.takePending().isEmpty
        var notifications = ""
        let posts = tuiContext.terminalFeatures.postsNotifications
        for message in owed.takePendingAttention() {
            if posts, let notification = TerminalHostState.notification(message) {
                notifications += notification
            } else {
                rings = true
            }
        }
        return (notifications, rings ? TerminalHostState.bell : "")
    }

    /// What handing the terminal back to the shell — a suspend, or the exit —
    /// writes: the terminal's own title, restored where the app saved it, and
    /// the app's progress bar taken down; owed no more from now
    /// (`Terminal.hostState`). The next frame drawn, after a resume, sets both
    /// again.
    func handBackHostState() -> String {
        terminal.hostState.restore()
    }
}
