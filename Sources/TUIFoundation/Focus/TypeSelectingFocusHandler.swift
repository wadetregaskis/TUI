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
    /// `Picker`'s only while its drop-down is open — and neither where
    /// `.typeSelectDisabled()` turned type select off (``TypeSelectBuffer/isEnabled``).
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

    /// When the last of them came, on ``clock``.
    private var lastKey: UInt64?

    /// How long a pause starts a new prefix — a second — in the nanoseconds
    /// ``clock`` reads.
    private static let timeoutNanos: UInt64 = 1_000_000_000

    /// The clock the pause is measured on, in nanoseconds: the one input
    /// arrives on (``EnvironmentValues/eventClock``), set where the control
    /// is drawn (``sync(with:)``). In a running app that is the monotonic
    /// clock; a `TestApp`'s moves only as the test moves it, so a test's
    /// `advance(by:)` between two characters is the pause that parts them.
    /// It read the machine's clock until then, which a test could not move.
    private var clock: () -> UInt64 = { MonotonicClock.nowNanoseconds }

    /// Whether type select is on where the control is drawn
    /// (``EnvironmentValues/isTypeSelectEnabled``, `.typeSelectDisabled(_:)`):
    /// set by the control's render, for event time. Off, ``take(_:)`` takes
    /// nothing, so a typed character goes on to the next handler, and the
    /// control does not hold typed keys (``TypeSelectingFocusHandler``).
    /// Turning it off forgets what was typed.
    package var isEnabled = true {
        didSet { if !isEnabled { reset() } }
    }

    package init() {}

    /// Takes what the environment where the control is drawn says of type
    /// select: whether it is on, and the clock a pause is measured on.
    package mutating func sync(with environment: EnvironmentValues) {
        isEnabled = environment.isTypeSelectEnabled
        clock = environment.eventClock ?? { MonotonicClock.nowNanoseconds }
    }

    /// Forgets what was typed: the next character starts a new prefix.
    package mutating func reset() {
        prefix = ""
        lastKey = nil
    }

    /// Whether type select takes `event`: any printable character but Space,
    /// with no Control, Option or ⌘ held — nor one Option composed (`ƒ` for
    /// ⌥F, `KeyEvent.optionComposedKey`), which is the Option chord's to take
    /// where the terminal does not send Option as Alt.
    package static func takes(_ event: KeyEvent) -> Bool {
        guard case .character(let character) = event.key, !event.ctrl, !event.alt, !event.command,
            event.optionComposedKey == nil,
            character != " ", !character.isNewline
        else { return false }
        return character.unicodeScalars.allSatisfy { !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 }
    }

    /// Takes `event` into the prefix — starting a new one after a pause — if
    /// it is a character type select takes (``takes(_:)``) and type select is
    /// on (``isEnabled``).
    ///
    /// - Returns: Whether the key was taken.
    package mutating func take(_ event: KeyEvent) -> Bool {
        guard isEnabled, Self.takes(event), case .character(let character) = event.key else { return false }
        let now = clock()
        if let lastKey, now &- lastKey > Self.timeoutNanos { prefix = "" }
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
