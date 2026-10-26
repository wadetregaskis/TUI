//  🖥️ TUI — A Terminal UI framework for Swift
//  TypeSelectingFocusHandler.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// A focused control that finds its rows by typed characters (type select).
///
/// Where one holds the focus, it takes every character type select takes
/// (``TypeSelectBuffer/takes(_:)``), whether or not a row answers to it, and
/// no bare-key binding hears one: not the status bar's items, an app's bare
/// `.keyboardShortcut`, nor TUI's own quit, theme, appearance and help keys
/// (the owner's ruling B77-KEYTIME, 2026-10-23). The status bar leaves out
/// the items it would advertise for them meanwhile
/// (``StatusBarState/currentItems``).
package protocol TypeSelectingFocusHandler: AnyObject {
    /// Whether it takes typed characters now: a list's or table's always, a
    /// `Picker`'s only while its drop-down is open.
    var takesTypedCharacters: Bool { get }
}

/// The type select of something that holds the keyboard WITHOUT holding the
/// focus — an open pop-up menu, whose rows report to its highlight rather than
/// to the focus ring — published for the frame on the key dispatcher
/// (``KeyEventDispatcher/setTypeSelectTarget(_:sectionID:)``), where the input
/// handler asks it as it asks a focused ``TypeSelectingFocusHandler``: it takes
/// every character type select takes.
///
/// A closure, as a key handler is one: made where the menu draws, and called
/// by the input handler, between frames, on the same thread.
package struct TypeSelectTarget {
    /// Takes a key for type select, if it is a character it takes, moving the
    /// highlight to the row the prefix names; answers whether it was taken —
    /// whether or not a row matched.
    package let typeSelect: (KeyEvent) -> Bool

    package init(typeSelect: @escaping (KeyEvent) -> Bool) {
        self.typeSelect = typeSelect
    }
}

// MARK: - The typed prefix

/// What a control that finds its rows by typed characters has been typed:
/// the prefix, and when its last character came — a gap of a second starts a
/// new one, as macOS's type select forgets what was typed after about a
/// second.
///
/// One rule for every control that type-selects — a `List`, a `Table`
/// (TUILists), a `Picker`'s drop-down, a pop-up menu — so each takes the
/// same characters and forgets them on the same clock.
package struct TypeSelectBuffer {
    /// The characters typed so far.
    package private(set) var prefix = ""

    /// When the last of them came.
    private var lastKey: ContinuousClock.Instant?

    /// How long a pause starts a new prefix.
    package static var timeout: Duration { .seconds(1) }

    package init() {}

    /// Forgets what was typed: the next character starts a new prefix.
    package mutating func reset() {
        prefix = ""
        lastKey = nil
    }

    /// Whether type select takes `event`: any printable character but Space,
    /// with no Control, Option or ⌘ held.
    package static func takes(_ event: KeyEvent) -> Bool {
        guard case .character(let character) = event.key, !event.ctrl, !event.alt, !event.command,
            character != " ", !character.isNewline
        else { return false }
        return character.unicodeScalars.allSatisfy { !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 }
    }

    /// Takes `event` into the prefix — starting a new one after a pause — if
    /// it is a character type select takes (``takes(_:)``).
    ///
    /// - Returns: Whether the key was taken.
    package mutating func take(_ event: KeyEvent) -> Bool {
        guard Self.takes(event), case .character(let character) = event.key else { return false }
        let now = ContinuousClock.now
        if let lastKey, now - lastKey > Self.timeout { prefix = "" }
        lastKey = now
        prefix.append(character)
        return true
    }

    /// The text a menu row or a drop-down option is found by, from its drawn
    /// line: what is written there from its first letter or digit — so not
    /// the space before it, nor a mark or an icon drawn ahead of the title
    /// (a toggle row's `[■]`, a picker option's ✓, an SF Symbol's glyph), as
    /// a desktop menu's type select matches an item's title.
    package static func title(ofDrawn line: String) -> String {
        let plain = line.stripped
        guard let start = plain.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return "" }
        return String(plain[start...])
    }

    /// The row `prefix` names among `count` rows: the first, starting at
    /// `current` for a prefix of more than one character (still typing the
    /// same name) and after it for a first character (the next match),
    /// wrapping round, whose text starts with the prefix — ignoring case.
    /// `nil` when none does.
    ///
    /// - Parameters:
    ///   - current: The row the cursor or highlight is on, or `nil` for none
    ///     (a first character then starts at the top).
    ///   - text: A row's type-select text, or `nil` for a row type select
    ///     passes over.
    package static func match(
        _ prefix: String, count: Int, current: Int?, text: (Int) -> String?
    ) -> Int? {
        guard count > 0, !prefix.isEmpty else { return nil }
        let wanted = prefix.lowercased()
        let start = current.map { prefix.count > 1 ? $0 : $0 + 1 } ?? 0
        for step in 0..<count {
            let index = (start + step) % count
            guard let rowText = text(index), !rowText.isEmpty else { continue }
            if rowText.lowercased().hasPrefix(wanted) { return index }
        }
        return nil
    }
}
