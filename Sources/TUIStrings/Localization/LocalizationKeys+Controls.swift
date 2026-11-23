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

    /// The words of the colour picker and the gradient editor (TUIColorPicker):
    /// the colour panel's default title, its tabs, its opacity row and the 256
    /// tab's toggle. Internal to the package, as the file panel's are. The
    /// gradient editor's title is ``Label/gradient``.
    package enum ColorPicker: String, CaseIterable {
        case title = "colorPicker.title"
        case semantic = "colorPicker.semantic"
        case xterm256 = "colorPicker.xterm256"
        case greyscale = "colorPicker.greyscale"
        case named = "colorPicker.named"
        case webSafe = "colorPicker.webSafe"
        case crayons = "colorPicker.crayons"
        case opacity = "colorPicker.opacity"
        case showNumbers = "colorPicker.showNumbers"
    }
}

extension LocalizationKey.ImagePlaceholder: FrameworkLocalizationKey {}
extension LocalizationKey.ColorPicker: FrameworkLocalizationKey {}
