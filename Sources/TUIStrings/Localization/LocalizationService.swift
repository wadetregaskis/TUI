//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationService.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUICore

// MARK: - Localization Service

/// Manages language selection and string localization.
///
/// Loads translations from JSON files, resolves localized strings using
/// dot-notation keys, and persists language preference to disk.
///
/// ## Where a key is looked up
///
/// Two kinds of key are looked up, each in its own order, and both language
/// by language: in the languages the user asked for, most preferred first,
/// and then in English.
///
/// - **The app's own keys** — ``Text/init(_:tableName:bundle:comment:)``,
///   ``string(for:)-(String)``, `LocalizedString("…")` — read, in each
///   language: the table the call names (if it names one), the strings the app
///   registered (``register(translations:)``), the app's `Localizable` table,
///   and then TUI's own strings, so an app can borrow TUI's translations.
/// - **TUI's own words** — its controls' labels and the typed keys
///   (``LocalizationKey``) — read, in each language: the strings the app
///   registered, a table the app names `TUI` (`TUI.strings` in its
///   `.lproj` folders), and TUI's own translation. The app's `Localizable`
///   table does not change them: an app that happens to spell `button.ok` in
///   it has not asked for TUI's OK to change. Only where TUI has no
///   translation of the key in that language is the app's `Localizable` read
///   for it, so that a language TUI does not ship gets the app's words
///   rather than English.
///
/// "The languages the user asked for" are the language set with
/// ``setLanguage(_:)`` (or stored by it), or else the environment's: every
/// language it lists up to and including the first TUI ships, which is
/// ``currentLanguage``. So under `LANG=pt_BR.UTF-8` the app's Portuguese
/// strings are read first, and TUI's words fall back to English only for
/// what the app does not spell in Portuguese.
public final class LocalizationService: @unchecked Sendable {
    /// The shared localization service instance.
    public static let shared = LocalizationService()

    /// Currently active language: the one TUI's own words are in, where it
    /// has a translation of them.
    ///
    /// Always one of the languages TUI ships. The environment may ask for
    /// another first — Portuguese, say — and the app's own strings are read in
    /// that one before this; see "Where a key is looked up" above.
    ///
    /// No `didSet` doing work: the persistence and the re-render belong to
    /// ``setLanguage(_:)``, OUTSIDE its lock. Run from an observer they ran
    /// inside the critical section, and a storage failure there reports
    /// synchronously to the app's handler — a handler that localizes its own
    /// message re-entered `string(for:)`, and the lock is not recursive.
    public private(set) var currentLanguage: Language

    /// The locale the app formats in, and what `\.locale` is each frame
    /// unless a subtree sets its own: the user's locale, as SwiftUI's
    /// `\.locale` is.
    ///
    /// With no language chosen it is the environment's first language with
    /// the user's region, whether TUI ships that language or not: under
    /// `LANG=pt_BR.UTF-8` it is `pt_BR`, so numbers and dates are written as
    /// Brazil writes them, while the words are the app's Portuguese ones where
    /// it has them and TUI's English (``currentLanguage``) where it does
    /// not. Once a language is chosen (``setLanguage(_:)``, or the choice
    /// stored by it) it is that language with the user's region
    /// (``Language/locale(in:)``) — `de` under `LANG=en_GB.UTF-8` is German
    /// written for Britain — as macOS's per-app language makes
    /// `Locale.current`. Moved with ``currentLanguage``, under `lock`.
    ///
    /// Read under the lock, unlike ``currentLanguage``: a `Locale` holds a
    /// reference, which a read racing ``setLanguage(_:)`` must not tear.
    public var currentLocale: Locale {
        lock.withLock { _currentLocale }
    }

    /// ``currentLocale``'s storage, under `lock`.
    private var _currentLocale: Locale

    /// The region the user's locale names, read once when the service is
    /// made: see `systemRegion(environment:current:)`.
    private let region: Locale.Region?

    /// The language codes a key is looked up in, most preferred first, ending
    /// in English: ``currentLanguage``'s code, after any the environment asked
    /// for ahead of it that TUI has no translations of, and then `"en"`.
    /// Moved with ``currentLanguage``, under `lock`.
    private var lookupCodes: [String]

    /// Cached translations: [languageCode: [dotPath: localizedString]]
    private var translationCache: [String: [String: String]] = [:]

