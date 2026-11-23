//  🖥️ TUI — A Terminal UI framework for Swift
//  LanguageTag.swift
//
//  A language as the localization service keys its strings: the language, the
//  script where it is not the language's own, and the region.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization

/// A language a string is asked for in, as ``LocalizationService`` keys its
/// lookups: `zh-Hant-TW`, `pt-BR`, `de`.
///
/// Read from a POSIX locale name (`zh_TW.UTF-8`, `de_DE@euro`) or a BCP-47 tag
/// (`zh-Hant-TW`), and written one way whichever it came as, so the same
/// language is always the same string: the language code in lower case, the
/// script in title case, the region in upper case, joined by hyphens.
///
/// The script is written only where it tells the language apart: where it is
/// not the one the language is written in by default, or not the one the
/// region would give it. `zh_TW` is `zh-Hant-TW`, because Chinese is
/// Simplified unless something says otherwise and Taiwan's is Traditional;
/// `zh-Hans` is `zh`; `de_DE` is `de-DE`, never `de-Latn-DE`. Foundation's
/// likely-subtag data (`Locale.Language.script`, which infers a script left
/// unstated) decides each default, on every platform.
///
/// The world region (`001`), which swift-foundation reports where it has
/// nothing to read, is no region.
struct LanguageTag: Hashable, Sendable {
    /// The language code, `zh`.
    let language: String

    /// The script, where it is written (see above): `Hant` in `zh-Hant-TW`.
    let script: String?

    /// The region, `TW`, or a UN M.49 area, `419`.
    let region: String?

    /// The tag with no region: the language in its script, `zh-Hant` for
    /// `zh-Hant-TW` and `pt` for `pt-BR`. Its script is written only where it
    /// is not the language's own, so Simplified Chinese in Taiwan
    /// (`zh-Hans-TW`) is `zh`, and Traditional (`zh-Hant-TW`) is `zh-Hant`.
    let bare: String

    /// The tag as one string: `zh-Hant-TW`.
    var identifier: String {
        var identifier = language
        if let script { identifier += "-" + script }
        if let region { identifier += "-" + region }
        return identifier
    }

    /// The codes a string is looked up under for this language, the full tag
    /// first and then the bare one (the owner's O-06 (a), 2026-11-21):
    /// `["pt-BR", "pt"]`, `["zh-Hant-TW", "zh-Hant"]`, `["de"]`.
    ///
    /// Never the language code alone where the script is not the language's
    /// own: Traditional Chinese does not fall back to `zh`, which is
    /// Simplified, as Foundation's own matching does not
    /// (`Bundle.preferredLocalizations` gives `zh-Hant` no `zh.lproj`, and
    /// SwiftUI's `\.locale` reads `zh-Hant.lproj` for `zh_TW`;
    /// `Tools/SwiftUIProbes/Small parity items (PARITYMISC)/locale-scripts/`).
    var lookupCodes: [String] {
        let full = identifier
        return full == bare ? [full] : [full, bare]
    }

    /// The language a POSIX locale name or BCP-47 tag names, or `nil` where it
    /// names none: the neutral `C` and `POSIX` locales, an empty value, or
    /// anything whose first part is not a two- or three-letter code. NOT
    /// `prefix(2)`, which would read `C` and `POSIX` as the codes "c" and
    /// "po", and Filipino (`fil`) as Finnish.
    ///
    /// Remembered, keyed by `name`: see ``memo``.
    init?(_ name: some StringProtocol) {
        let name = String(name)
        if let known = Self.memo.withLock({ $0[name] }) {
            guard let known else { return nil }
            self = known
            return
        }
        let parsed = Self.parse(name)
        Self.memo.withLock { memo in
            if memo.count >= Self.memoLimit { memo.removeAll(keepingCapacity: true) }
            memo[name] = .some(parsed)
        }
        guard let parsed else { return nil }
        self = parsed
    }

    private init(language: String, script: String?, region: String?, bare: String) {
        self.language = language
        self.script = script
        self.region = region
        self.bare = bare
    }

    /// What ``init(_:)`` reads `name` as, worked out afresh.
    private static func parse(_ name: String) -> Self? {
        let tag = name.prefix { !".@".contains($0) }
        let parts = tag.split(whereSeparator: { "-_".contains($0) })
        guard let first = parts.first, (2...3).contains(first.count), first.allSatisfy(\.isLetter) else { return nil }
        let language = first.lowercased()
        var stated: String?
        var region: String?
        for part in parts.dropFirst() {
            if stated == nil, region == nil, part.count == 4, part.allSatisfy(\.isLetter) {
                stated = part.prefix(1).uppercased() + part.dropFirst().lowercased()
            } else if part.count == 2, part.allSatisfy(\.isLetter) {
                region = part.uppercased()
                break
            } else if part.count == 3, part.allSatisfy(\.isNumber) {
                region = String(part)
                break
            } else {
                break  // a variant (`en_US_POSIX`) or an extension: the tag ends here
            }
        }
        if region == "001" { region = nil }

        let languageScript = likelyScript(language)
        let regionScript = region.flatMap { likelyScript(language + "-" + $0) } ?? languageScript
        let script = stated ?? regionScript
        let bare = script.flatMap { $0 == languageScript ? nil : language + "-" + $0 } ?? language
        let written = script == languageScript && script == regionScript ? nil : script
        return Self(language: language, script: written, region: region, bare: bare)
    }

    /// The script `identifier` is written in where it does not say:
    /// Foundation's likely subtags, `Hant` for `zh-TW`.
    private static func likelyScript(_ identifier: String) -> String? {
        Locale.Language(identifier: identifier).script?.identifier
    }

    /// What ``init(_:)`` has read each name as, `nil` for a name that names no
    /// language.
    ///
    /// A private, bounded, process-wide memo of a pure function, the one kind
    /// of process-wide store the architecture rules allow without a ruling: the
    /// same name always reads as the same tag (Foundation's likely-subtag data
    /// is fixed for the process), and nothing outside can tell a hit from a
    /// miss. Keyed by the whole name, which is everything the parse reads.
    /// Kept because a subtree's `\.locale` is read through it each time it is
    /// set, every frame, and the likely-subtag lookups cost about 2 µs where
    /// the memo costs a hash.
    private static let memo = Mutex<[String: Self?]>([:])

    /// How many names ``memo`` holds before it starts again: far more than
    /// an app's languages.
    private static let memoLimit = 256
}

extension LocalizationService.Language {
    /// The language TUI ships whose strings a reader of `tag` reads, if any:
    /// the one whose code is the tag's bare form (``LanguageTag/bare``). So
    /// TUI's Chinese, which is Simplified (`zh`), is no reader of Traditional
    /// Chinese's (`zh-Hant`), and a German reader in Switzerland reads German.
    init?(reading tag: LanguageTag) {
        self.init(rawValue: tag.bare)
    }
}

extension LocalizationService {
    /// The language tag `name` names — a POSIX locale name, a BCP-47 tag or a
    /// `Locale`'s identifier — as the service keys its strings (`zh_TW` is
    /// `zh-Hant-TW`, ``LanguageTag``), or `nil` where it names no language.
    package static func languageTag(of name: String) -> String? {
        LanguageTag(name)?.identifier
    }
}
