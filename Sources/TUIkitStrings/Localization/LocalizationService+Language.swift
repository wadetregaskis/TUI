//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationService+Language.swift
//
//  The languages TUIkit ships translations of.
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

        /// The `Locale` this language formats numbers, dates, and the like
        /// in — the app's chosen language drives its number grouping, so a
        /// German app groups "12.000" and a French one "12 000" while the
        /// UI text is already in that language. Derived from the language
        /// code; a bare-code locale carries the correct grouping / decimal
        /// separators without pinning a region.
        public var locale: Locale {
            Locale(identifier: rawValue)
        }
    }
}