    /// App-supplied translations: [languageCode: [dotPath: localizedString]],
    /// registered by the host application via ``register(translations:)``. These
    /// are checked before the bundled framework strings, so an app can add its
    /// own keys and override framework defaults.
    private var appTranslations: [String: [String: String]] = [:]

    /// Whether any key in ``appTranslations`` holds a printf conversion other
    /// than `%@` — `%lld`, `%lf`, … — and so may be a key as SwiftUI spells an
    /// interpolated number (`LocalizedStringKey.swiftUIKey`). Until one is
    /// registered, a key in that spelling is not looked for among the
    /// registered strings: none could hold it, and an interpolated `Text` that
    /// is no key at all would otherwise hash its key a second time on every
    /// lookup, in every language. Under `lock`.
    private var registeredKeysSpellSwiftUI = false

    /// What ``string(for:swiftUIKey:tableName:bundle:)`` has answered, so a key
    /// asked for again — every `Text` of every frame — is one lookup rather
    /// than a walk of every language and every table, twice where SwiftUI
    /// spells the key differently. Emptied by everything that can change an
    /// answer: the language, and the strings an app registers. Under `lock`.
    private var resolved = ResolvedStrings()

    /// The numbers ``formatted(_:)`` has written in ``currentLocale``, so a
    /// body that interpolates an unchanged number into a key — every frame —
    /// looks it up rather than formatting it again. Emptied whenever
    /// ``currentLocale`` moves. Under `lock`.
    private var formattedNumbers = GenerationalMemo<InterpolatedNumber, String>(limit: formattedNumberLimit)

    /// How many numbers one generation of ``formattedNumbers`` holds.
    static let formattedNumberLimit = 1_024

    /// How many numbers ``formatted(_:)`` has written afresh, rather than
    /// found kept — for the tests that count them. Under `lock`.
    private var numbersWritten = 0

    /// ``numbersWritten``, read under the lock.
    var numbersFormatted: Int { lock.withLock { numbersWritten } }

    /// The app's own string tables — see ``BundleStringTables``. Used under
    /// `lock`.
    private let bundleTables: BundleStringTables

    /// Where TUI's own translations are read from: its resource bundle.
    let resources: ModuleResources

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Where this service persists its preference, when that is not the app's
    /// own config directory: the constructor override the localization tests
    /// use, and the scoped redirect in ``withPersistence(redirectedTo:_:)``.
    ///
    /// Read under `lock`, so that redirect is safe against a concurrent
    /// ``setLanguage(_:)``.
    private var configDirectoryOverride: String?

    /// The render states of the apps running from this service, which a
    /// change of what it holds asks for a frame wherever the change was made:
    /// see ``noteRunning(_:)``. Behind a lock of its own, not `lock`: it is
    /// read after a change has let go of that one, and noted from another
    /// file.
    let runningApps = Lock<[any AppRenderState]>(initialState: [])

    /// Creates and initializes the localization service.
    ///
    /// Loads the stored language preference, falling back to the language the
    /// environment asks for — see `systemPreferredLanguage(environment:preferredLanguages:)`
    /// — and then to English.
    public init() {
        self.configDirectoryOverride = nil
        self.bundleTables = BundleStringTables()
        self.resources = .current

        let initial = Self.initialLanguage(
            stored: Self.loadLanguagePreference(), asked: Self.systemPreferredLanguageCodes())
        self.currentLanguage = initial.language
        self.lookupCodes = initial.codes
        self.region = Self.systemRegion()
        self._currentLocale = Self.userLocale(initial, region: region)

        // Preload current language translations
        lock.lock()
        _ = _translations(for: currentLanguage.rawValue)
        lock.unlock()
    }

    /// Creates a localization service with a custom config directory.
    ///
    /// Used for testing to isolate file system access, to read string tables
    /// from a bundle of the test's own in place of the main bundle, and to
    /// read TUI's own translations from `resources` in place of its
    /// resource bundle. The language is the stored one, else the one
    /// `environment` asks for (its POSIX variables alone — never the machine's
    /// preferred languages), else English.
    init(
        configDirectoryPath: String, defaultBundle: Bundle = .main, environment: [String: String] = [:],
        resources: ModuleResources = .current
    ) {
        self.configDirectoryOverride = configDirectoryPath
        self.bundleTables = BundleStringTables(defaultBundle: defaultBundle)
        self.resources = resources

        let initial = Self.initialLanguage(
            stored: Self.loadLanguagePreference(from: configDirectoryPath),
            asked: Self.systemPreferredLanguageCodes(environment: environment, preferredLanguages: []))
        self.currentLanguage = initial.language
        self.lookupCodes = initial.codes
        self.region = Self.systemRegion(environment: environment, current: nil)
        self._currentLocale = Self.userLocale(initial, region: region)

        lock.lock()
        _ = _translations(for: currentLanguage.rawValue)
        lock.unlock()
    }

