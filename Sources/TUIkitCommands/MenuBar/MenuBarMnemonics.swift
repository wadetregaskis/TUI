//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBarMnemonics.swift
//
//  Which letter, held with Option, opens each of the menu bar's menus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// The letters that open the menu bar's menus with Option (Alt, where the
/// terminal sends Option as Meta): one per title, no two titles the same.
///
/// **The rule.** In bar order, each title takes its first ASCII letter that
/// no title before it has taken, and failing that the next unused letter of
/// its title, as Windows' access keys are chosen. A title with no letter left
/// — every letter of it taken, or none ASCII, as in a Japanese or Chinese
/// title — has none: F10 and the arrows reach it, as they reach every menu.
/// The app's menu has none: its title is the app's name, whose first letter
/// would take Edit's or File's, and F10 opens it, as the first menu.
///
/// **A focused text field.** It keeps the Option-letters it edits with
/// (Option-B and Option-F, back and forward a word; ``TextInputFocusHandler/editsWith(_:)``),
/// and a field is asked for a key before the bar's letters, which are
/// framework defaults (`KeyboardShortcutRegistry.registerDefault`). So while
/// one has the focus, a title whose letter it keeps takes its next letter not
/// taken and not kept instead — File's F becomes I in English — and every
/// other title keeps its own, so the letters move as little as they can.
///
/// **Other conflicts.** An app's own shortcut on an Option-letter chord wins
/// over the bar's letter, as every app shortcut wins over a framework default;
/// the title is then reached by F10 and the arrows. The letters are shown —
/// underlined — while Option is held, where the terminal reports a modifier
/// key held on its own (the kitty keyboard protocol); elsewhere they are not
/// shown (Terminal compatibility survey.md, "The menu bar's keys").
enum MenuBarMnemonics {
    /// Each title's letter, lowercased; `nil` for a title given as `nil` (the
    /// app's menu) and for one with no letter left.
    ///
    /// - Parameters:
    ///   - titles: The titles as drawn, in bar order.
    ///   - kept: The letters the focused view keeps, which no title takes.
    static func assign(_ titles: [String?], keeping kept: Set<Character> = []) -> [Character?] {
        let letters = titles.map { $0.map(candidates) ?? [] }
        var taken = Set<Character>()
        var chosen: [Character?] = letters.map { candidates in
            guard let letter = candidates.first(where: { !taken.contains($0) }) else { return nil }
            taken.insert(letter)
            return letter
        }
        guard !kept.isEmpty else { return chosen }
        for (index, letter) in chosen.enumerated() {
            guard let letter, kept.contains(letter) else { continue }
            let next = letters[index].first { !taken.contains($0) && !kept.contains($0) }
            chosen[index] = next
            if let next { taken.insert(next) }
        }
        return chosen
    }

    /// `title`'s ASCII letters, lowercased, each once, in order.
    static func candidates(_ title: String) -> [Character] {
        var seen = Set<Character>()
        var letters: [Character] = []
        for character in title where character.isASCII && character.isLetter {
            let letter = Character(character.lowercased())
            if seen.insert(letter).inserted { letters.append(letter) }
        }
        return letters
    }

    /// The letters `focused` keeps with Option: those it edits with, if it
    /// is a text control; none otherwise.
    @MainActor
    static func kept(by focused: Focusable?) -> Set<Character> {
        guard let input = focused as? any TextInputFocusHandler else { return [] }
        return Set(
            alphabet.filter { input.editsWith(KeyEvent(key: .character($0), alt: true)) })
    }

    /// `title` around the first appearance of `letter`, either case: what
    /// comes before it, it as drawn, and what comes after; `nil` if it is not
    /// there.
    static func split(_ title: String, at letter: Character) -> (before: String, letter: String, after: String)? {
        guard let index = title.firstIndex(where: { Character($0.lowercased()) == letter }) else { return nil }
        return (String(title[..<index]), String(title[index]), String(title[title.index(after: index)...]))
    }

    /// The letters a title can be given.
    private static let alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
}
