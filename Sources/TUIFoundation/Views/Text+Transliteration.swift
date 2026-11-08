//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+Transliteration.swift
//
//  An experiment behind a flag (owner, 2026-11-08): for a terminal that can show
//  only ASCII, spell other scripts in Latin letters BEFORE layout, so "你好" is
//  "ni hao", six cells, and the layout makes room for it. The folding at output
//  (`PlainTerminalText` in TUIApp) has to keep each character to the cells it was
//  laid out in, which cuts "你好" to "niha". That folding stays, for what this
//  doesn't reach: chrome, text being edited, and anything drawn without `Text`.
//  `TUI_PLAIN_TEXT=transliterate` turns it on; see
//  `Documentation/Historical/Text, editing and the clipboard/ASCII transliteration before layout.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import TUICore

private struct TransliteratesTextKey: EnvironmentKey {
    // `false`, and not read from the process environment: a key's default
    // must not depend on where a test runs. The render loop writes the
    // user's answer at the root.
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether text is spelled in ASCII before it is laid out: `你好` as
    /// `ni hao`, `Привет` as `Privet`, `é` as `e`.
    ///
    /// `true` only where the user set `TUI_PLAIN_TEXT=transliterate` in the
    /// environment the app runs in; the render loop writes it at the root of
    /// every frame. Every ``Text`` measures and draws its words spelled this
    /// way, and so do the controls that draw a title of their own (a
    /// button's, a table's cells and headers, a panel's title). Text being
    /// edited keeps its own characters. Package-only while it is an
    /// experiment.
    package var transliteratesText: Bool {
        get { self[TransliteratesTextKey.self] }
        set { self[TransliteratesTextKey.self] = newValue }
    }
}

/// Other scripts spelled in Latin letters, and Latin letters spelled in ASCII:
/// ICU's `Any-Latin; Latin-ASCII`, which Foundation carries.
package enum TextTransliteration {
    /// `string` spelled in ASCII where ICU knows how, and as it was where it
    /// doesn't: an emoji, an arrow, a box-drawing line come back unchanged, for
    /// the folding at output to deal with in the cells they take.
    ///
    /// A string that is ASCII already comes back without a look at the memo.
    package static func transliterated(_ string: String) -> String {
        guard string.utf8.contains(where: { $0 >= 0x80 }) else { return string }
        guard string.utf8.count <= Memo.longestKept else { return spelled(string) }
        if let kept = Memo.state.withLock({ $0.results[string] }) { return kept }
        // Spelled outside the lock: a transform takes tens of microseconds,
        // and two threads spelling the same string at once only waste one.
        let result = spelled(string)
        Memo.state.withLock { $0.keep(result, for: string) }
        return result
    }

    /// `string` transliterated when `transliterates`, as it was otherwise: the
    /// one spelling every site uses, so none forgets the ASCII fast path.
    package static func transliterated(_ string: String, if transliterates: Bool) -> String {
        transliterates ? transliterated(string) : string
    }

    /// The transform itself. `nil` from Foundation, which a platform without
    /// ICU's transliterators may answer, leaves the string to the folding at
    /// output, which needs nothing but the standard library for accents.
    static func spelled(_ string: String) -> String {
        string.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? string
    }

    /// What has been spelled, so a frame that draws the same words as the last
    /// one doesn't ask ICU again.
    ///
    /// A static, and not a singleton in the sense of the project's "No
    /// Singletons" rule: a private, bounded memo of a pure function. The
    /// transform is fixed and ICU's data doesn't change while a process runs,
    /// so the string is everything the function reads, and nothing outside the
    /// memo can tell a hit from a miss. The same exemption as the ASCII
    /// palette's search index (`ASCIIPalette+SearchIndex.swift`).
    private enum Memo {
        struct State {
            var results: [String: String] = [:]
            var order: [String] = []

            /// Keeps `result`, letting the oldest go once there are
            /// ``capacity``: first in, first out, as the palette's index does.
            mutating func keep(_ result: String, for string: String) {
                guard results.updateValue(result, forKey: string) == nil else { return }
                order.append(string)
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
