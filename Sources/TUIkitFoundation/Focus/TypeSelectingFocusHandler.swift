//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeSelectingFocusHandler.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A focused control that finds its rows by typed characters (type select),
/// asked by the input handler whether a prefix is under way.
package protocol TypeSelectingFocusHandler: AnyObject {
    /// Whether characters typed now continue a prefix — one was typed less
    /// than the type-select timeout ago.
    var isTypeSelecting: Bool { get }
}

// MARK: - The typed prefix

/// What a control that finds its rows by typed characters has been typed:
/// the prefix, and when its last character came — a gap of a second starts a
/// new one, as macOS's type select forgets what was typed after about a
/// second.
///
/// One rule for every control that type-selects — a `List`, a `Table`
/// (TUIkitLists), a `Picker`'s drop-down, a pop-up menu — so each takes the
/// same characters and forgets them on the same clock.
package struct TypeSelectBuffer {
    /// The characters typed so far.
    package private(set) var prefix = ""

    /// When the last of them came.
    private var lastKey: ContinuousClock.Instant?

    /// How long a pause starts a new prefix.
    package static var timeout: Duration { .seconds(1) }

    package init() {}

    /// Whether characters typed now continue the prefix: one was typed less
    /// than ``timeout`` ago.
    package var isTypeSelecting: Bool {
        guard !prefix.isEmpty, let lastKey else { return false }
        return ContinuousClock.now - lastKey <= Self.timeout
    }

    /// Takes `event` into the prefix — starting a new one after a pause — if
    /// it is a character type select takes: any printable character but
    /// Space, with neither Control nor Option held.
    ///
    /// - Returns: Whether the key was taken.
    package mutating func take(_ event: KeyEvent) -> Bool {
        guard case .character(let character) = event.key, !event.ctrl, !event.alt,
            character != " ", !character.isNewline,
            character.unicodeScalars.allSatisfy({ !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 })
        else { return false }
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
