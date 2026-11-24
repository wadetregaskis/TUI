//  🖥️ TUI — A Terminal UI framework for Swift
//  ScreenRedraw.swift
//
//  View ▸ Redraw and its key, F5: the whole screen written again, for a
//  screen something else wrote over (H-72; the owner's O-15 (a), 2026-11-21).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// TUI's Redraw: the frame writer forgets what it believes is on the screen,
/// and the next frame writes every row whole, as after a resize
/// (`RenderLoop.invalidateDiffCache()`).
///
/// The writer sends only the cells that changed since its last frame, judged
/// against its own record of the screen, never the terminal's. Whatever else
/// writes to the terminal — a stray `print`, a library logging to stderr,
/// another process writing to the tty, the terminal's own Clear Buffer —
/// leaves rows the writer believes are drawn and will not touch again until
/// they change. Resizing the window was the only way to have them repainted.
///
/// The key is F5. Most full-screen programs repaint on ⌃L, but here ⌃L is a
/// list row's swipe actions where the terminal does not report Shift on the
/// arrows (the owner's A48). F5 is the key that means refresh or reload in
/// browsers, file managers and Windows; it is free among TUI's own keys (F1
/// the list of keys, F2 the settings panel, F6 the toasts, F10 the menu
/// bar); and, being a framework default in the chain's last layer, an app
/// that binds F5 has it first, the menu item then naming no key. A terminal
/// sends it as `ESC[15~` (Terminal compatibility survey, "The redraw key").
package enum ScreenRedraw {
    /// F5, the redraw where nothing of the app's takes it.
    package static let key = Key.f5

    /// F5 as the menu bar's item shows it: AppKit's scalar for F5, as SwiftUI
    /// source names a function key.
    package static let shortcut = KeyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: [])
}
