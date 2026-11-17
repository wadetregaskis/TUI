//  🖥️ TUI — A Terminal UI framework for Swift
//  TextDrop.swift
//
//  Dropped text: what a `TextField`, a `SecureField` and a `TextEditor` take
//  from a drag, as SwiftUI's do. Measured on macOS 15.8.3
//  (`Tools/SwiftUIProbes/Pasted line breaks and drops (1117)/paste.out`): a
//  field takes a dropped string only while it is focused — an unfocused one
//  registers for no drag types — and its field editor inserts it as a copy;
//  a `TextEditor` takes one focused or not, and the focus stays where it was.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The drop zone a text control registers for dragged text.
@MainActor
enum TextDrop {
    /// The text `payload` is, for a text control: a `String`, alone. A
    /// selection of several values (`DragItems`) is not text to insert, as no
    /// measurement says how a field would join them.
    static func text(of payload: Any) -> String? {
        let items = DragAndDropSession.items(of: payload)
        guard items.count == 1 else { return nil }
        return items[0] as? String
    }

    /// Registers `buffer`'s rectangle as a drop zone for dragged text.
    ///
    /// The drop is a copy: the destination proposes one, so the badge says so
    /// and the source keeps what it carried. A drag the keyboard carries
    /// (``DragAndDropSession/isKeyboardCarry``) can reach the control
    /// whether or not it is focused, since going there focuses it, and drops
    /// at the caret; the pointer's drops on the cell it was released over.
    ///
    /// - Parameters:
    ///   - buffer: The control's rendered buffer, whose region is the zone.
    ///   - context: The render context; nothing is registered while measuring
    ///     or outside a running app.
    ///   - focusID: The control's focus stop: what a carry stops at, and what
    ///     must be focused for a field to take the pointer's drop.
    ///   - takesUnfocused: Whether the control takes a drop while not focused,
    ///     as a `TextEditor` does and a field does not.
    ///   - drop: Inserts the text, at the zone-local cell given, or at the
    ///     caret for `nil`; answers whether the text changed.
    static func install(
        on buffer: inout FrameBuffer, context: RenderContext, focusID: String, takesUnfocused: Bool,
        drop: @escaping (_ text: String, _ cell: (x: Int, y: Int)?) -> Bool
    ) {
        guard !context.isMeasuring, let session = context.environment.dragAndDropSession else { return }
        let focusManager = context.environment.focusManager
        DropZone.install(
            on: &buffer, context: context,
            // Weakly, as `DropZone` holds them: the session holds this target.
            accepts: { [weak session, weak focusManager] payload in
                guard text(of: payload) != nil else { return false }
                return takesUnfocused || session?.isKeyboardCarry == true
                    || focusManager?.isFocused(id: focusID) == true
            },
            perform: { [weak session] payload, info in
                guard let text = text(of: payload) else { return false }
                return drop(text, session?.isKeyboardCarry == true ? nil : (info.x, info.y))
            },
            setTargeted: { _ in },
            proposedOperation: { .copy },
            focusIDs: [focusID])
    }
}
