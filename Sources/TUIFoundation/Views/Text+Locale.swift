//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+Locale.swift
//
//  A `Text` made from a key reads it again, when it is drawn, in the language
//  a subtree's `\.locale` names — the lazy half of the owner's option B
//  (2026-10-14/15): `\.locale` picks the string language, as SwiftUI's does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization

// MARK: - Where a text's words came from

/// What a `Text` made from a key needs to read it again in another language
/// or locale: the key, the table it was read from, the language it was read
/// in, and the locale its numbers were written in.
///
/// One object per key, table and language where the text holding it can be
/// equal to another (``source(_:tableName:bundle:language:locale:words:)``), so two
/// `Text`s made from one key — a body run for the measure and again for the
/// render — hold the same one, and the per-pass memos, which hash a view's
/// bytes, see equal values as equal. Compared by value too, for the memos that
/// compare with `==`. Immutable, so sharing it across threads is safe.
package final class LocalizedTextSource: Equatable, Sendable {
    let key: LocalizedStringKey
    let tableName: String?
    let bundle: Bundle?
    /// The language the words were read in first, as a code.
    let language: String
    /// The locale the key's numbers (`LocalizedStringKey.numberArguments`) were
    /// written in where a subtree's `\.locale` chose it; `nil` for the app's
    /// (`LocalizationService.currentLocale`), as the key wrote them.
    let locale: Locale?
    /// Whether the key is one of TUI's own (`Text(localized:)`), read in TUI's
    /// order (`LocalizationService.frameworkReading(_:in:)`) rather than an
    /// app's.
    let isFramework: Bool

    private init(
        key: LocalizedStringKey, tableName: String?, bundle: Bundle?, language: String, locale: Locale?,
        isFramework: Bool
    ) {
        self.key = key
        self.tableName = tableName
        self.bundle = bundle
        self.language = language
        self.locale = locale
        self.isFramework = isFramework
    }

    package static func == (lhs: LocalizedTextSource, rhs: LocalizedTextSource) -> Bool {
        lhs === rhs
            || (lhs.language == rhs.language && lhs.key == rhs.key && lhs.tableName == rhs.tableName
                && lhs.bundle == rhs.bundle && lhs.locale == rhs.locale && lhs.isFramework == rhs.isFramework)
    }

    /// What one is filed under: compared whole, and hashed by the parts that
    /// tell two keys apart in practice — the lookup key, the values, the
    /// language. A key's synthesized hash read every field, its two
    /// dictionaries included, for every keyed `Text` made: a hash and a copy
    /// that were most of a lookup's cost on `churn`.
    private struct Filed: Hashable {
        let key: LocalizedStringKey
        let tableName: String?
        let bundle: ObjectIdentifier?
        let language: String
        /// Compared, not hashed: the key's words already differ wherever
        /// its numbers were written in another locale.
        let locale: Locale?
        /// Compared, not hashed: TUI's keys and an app's rarely share a name.
        let isFramework: Bool

        func hash(into hasher: inout Hasher) {
            hasher.combine(key.key)
            hasher.combine(key.arguments)
            hasher.combine(language)
        }
    }

    /// The most kept: a backstop against keys made from data, as
    /// `MarkdownTemplate`'s parses are kept — emptied when full, at the cost
    /// of one memo miss each for what was in it.
    static let limit = 4_096

    /// Behind a lock, not the main actor: a `Text` of a literal may be made
    /// anywhere (`Text` is built in free functions, on other actors), and this
    /// is the one thing its initialiser touches beyond its own bytes.
    private static let kept = Mutex<[Filed: LocalizedTextSource]>([:])

    /// The most UTF-8 bytes a `String` keeps in its own bytes, with no buffer
    /// of its own: 15 on a 64-bit platform, 10 on a 32-bit one.
    private static let inlineCapacity = MemoryLayout<Int>.size == 8 ? 15 : 10

    /// The one a `Text` reading `words` holds for `key`, read in `language`
    /// from `tableName` of `bundle`, its numbers written in `locale` (`nil`
    /// for the app's).
    ///
    /// The kept one (``interned(_:tableName:bundle:language:)``) where the text
    /// can be equal to another made from the key: where the key has no values,
    /// so its words are the table's one string, or where the words fit in the
    /// string's own bytes. Values spelled into longer words make a string of
    /// its own every time, so the text's bytes never equal another's whatever
    /// its source, and a lookup would buy no memo hit. Such a text gets a source
    /// of its own instead. On `scrollfollow`, whose rows are such texts, the
    /// lookup was most of a +6.9% (2026-10-18).
    static func source(
        _ key: LocalizedStringKey, tableName: String?, bundle: Bundle?, language: String, locale: Locale?,
        words: String
    ) -> LocalizedTextSource {
        if !key.arguments.isEmpty, words.utf8.count > inlineCapacity {
            return LocalizedTextSource(
                key: key, tableName: tableName, bundle: bundle, language: language, locale: locale, isFramework: false)
        }
        return interned(key, tableName: tableName, bundle: bundle, language: language, locale: locale)
    }

    /// The one for TUI's own key `key`, read in the app's language: what a
    /// view keeps of a word of TUI's it shows, to read again under a subtree's
    /// `\.locale` (``LocalizedTextSource/words(in:)``).
    package static func framework(_ key: String) -> LocalizedTextSource {
        interned(
            LocalizedStringKey(key), tableName: nil, bundle: nil,
            language: LocalizationService.shared.frameworkReading(key, in: nil).language, locale: nil,
            isFramework: true)
    }

    /// The one for `key` read in `language` from `tableName` of `bundle`, its
    /// numbers written in `locale`.
    static func interned(
        _ key: LocalizedStringKey, tableName: String?, bundle: Bundle?, language: String, locale: Locale?,
        isFramework: Bool = false
    ) -> LocalizedTextSource {
        let filed = Filed(
            key: key, tableName: tableName, bundle: bundle.map(ObjectIdentifier.init), language: language,
            locale: locale, isFramework: isFramework)
        return Self.kept.withLock { kept in
            if let source = kept[filed] { return source }
            let source = LocalizedTextSource(
                key: key, tableName: tableName, bundle: bundle, language: language, locale: locale,
                isFramework: isFramework)
            if kept.count >= limit { kept.removeAll(keepingCapacity: true) }
            kept[filed] = source
            return source
        }
    }
}

