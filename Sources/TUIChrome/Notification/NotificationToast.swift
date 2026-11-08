//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationToast.swift
//
//  One toast, composed from views.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Notification Toast

/// One toast as the scene draws it: the message, led by its style's glyph,
/// inside a border in its style's colour, faded to `opacity`.
///
/// Composed from views rather than assembled line by line, so the message is
/// a `Text` like any other — wrapped to the toast's width, bold under a bold
/// legibility weight — and the glyph, the border and the fade are the
/// modifiers every view has.
///
/// The fade is always applied, at 1 for the visible stretch, so the toast's
/// structure — and the identities of everything in it — never changes
/// between its fade-in and the rest of its life.
struct NotificationToast: View {
    /// The notification drawn.
    let entry: NotificationEntry

    /// The toast's width, border included.
    let width: Int

    /// How opaque it is: 0 to 1, the fades at either end of its life.
    let opacity: Double

    /// The cells the border takes from the width: its line and the blank cell
    /// inside it, either side.
    static let chromeWidth = 4

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            if let glyph = entry.style.glyph {
                Text(verbatim: glyph).bold().foregroundStyle(entry.style.colour)
            }
            Text(verbatim: entry.message)
        }
        .frame(width: max(1, width - Self.chromeWidth), alignment: .leading)
        .border(entry.style.colour)
        .opacity(opacity)
    }
}
