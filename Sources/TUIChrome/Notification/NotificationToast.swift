//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationToast.swift
//
//  One toast, composed from views.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Notification Toast

/// One toast as the scene draws it: the message — or the views the post gave
/// in its place — led by its style's glyph, with its buttons on the last row,
/// inside a border in its style's colour.
///
/// Composed from views rather than assembled line by line, so the message is
/// a `Text` like any other — wrapped to the toast's width, bold under a bold
/// legibility weight — its buttons are `Button`s, and the glyph and the border
/// are the modifiers every view has.
///
/// Its buttons sit at its trailing edge. Its emoji — its style's glyph, and any
/// in the message or the views — are drawn only while it is fully opaque.
///
/// It is drawn at full strength whatever its `opacity`: the fade is its
/// layer's (``NotificationOverlay``), from outside it, so it takes the toast's
/// surface toward the page behind. A fade applied here, inside the surface,
/// faded toward that surface, and the toast was a blank box over the page
/// through both its fades. Its structure — and the identities of everything in
/// it, its buttons' focus included — never changes between its fade-in and the
/// rest of its life.
struct NotificationToast: View {
    /// The notification drawn.
    let entry: NotificationEntry

    /// The toast's width, border included.
    let width: Int

    /// How opaque its layer is drawn: 0 to 1, the fades at either end of its
    /// life. Read here only for its emoji, which wait for a full 1.
    let opacity: Double

    /// What choosing one of the toast's buttons does with its action: runs it,
    /// dismisses the toast and moves the focus on — once, as the toast's are
    /// still drawn, and still take a click, for the fade-out that follows.
    let choose: @MainActor (_ action: @escaping @MainActor @Sendable () -> Void) -> Void

    /// The cells the border takes from the width: its line and the blank cell
    /// inside it, either side.
    static let chromeWidth = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 1) {
                if let glyph = entry.style.glyph {
                    // Bold and in the style's colour, which an emoji ignores —
                    // it is drawn in its own — but the ASCII a plain-text
                    // terminal gets in its place (`PlainTerminalText`) keeps.
                    Text(verbatim: glyph).bold().foregroundStyle(entry.style.colour)
                }
                if let content = entry.content {
                    content()
                } else {
                    Text(verbatim: entry.message)
                }
            }
            let buttons = Self.buttons(of: entry)
            if !buttons.isEmpty {
                HStack(spacing: 1) {
                    ForEach(buttons.indices, id: \.self) { index in
                        Button(buttons[index].title, role: buttons[index].role) {
                            choose(buttons[index].handler)
                        }
                        .focusID(NotificationKeyboard.focusID(entry.id, button: index))
                    }
                }
                // At the toast's trailing edge, as a dialog's are, while its
                // message reads from the leading one (the owner, 2026-11-10).
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: max(1, width - Self.chromeWidth), alignment: .leading)
        // The framework's chrome keeps the blank cell inside its line that an
        // app's `.border()` no longer draws (the owner, 2026-11-17).
        .bordered(style: nil, colour: AnimatedColor(entry.style.colour), width: 1, insetsContent: true)
        // An emoji is drawn in colours of its own, which no fade reaches, so
        // it would stand at full strength while the rest fades in round it.
        // It waits for the fade-in to finish and goes as the fade-out starts,
        // its cells blank meanwhile (the owner's ruling NOTIF-EMOJI (a),
        // 2026-11-10). Applied at 1 too, so the structure never changes.
        .hidingEmoji(opacity < 1)
    }

    /// The buttons the toast of `entry` carries: its actions, or — for one
    /// posted to stay until dismissed, with none — a Close button, so the
    /// keyboard can always take it away.
    static func buttons(of entry: NotificationEntry) -> [NotificationAction] {
        guard entry.actions.isEmpty, entry.staysUntilDismissed else { return entry.actions }
        let close = LocalizationService.shared.string(for: LocalizationKey.Button.close)
        return [NotificationAction(verbatim: close, role: .close) {}]
    }
}
