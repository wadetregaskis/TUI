//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BundleStringTables.swift
//
//  An app's own string tables (`de.lproj/Localizable.strings` and the like),
//  read through Foundation for the keys TUIkit's registered dictionaries miss.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The string tables of the bundles a ``LocalizationService`` has been asked to
/// look in, read through `Bundle.localizedString(forKey:value:table:)`.
///
/// SwiftUI resolves a `LocalizedStringKey` in a bundle's string table —
/// `Localizable` in the main bundle unless `Text(_:tableName:bundle:comment:)`
/// names others — and an app ported from it arrives with those tables. TUIkit's
/// own strings, and anything an app registers with
/// ``LocalizationService/register(translations:)``, stay in its dictionaries;
/// ``LocalizationService`` interleaves the two by language (see
/// `LocalizationService.string(for:tableName:bundle:)`), so the app's table
/// in its language is read before any English.
///
/// The language is TUIkit's, not the process's: ``string(for:tableName:bundle:language:)``
/// reads the `.lproj` that best matches the language it is asked for (`zh`
/// finds `zh-Hans.lproj`), and ``fallbackString(for:tableName:bundle:)`` reads
/// as Foundation picks for the bundle on its own (its development region, or
/// a table outside any `.lproj`), the last place a key is looked for.
/// Switching the language at run time therefore switches these strings too.
///
/// Only `.strings` tables are read, which swift-corelibs-foundation reads off
/// Darwin as well. A String Catalog (`.xcstrings`) is compiled into them by
/// Xcode only, so a SwiftPM app ships `.strings` files or registers a
/// dictionary. A `.stringsdict` plural rule is not applied: TUIkit substitutes
/// `%@` itself.
///
/// Not thread-safe: the service calls it under its own lock.
final class BundleStringTables {
    /// One table of one bundle: whether it exists at all, the `.lproj`
    /// bundles that hold it, by language, and the answers already read.
    private final class Table {
        let bundle: Bundle
        let name: String
        /// Whether the bundle holds a table of this name anywhere — the one
        /// question asked on every miss of an app that ships no tables.
        let exists: Bool
        /// The `.lproj` sub-bundle each language reads, `.some(nil)` where the
        /// bundle has none for it.
        var localizations: [LocalizationService.Language: Bundle?] = [:]
        /// What each key resolved to in each language's `.lproj`, `.some(nil)`
        /// for a key the table lacks — bounded, see ``Answers``.
        var answers: [LocalizationService.Language: Answers] = [:]
        /// What each key resolved to as Foundation chooses for the bundle.
        var fallbackAnswers = Answers()

        init(bundle: Bundle, name: String) {
            self.bundle = bundle
            self.name = name
            self.exists =
                bundle.path(forResource: name, ofType: "strings") != nil
                || bundle.localizations.contains {
                    bundle.path(forResource: name, ofType: "strings", inDirectory: nil, forLocalization: $0) != nil
                }
        }
    }

    /// A table of a bundle. The entry holds the bundle, so its address cannot
    /// be reused by another while it is a key here.
    private struct Key: Hashable {
        let bundle: ObjectIdentifier
        let table: String
    }

    private var tables: [Key: Table] = [:]

    /// The main bundle's `Localizable` table: every key a dictionary misses
    /// asks it, so it is found without hashing anything.
    private var defaultTable: Table?

    /// The bundle a key with no bundle of its own is looked up in.
    let defaultBundle: Bundle

    /// What Foundation answers for a key the table lacks: a value no table
    /// spells, so a translation that happens to equal its key still counts.
    private static let missing = "\u{FFFF}TUIkit.missing\u{FFFF}"

    /// How many answers one generation of a table's answers holds, per
    /// language and for its fallback — see ``Answers``.
    ///
    /// The answers only spare Foundation's lookup, which reads a table it has
    /// already loaded, so forgetting costs a re-read and nothing else. Without
    /// a bound, an app with tables that makes its keys at run time —
    /// `LocalizedStringKey(someString)` over data — kept one entry per key it
    /// ever asked for, for the life of the process. An app's literal keys are
    /// far fewer than this, so they are never forgotten in practice.
    static let answerLimit = 4_096

    /// The answers one table keeps for one language (or its fallback): at
    /// most two generations of ``BundleStringTables/answerLimit`` each.
    ///
    /// NOT one map emptied when it fills. That was the flat cap a memo of
    /// TUIkit's has already lost to once (the text-wrap memo): a working set
    /// just over the limit — 4,097 keys a frame — filled the map, emptied it
    /// at the 4,097th key and refilled it, so every frame read every key from
    /// Foundation again and nothing was ever served. Here a full generation
    /// becomes the previous one and the one before it is forgotten, and an
    /// answer found in the previous generation moves back into the current
    /// one, so a set of keys asked for again and again stays kept whole up to
    /// twice the limit, and only keys nobody has asked for in a whole
    /// generation are forgotten.
    struct Answers {
        private var current: [String: String?] = [:]
        private var previous: [String: String?] = [:]

