//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameworkLocalizationParityTests.swift
//
//  Every language TUI ships carries every one of TUI's own keys, translated,
//  with the count and plural forms English has: the framework's twin of
//  `ExampleLocalizationParityTests`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIStrings

/// TUI's own translation tables (`Sources/TUIStrings/Localization/translations`),
/// held to English's.
///
/// A missing or untranslated key does not crash and fails no build: it renders
/// in English beside translated neighbours, which is how "N more rows below",
/// the colour picker's tabs and the image placeholder's words shipped English
/// in every language. `LocalizationKeyConsistencyTests` holds the keys to the
/// `LocalizationKey` enums; this holds the languages to English, as the
/// Example's guard holds the Example's.
@Suite("Framework localization parity")
struct FrameworkLocalizationParityTests {
    /// The tables in the source tree, read as the bundle has them.
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TUIFoundationTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Sources/TUIStrings/Localization/translations")

    /// `[language: [key: value]]` for every language TUI ships.
    private static func loadTables() -> [String: [String: String]] {
        var tables: [String: [String: String]] = [:]
        for language in LocalizationService.Language.allCases {
            let url = directory.appendingPathComponent("\(language.rawValue).json")
            guard let data = try? Data(contentsOf: url),
                let table = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { continue }
            tables[language.rawValue] = table
        }
        return tables
    }

    /// The family a key belongs to: what precedes its first dot.
    private static func family(of key: String) -> String {
        String(key.prefix { $0 != "." })
    }

    @Test("Every framework language has exactly the English key set, none of them empty")
    func everyLanguageMatchesEnglish() {
        let tables = Self.loadTables()
        #expect(tables.count == LocalizationService.Language.allCases.count, "a table failed to load: \(tables.keys)")
        guard let english = tables["en"] else {
            Issue.record("no English table")
            return
        }
        #expect(english.count > 250, "the English table looks truncated")
        let englishKeys = Set(english.keys)
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) {
            let keys = Set(table.keys)
            let missing = englishKeys.subtracting(keys).sorted()
            let extra = keys.subtracting(englishKeys).sorted()
            #expect(missing.isEmpty, "\(language) is missing \(missing.count) keys: \(missing.prefix(5))")
            #expect(extra.isEmpty, "\(language) has \(extra.count) keys English does not: \(extra.prefix(5))")
            let empty = table.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.keys.sorted()
            #expect(empty.isEmpty, "\(language) has empty values: \(empty.prefix(5))")
        }
    }

    @Test("No framework translation was left as its English text")
    func translationsAreNotCopies() {
        // Proper nouns, "OK" and numbers legitimately match English, so this
        // bounds a proportion — overall, and per key family, where a family
        // pasted from English would hide in the overall figure.
        let tables = Self.loadTables()
        guard let english = tables["en"] else { return }
        let families = Dictionary(grouping: english.keys, by: Self.family(of:))
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) where language != "en" {
            let identical = english.keys.count { table[$0] == english[$0] }
            let ratio = Double(identical) / Double(max(1, english.count))
            #expect(ratio < 0.1, "\(language): \(identical)/\(english.count) strings are byte-identical to English")
            for (family, keys) in families.sorted(by: { $0.key < $1.key }) where keys.count >= 4 {
                let same = keys.filter { table[$0] == english[$0] }.sorted()
                #expect(
                    Double(same.count) / Double(keys.count) < 0.5,
                    "\(language): \(same.count)/\(keys.count) of \(family) are English: \(same.prefix(5))")
            }
        }
    }

    @Test("Every translation keeps English's placeholders")
    func placeholdersSurvive() {
        // A translation that drops `%@` drops the name, the count or the path
        // it stands for; one that adds one prints whatever comes next.
        let tables = Self.loadTables()
        guard let english = tables["en"] else { return }
        func placeholders(_ text: String) -> Int { text.components(separatedBy: "%@").count - 1 }
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) where language != "en" {
            let wrong = english.keys.filter { key in
                table[key].map { placeholders($0) != placeholders(english[key] ?? "") } ?? false
            }.sorted()
            #expect(wrong.isEmpty, "\(language) changes the placeholders of \(wrong)")
        }
    }

    @Test("Every counted phrase has both plural forms")
    func pluralFamiliesAreWhole() {
        // The counted keys are `stem.one` and `stem.other`, chosen by the CLDR
        // plural category of the count (`TimeSpan.pluralCategory`). A stem with
        // one form alone reads its key for a count in the other.
        let tables = Self.loadTables()
        guard let english = tables["en"] else { return }
        let suffixes = [".one", ".other"]
        let stems = Set(english.keys.compactMap { key in
            suffixes.first { key.hasSuffix($0) }.map { String(key.dropLast($0.count)) }
        })
        #expect(!stems.isEmpty, "no counted phrases found")
        for stem in stems.sorted() {
            for suffix in suffixes {
                #expect(english[stem + suffix] != nil, "\(stem) has no \(suffix) form")
            }
        }
    }
}
