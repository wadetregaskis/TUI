//  🖥️ TUI — A Terminal UI framework for Swift
//  Button+LocalizedTitle.swift
//
//  A button's title read from a key follows a subtree's `\.locale`, as a
//  `Text` made from a key does (`Text+Locale.swift`): its words are read
//  when the button is made, and again when it is drawn where `\.locale`
//  names a language.
//
//  Created by Wade Tregaskis
//  License: MIT

extension LocalizedTextSource {
    /// The words of the key this came from, read in `language` first: as a
    /// `Text` made from it reads them there (``Text/relocalized(in:)``), or,
    /// for one of TUI's keys, in TUI's order.
    @MainActor
    func words(in language: String) -> String {
        guard !isFramework else { return LocalizationService.shared.frameworkReading(key.key, in: language).text }
        return Text(key, tableName: tableName, bundle: bundle, language: language, locale: locale).content
    }
}

extension Text {
    /// One of TUI's own words, of any family, read again where it is drawn
    /// under a locale of another language (``init(frameworkKey:language:)``).
    package init(localized key: some FrameworkLocalizationKey) {
        self.init(frameworkKey: key.rawValue, language: nil)
    }
}
