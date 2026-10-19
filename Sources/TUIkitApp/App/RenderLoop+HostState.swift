//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+HostState.swift
//
//  The terminal's window title, from the window in front, and its progress
//  bar, from the views drawn: what each frame writes of them, and what handing
//  the terminal back gives back.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

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

    /// What this frame, drawn at `now` on the monotonic clock, writes to the
    /// terminal beyond its cells: the window title, where it changed since the
    /// last frame wrote it; and, on a terminal that draws one
    /// (``TerminalFeatures/showsProgress``), the progress bar, where it
    /// changed, or where it is due to be sent again.
    func hostStateWrites(atNanos now: Int64) -> String {
        let title = hostState.show(title: terminalWindowTitle)
        guard tuiContext.terminalFeatures.showsProgress else { return title }
        return title + hostState.show(progress: terminalProgress, atNanos: now)
            + hostState.keepAlive(atNanos: now)
    }

    /// What handing the terminal back to the shell — a suspend, or the exit —
    /// writes: the terminal's own title, restored where the app saved it, and
    /// the app's progress bar taken down. The next frame drawn, after a
    /// resume, sets both again.
    func handBackHostState() -> String {
        hostState.restore()
    }
}
