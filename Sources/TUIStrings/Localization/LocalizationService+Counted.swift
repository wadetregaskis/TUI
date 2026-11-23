//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationService+Counted.swift
//
//  One of TUI's phrases with a count in it, in the plural form the count
//  takes in the language it is read in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension LocalizationService {
    /// One of TUI's counted phrases: the member of the key family `stem`
    /// (`stem.one`, `stem.other`) for the CLDR plural category `count` takes
    /// in the language it is read in, with `spelled` — the count as the
    /// caller wrote it, in its locale's digits — for its `%@`.
    ///
    /// Read as ``frameworkReading(_:in:)`` reads: in `language` (a code)
    /// first, then English, where one is given, and else in the root's or the
    /// service's language. The category is that language's, by the rules the
    /// span tables follow (`TimeSpan.pluralCategory(of:in:)`); a language TUI
    /// ships no table of takes English's.
    ///
    /// ```swift
    /// service.countedFrameworkString("scrollIndicator.rows.moreBelow", count: 1, spelled: "1", in: "de")
    /// // "1 weitere Zeile unten"
    /// ```
    package func countedFrameworkString(_ stem: String, count: Int, spelled: String, in language: String?) -> String {
        let code = language ?? stringLanguage
        let category = TimeSpan.pluralCategory(of: count, in: Language(rawValue: code) ?? .english)
        let pattern = frameworkReading(stem + "." + category, in: language).text
        return pattern.replacingOccurrences(of: "%@", with: spelled)
    }
}
