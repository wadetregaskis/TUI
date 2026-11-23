//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationKeys+Controls.swift
//
//  The keys of words TUI's own controls draw that an app has no public key
//  for: internal to the package, as the file panel's are.
//
//  Created by Wade Tregaskis
//  License: MIT

extension LocalizationKey {
    /// What an image draws while it has no picture: the line a failed load
    /// shows, its reason as `%@`. (A load under way shows ``Label/loading``.)
    /// Internal to the package, as the file panel's words are.
    package enum ImagePlaceholder: String, CaseIterable {
        case failed = "imagePlaceholder.failed"
    }

    /// An Undo or Redo command's title for a step with a name, the name as
    /// `%@`: Foundation's own format in each language (`Undo %@` and
    /// `Redo %@` of its `Undo.loctable`, read off macOS), where the word comes
    /// first in some and last in others. A step with no name is titled
    /// ``Menu/undo`` or ``Menu/redo`` alone. Read through
    /// `LocalizationService.undoMenuTitle(forUndoActionName:)`.
    package enum UndoTitle: String, CaseIterable {
        case undo = "undoTitle.undo"
        case redo = "undoTitle.redo"
    }
}

extension LocalizationKey.ImagePlaceholder: FrameworkLocalizationKey {}
