//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationService.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

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
///   and then TUIkit's own strings, so an app can borrow TUIkit's translations.
/// - **TUIkit's own words** — its controls' labels and the typed keys
///   (``LocalizationKey``) — read, in each language: the strings the app
///   registered, a table the app names `TUIkit` (`TUIkit.strings` in its
///   `.lproj` folders), and TUIkit's own translation. The app's `Localizable`
///   table does not change them: an app that happens to spell `button.ok` in
///   it has not asked for TUIkit's OK to change. Only where TUIkit has no
///   translation of the key in that language is the app's `Localizable` read
///   for it, so that a language TUIkit does not ship gets the app's words
///   rather than English.
///
/// "The languages the user asked for" are the language set with
/// ``setLanguage(_:)`` (or stored by it), or else the environment's: every
/// language it lists up to and including the first TUIkit ships, which is
/// ``currentLanguage``. So under `LANG=pt_BR.UTF-8` the app's Portuguese
/// strings are read first, and TUIkit's words fall back to English only for
/// what the app does not spell in Portuguese.
public final class LocalizationService: @unchecked Sendable {
    /// The shared localization service instance.
    public static let shared = LocalizationService()

    /// Currently active language: the one TUIkit's own words are in, where it
    /// has a translation of them.
    ///
    /// Always one of the languages TUIkit ships. The environment may ask for
    /// another first — Portuguese, say — and the app's own strings are read in
    /// that one before this; see "Where a key is looked up" above.
    ///
    /// No `didSet` doing work: the persistence and the re-render belong to
    /// ``setLanguage(_:)``, OUTSIDE its lock. Run from an observer they ran
    /// inside the critical section, and a storage failure there reports
    /// synchronously to the app's handler — a handler that localizes its own
    /// message re-entered `string(for:)`, and the lock is not recursive.
    public private(set) var currentLanguage: Language

    /// The locale the app formats in: ``currentLanguage`` with the user's
    /// region (``Language/locale(in:)``), so `de` under `LANG=en_GB.UTF-8` is
    /// German written for Britain. Moved with ``currentLanguage``, under
    /// `lock`; what `\.locale` is, each frame, unless a subtree sets its own.
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
    /// for ahead of it that TUIkit has no translations of, and then `"en"`.
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

    /// The app's own string tables — see ``BundleStringTables``. Used under
    /// `lock`.
    private let bundleTables: BundleStringTables

    /// Where TUIkit's own translations are read from: its resource bundle.
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
        self._currentLocale = initial.language.locale(in: region)

