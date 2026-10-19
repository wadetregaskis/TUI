//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+HostState.swift
//
//  The terminal's window title, from the window in front: what each frame
//  writes of it, and what handing the terminal back gives back.
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

    /// What this frame writes to the terminal beyond its cells: the window
    /// title, where it changed since the last frame wrote it.
    func hostStateWrites() -> String {
        hostState.show(title: terminalWindowTitle)
    }

    /// What handing the terminal back to the shell — a suspend, or the exit —
    /// writes: the terminal's own title, restored where the app saved it. The
    /// next frame drawn, after a resume, saves and sets it again.
    func handBackHostState() -> String {
        hostState.restore()
    }
}
