//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoKey.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Undo Key

/// The app-wide undo and redo keys, as the input chain reads them.
///
/// The owner's choice (decisions A1), recorded with each terminal's reach in
/// `Documentation/Terminal-compatibility.md`, "Undo and redo":
///
/// - **Undo:** Ctrl-minus. A legacy encoding sends 0x1F for it, and for
///   Ctrl-_ and Ctrl-/ too, which `KeyEvent.parse` reads as Ctrl-minus; under
///   the kitty keyboard protocol Ctrl-/ arrives as itself, and undoes too.
/// - **Redo:** Ctrl-Shift-Z and Ctrl-Shift-minus (Ctrl-_), which only the
///   kitty keyboard protocol tells from Ctrl-Z and Ctrl-minus; and Option-_,
///   which a terminal sending Option as Meta sends as `ESC _`.
///
/// Ctrl-Z itself is not here: unclaimed, it suspends the app. Ctrl-Y is the
/// text controls' yank.
enum UndoKey: Equatable {
    case undo
    case redo

    /// The command `event` is, or `nil` for any other key.
    init?(_ event: KeyEvent) {
        guard event.phase != .release, case .character(let character) = event.key else { return nil }
        if event.ctrl, !event.alt {
            switch character {
            case "-" where !event.shift, "/" where !event.shift:
                self = .undo
            // Ctrl-Shift-minus: the shifted key where the terminal reports it,
            // the key with Shift where it reports only the bit.
            case "_", "-":
                self = .redo
            case "Z" where event.shift, "z" where event.shift:
                self = .redo
            default:
                return nil
            }
        } else if event.alt, !event.ctrl, character == "_" {
            self = .redo
        } else {
            return nil
        }
    }

    /// Undoes or redoes on `manager`, reporting whether there was a step to.
    ///
    /// The input chain is not isolated to the main actor, though it only ever
    /// runs there; `UndoManager` is.
    func perform(on manager: UndoManager) -> Bool {
        MainActor.assumeIsolated {
            switch self {
            case .undo:
                guard manager.canUndo else { return false }
                manager.undo()
            case .redo:
                guard manager.canRedo else { return false }
                manager.redo()
            }
            return true
        }
    }
}
