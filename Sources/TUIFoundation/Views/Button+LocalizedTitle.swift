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

/// Where a button's title came from, to read it again in another language.
package enum LocalizedTitle: Sendable {
    /// An app's key, read as `Text(_:)` reads one.
    case key(LocalizedStringKey)
    /// One of TUI's own keys, by its raw value, read in TUI's order.
    case framework(String)

    /// The title's words in `language` first.
    @MainActor
    func words(in language: String) -> String {
        switch self {
        case .key(let key): Text(key, tableName: nil, bundle: nil, language: language).content
        case .framework(let key): LocalizationService.shared.frameworkReading(key, in: language).text
        }
    }
}

extension Text {
    /// One of TUI's own words, of any family, read again where it is drawn
    /// under a locale of another language (``init(frameworkKey:language:)``).
    package init(localized key: some FrameworkLocalizationKey) {
        self.init(frameworkKey: key.rawValue, language: nil)
    }
}