        // Preload current language translations
        lock.lock()
        _ = _translations(for: currentLanguage.rawValue)
        lock.unlock()
    }

    /// Creates a localization service with a custom config directory.
    ///
    /// Used for testing to isolate file system access, to read string tables
    /// from a bundle of the test's own in place of the main bundle, and to
    /// read TUIkit's own translations from `resources` in place of its
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
        self._currentLocale = initial.language.locale(in: region)

        lock.lock()
        _ = _translations(for: currentLanguage.rawValue)
        lock.unlock()
    }

    /// Changes the active language and persists the preference, and asks for
    /// nothing to be drawn: this service's half of ``setLanguage(_:)``.
    ///
    /// The other half, the re-render, is the app's. This service sits below
    /// the views and the app's render state, and once TUIkit is split into
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
    /// * it asks the app whose work calls it for a frame, which a suite
    ///   pinning a language for its renders has no reason to.
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
        lock.unlock()
    }

    /// The language a service starts in, and the codes it looks keys up in:
    /// the `stored` choice alone, else the languages the environment `asked`
    /// for, else English.
    private static func initialLanguage(stored: Language?, asked: [String]) -> (language: Language, codes: [String]) {
        if let stored {
            return (stored, lookupCodes(asked: [], language: stored))
        }
        let language = asked.last.flatMap(Language.init(rawValue:)) ?? .english
        return (language, lookupCodes(asked: asked, language: language))
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
    /// an interpolated number, which TUIkit's own spelling never holds.
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
    /// as SwiftUI looks a key up, then TUIkit's own strings, so an app can
    /// borrow TUIkit's translations. Last, the table as Foundation picks it
    /// for the bundle, and then the key itself. See "Where a key is looked
    /// up" on ``LocalizationService``.
    ///
    /// The typed keys — `string(for: LocalizationKey.Button.ok)` and the
    /// rest — ask for TUIkit's own word instead, which an app's
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
    /// this goes on to the app's other strings and TUIkit's. The default
    /// table written out — `tableName: "Localizable"`, `bundle: .main` — is
    /// not "named": it reads exactly as leaving them off does, as in SwiftUI.
    ///
    /// `swiftUIKey` is the same key as SwiftUI spells it, where that differs
    /// (`LocalizedStringKey.swiftUIKey`: `Moved %lld rows to %@` for
    /// `Moved %@ rows to %@`): in each language it is looked for first, in
    /// every place, then `key`, so a String Catalog extracted from SwiftUI code
    /// is found, and so is a table keyed as TUIkit's own are.
    package func string(
        for key: String, swiftUIKey: String? = nil, tableName: String?, bundle: Bundle?
    ) -> String {
        lock.lock()
        defer { lock.unlock() }

        let memoKey = ResolvedStrings.Key(key: key, swiftUIKey: swiftUIKey, tableName: tableName, bundle: bundle)
        if let answer = resolved.answer(for: memoKey) { return answer }
        let answer = _resolve(key, swiftUIKey: swiftUIKey, tableName: tableName, bundle: bundle)
        resolved.remember(answer, for: memoKey)
        return answer
    }

    /// The walk ``string(for:swiftUIKey:tableName:bundle:)`` remembers the
    /// answer of. Called under the lock.
    private func _resolve(_ key: String, swiftUIKey: String?, tableName: String?, bundle: Bundle?) -> String {
        let namesTable = !bundleTables.isDefaultTable(tableName, in: bundle)
        for code in lookupCodes {
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
    /// `Localizable` table, and TUIkit's own. A key `spelledAsSwiftUI` is not
    /// looked for in TUIkit's own, none of which is spelt so, nor among the
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

    /// TUIkit's own word for one of its own keys — the lookup TUIkit's
    /// controls make, and the typed keys (``LocalizationKey``).
    ///
    /// An app changes these only on purpose, never by spelling the same key
    /// in its own `Localizable` table by accident. Language by language —
    /// the languages the user asked for, then English — and in each:
    ///
    /// 1. the strings the app registered (``register(translations:)``);
    /// 2. the app's `TUIkit` table — `TUIkit.strings` in that language's
    ///    `.lproj` of the main bundle;
    /// 3. TUIkit's own translation;
    /// 4. only where TUIkit has no translation of the key in that language —
    ///    a language it does not ship, or a key it lacks — the app's
    ///    `Localizable` table, so that some of an app's words are better than
    ///    none.
    ///
    /// Last, the two tables as Foundation picks them for the bundle, and then
    /// the key itself.
    ///
    /// - Parameter key: One of TUIkit's keys (`LocalizationKey`'s raw values).
    /// - Returns: The localized string, or the key if not found.
    package func frameworkString(for key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        for code in lookupCodes {
            if let value = _frameworkValue(key, in: code) {
                return value
            }
        }
        return _frameworkFallback(key)
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

    /// Resolves one of TUIkit's own keys in `language`, whatever the current
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

    /// TUIkit's own translations in the language `code`, loaded from its JSON
    /// the first time they are asked for; empty for a language TUIkit ships
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

    /// TUIkit's word for `key` in the language `code`, as the app has set it:
    /// the app's `TUIkit` table, then TUIkit's own translation.
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
    /// app's `TUIkit` table, TUIkit's own translation, and — only where TUIkit
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

    /// The last step of ``frameworkString(for:)``: the app's `TUIkit` table,
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
