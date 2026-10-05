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
/// ``LocalizationService/register(translations:)``, stay in its dictionaries,
/// which are asked first; a table is read only for a key they do not hold.
///
/// The language is TUIkit's, not the process's: the table is read from the
/// `.lproj` that best matches ``LocalizationService/currentLanguage`` (`zh`
/// finds `zh-Hans.lproj`), then from the English one, as the dictionaries fall
/// back, and last as Foundation picks for the bundle on its own (its
/// development region, or a table outside any `.lproj`). Switching the
/// language at run time therefore switches these strings too.
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
        /// What each key resolved to, `.some(nil)` for a key the table lacks.
        var answers: [LocalizationService.Language: [String: String?]] = [:]

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

    init(defaultBundle: Bundle = .main) {
        self.defaultBundle = defaultBundle
    }

    /// The text of `key` in the table named `tableName` (`Localizable` for
    /// `nil`) of `bundle` (the default bundle for `nil`), in `language`, or
    /// `nil` where the table does not hold it.
    func string(
        for key: String, tableName: String?, bundle: Bundle?, language: LocalizationService.Language
    ) -> String? {
        let table: Table
        if tableName == nil, bundle == nil || bundle === defaultBundle {
            if let defaultTable {
                table = defaultTable
            } else {
                table = Table(bundle: defaultBundle, name: "Localizable")
                defaultTable = table
            }
        } else {
            let bundle = bundle ?? defaultBundle
            let name = tableName ?? "Localizable"
            let tableKey = Key(bundle: ObjectIdentifier(bundle), table: name)
            if let found = tables[tableKey] {
                table = found
            } else {
                table = Table(bundle: bundle, name: name)
                tables[tableKey] = table
            }
        }
        guard table.exists else { return nil }
        if let answer = table.answers[language]?[key] { return answer }
        let answer = read(key, in: table, language: language)
        table.answers[language, default: [:]][key] = answer
        return answer
    }

    /// Reads `key` from `table`: the language's `.lproj`, then English's, then
    /// as Foundation chooses for the bundle itself.
    private func read(_ key: String, in table: Table, language: LocalizationService.Language) -> String? {
        for candidate in language == .english ? [language] : [language, .english] {
            guard let source = localization(of: table, for: candidate) else { continue }
            let value = source.localizedString(forKey: key, value: Self.missing, table: table.name)
            if value != Self.missing { return value }
        }
        let value = table.bundle.localizedString(forKey: key, value: Self.missing, table: table.name)
        return value == Self.missing ? nil : value
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
