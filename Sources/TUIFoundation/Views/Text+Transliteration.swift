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
    ///
    /// Its escape sequences and bare control characters are removed first,
    /// unless ``View/textKeepsEscapeSequences(_:)`` is in force here: see
    /// ``TextTransliteration/spelled(_:as:keepingEscapes:)``. As written, a
    /// string with none costs a byte scan.
    package func spelled(_ string: String) -> String {
        TextTransliteration.spelled(string, as: textSpelling, keepingEscapes: environment.textKeepsEscapeSequences)
    }
}

extension EnvironmentValues {
    /// Has the words below spelled in ASCII, read as this environment's
    /// locale's language reads its script (``TextReading``): what a root does
    /// where the person set `TUI_PLAIN_TEXT=transliterate` — the app's render
    /// loop, a one-off render's, a headless app's — after the services that
    /// publish the locale.
    ///
    /// And no emoji chrome (``supportsEmojiChrome``), so a control that draws
    /// an emoji only where the terminal shows them legibly — the search
    /// field's magnifier — draws what it draws elsewhere: in ASCII the
    /// magnifier was `:right_pointing_magnifying_glass:`.
    package mutating func spellTextInASCII() {
        textSpelling = .ascii(TextReading(languageCode: locale.language.languageCode?.identifier))
        supportsEmojiChrome = false
    }

    /// Has the key symbols below spelled in ASCII and nothing else
    /// (``TextSpelling/asciiKeys``): what a root does for a terminal that
    /// shows only ASCII where the person did not ask for the transliteration,
    /// so `⌥F` is `Alt-F` rather than a blank and an `F`. No emoji chrome
    /// either, as for ``spellTextInASCII()``.
    package mutating func spellKeysInASCII() {
        textSpelling = .asciiKeys
        supportsEmojiChrome = false
    }
}

// MARK: - What a Text draws

@MainActor extension Text {
    /// The string this text will actually DRAW: its escape sequences and bare
    /// control characters removed unless `keepingEscapes` says otherwise
    /// (``View/textKeepsEscapeSequences(_:)``), spelled as the context says
    /// (``RenderContext/textSpelling``: in ASCII, where asked), cased, then
    /// redacted. Transliterated first, so `.uppercase` has letters to
    /// raise: `你好` is `NI HAO`, not `ni hao`.
    ///
    /// Every site that needs the drawn string goes through here — the measure,
    /// the render, and the per-run walk of a concatenation — so a redaction can
    /// never change the width the measure reserved. Measuring the written
    /// string while drawing a transformed one is the measure/render parity bug
    /// class; `.textCase` was already routed this way for exactly that reason
    /// (ß → SS changes the width), and redaction joins it.
    ///
    /// The redaction is the caller's read of
    /// `EnvironmentValues.effectiveRedactionReasons` rather than a read made
    /// here: the render draws its content AND every run of a concatenation,
    /// and a read per string was an environment lookup each time (two under
    /// `.privacy`) for the same answer.
    ///
    /// `keepingEscapes` is asked only of a string that holds something to
    /// remove, so the environment read it stands for is skipped for virtually
    /// every string.
    static func displayString(
        _ string: String, textCase: TextCase?, redaction: RedactionReasons, spelling: TextSpelling,
        keepingEscapes: @autoclosure () -> Bool
    ) -> String {
        redaction.redacting(
            applyingCase(
                textCase, to: TextTransliteration.spelled(string, as: spelling, keepingEscapes: keepingEscapes())))
    }

    /// ``displayString(_:textCase:redaction:spelling:keepingEscapes:)`` with
    /// the spelling and the escape sequences as `context` says: what a `Text`
    /// draws in a context, its redaction read by the caller once for all its
    /// runs.
    static func displayString(
        _ string: String, textCase: TextCase?, redaction: RedactionReasons, context: RenderContext
    ) -> String {
        displayString(
            string, textCase: textCase, redaction: redaction, spelling: context.textSpelling,
            keepingEscapes: context.environment.textKeepsEscapeSequences)
    }
}

extension BadgeValue {
    /// This badge with its words spelled as `spelling` says: a string badge in
    /// ASCII where asked, a number as it is. For the badges drawn without a
    /// ``Text`` — a tab's, a list row's — spelled where the badge is read, so
    /// its width and its drawing agree. Its escape sequences go as a `Text`'s
    /// do (``TextTransliteration/spelled(_:as:keepingEscapes:)``).
    package func spelled(as spelling: TextSpelling, keepingEscapes: @autoclosure () -> Bool) -> BadgeValue {
        guard case .string(let words?) = self, spelling.isASCII || words.mayHoldTerminalControls else { return self }
        return .string(TextTransliteration.spelled(words, as: spelling, keepingEscapes: keepingEscapes()))
    }

    /// Whether this is a string badge holding something
    /// ``spelled(as:keepingEscapes:)`` would remove
    /// (`String.mayHoldTerminalControls`).
    package var mayHoldTerminalControls: Bool {
        guard case .string(let words?) = self else { return false }
        return words.mayHoldTerminalControls
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
/// 5. What is left that has an ASCII form (``GlyphSpelling``): an SF Symbol as
///    its name, `:gearshape:`; the framework's shapes as
///    `TerminalSymbols.ASCII` writes them, `▶` `>`; an emoji that is text by
///    default, `❤` `<3`.
///
/// What none of these knows comes back as it was, for the folding at output to
/// deal with in the cells it takes.
package enum TextTransliteration {
    /// `string` spelled as `spelling` says: as written, its key symbols in
    /// ASCII, or all of it in ASCII; and first, unless `keepingEscapes`, its
    /// escape sequences and bare control characters removed
    /// (`String.sanitizedForTerminal`).
    ///
    /// The one place a view's words lose them (the owner's ruling TEXT-ESC,
    /// 2026-11-10): every view that draws a string goes through here — a
    /// ``Text`` by `displayString`, the rest by ``RenderContext/spelled(_:)``
    /// — so a string from outside the app cannot write the clipboard (OSC 52),
    /// set the window's title or change colours, whichever view shows it.
    /// Text being edited is not spelled, and shows each control character as
    /// `U+FFFD` instead (`TextFieldHandler.displayCharacter`).
    ///
    /// `keepingEscapes` is ``View/textKeepsEscapeSequences(_:)``'s answer, by
    /// default `false`: a caller with no environment to ask removes them, which
    /// is never the unsafe answer. It is asked only where the string holds
    /// something to remove (`String.mayHoldTerminalControls`, a byte scan), so
    /// the environment read it stands for is made for almost no string.
    /// Removed before the spelling, so the transforms never see a sequence.
    @inline(__always)
    package static func spelled(
        _ string: String, as spelling: TextSpelling, keepingEscapes: @autoclosure () -> Bool = false
    ) -> String {
        let string = string.mayHoldTerminalControls && !keepingEscapes() ? string.sanitizedForTerminal : string
        switch spelling {
        case .asWritten: return string
        case .asciiKeys: return KeyNotation.asciiSpelling(string)
        case .ascii(let reading): return transliterated(string, reading: reading)
        }
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
        return GlyphSpelling.spelled(withoutMarks(latin))
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