    /// Changes the active language and persists the preference, and asks for
    /// nothing to be drawn: this service's half of ``setLanguage(_:)``.
    ///
    /// The other half, the re-render, is the app's. This service sits below
    /// the views and the app's render state, and once TUI is split into
    /// modules it cannot name them; ``setLanguage(_:)`` is an extension beside
    /// the views (`LocalizationExtensions.swift`) that calls this and then
    /// asks for the frame. Internal for that one caller: a language changed
    /// here alone is not on screen until something else draws.
    ///
    /// - Parameter language: The new language to activate.
    package func setLanguageWithoutRendering(_ language: Language) {
        lock.lock()
        currentLanguage = language
        _currentLocale = language.locale(in: region)
        lookupCodes = Self.lookupCodes(asked: [], language: language)
        resolved = ResolvedStrings()
        formattedNumbers = GenerationalMemo(limit: Self.formattedNumberLimit)
        lock.unlock()
        // After the lock, deliberately — see `currentLanguage`.
        saveLanguagePreference(language)
    }

    /// Runs `body` with this service persisting its language into `directory`
    /// rather than into the app's config directory, and puts the previous
    /// destination back afterwards.
    ///
    /// The seam a test of the SHARED service needs, and internal because
    /// nothing about it is API an app wants. ``setLanguage(_:)`` writes the
    /// choice to ``defaultConfigDirectoryPath()``, which is named after
    /// `ProcessInfo.processName` — under the test runner that is a real file in
    /// the developer's own home, `~/Library/Application Support/
    /// swiftpm-testing-helper/language`. It outlives the run, and the next
    /// process to build this service reads it as the stored preference in
    /// preference to the environment, so one test that set a language pinned
    /// that language for every later run on that machine.
    ///
    /// - Parameters:
    ///   - directory: Where the preference may be written for the duration.
    ///   - body: The work to run with the redirect in force.
    func withPersistence<T>(redirectedTo directory: String, _ body: () throws -> T) rethrows -> T {
        let previous = lock.withLock { () -> String? in
            let previous = configDirectoryOverride
            configDirectoryOverride = directory
            return previous
        }
        defer { lock.withLock { configDirectoryOverride = previous } }
        return try body()
    }

    /// Sets the active language WITHOUT persisting it and without asking for a
    /// re-render — the seam a test suite needs against the shared service.
    ///
    /// ``setLanguage(_:)`` is the wrong tool for a test on two counts:
    ///
    /// * it **persists**, into the directory named after `ProcessInfo.processName`
    ///   — under the test runner a real file in the developer's own home (see
    ///   ``withPersistence(redirectedTo:)``), read back as the stored preference
    ///   by every later run on that machine;
    /// * it asks every app running from the service, and the app whose work
    ///   calls it, for a frame, which a suite pinning a language for its
    ///   renders has no reason to.
    ///
    /// This does neither: it moves `currentLanguage` under the lock and stops.
    ///
    /// Internal, and named for its one caller: the test suite's
    /// `.rendersEnglishUI` trait, which pins English on the shared service
    /// before a suite whose assertions read the framework's own words back out
    /// of a rendered buffer. That pin is deliberately ONE-WAY — it never puts a
    /// previous language back — because a window during which the process
    /// language is something else is exactly the defect the trait exists to
    /// prevent, and restoring one would reintroduce it.
    ///
    /// - Parameter language: The language to pin.
    func pinLanguageForTesting(_ language: Language) {
        lock.lock()
        currentLanguage = language
        _currentLocale = language.locale(in: region)
        lookupCodes = Self.lookupCodes(asked: [], language: language)
        resolved = ResolvedStrings()
        formattedNumbers = GenerationalMemo(limit: Self.formattedNumberLimit)
        lock.unlock()
    }

