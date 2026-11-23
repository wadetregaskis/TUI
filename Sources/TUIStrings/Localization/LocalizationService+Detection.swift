//  🖥️ TUI — A Terminal UI framework for Swift
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
    /// GUI-launched one, reads exactly what it always did. On Windows the list
    /// is the user's display languages (``systemLanguageList``), as Foundation's
    /// is the same sentinel there and Windows sets no POSIX variable.
    ///
    /// Both inputs are parameters so the two platforms' answers can be posed
    /// on either; the defaults are what the running process actually has.
    static func systemPreferredLanguage(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = systemLanguageList
    ) -> Language? {
        systemPreferredLanguageCodes(environment: environment, preferredLanguages: preferredLanguages)
            .last.flatMap { LanguageTag($0) }.flatMap(Language.init(reading:))
    }

    /// The languages the environment asks for, as language tags (`"pt-BR"`,
    /// `"zh-Hant-TW"`; ``LanguageTag``), most preferred first: each one up to
    /// and including the first this framework has translations of —
    /// ``systemPreferredLanguage(environment:preferredLanguages:)`` — or every
    /// one, where it has none of them.
    ///
    /// The languages ahead of that one are those TUI ships no translations
    /// of, and they are still the user's first choice: an app's own strings
    /// are read in them first (see ``LocalizationService``), so a Portuguese
    /// app on a Portuguese machine speaks Portuguese, TUI's own words
    /// included where the app spells them, before anything else. Each is
    /// read under its full tag and then its bare one: `pt-BR`, then `pt`.
    ///
    /// Searched in the same order as the language itself: the POSIX
    /// variables, then the preferred-languages list. Under the neutral `C`
    /// locale (``messagesLocaleIsNeutral(_:)``) it is English alone, and
    /// neither is searched.
    static func systemPreferredLanguageCodes(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = systemLanguageList
    ) -> [String] {
        if messagesLocaleIsNeutral(environment) { return [Language.english.rawValue] }
        var tags: [LanguageTag] = []
        // These are canonical BCP-47 tags, language subtag first — no
        // `C`/`POSIX` here.
        let fromList = preferredLanguages.lazy.compactMap { LanguageTag($0) }
        for tag in posixLanguageTags(environment) + Array(fromList) where !tags.contains(tag) {
            tags.append(tag)
            if Language(reading: tag) != nil { break }
        }
        return tags.map(\.identifier)
    }

    /// The language named by the POSIX locale variables, if this framework
    /// has it.
    ///
    /// gettext's documented precedence, which is the one a terminal user
    /// expects to work: `LANGUAGE` outranks `LC_ALL`, which outranks
    /// `LC_MESSAGES`, which outranks `LANG`. `LANGUAGE` alone may hold a
    /// colon-separated priority list, and every variable is searched for the
    /// first language actually bundled rather than being consumed by its first
    /// entry — a `pt:es` list should speak Spanish, not English. Under the
    /// neutral `C` locale (``messagesLocaleIsNeutral(_:)``), English.
    static func posixEnvironmentLanguage(_ environment: [String: String]) -> Language? {
        if messagesLocaleIsNeutral(environment) { return .english }
        return posixLanguageTags(environment).lazy.compactMap(Language.init(reading:)).first
    }

    /// Whether the POSIX variable that decides the language of messages —
    /// the first of `LC_ALL`, `LC_MESSAGES` and `LANG` that is set and not
    /// empty, POSIX's rule — names the neutral `C` or `POSIX` locale, with or
    /// without a codeset (`C.UTF-8`).
    ///
    /// That locale is the untranslated one: English, on Linux and macOS alike
    /// (the owner's O-07 (b), 2026-11-21). `LC_ALL=C app` is how a script, a
    /// CI job or a bug report asks any program for its untranslated output, so
    /// neither `LANGUAGE` (gettext ignores it under `C`) nor the system's
    /// preferred languages is read. It used to mean "no preference": the
    /// next variable spoke, so `LC_ALL=C` on a German machine was German.
    /// Only the deciding variable counts: `LC_ALL=de_DE.UTF-8 LANG=C` is
    /// German.
    static func messagesLocaleIsNeutral(_ environment: [String: String]) -> Bool {
        let deciding = ["LC_ALL", "LC_MESSAGES", "LANG"].lazy.compactMap { environment[$0] }.first { !$0.isEmpty }
        return deciding.map(LanguageTag.isNeutral) ?? false
    }

    /// Every language the POSIX locale variables name, in gettext's
    /// precedence (see ``posixEnvironmentLanguage(_:)``).
    private static func posixLanguageTags(_ environment: [String: String]) -> [LanguageTag] {
        ["LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"].flatMap { name in
            (environment[name] ?? "").split(separator: ":").compactMap { LanguageTag($0) }
        }
    }

    /// The region the user's locale names, for formatting: the territory of
    /// the first POSIX variable that names one (``LanguageTag/region``: `GB` in
    /// `en_GB.UTF-8`, `TW` in `zh-Hant-TW`, none in `de`), in the precedence that decides
    /// how dates and numbers are written (`LC_ALL`, then `LC_TIME`,
    /// `LC_NUMERIC`, then `LANG`), else `current`'s region — on Darwin the
    /// user's region preference. The world region (`001`), which swift-foundation
    /// answers with off Darwin when it has nothing to read, is no region. So is
    /// the neutral `C` or `POSIX` locale where one of those variables names it
    /// before any names a territory: the untranslated locale has none, and the
    /// system's is not read (O-07 (b), 2026-11-21; see
    /// ``messagesLocaleIsNeutral(_:)``).
    ///
    /// Both inputs are parameters so either platform's answer can be posed on
    /// either; the defaults are what the running process has.
    static func systemRegion(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        current: Locale? = systemLocale
    ) -> Locale.Region? {
        for name in ["LC_ALL", "LC_TIME", "LC_NUMERIC", "LANG"] {
            guard let value = environment[name], !value.isEmpty else { continue }
            if LanguageTag.isNeutral(value) { return nil }
            if let region = LanguageTag(value)?.region { return Locale.Region(region) }
        }
        guard let region = current?.region, region.identifier != "001" else { return nil }
        return region
    }
}