        /// The answer kept for `key` — `.some(nil)` for a key the table was
        /// found to lack — or `nil` where none is kept.
        mutating func answer(for key: String) -> String?? {
            if let kept = current[key] { return kept }
            guard let kept = previous[key] else { return nil }
            remember(kept, for: key)
            return kept
        }

        /// Keeps `answer` for `key`, starting a new generation first if the
        /// current one is full.
        mutating func remember(_ answer: String?, for key: String) {
            if current.count >= BundleStringTables.answerLimit {
                // The old previous generation's storage becomes the new
                // current one, emptied, so a turnover allocates nothing.
                swap(&current, &previous)
                current.removeAll(keepingCapacity: true)
            }
            current[key] = .some(answer)
        }

        /// How many answers are kept, in both generations.
        var count: Int { current.count + previous.count }
    }

    init(defaultBundle: Bundle = .main) {
        self.defaultBundle = defaultBundle
    }

    /// The text of `key` in the table named `tableName` (`Localizable` for
    /// `nil`) of `bundle` (the default bundle for `nil`), read from the
    /// `.lproj` that matches `language`, or `nil` where that has none or does
    /// not hold the key.
    func string(
        for key: String, tableName: String?, bundle: Bundle?, language: LocalizationService.Language
    ) -> String? {
        let table = self.table(named: tableName, in: bundle)
        guard table.exists else { return nil }
        if let answer = table.answers[language, default: Answers()].answer(for: key) { return answer }
        var answer: String?
        if let source = localization(of: table, for: language) {
            foundationReads += 1
            let value = source.localizedString(forKey: key, value: Self.missing, table: table.name)
            if value != Self.missing { answer = value }
        }
        table.answers[language, default: Answers()].remember(answer, for: key)
        return answer
    }

    /// The text of `key` in the same table as Foundation chooses for the
    /// bundle itself, with no language asked for: its development region, or
    /// a table outside any `.lproj`. The last place a key is looked for.
    func fallbackString(for key: String, tableName: String?, bundle: Bundle?) -> String? {
        let table = self.table(named: tableName, in: bundle)
        guard table.exists else { return nil }
        if let answer = table.fallbackAnswers.answer(for: key) { return answer }
        foundationReads += 1
        let value = table.bundle.localizedString(forKey: key, value: Self.missing, table: table.name)
        let answer = value == Self.missing ? nil : value
        table.fallbackAnswers.remember(answer, for: key)
        return answer
    }

    /// How many answers the tables keep, in all — for the tests of the bound.
    var keptAnswerCount: Int {
        let tables = Array(tables.values) + (defaultTable.map { [$0] } ?? [])
        return tables.reduce(0) { total, table in
            total + table.fallbackAnswers.count + table.answers.values.reduce(0) { $0 + $1.count }
        }
    }

    /// How many times a table was read through Foundation, for an answer not
    /// kept — for the tests of the bound's hit rate. One increment a miss.
    private(set) var foundationReads = 0

    /// The table named `tableName` of `bundle`, `nil` meaning `Localizable`
    /// and the default bundle: made once and kept.
    private func table(named tableName: String?, in bundle: Bundle?) -> Table {
        if tableName == nil, bundle == nil || bundle === defaultBundle {
            if let defaultTable { return defaultTable }
            let table = Table(bundle: defaultBundle, name: "Localizable")
            defaultTable = table
            return table
        }
        let bundle = bundle ?? defaultBundle
        let name = tableName ?? "Localizable"
        let tableKey = Key(bundle: ObjectIdentifier(bundle), table: name)
        if let found = tables[tableKey] { return found }
        let table = Table(bundle: bundle, name: name)
        tables[tableKey] = table
        return table
    }

    /// The `.lproj` sub-bundle of `table`'s bundle that best matches
    /// `language` — `nil` where it has none in that language, rather than the
    /// fallback Foundation's matching offers.
    private func localization(of table: Table, for language: LocalizationService.Language) -> Bundle? {
        if let known = table.localizations[language] { return known }
        let code = language.rawValue
        var found: Bundle?
        let matches = Bundle.preferredLocalizations(from: table.bundle.localizations, forPreferences: [code])
        if let name = matches.first, Locale(identifier: name).language.languageCode?.identifier == code,
            let path = table.bundle.path(forResource: name, ofType: "lproj")
        {
            found = Bundle(path: path)
        }
        table.localizations[language] = .some(found)
        return found
    }
}
