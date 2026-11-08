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
/// inside a border in its style's colour, faded to `opacity`.
///
/// Composed from views rather than assembled line by line, so the message is
/// a `Text` like any other — wrapped to the toast's width, bold under a bold
/// legibility weight — its buttons are `Button`s, and the glyph, the border
/// and the fade are the modifiers every view has.
///
/// The fade is always applied, at 1 for the visible stretch, so the toast's
/// structure — and the identities of everything in it, its buttons' focus
/// included — never changes between its fade-in and the rest of its life.
struct NotificationToast: View {
    /// The notification drawn.
    let entry: NotificationEntry

    /// The toast's width, border included.
    let width: Int

    /// How opaque it is: 0 to 1, the fades at either end of its life.
    let opacity: Double

    /// Called after one of the toast's buttons ran its action: dismisses the
    /// toast and moves the focus on.
    let chosen: @MainActor () -> Void

    /// The cells the border takes from the width: its line and the blank cell
    /// inside it, either side.
    static let chromeWidth = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 1) {
                if let glyph = entry.style.glyph {
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
                            buttons[index].handler()
                            chosen()
                        }
                        .focusID(NotificationKeyboard.focusID(entry.id, button: index))
                    }
                }
            }
        }
        .frame(width: max(1, width - Self.chromeWidth), alignment: .leading)
        .border(entry.style.colour)
        .opacity(opacity)
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
