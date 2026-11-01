//  🖥️ TUI — A Terminal UI framework for Swift
//  ChromeStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStyling

// MARK: - Chrome style

/// How the window's bars — the top bar and the bottom bar — separate
/// themselves from the page between them.
///
/// One style for both, because the two are read together: a boxed footer under
/// a ruled header looks like a mistake even though each is defensible alone. An
/// app chooses it with SwiftUI's `windowToolbarStyle(_:)` on the scene — see
/// ``WindowToolbarStyle`` for which style draws which frame — and a
/// ``StatusBar`` drawn as a view of its own takes one directly.
///
/// Every style draws with the current ``Appearance``'s border glyphs and the
/// palette's `border` colour, so a custom border restyles the chrome in step
/// with the rest of the app.
///
/// TUI-specific: SwiftUI has no app header or status bar.
public enum ChromeStyle: String, Sendable, Hashable, CaseIterable, Codable {
    /// Content, plus a full-width rule on the side facing the page — under the
    /// header, over the status bar.
    ///
    /// The lightest thing that still reads as a boundary. The two bars mirror
    /// each other, which is what makes a header and a footer look like a pair.
    ///
    /// ```
    /// My App                                    v1.0
    /// ────────────────────────────────────────────────
    ///  … the page …
    /// ────────────────────────────────────────────────
    ///   ↑↓ nav          ↩ select          ⌃Q quit
    /// ```
    case rule

    /// Content inside a full box, like a container view.
    ///
    /// The default: two extra rows per bar and a wall down each side, so the
    /// chrome reads as a panel of its own rather than as a margin.
    ///
    /// ```
    /// ╭──────────────────────────────────────────────╮
    /// │  ↑↓ nav          ↩ select          ⌃Q quit   │
    /// ╰──────────────────────────────────────────────╯
    /// ```
    case bordered

    /// Content alone — no rule, no box.
    ///
    /// The fewest rows a bar can occupy, for apps that would rather spend the
    /// height on the page. The bars are still distinguishable by their
    /// background colour (`appHeaderBackground` / `statusBarBackground`).
    case compact
}
