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
        if let fromEnvironment = posixEnvironmentLanguage(environment) {
            return fromEnvironment
        }
        for langCode in preferredLanguages {
            // These are canonical BCP-47 tags, language subtag first, so the
            // two leading characters are the language — no `C`/`POSIX` here.
            let base = langCode.prefix(2).lowercased()
            if let language = Language(rawValue: base) {
                return language
            }
        }
        return nil
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
        for name in ["LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"] {
            guard let value = environment[name] else { continue }
            for entry in value.split(separator: ":") {
                // The letters up to the territory, encoding or modifier:
                // `de_DE.UTF-8@euro` is German. NOT `prefix(2)`, which would
                // read the neutral `C` and `POSIX` locales — they mean "no
                // language preference" — as the codes "c" and "po".
                let code = entry.prefix { $0.isLetter }
                guard code.count == 2, let language = Language(rawValue: code.lowercased())
                else { continue }
                return language
            }
        }
        return nil
    }
}
