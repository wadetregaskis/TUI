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
/// | ``info`` | `Color.palette.info` | ℹ️ |
/// | ``success`` | `Color.palette.success` | ✅ |
/// | ``warning`` | `Color.palette.warning` | ⚠️ |
/// | ``error`` | `Color.palette.error` | ❌ |
///
/// The glyphs are emoji, two cells wide, in the forms that are emoji
/// everywhere: ℹ️ and ⚠️ carry U+FE0F, which asks for the emoji presentation
/// their bases lack by default, and ✅ and ❌ are emoji without it. An emoji
/// is drawn in its own colours, so the palette's colour is the border's: the
/// meaning rests on the glyph's shape, never on a colour. Where a terminal
/// advances the cursor a cell short over one, the writer makes up the cell,
/// as for any emoji (measured for these four: *Terminal compatibility
/// survey*, "Notification glyphs"). A terminal that can show nothing but ASCII
/// gets `!`, `i`, `ok` and `X` in their place, in the style's colour.
///
/// TUI-specific: SwiftUI has no toast.
public enum NotificationStyle: Hashable, Sendable, CaseIterable {
    /// No particular meaning: the palette's border colour and no glyph — a
    /// toast as it looked before toasts had styles.
    case plain
    /// News the person may want: the palette's `info` colour, led by ℹ️.
    case info
    /// Something finished as hoped: the palette's `success` colour, led by ✅.
    case success
    /// Something the person should look at: the palette's `warning` colour,
    /// led by ⚠️.
    case warning
    /// Something failed: the palette's `error` colour, led by ❌.
    case error
}

extension NotificationStyle {
    /// The glyph a toast of this style leads with: `nil` for ``plain``.
    ///
    /// The alert presets' marks (`AlertPanelMark`, a module above this one)
    /// but for an error: ❌, a failure reported, where an alert's 🛑 stops the
    /// person before they go on. Spelled by scalar, so the selector is seen.
    var glyph: String? {
        switch self {
        case .plain: nil
        case .info: "\u{2139}\u{FE0F}"
        case .success: "\u{2705}"
        case .warning: "\u{26A0}\u{FE0F}"
        case .error: "\u{274C}"
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