    /// The language a service starts in, and the codes it looks keys up in:
    /// the `stored` choice alone, else the languages the environment `asked`
    /// for, else English. `chosen` says which: a stored choice is the app's.
    private static func initialLanguage(
        stored: Language?, asked: [String]
    ) -> (language: Language, codes: [String], chosen: Bool) {
        if let stored {
            return (stored, lookupCodes(asked: [], language: stored), true)
        }
        let language = asked.last.flatMap(Language.init(rawValue:)) ?? .english
        return (language, lookupCodes(asked: asked, language: language), false)
    }

    /// The user's locale, as a service starting in `initial` sees it (see
    /// ``currentLocale``): the chosen language with `region`, or, with none
    /// chosen, the first language the environment asked for with `region` —
    /// which is ``currentLanguage`` unless that first language is one TUI
    /// does not ship.
    private static func userLocale(
        _ initial: (language: Language, codes: [String], chosen: Bool), region: Locale.Region?
    ) -> Locale {
        guard !initial.chosen, let asked = initial.codes.first, asked != initial.language.rawValue,
            Language(rawValue: asked) == nil
        else { return initial.language.locale(in: region) }
        guard let region else { return Locale(identifier: asked) }
        return Locale(languageCode: Locale.LanguageCode(asked), languageRegion: region)
    }

    /// `asked`, then `language`'s code, then English's, each once.
    private static func lookupCodes(asked: [String], language: Language) -> [String] {
        var codes = asked
        for code in [language.rawValue, Language.english.rawValue] where !codes.contains(code) {
            codes.append(code)
        }
        return codes
    }

    /// The language codes keys are looked up in, in order — for the tests.
    var lookupLanguageCodes: [String] {
        lock.withLock { lookupCodes }
    }

    /// Merges an app's translations into this service, and asks for nothing
    /// to be drawn: this service's half of ``register(translations:)``, which
    /// is the app's API and asks for the frame (see
    /// ``setLanguageWithoutRendering(_:)`` for why the halves are apart).
    ///
    /// - Parameter translations: Language-code-keyed translation tables to add.
    package func registerWithoutRendering(translations: [String: [String: String]]) {
        lock.lock()
        defer { lock.unlock() }
        resolved = ResolvedStrings()
        for (code, table) in translations {
            appTranslations[code, default: [:]].merge(table) { _, new in new }
            if !registeredKeysSpellSwiftUI, table.keys.contains(where: Self.holdsPrintfConversion) {
                registeredKeysSpellSwiftUI = true
            }
        }
    }

    /// Whether `key` holds a printf conversion other than `%@` (and other than
    /// `%%`, a literal percent sign): the mark of a key spelt as SwiftUI spells
    /// an interpolated number, which TUI's own spelling never holds.
    static func holdsPrintfConversion(_ key: String) -> Bool {
        var bytes = key.utf8.makeIterator()
        while let byte = bytes.next() {
            guard byte == UInt8(ascii: "%") else { continue }
            switch bytes.next() {
            case UInt8(ascii: "@"), UInt8(ascii: "%"): continue
            case nil: return false
            default: return true
            }
        }
        return false
    }

    /// Resolves a localized string using a dot-notation key, as the app's
    /// own text is resolved.
    ///
    /// Looked up language by language — the languages the user asked for,
    /// then English — and in each: the strings the app registered, then the
    /// main bundle's `Localizable` string table in that language's `.lproj`,
    /// as SwiftUI looks a key up, then TUI's own strings, so an app can
    /// borrow TUI's translations. Last, the table as Foundation picks it
    /// for the bundle, and then the key itself. See "Where a key is looked
    /// up" on ``LocalizationService``.
    ///
    /// The typed keys — `string(for: LocalizationKey.Button.ok)` and the
    /// rest — ask for TUI's own word instead, which an app's
    /// `Localizable` table does not change.
    ///
    /// - Parameter key: Dot-notation path (e.g., "button.ok", "error.invalid_input")
    /// - Returns: The localized string, or the key if not found.
    public func string(for key: String) -> String {
        string(for: key, tableName: nil, bundle: nil)
    }

