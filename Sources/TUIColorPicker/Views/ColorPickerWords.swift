//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorPickerWords.swift
//
//  The colour picker's and the gradient editor's own words.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// One of the colour picker's words (``LocalizationKey/ColorPicker``), read
/// in `language` — a subtree's `\.stringLanguage`, `nil` for the app's — as
/// TUI's own controls read theirs (`LocalizationService.frameworkReading`):
/// "Graustufen" for `.greyscale` under a German `\.locale`.
///
/// For a title the panel hands on as a string: a tab's, the dialog's, a
/// toggle's. A `Text` of one is `Text(localized:)`, which reads it again
/// where it is drawn.
@MainActor func colorPickerWord(_ key: LocalizationKey.ColorPicker, in language: String?) -> String {
    LocalizationService.shared.frameworkReading(key.rawValue, in: language).text
}
