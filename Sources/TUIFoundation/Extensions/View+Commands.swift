//  🖥️ TUI — A Terminal UI framework for Swift
//  View+Commands.swift
//
//  SwiftUI's move, exit and delete commands: actions a focused view takes
//  when the focused control lets an arrow, Escape or Delete key go.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Move Command Direction

/// The direction of a move command — SwiftUI's `MoveCommandDirection`.
public enum MoveCommandDirection: Hashable, Sendable {
    case up
    case down
    case left
    case right

    /// The direction an arrow key moves in, or `nil` for any other key.
    init?(_ key: KeyEquivalent) {
        switch key {
        case .upArrow: self = .up
        case .downArrow: self = .down
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        default: return nil
        }
    }
}

// MARK: - Commands

/// SwiftUI's commands, as macOS 15 delivers them (measured through a key
/// window):
///
/// - **While the focus is on the view or inside it**, like ``View/onKeyPress(phases:action:)``.
/// - **After the focused control lets the key go.** A `List` keeps its arrows,
///   a `TextField` its Backspace; a key the control does not use becomes the
///   command. And before the app's keyboard shortcuts: an exit command takes
///   Escape from the cancel button.
/// - **The innermost wins.** Only the handler nearest the focused control runs,
///   and it consumes the key. A `nil` action still does: the view keeps the
///   command and does nothing with it.
///
/// Focus-blind key handlers come before the focused control in TUI (an
/// ``View/onKeyEvent(_:)`` at Layer 2, a `NavigationStack`'s Escape-to-pop), so
/// one that takes Escape takes it from an exit command too — except while a
/// text field holds the focus, which has every key first, and its commands
/// with it. An `onKeyPress(.escape)` on the focus path comes before them all.
/// The focus system's own use of an arrow, moving the focus to the next
/// control (a TUI affordance macOS lacks), comes after a move command.
extension View {
    /// Performs an action when the user presses an arrow key the focused
    /// control does not use, while this view has the focus or contains it.
    ///
    /// Any arrow, held with any modifier, is a move command, as on macOS.
    ///
    /// ```swift
    /// Grid { … }
    ///     .focusable()
    ///     .onMoveCommand { direction in
    ///         cursor.move(direction)
    ///     }
    /// ```
    ///
    /// - Parameter action: The action to perform, given the direction; `nil`
    ///   keeps the command for this view and does nothing.
    /// - Returns: A view that handles move commands while it holds the focus.
    nonisolated public func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View {
        command { press in
            guard let direction = MoveCommandDirection(press.key) else { return false }
            action?(direction)
            return true
        }
    }

    /// Performs an action when the user presses Escape and the focused control
    /// does not use it, while this view has the focus or contains it — the
    /// exit command.
    ///
    /// Escape alone or with Shift, as on macOS. (macOS also sends it for ⌘.,
    /// which a terminal cannot deliver.)
    ///
    /// It is asked before the status bar's items and the key handlers of the
    /// views around it — an app's "⎋ back", say — as the view nearest the
    /// focus answers first.
    ///
    /// - Parameter action: The action to perform; `nil` keeps the command for
    ///   this view and does nothing.
    /// - Returns: A view that handles the exit command while it holds the focus.
    nonisolated public func onExitCommand(perform action: (() -> Void)?) -> some View {
        command { press in
            guard press.key == .escape, press.modifiers.chordModifiers.isSubset(of: .shift) else { return false }
            action?()
            return true
        }
    }

    /// Performs an action when the user presses Backspace or forward Delete
    /// and the focused control does not use it, while this view has the focus
    /// or contains it — the delete command.
    ///
    /// Either key alone or with Shift, as on macOS; with Control or Option it
    /// is a different editing command and not this one.
    ///
    /// - Parameter action: The action to perform; `nil` keeps the command for
    ///   this view and does nothing.
    /// - Returns: A view that handles the delete command while it holds the
    ///   focus.
    nonisolated public func onDeleteCommand(perform action: (() -> Void)?) -> some View {
        command { press in
            guard press.key == .delete || press.key == .deleteForward,
                press.modifiers.chordModifiers.isSubset(of: .shift)
            else { return false }
            action?()
            return true
        }
    }

    /// The focus-path modifier a key command is: a handler on the command
    /// stage, given the press, that answers whether it took the key.
    nonisolated private func command(_ takes: @escaping (KeyPress) -> Bool) -> FocusPathModifier<Self> {
        let handler: (KeyEvent) -> Bool = { event in
            KeyPress(event).map(takes) ?? false
        }
        return FocusPathModifier(content: self, stage: .command) { _ in handler }
    }
}