    /// Resolves `key` as ``string(for:)`` does, in the table named
    /// `tableName` of `bundle` — `Localizable` and the main bundle where
    /// `nil`, as SwiftUI's `Text(_:tableName:bundle:comment:)` reads them.
    ///
    /// A table named explicitly is asked first in each language, ahead of the
    /// registered strings, since the call says where the key is; then the
    /// rest as ``string(for:)`` — a deliberate deviation (owner decision A14):
    /// where the named table lacks the key, SwiftUI shows the key itself, and
    /// this goes on to the app's other strings and TUI's. The default
    /// table written out — `tableName: "Localizable"`, `bundle: .main` — is
    /// not "named": it reads exactly as leaving them off does, as in SwiftUI.
    ///
    /// `swiftUIKey` is the same key as SwiftUI spells it, where that differs
    /// (`LocalizedStringKey.swiftUIKey`: `Moved %lld rows to %@` for
    /// `Moved %@ rows to %@`): in each language it is looked for first, in
    /// every place, then `key`, so a String Catalog extracted from SwiftUI code
    /// is found, and so is a table keyed as TUI's own are.
    package func string(
        for key: String, swiftUIKey: String? = nil, tableName: String?, bundle: Bundle?
    ) -> String {
        reading(key, swiftUIKey: swiftUIKey, tableName: tableName, bundle: bundle, in: nil).text
    }

    /// `number` as ``currentLocale`` writes it — a number interpolated into a
    /// key with no specifier, `Text("\(count) rows")` — kept, so asking again
    /// is a lookup.
    ///
    /// A key is built every time a body runs, so without the memo every frame
    /// paid the formatting (``InterpolatedNumber/formatted(in:)``, about
    /// 0.3 µs) for every number on screen whether it had changed or not.
    /// Formatted outside the lock: the first number in a locale makes
    /// Foundation's formatter for it, which is not quick.
    package func formatted(_ number: InterpolatedNumber) -> String {
        let locale: Locale
        do {
            lock.lock()
            defer { lock.unlock() }
            if let kept = formattedNumbers.answer(for: number) { return kept }
            locale = _currentLocale
        }
        let written = number.formatted(in: locale)
        lock.withLock {
            numbersWritten += 1
            // Not kept if the locale moved meanwhile: the memo is the new one's.
            if _currentLocale == locale { formattedNumbers.remember(written, for: number) }
        }
        return written
    }

    /// The language the app's own keys are read in first — the first of the
    /// languages the user asked for, or the one the app chose — as a code.
    /// What a `Text` made from a key notes it was read in, so that a subtree
    /// whose `\.locale` names another language can read it again in that one.
    package var stringLanguage: String {
        lock.withLock { lookupCodes[0] }
    }

    /// `key` as ``string(for:swiftUIKey:tableName:bundle:)`` resolves it, and
    /// the language it was read in first, from one lock.
    ///
    /// With a `language`, it is read as a subtree whose `\.locale` names that
    /// language reads it, as SwiftUI's `Text` does (measured 2026-10-18): in
    /// that language first, every place in turn, and then in English — where
    /// SwiftUI shows the key itself when the language's table lacks it
    /// (Deliberate deviations E4). `nil`, or the service's own first language,
    /// reads it as ``string(for:swiftUIKey:tableName:bundle:)`` does.
    package func reading(
        _ key: String, swiftUIKey: String?, tableName: String?, bundle: Bundle?, in language: String?
    ) -> (text: String, language: String) {
        lock.lock()
        defer { lock.unlock() }
        let own = lookupCodes[0]
        let other = language.flatMap { $0 == own ? nil : $0 }
        let memoKey = ResolvedStrings.Key(
            key: key, swiftUIKey: swiftUIKey, tableName: tableName, bundle: bundle, language: other)
        if let answer = resolved.answer(for: memoKey) { return (answer, other ?? own) }
        let codes = other.map { Self.lookupCodes(asked: [$0], language: .english) } ?? lookupCodes
        let answer = _resolve(key, swiftUIKey: swiftUIKey, tableName: tableName, bundle: bundle, codes: codes)
        resolved.remember(answer, for: memoKey)
        return (answer, other ?? own)
    }

    /// The walk ``reading(_:swiftUIKey:tableName:bundle:in:)`` remembers the
    /// answer of, through `codes` in order. Called under the lock.
    private func _resolve(
        _ key: String, swiftUIKey: String?, tableName: String?, bundle: Bundle?, codes: [String]
    ) -> String {
        let namesTable = !bundleTables.isDefaultTable(tableName, in: bundle)
        for code in codes {
            if let swiftUIKey,
                let value = _appValue(
                    swiftUIKey, in: code, namesTable: namesTable, tableName: tableName, bundle: bundle,
                    spelledAsSwiftUI: true)
            {
                return value
            }
            if let value = _appValue(
                key, in: code, namesTable: namesTable, tableName: tableName, bundle: bundle, spelledAsSwiftUI: false)
            {
                return value
            }
        }

        if let swiftUIKey,
            let value = _appFallback(swiftUIKey, namesTable: namesTable, tableName: tableName, bundle: bundle)
        {
            return value
        }
        return _appFallback(key, namesTable: namesTable, tableName: tableName, bundle: bundle) ?? key
    }

