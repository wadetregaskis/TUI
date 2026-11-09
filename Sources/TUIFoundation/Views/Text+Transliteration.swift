//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+Transliteration.swift
//
//  An experiment behind a flag (owner, 2026-11-08): for a terminal that can show
//  only ASCII, spell other scripts in Latin letters BEFORE layout, so "你好" is
//  "ni hao", six cells, and the layout makes room for it. The folding at output
//  (`PlainTerminalText` in TUIApp) has to keep each character to the cells it was
//  laid out in, which cuts "你好" to "niha". That folding stays, for what this
//  doesn't reach: chrome, and text being edited.
//  `TUI_PLAIN_TEXT=transliterate` turns it on; see
//  `Documentation/Historical/Text, editing and the clipboard/ASCII transliteration before layout.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import TUICore
import TUIView

extension RenderContext {
    /// `string` as this context spells words (``textSpelling``): in ASCII where
    /// the person asked for it, as written otherwise.
    ///
    /// The one entry point for a view that draws a string of its own rather
    /// than through a ``Text`` — a tab's title, a status bar item, a badge — so
    /// its words are spelled as a `Text`'s are. Call it once, where the string
    /// is first read in a measure or a render, and use what it answers for both:
    /// a string measured as written and drawn spelled is cut or overflows.
    /// As written, it costs a byte compare.
    package func spelled(_ string: String) -> String {
        TextTransliteration.spelled(string, as: textSpelling)
    }
}

extension EnvironmentValues {
    /// Has the words below spelled in ASCII, read as this environment's
    /// locale's language reads its script (``TextReading``): what a root does
    /// where the person set `TUI_PLAIN_TEXT=transliterate` — the app's render
    /// loop, a one-off render's, a headless app's — after the services that
    /// publish the locale.
    package mutating func spellTextInASCII() {
        textSpelling = .ascii(TextReading(languageCode: locale.language.languageCode?.identifier))
    }
}

extension BadgeValue {
    /// This badge with its words spelled as `spelling` says: a string badge in
    /// ASCII where asked, a number as it is. For the badges drawn without a
    /// ``Text`` — a tab's, a list row's — spelled where the badge is read, so
    /// its width and its drawing agree.
    package func spelled(as spelling: TextSpelling) -> BadgeValue {
        guard spelling.isASCII, case .string(let words?) = self else { return self }
        return .string(TextTransliteration.spelled(words, as: spelling))
    }
}

