//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationService+UndoTitles.swift
//
//  Undo and Redo titles with a step's name in them, joined as Foundation's
//  `UndoManager` joins them on macOS, in each of TUI's languages.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension LocalizationService {
    /// The title of the Undo command for the step named `actionName`, in the
    /// root's or the service's language: Foundation's own format for that
    /// language (`undoTitle.undo`) — "Undo Delete", "Löschen widerrufen",
    /// "撤销删除" — or the verb alone (`menu.undo`) for a step with no name.
    ///
    /// Foundation's `UndoManager.undoMenuTitle(forUndoActionName:)` on macOS,
    /// read off it per language (its `Undo.loctable`), for the platforms whose
    /// Foundation has no `UndoManager` and for the menu bar, which titles in
    /// the scene's language rather than the process's. Where the name is empty
    /// Foundation still writes its format, leaving "Undo " with a trailing
    /// space; this gives the bare verb, the command's own title.
    package func undoMenuTitle(forUndoActionName actionName: String) -> String {
        title(LocalizationKey.UndoTitle.undo, verb: LocalizationKey.Menu.undo, actionName)
    }

    /// The title of the Redo command for the step named `actionName`, as
    /// ``undoMenuTitle(forUndoActionName:)`` titles Undo (`undoTitle.redo`,
    /// `menu.redo`).
    package func redoMenuTitle(forUndoActionName actionName: String) -> String {
        title(LocalizationKey.UndoTitle.redo, verb: LocalizationKey.Menu.redo, actionName)
    }

    private func title(
        _ format: LocalizationKey.UndoTitle, verb: LocalizationKey.Menu, _ actionName: String
    ) -> String {
        guard !actionName.isEmpty else { return frameworkString(for: verb.rawValue) }
        return frameworkString(for: format.rawValue).replacingOccurrences(of: "%@", with: actionName)
    }
}