    /// `key` in `code` as ``string(for:swiftUIKey:tableName:bundle:)`` reads
    /// it: the named table, the strings the app registered, the app's
    /// `Localizable` table, and TUI's own. A key `spelledAsSwiftUI` is not
    /// looked for in TUI's own, none of which is spelt so, nor among the
    /// registered strings until one is (``registeredKeysSpellSwiftUI``).
    /// Called under the lock.
    private func _appValue(
        _ key: String, in code: String, namesTable: Bool, tableName: String?, bundle: Bundle?,
        spelledAsSwiftUI: Bool
    ) -> String? {
        if namesTable, let value = bundleTables.string(for: key, tableName: tableName, bundle: bundle, language: code) {
            return value
        }
        if !spelledAsSwiftUI || registeredKeysSpellSwiftUI, let value = appTranslations[code]?[key] {
            return value
        }
        // The app's table costs a stored Bool for an app that ships none.
        if let value = bundleTables.string(for: key, tableName: nil, bundle: nil, language: code) {
            return value
        }
        return spelledAsSwiftUI ? nil : _tuikitValue(key, in: code)
    }

    /// `key` in the tables as Foundation picks them for the bundle, the named
    /// one first: the last places ``string(for:swiftUIKey:tableName:bundle:)``
    /// looks. Called under the lock.
    private func _appFallback(_ key: String, namesTable: Bool, tableName: String?, bundle: Bundle?) -> String? {
        if namesTable, let value = bundleTables.fallbackString(for: key, tableName: tableName, bundle: bundle) {
            return value
        }
        return bundleTables.fallbackString(for: key, tableName: nil, bundle: nil)
    }

    /// TUI's own word for one of its own keys — the lookup TUI's
    /// controls make, and the typed keys (``LocalizationKey``).
    ///
    /// An app changes these only on purpose, never by spelling the same key
    /// in its own `Localizable` table by accident. Language by language —
    /// the languages the user asked for, then English — and in each:
    ///
    /// 1. the strings the app registered (``register(translations:)``);
    /// 2. the app's `TUI` table — `TUI.strings` in that language's
    ///    `.lproj` of the main bundle;
    /// 3. TUI's own translation;
    /// 4. only where TUI has no translation of the key in that language —
    ///    a language it does not ship, or a key it lacks — the app's
    ///    `Localizable` table, so that some of an app's words are better than
    ///    none.
    ///
    /// Last, the two tables as Foundation picks them for the bundle, and then
    /// the key itself.
    ///
    /// - Parameter key: One of TUI's keys (`LocalizationKey`'s raw values).
    /// - Returns: The localized string, or the key if not found.
    package func frameworkString(for key: String) -> String {
        frameworkReading(key, in: nil).text
    }

    /// One of TUI's own keys as ``frameworkString(for:)`` reads it, and the
    /// language it was read in first, from one lock.
    ///
    /// With a `language`, it is read as a subtree whose `\.locale` names that
    /// language reads it, as ``reading(_:swiftUIKey:tableName:bundle:in:)``
    /// reads an app's key: in that language first, then in English. `nil`, or
    /// the service's own first language, reads it as ``frameworkString(for:)``
    /// does.
    package func frameworkReading(_ key: String, in language: String?) -> (text: String, language: String) {
        lock.lock()
        defer { lock.unlock() }
        let own = lookupCodes[0]
        let other = language.flatMap { $0 == own ? nil : $0 }
        let codes = other.map { Self.lookupCodes(asked: [$0], language: .english) } ?? lookupCodes
        for code in codes {
            if let value = _frameworkValue(key, in: code) {
                return (value, other ?? own)
            }
        }
        return (_frameworkFallback(key), other ?? own)
    }

