//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Locale.swift
//
//  A `Text` made from a key reads it again, when it is drawn, in the language
//  a subtree's `\.locale` names — the lazy half of the owner's option B
//  (2026-10-14/15): `\.locale` picks the string language, as SwiftUI's does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Where a text's words came from

/// What a `Text` made from a key needs to read it again in another language:
/// the key, the table it was read from, and the language it was read in.
///
/// One object per key, table and language (``interned(_:tableName:bundle:language:)``),
/// so two `Text`s made from one key — a body run for the measure and again for
/// the render — hold the same one, and the per-pass memos, which hash a view's
/// bytes, see equal values as equal. Compared by value too, for the memos that
/// compare with `==`. Immutable, so sharing it across threads is safe.
package final class LocalizedTextSource: Equatable, @unchecked Sendable {
    let key: LocalizedStringKey
    let tableName: String?
    let bundle: Bundle?
    /// The language the words were read in first, as a code.
    let language: String

    private init(key: LocalizedStringKey, tableName: String?, bundle: Bundle?, language: String) {
        self.key = key
        self.tableName = tableName
        self.bundle = bundle
        self.language = language
    }

    package static func == (lhs: LocalizedTextSource, rhs: LocalizedTextSource) -> Bool {
        lhs === rhs
            || (lhs.language == rhs.language && lhs.key == rhs.key && lhs.tableName == rhs.tableName
                && lhs.bundle == rhs.bundle)
    }

    /// What one is filed under.
    private struct Filed: Hashable {
        let key: LocalizedStringKey
        let tableName: String?
        let bundle: ObjectIdentifier?
        let language: String
    }

    /// The most kept: a backstop against keys made from data, as
    /// `MarkdownTemplate`'s parses are kept — emptied when full, at the cost
    /// of one memo miss each for what was in it.
    static let limit = 4_096

    @MainActor private static var kept: [Filed: LocalizedTextSource] = [:]

    /// The one for `key` read in `language` from `tableName` of `bundle`.
    @MainActor
    static func interned(
        _ key: LocalizedStringKey, tableName: String?, bundle: Bundle?, language: String
    ) -> LocalizedTextSource {
        let filed = Filed(key: key, tableName: tableName, bundle: bundle.map(ObjectIdentifier.init), language: language)
        if let source = kept[filed] { return source }
        let source = LocalizedTextSource(key: key, tableName: tableName, bundle: bundle, language: language)
        if kept.count >= limit { kept.removeAll(keepingCapacity: true) }
        kept[filed] = source
        return source
    }
}

// MARK: - Reading it again

extension Text {
    /// `key` read as ``init(_:tableName:bundle:comment:)`` reads it, in
    /// `language` first where one is given: the language a subtree's
    /// `\.locale` names (``relocalized(in:)``). `nil` reads it in the app's.
    init(_ key: LocalizedStringKey, tableName: String?, bundle: Bundle?, language: String?) {
        let reading = LocalizationService.shared.reading(
            key.key, swiftUIKey: key.swiftUIKey, tableName: tableName, bundle: bundle, in: language)
        let template = reading.text
        defer {
            localization = LocalizedTextSource.interned(
                key, tableName: tableName, bundle: bundle, language: reading.language)
        }
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
    func relocalized(in context: RenderContext) -> Text? {
        guard let localization, let language = context.environment.stringLanguage,
            language != localization.language
        else { return nil }
        var read = Text(
            localization.key, tableName: localization.tableName, bundle: localization.bundle, language: language)
        read.style = style
        return read
    }
}
