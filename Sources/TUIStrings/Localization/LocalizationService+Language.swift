//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationService+Language.swift
//
//  The languages TUI ships translations of.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

extension LocalizationService {
    /// Supported languages
    public enum Language: String, Codable, CaseIterable {
        case english = "en"
        case german = "de"
        case french = "fr"
        case italian = "it"
        case spanish = "es"
        case simplifiedChinese = "zh"
        case japanese = "ja"

        /// Human-readable name (in the language itself).
        public var displayName: String {
            switch self {
            case .english: "English"
            case .german: "Deutsch"
            case .french: "Français"
            case .italian: "Italiano"
            case .spanish: "Español"
            case .simplifiedChinese: "简体中文"
            case .japanese: "日本語"
            }
        }

        /// The `Locale` this language formats numbers, dates, and the like in
        /// for a user in `region`: the language's own conventions — a German
        /// app groups "12.000" and a French one "12 000" while its words are
        /// already in that language — with the region's where the language's
        /// data has a regional form, as SwiftUI's `\.locale`, the user's
        /// locale, carries its region: `en` in `GB` writes a date day first.
        /// A bare-code locale where `region` is `nil`.
        ///
        /// Simplified Chinese states its script, so a region whose own
        /// Chinese is Traditional (`TW`, `HK`) does not change it.
        public func locale(in region: Locale.Region?) -> Locale {
            let script: Locale.Script? = self == .simplifiedChinese ? .hanSimplified : nil
            guard region != nil || script != nil else { return Locale(identifier: rawValue) }
            return Locale(languageCode: Locale.LanguageCode(rawValue), script: script, languageRegion: region)
        }
    }
}
