//  🖥️ TUI — A Terminal UI framework for Swift
//  TextSpelling.swift
//
//  How the words a view draws are spelled: as written, or in ASCII before they
//  are laid out (`TUI_PLAIN_TEXT=transliterate`, an experiment; see
//  `Documentation/Historical/Text, editing and the clipboard/ASCII transliteration before layout.md`).
//  The value lives here, beside `RenderContext`, so a context can carry it as a
//  field; the spelling itself is TUIFoundation's (`TextTransliteration`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// How the words a view draws are spelled.
///
/// One byte, so ``RenderContext`` carries it in padding it already had, and a
/// view asks it with a load and a compare rather than an environment lookup:
/// every `Text` asks it on every measure and render, where it is
/// ``asWritten`` but for the person who asked for ASCII.
package enum TextSpelling: Hashable, Sendable {
    /// As written: the default.
    case asWritten
    /// In ASCII, read as the app's language reads its own script where that
    /// matters (``TextReading``).
    case ascii(TextReading)

    /// Whether words are spelled in ASCII.
    @inlinable package var isASCII: Bool {
        if case .asWritten = self { return false }
        return true
    }
}

/// Which of the readings of a script that has several the ASCII spelling uses:
/// the app's language's, where it has one of its own.
///
/// Han is read as Chinese pinyin except for Japanese, whose kanji have their
/// own readings; Cyrillic by the BGN/PCGN romanization of the language that
/// writes it, since `и` is `i` in Russian and `y` in Ukrainian. Every other
/// language reads alike (``standard``). Text with kana in it is read as
/// Japanese whatever the app's language.
package enum TextReading: UInt8, Hashable, Sendable {
    /// Han as pinyin, Cyrillic as Russian.
    case standard
    /// Kanji as Japanese.
    case japanese
    /// Cyrillic as Ukrainian.
    case ukrainian
    /// Cyrillic as Belarusian.
    case belarusian
    /// Cyrillic as Bulgarian.
    case bulgarian
    /// Cyrillic as Macedonian.
    case macedonian
    /// Cyrillic as Serbian.
    case serbian

    /// The reading for a language, by its code (`ja`, `uk`): ``standard`` for
    /// every language that has none of its own, and for none.
    package init(languageCode: String?) {
        switch languageCode {
        case "ja": self = .japanese
        case "uk": self = .ukrainian
        case "be": self = .belarusian
        case "bg": self = .bulgarian
        case "mk": self = .macedonian
        case "sr": self = .serbian
        default: self = .standard
        }
    }
}

private struct TextSpellingKey: EnvironmentKey {
    // As written, and never read from the process environment: a key's default
    // must not depend on where a test runs. The render loop writes the user's
    // answer at the root.
    static let defaultValue = TextSpelling.asWritten
}

extension EnvironmentValues {
    /// How the words below are spelled: what a ``RenderContext`` made from
    /// this environment carries as its ``RenderContext/textSpelling``.
    ///
    /// Read only there, once, when a context is made from an environment: the
    /// render loop's root, a one-off render's, a toolbar's. A view asks its
    /// context. Package-only while the ASCII spelling is an experiment.
    package var textSpelling: TextSpelling {
        get { self[TextSpellingKey.self] }
        set { self[TextSpellingKey.self] = newValue }
    }
}