// MARK: - Reading it again

@MainActor extension Text {
    /// One of TUI's own keys, read as `Text(localized:)` reads it, in
    /// `language` first where one is given (``relocalized(in:)``); `nil`
    /// reads it in the app's. It notes where its words came from, so a
    /// subtree whose `\.locale` names another language reads it again there,
    /// as SwiftUI's own controls' words follow `\.locale`.
    nonisolated init(frameworkKey key: String, language: String?) {
        let reading = LocalizationService.shared.frameworkReading(key, in: language)
        self.init(verbatim: reading.text)
        localization = LocalizedTextSource.interned(
            LocalizedStringKey(key), tableName: nil, bundle: nil, language: reading.language, locale: nil,
            isFramework: true)
    }

    /// `key` read as ``init(_:tableName:bundle:comment:)`` reads it, in
    /// `language` first where one is given: the language a subtree's
    /// `\.locale` names (``relocalized(in:)``). `nil` reads it in the app's.
    /// Its numbers are written in `locale`, that subtree's `\.locale`, where
    /// one is given, and as the key wrote them, in the app's, where not.
    nonisolated init(_ key: LocalizedStringKey, tableName: String?, bundle: Bundle?, language: String?, locale: Locale? = nil) {
        let reading = LocalizationService.shared.reading(
            key.key, swiftUIKey: key.swiftUIKey, tableName: tableName, bundle: bundle, in: language)
        let template = reading.text
        defer {
            localization = LocalizedTextSource.source(
                key, tableName: tableName, bundle: bundle, language: reading.language, locale: locale, words: content)
        }
        // The source keeps the key as it came, so another locale writes its
        // numbers afresh; everything below reads them as `locale` writes them.
        let key = locale.map { key.formattingNumbers(in: $0) } ?? key
        // A byte scan first: most keys hold nothing Markdown could act on, and
        // those take the plain path exactly as before. An interpolated `Text`
        // with styling of its own is spliced in on the Markdown path too.
        if InlineMarkdown.mightContainMarkup(template) || !key.styledArguments.isEmpty {
            let parsed = Self.markdownRuns(in: template, key: key)
            self.init(verbatim: parsed.content)
            runs = parsed.runs
            return
        }
        self.init(
            verbatim: key.arguments.isEmpty ? template : LocalizedStringKey.substituting(key.arguments, into: template))
        if !key.liveArguments.isEmpty {
            runs = [
                Run(
                    text: content, style: TextStyle(),
                    live: LiveTextBox(
                        LocalizedKeySource(key: key, tableName: tableName, bundle: bundle, language: language)))
            ]
        }
    }

    /// This text as a subtree whose `\.locale` names another language reads
    /// it: its key read in that language first, with this text's own style —
    /// what its modifiers stated — over it. `nil` where nothing names a
    /// language, or it names the one the words were read in, which is the
    /// common case and costs one environment read.
    ///
    /// Read where the text is drawn, as SwiftUI resolves a `Text`'s key: the
    /// environment is not known when a `Text` is made.
    ///
    /// A key with numbers (`LocalizedStringKey.numberArguments`) is read again,
    /// too, where the subtree's locale is not the one they were written in,
    /// though its language is the same: `en_IN` groups `12,34,567` where the
    /// app's `en_US` wrote `1,234,567`. That costs such a text, under such a
    /// subtree, a comparison of two locales; elsewhere it costs nothing more.
    func relocalized(in context: RenderContext) -> Text? {
        guard let localization, let language = context.environment.stringLanguage else { return nil }
        if localization.isFramework {
            guard language != localization.language else { return nil }
            var read = Text(frameworkKey: localization.key.key, language: language)
            read.style = style
            return read
        }
        var locale = localization.locale
        if !localization.key.numberArguments.isEmpty {
            let wanted = context.environment.locale
            if wanted != (localization.locale ?? LocalizationService.shared.currentLocale) { locale = wanted }
        }
        guard language != localization.language || locale != localization.locale else { return nil }
        var read = Text(
            localization.key, tableName: localization.tableName, bundle: localization.bundle, language: language,
            locale: locale)
        read.style = style
        return read
    }

    /// This text as it reads under `context`: ``relocalized(in:)``'s reading
    /// where that reads it again, and this text otherwise.
    ///
    /// For a caller that takes a text's words without measuring or drawing it,
    /// which is where a text reads its key again: a table draws a plain cell
    /// as the string it holds. A text that is no key pays a nil check.
    package func reading(in context: RenderContext) -> Text {
        guard localization != nil, let read = relocalized(in: context) else { return self }
        return read
    }
}
