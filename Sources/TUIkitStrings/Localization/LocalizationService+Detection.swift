//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationService+Detection.swift
//
//  Which language the environment asks for: the POSIX locale variables, then
//  the system's preferred languages.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension LocalizationService {
    /// The language the environment asks for, if this framework has it.
    ///
    /// The POSIX locale variables are consulted FIRST, on every platform, and
    /// not merely when `preferredLanguages` comes back empty: off Darwin it
    /// never does, because swift-foundation's `LocaleCache` has no user
    /// preferences to read and answers with the hard-coded sentinel
    /// `["en-001"]`. Asking only that list is why a Linux app started in
    /// English on a fully German machine, and why an `isEmpty` guard would
    /// never have fired. Darwin's list is a genuine preference and still
    /// decides — a process with no POSIX locale variables set, which is every
    /// GUI-launched one, reads exactly what it always did.
    ///
    /// Both inputs are parameters so the two platforms' answers can be posed
    /// on either; the defaults are what the running process actually has.
    static func systemPreferredLanguage(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = NSLocale.preferredLanguages
    ) -> Language? {
        systemPreferredLanguageCodes(environment: environment, preferredLanguages: preferredLanguages)
            .last.flatMap(Language.init(rawValue:))
    }

    /// The languages the environment asks for, as language codes (`"pt"`),
    /// most preferred first: each one up to and including the first this
    /// framework has translations of — ``systemPreferredLanguage(environment:preferredLanguages:)``
    /// — or every one, where it has none of them.
    ///
    /// The languages ahead of that one are those TUIkit ships no translations
    /// of, and they are still the user's first choice: an app's own strings
    /// are read in them first (see ``LocalizationService``), so a Portuguese
    /// app on a Portuguese machine speaks Portuguese, TUIkit's own words
    /// included where the app spells them, before anything else.
    ///
    /// Searched in the same order as the language itself: the POSIX
    /// variables, then the preferred-languages list.
    static func systemPreferredLanguageCodes(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = NSLocale.preferredLanguages
    ) -> [String] {
        var codes: [String] = []
        // These are canonical BCP-47 tags, language subtag first — no
        // `C`/`POSIX` here.
        let fromList = preferredLanguages.lazy.compactMap { languageCode(of: $0) }
        for code in posixLanguageCodes(environment) + Array(fromList) where !codes.contains(code) {
            codes.append(code)
            if Language(rawValue: code) != nil { break }
        }
        return codes
    }

    /// The language named by the POSIX locale variables, if this framework
    /// has it.
    ///
    /// gettext's documented precedence, which is the one a terminal user
    /// expects to work: `LANGUAGE` outranks `LC_ALL`, which outranks
    /// `LC_MESSAGES`, which outranks `LANG`. `LANGUAGE` alone may hold a
    /// colon-separated priority list, and every variable is searched for the
    /// first language actually bundled rather than being consumed by its first
    /// entry — a `pt:es` list should speak Spanish, not English.
    static func posixEnvironmentLanguage(_ environment: [String: String]) -> Language? {
        posixLanguageCodes(environment).lazy.compactMap(Language.init(rawValue:)).first
    }

    /// Every language code the POSIX locale variables name, in gettext's
    /// precedence (see ``posixEnvironmentLanguage(_:)``).
    private static func posixLanguageCodes(_ environment: [String: String]) -> [String] {
        ["LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"].flatMap { name in
            (environment[name] ?? "").split(separator: ":").compactMap { languageCode(of: $0) }
        }
    }

    /// The language code a locale name begins with, or `nil` where it names
    /// none.
    ///
    /// The letters up to the territory, script, encoding or modifier:
    /// `de_DE.UTF-8@euro` is German, `zh-Hans-CN` Chinese. NOT `prefix(2)`, which would read the
    /// neutral `C` and `POSIX` locales — they mean "no language preference" —
    /// as the codes "c" and "po", and Filipino (`fil`) as Finnish. A code is
    /// two or three letters (ISO 639-1 or -2), so anything else names none.
    private static func languageCode(of name: some StringProtocol) -> String? {
        let code = name.prefix { !"-_.@".contains($0) }
        guard (2...3).contains(code.count), code.allSatisfy(\.isLetter) else { return nil }
        return code.lowercased()
    }
}