/// Other scripts spelled in Latin letters, and Latin letters spelled in ASCII.
///
/// In order:
/// 0. The key symbols, which no transform has letters for: `⌃Q` is `^Q`, and
///    the others are their names, `⌥F` `Alt-F` — see
///    ``KeyNotation/asciiSpelling(_:)``.
/// 1. Emoji become a short ASCII form: an emoticon where one is known (`🙂`
///    `:)`), else a name between colons (`🎉` `:party_popper:`) — see
///    ``EmojiSpelling``.
/// 2. Japanese is read as Japanese, on Darwin, where the text has kana in it or
///    the app's language is Japanese: `CFStringTokenizer`'s Latin
///    transcription, which knows kanji readings (`日本語` `nippon go`). ICU's
///    `Any-Latin` reads every Han character as Chinese.
/// 3. ICU's transliterators, which Foundation carries: Cyrillic by the BGN/PCGN
///    romanization of the app's language (Russian's unless it writes another),
///    Greek by UNGEGN's modern one, everything else `Any-Latin`, then
///    `Latin-ASCII`.
/// 4. The few letters `Latin-ASCII` keeps: Arabic's and Hebrew's `ʿ` and `ʾ`
///    become `'`; the BGN soft and hard sign marks `ʹ` and `ʺ` are dropped.
///
/// What none of these knows (box drawing, `✓`) comes back as it was, for the
/// folding at output to deal with in the cells it takes.
package enum TextTransliteration {
    /// `string` spelled as `spelling` says: as written, or in ASCII.
    @inline(__always)
    package static func spelled(_ string: String, as spelling: TextSpelling) -> String {
        guard case .ascii(let reading) = spelling else { return string }
        return transliterated(string, reading: reading)
    }

    /// `string` spelled in ASCII where it can be, read as `reading` says.
    ///
    /// A string that is ASCII already comes back without a look at the memo.
    package static func transliterated(_ string: String, reading: TextReading = .standard) -> String {
        guard string.utf8.contains(where: { $0 >= 0x80 }) else { return string }
        guard string.utf8.count <= Memo.longestKept else { return spelling(string, reading: reading) }
        let key = Memo.Key(string: string, reading: reading)
        if let kept = Memo.state.withLock({ $0.results[key] }) { return kept }
        // Spelled outside the lock: a transform takes tens of microseconds,
        // and two threads spelling the same string at once only waste one.
        let result = spelling(string, reading: reading)
        Memo.state.withLock { $0.keep(result, for: key) }
        return result
    }

    /// The transform itself, unmemoized: the steps in the type's
    /// discussion.
    ///
    /// `nil` from Foundation, which a platform without ICU's transliterators
    /// may answer, leaves the words as the steps before it left them, for the
    /// folding at output, which needs nothing but the standard library.
    static func spelling(_ string: String, reading: TextReading) -> String {
        var words = EmojiSpelling.spelled(KeyNotation.asciiSpelling(string))
        if JapaneseReading.applies(to: words, reading: reading) {
            words = JapaneseReading.romanized(words)
        }
        let transform = StringTransform(transformID(reading))
        let latin = words.applyingTransform(transform, reverse: false) ?? words
        return withoutMarks(latin)
    }

    /// The ICU transform for `reading`: its Cyrillic romanization, Greek's, and
    /// then every other script's.
    ///
    /// BGN/PCGN's romanizations, rather than the ISO 9 `Any-Latin` applies to
    /// Cyrillic, because they read as the words sound: `Имя` is `Imya`, where
    /// ISO 9 folded to ASCII made it `Ima`, and `Щука` `Shchuka`, not `Suka`.
    /// Each Cyrillic one touches only its own script's letters, so a string in
    /// several scripts passes through all of them. UNGEGN's Greek does not: it
    /// marks every `:` with a combining macron below (`ok :̱)`), so it is
    /// filtered to Greek letters (`[:Greek:]`, an element's own filter, with no
    /// space: a filter and a space before the first element filter the whole
    /// chain).
    static func transformID(_ reading: TextReading) -> String {
        let cyrillic: String
        switch reading {
        case .standard, .japanese: cyrillic = "Russian-Latin/BGN"
        case .ukrainian: cyrillic = "Ukrainian-Latin/BGN"
        case .belarusian: cyrillic = "Belarusian-Latin/BGN"
        case .bulgarian: cyrillic = "Bulgarian-Latin/BGN"
        case .macedonian: cyrillic = "Macedonian-Latin/BGN"
        case .serbian: cyrillic = "Serbian-Latin/BGN"
        }
        return cyrillic + "; [:Greek:]Greek-Latin/UNGEGN; Any-Latin; Latin-ASCII"
    }

    /// `latin` without the modifier letters `Latin-ASCII` keeps: Arabic's and
    /// Hebrew's ʿayin and ʾalif/hamza as an apostrophe, as ASCII romanizations
    /// write them, and BGN's soft and hard sign marks dropped, as the
    /// simplified form people type does (`obʺyëm` is `obyem`).
    static func withoutMarks(_ latin: String) -> String {
        guard latin.utf8.contains(where: { $0 >= 0x80 }) else { return latin }
        var scalars = String.UnicodeScalarView()
        for scalar in latin.unicodeScalars {
            switch scalar.value {
            case 0x02BE, 0x02BF: scalars.append("'")
            case 0x02B9, 0x02BA: continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// What has been spelled, so a frame that draws the same words as the last
    /// one doesn't ask ICU again.
    ///
    /// A static, and not a singleton in the sense of the project's "No
    /// Singletons" rule: a private, bounded memo of a pure function. The
    /// transform is fixed and ICU's data doesn't change while a process runs,
    /// so the string and the reading are everything the function reads, and
    /// nothing outside the memo can tell a hit from a miss. The same exemption
    /// as the ASCII palette's search index (`ASCIIPalette+SearchIndex.swift`).
    private enum Memo {
        /// A string and how it is read: `日本` is `ri ben` read as Chinese and
        /// `nippon` read as Japanese.
        struct Key: Hashable {
            let string: String
            let reading: TextReading
        }

        struct State {
            var results: [Key: String] = [:]
            var order: [Key] = []

            /// Keeps `result`, letting the oldest go once there are
            /// ``capacity``: first in, first out, as the palette's index does.
            mutating func keep(_ result: String, for key: Key) {
                guard results.updateValue(result, forKey: key) == nil else { return }
                order.append(key)
                if order.count > capacity {
                    results.removeValue(forKey: order.removeFirst())
                }
            }
        }

        static let state = Mutex(State())

        /// Enough for every distinct string on a busy page, several times
        /// over: a Stress scenario draws a few hundred.
        static let capacity = 2048

        /// A string longer than this, in UTF-8 bytes, is spelled every time and
        /// not kept, so the memo holds at most a few megabytes.
        static let longestKept = 1024
    }
}
