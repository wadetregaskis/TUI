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

    /// The scroll indicators' "N more rows below": per unit, a phrase for each
    /// rung of the line's ladder (`moreAbove`/`moreBelow`, then `above`/`below`
    /// without "more", then `count` without the direction), and per CLDR
    /// plural category, `%@` standing for the count. Read through
    /// `LocalizationService.countedFrameworkString(_:count:spelled:in:)`, in
    /// the language of the view's `\.locale`. Internal to the package.
    package enum ScrollIndicator: String, CaseIterable {
        case rowsMoreAboveOne = "scrollIndicator.rows.moreAbove.one"
        case rowsMoreAboveOther = "scrollIndicator.rows.moreAbove.other"
        case rowsMoreBelowOne = "scrollIndicator.rows.moreBelow.one"
        case rowsMoreBelowOther = "scrollIndicator.rows.moreBelow.other"
        case rowsAboveOne = "scrollIndicator.rows.above.one"
        case rowsAboveOther = "scrollIndicator.rows.above.other"
        case rowsBelowOne = "scrollIndicator.rows.below.one"
        case rowsBelowOther = "scrollIndicator.rows.below.other"
        case rowsCountOne = "scrollIndicator.rows.count.one"
        case rowsCountOther = "scrollIndicator.rows.count.other"
        case linesMoreAboveOne = "scrollIndicator.lines.moreAbove.one"
        case linesMoreAboveOther = "scrollIndicator.lines.moreAbove.other"
        case linesMoreBelowOne = "scrollIndicator.lines.moreBelow.one"
        case linesMoreBelowOther = "scrollIndicator.lines.moreBelow.other"
        case linesAboveOne = "scrollIndicator.lines.above.one"
        case linesAboveOther = "scrollIndicator.lines.above.other"
        case linesBelowOne = "scrollIndicator.lines.below.one"
        case linesBelowOther = "scrollIndicator.lines.below.other"
        case linesCountOne = "scrollIndicator.lines.count.one"
        case linesCountOther = "scrollIndicator.lines.count.other"
    }
}

extension LocalizationKey.ImagePlaceholder: FrameworkLocalizationKey {}
extension LocalizationKey.ColorPicker: FrameworkLocalizationKey {}
