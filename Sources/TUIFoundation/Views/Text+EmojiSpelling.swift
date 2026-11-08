//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+EmojiSpelling.swift
//
//  Emoji spelled in ASCII when text is (`TUI_PLAIN_TEXT=transliterate`): ICU
//  has nothing to say about them, so they fell through to the folding at
//  output, which can only put two cells of placeholder where one was.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Emoji as short ASCII: an emoticon where a well-known one exists, else a name
/// between colons, as chat apps and GitHub write them.
///
/// - The faces and hearts people type as emoticons are those: `🙂` `:)`,
///   `😂` `:'D`, `❤️` `<3`, `👍` `:+1:`.
/// - A few common ones whose Unicode name is long or odd have a shorter one:
///   `🎉` `:tada:`, `✅` `:check:`.
/// - Every other emoji is its Unicode name, lowercased, with `_` for spaces and
///   without a trailing "sign": `🚀` `:rocket:`, `🦋` `:butterfly:`. The
///   standard library carries the names, so this needs no ICU.
/// - A flag is its region's code, `🇯🇵` `[JP]`; a keycap its key, `1️⃣` `[1]`.
/// - Skin tones and the emoji presentation selector are dropped; a sequence
///   joined with zero-width joiners names each part, `:man_woman_girl:`.
///
/// An emoji is a character drawn as an emoji by default, or by the selector
/// asking for it: `©` and `™`, text by default, are left for `Latin-ASCII`,
/// which knows them (`(C)`, `TM`).
enum EmojiSpelling {
    /// `string` with each emoji spelled; the same string where it has none.
    static func spelled(_ string: String) -> String {
        guard string.unicodeScalars.contains(where: mayStartEmoji) else { return string }
        var spelled = ""
        for character in string {
            if let ascii = spelling(of: character) {
                spelled += ascii
            } else {
                spelled.append(character)
            }
        }
        return spelled
    }

    /// A cheap first look: whether `scalar` could begin an emoji at all.
    private static func mayStartEmoji(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x20E3 || (scalar.value >= 0xA9 && scalar.properties.isEmoji)
    }

    /// `character` spelled, or `nil` when it isn't an emoji.
    static func spelling(of character: Character) -> String? {
        let scalars = Array(character.unicodeScalars)
        guard let first = scalars.first else { return nil }
        // A keycap: the key, a digit or `#` or `*`, the selector, then U+20E3.
        if first.isASCII {
            return scalars.contains("\u{20E3}") ? "[\(Character(first))]" : nil
        }
        if let flag = flagSpelling(scalars) { return flag }
        let isEmoji =
            first.properties.isEmojiPresentation
            || (first.properties.isEmoji && scalars.contains("\u{FE0F}"))
        guard isEmoji else { return nil }
        // The base, without what only changes how it looks.
        let base = scalars.filter { !isPresentationOnly($0) }
        if let short = shortForms[String(String.UnicodeScalarView(base))] { return short }
        let parts = base.split(separator: "\u{200D}").compactMap { $0.first.flatMap(name(of:)) }
        guard !parts.isEmpty else { return nil }
        return ":" + parts.joined(separator: "_") + ":"
    }

    /// A pair of regional indicators as the region's code: `🇯🇵` `[JP]`.
    private static func flagSpelling(_ scalars: [Unicode.Scalar]) -> String? {
        let letters = scalars.compactMap { scalar -> Character? in
            guard (0x1F1E6...0x1F1FF).contains(scalar.value) else { return nil }
            return Unicode.Scalar(scalar.value - 0x1F1E6 + 0x41).map(Character.init)
        }
        guard !letters.isEmpty, letters.count == scalars.count else { return nil }
        return "[" + String(letters) + "]"
    }

    /// The selectors and the skin-tone modifiers: they change how an emoji
    /// looks, not what it is.
    private static func isPresentationOnly(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0xFE0F || scalar.value == 0xFE0E || (0x1F3FB...0x1F3FF).contains(scalar.value)
    }

    /// The scalar's Unicode name as a short name: lowercased, `_` for spaces
    /// and hyphens, without a trailing "sign" or "symbol".
    private static func name(of scalar: Unicode.Scalar) -> String? {
        guard var name = scalar.properties.name else { return nil }
        for suffix in [" SIGN", " SYMBOL"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return String(name.lowercased().map { $0 == " " || $0 == "-" ? "_" : $0 })
    }

    /// The emoji people use most, spelled shorter than their names: the
    /// emoticons people type for the faces and hearts, and shorter names where
    /// the Unicode name is long (`FACE WITH TEARS OF JOY`) or misleads
    /// (`HEAVY BLACK HEART` is red). Keyed by the emoji without its selector or
    /// skin tone.
    private static let shortForms: [String: String] = [
        "🙂": ":)", "😊": ":)", "☺": ":)", "😀": ":D", "😃": ":D", "😄": ":D", "😁": ":D",
        "😆": "XD", "😂": ":'D", "🤣": ":'D", "😉": ";)", "😛": ":P", "😜": ";P", "😝": "XP",
        "🙁": ":(", "☹": ":(", "😞": ":(", "😔": ":(", "😢": ":'(", "😭": ":'(",
        "😮": ":O", "😲": ":O", "😯": ":o", "😐": ":|", "😑": "-_-", "😕": ":/", "😒": ":/",
        "😍": ":heart_eyes:", "😘": ":*", "😗": ":*", "😎": "B)", "😇": "O:)", "😈": ">:)", "😠": ">:(",
        "😡": ">:(", "🙃": "(:", "😅": "^_^;", "😬": ":S", "😱": "D:", "🤔": ":thinking:",
        "❤": "<3", "♥": "<3", "💔": "</3", "💕": "<3<3", "💖": "<3", "💗": "<3", "💙": "<3",
        "💚": "<3", "💛": "<3", "💜": "<3", "🖤": "<3", "🧡": "<3", "🤍": "<3",
        "👍": ":+1:", "👎": ":-1:", "👏": ":clap:", "🙏": ":pray:", "👋": ":wave:", "👌": ":ok:",
        "🎉": ":tada:", "🎊": ":tada:", "✅": ":check:", "✔": ":check:", "☑": ":check:",
        "❌": ":x:", "❎": ":x:", "⚠": ":warning:", "❗": ":!:", "❓": ":?:", "‼": ":!!:",
        "⭐": ":star:", "🌟": ":star:", "✨": ":sparkles:", "💯": ":100:", "🔥": ":fire:",
        "💡": ":idea:", "🐛": ":bug:", "🚀": ":rocket:", "👀": ":eyes:", "💩": ":poop:",
    ]
}