    /// How many table answers the service keeps — for the tests of their
    /// bound (`BundleStringTables.answerLimit`).
    var keptTableAnswerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return bundleTables.keptAnswerCount
    }

    /// How many times the service read a table through Foundation for an
    /// answer it had not kept — for the tests of the bound's hit rate.
    var tableReadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return bundleTables.foundationReads
    }

    /// Resolves one of TUI's own keys in `language`, whatever the current
    /// language is — falling back to English, then to the key, as
    /// ``frameworkString(for:)`` does.
    ///
    /// For text whose language is the locale's rather than the app's: a span
    /// spelt from the tables (`TimeSpan.tableUnitList`) follows the locale it
    /// was formatted in, as Foundation's own spellings do.
    func string(for key: String, in language: Language) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let value = _frameworkValue(key, in: language.rawValue) {
            return value
        }
        if language != .english, let value = _frameworkValue(key, in: Language.english.rawValue) {
            return value
        }
        return _frameworkFallback(key)
    }

    // MARK: - Private Helpers (caller MUST hold lock)

    /// TUI's own translations in the language `code`, loaded from its JSON
    /// the first time they are asked for; empty for a language TUI ships
    /// none of, which is remembered too. English whose file cannot be read is
    /// the copy compiled in (``builtInEnglish``); any other language whose
    /// file cannot be read is empty, and falls back to English.
    ///
    /// - Important: Caller must hold `lock`.
    private func _translations(for code: String) -> [String: String] {
        if let cached = translationCache[code] {
            return cached
        }
        let loaded =
            loadTranslationsFromBundle(language: code)
            ?? (code == Language.english.rawValue ? Self.builtInEnglish : [:])
        translationCache[code] = loaded
        return loaded
    }

    /// TUI's word for `key` in the language `code`, as the app has set it:
    /// the app's `TUI` table, then TUI's own translation.
    ///
    /// - Important: Caller must hold `lock`.
    private func _tuikitValue(_ key: String, in code: String) -> String? {
        // The table costs a stored Bool for an app that ships none.
        if let value = bundleTables.string(
            for: key, tableName: BundleStringTables.frameworkTableName, bundle: nil, language: code)
        {
            return value
        }
        return _translations(for: code)[key]
    }

    /// One language's step of ``frameworkString(for:)``: registered, the
    /// app's `TUI` table, TUI's own translation, and — only where TUI
    /// has none — the app's `Localizable` table.
    ///
    /// - Important: Caller must hold `lock`.
    private func _frameworkValue(_ key: String, in code: String) -> String? {
        if let value = appTranslations[code]?[key] {
            return value
        }
        if let value = _tuikitValue(key, in: code) {
            return value
        }
        return bundleTables.string(for: key, tableName: nil, bundle: nil, language: code)
    }

    /// The last step of ``frameworkString(for:)``: the app's `TUI` table,
    /// then its `Localizable` one, as Foundation picks them for the bundle,
    /// then the key itself.
    ///
    /// - Important: Caller must hold `lock`.
    private func _frameworkFallback(_ key: String) -> String {
        bundleTables.fallbackString(for: key, tableName: BundleStringTables.frameworkTableName, bundle: nil)
            ?? bundleTables.fallbackString(for: key, tableName: nil, bundle: nil)
            ?? key
    }

    /// Saves language preference to config file.
    private func saveLanguagePreference(_ language: Language) {
        let path = configFilePath()
        let dirPath = (path as NSString).deletingLastPathComponent

        // Create directory if needed
        do {
            try FileManager.default.createDirectory(
                atPath: dirPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            StorageDiagnostics.report(
                StorageFailure(operation: .createDirectory, path: dirPath, underlying: error))
        }

        // Write language code
        do {
            try language.rawValue.write(
                toFile: path,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // Same contract as `@AppStorage`: a language the user chose that
            // does not reach the disk is a setting silently lost at the next
            // launch, so it goes through the one storage-failure channel.
            StorageDiagnostics.report(
                StorageFailure(
                    operation: .save, key: "language", path: path, underlying: error))
        }
    }

    /// Returns the config file path, using override if set.
    ///
    /// Its one caller, ``saveLanguagePreference(_:)``, runs OUTSIDE `lock` —
    /// deliberately, see ``currentLanguage`` — so reading the override under
    /// the lock here is not re-entrant.
    private func configFilePath() -> String {
        let dir = lock.withLock { configDirectoryOverride } ?? Self.defaultConfigDirectoryPath()
        return (dir as NSString).appendingPathComponent("language")
    }
}
