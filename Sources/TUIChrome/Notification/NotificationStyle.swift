//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationStyle.swift
//
//  What a notification is about, which its toast's colour and glyph say.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Notification Style

/// What a notification is about: news, a success, a warning or an error,
/// which its toast says twice — in the palette's colour for it, and with a
/// glyph it leads with, so the meaning never rests on colour alone.
///
/// ```swift
/// NotificationService.current.post("Upload failed", style: .error)
/// ```
///
/// | Style | Colour | Glyph |
/// |---|---|---|
/// | ``plain`` | the palette's border colour | none |
/// | ``info`` | `Color.palette.info` | `i` |
/// | ``success`` | `Color.palette.success` | `✓` |
/// | ``warning`` | `Color.palette.warning` | `!` |
/// | ``error`` | `Color.palette.error` | `✗` |
///
/// The glyphs are one cell wide in every terminal: `ℹ` and `⚠`, the obvious
/// choices, have emoji presentations some terminals draw two cells wide.
///
/// TUI-specific: SwiftUI has no toast.
public enum NotificationStyle: Hashable, Sendable, CaseIterable {
    /// No particular meaning: the palette's border colour and no glyph — a
    /// toast as it looked before toasts had styles.
    case plain
    /// News the person may want: the palette's `info` colour, led by `i`.
    case info
    /// Something finished as hoped: the palette's `success` colour, led by `✓`.
    case success
    /// Something the person should look at: the palette's `warning` colour,
    /// led by `!`.
    case warning
    /// Something failed: the palette's `error` colour, led by `✗`.
    case error
}

extension NotificationStyle {
    /// The glyph a toast of this style leads with: `nil` for ``plain``.
    var glyph: String? {
        switch self {
        case .plain: nil
        case .info: "i"
        case .success: "✓"
        case .warning: "!"
        case .error: "✗"
        }
    }

    /// The colour a toast of this style is bordered in, and its glyph drawn
    /// in: the palette's semantic colour, or its border colour for ``plain``.
    var colour: Color {
        switch self {
        case .plain: Color.palette.border
        case .info: Color.palette.info
        case .success: Color.palette.success
        case .warning: Color.palette.warning
        case .error: Color.palette.error
        }
    }
}
