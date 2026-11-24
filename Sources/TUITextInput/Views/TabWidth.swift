//  🖥️ TUI — A Terminal UI framework for Swift
//  TabWidth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - TabWidth

/// How a literal tab character advances the column in text-editing views
/// (``TextEditor``).
///
/// The macOS text system lays tabs out against *tab stops* — positions a tab
/// advances to (`NSParagraphStyle.tabStops`, falling back to
/// `defaultTabInterval`) — so a tab's visual width varies with where it
/// starts. ``periodic(_:)`` is that behaviour on the terminal's character
/// grid, and matches how terminals themselves (8-column stops), `vim`'s
/// `tabstop`, and code editors' "tab width" settings all treat tabs.
/// ``fixed(_:)`` instead always advances the same number of cells, for the
/// rare layout where tabs are just wide spaces.
///
/// Set it for a subtree with ``View/tabWidth(_:)``; the default is
/// `.periodic(4)`.
public enum TabWidth: Sendable, Equatable, Hashable {
    /// A tab advances to the next multiple of `interval` columns — proper tab
    /// *stops*. A tab starting exactly on a stop advances a full interval
    /// (there is always at least one cell, so adjacent columns never merge).
    case periodic(_ interval: Int)

    /// A tab always advances exactly `cells` columns, regardless of where it
    /// starts.
    case fixed(_ cells: Int)

    /// The display column immediately after a tab that begins at `column`.
    /// Intervals/cells are clamped to at least 1 so a degenerate value can't
    /// stall the layout walk.
    func advance(from column: Int) -> Int {
        switch self {
        case .periodic(let interval):
            let interval = max(1, interval)
            return ((column / interval) + 1) * interval
        case .fixed(let cells):
            return column + max(1, cells)
        }
    }
}

// MARK: - TabLayout

/// Character-index ↔ display-column arithmetic for a line that may contain
/// tabs or multi-cell characters (emoji, CJK), shared by ``TextEditor``'s
/// renderer (caret and selection placement, click mapping, the row walk) and
/// ``TextEditorHandler`` (vertical motion's visual-column preservation) so
/// the two can never disagree about where a character puts the columns after
/// it.
///
/// The editor's model stays character-indexed — these helpers translate at
/// the display boundary only, in terminal CELLS: a tab advances to its stop,
/// and a wide character advances by its real cell width. Plain lines (no tab,
/// every character one cell) take an O(1) fast path, so ASCII editing pays
/// nothing.
enum TabLayout {
    /// Told how many characters a walk stepped over to find their cells,
    /// once a walk, while a task binds it: the test seam that counts what a
    /// sideways editor's frame costs against the length of its lines (H-88),
    /// as `EditorLayout.buildReporter` counts layouts. Told by the walk, not
    /// by each step, so a walk asks the task for it once.
    @TaskLocal static var walkReporter: TaskLocalReporter<Int>?

    /// Tells ``walkReporter`` that a walk stepped over `steps` characters.
    static func reportWalk(_ steps: Int) {
        walkReporter?(steps)
    }

    /// Whether every character in `chars` occupies exactly one display cell
    /// (no tabs, no wide characters) — the fast-path predicate under which
    /// character index and display column coincide.
    private static func isPlain(_ chars: TextCharacters) -> Bool {
        if chars.isPrintableASCII { return true }
        var scanned = 0
        defer { reportWalk(scanned) }
        return !chars.contains {
            scanned += 1
            return $0 == "\t" || $0.terminalWidth != 1
        }
    }

    /// The display column after `character` when it begins at `column`: the
    /// next tab stop for a tab, `column` + the character's cell width
    /// otherwise, floored at one cell so a zero-width oddity can't stall a
    /// layout walk. That cell is DRAWN: a character with no width of its own
    /// is written as a one-cell stand-in (`TextFieldHandler.displayCharacter`),
    /// so the cells counted here are the cells the row takes (H-48).
    static func advance(from column: Int, over character: Character, tabWidth: TabWidth) -> Int {
        character == "\t"
            ? tabWidth.advance(from: column)
            : column + max(1, character.terminalWidth)
    }

    /// `advance(from:over:tabWidth:)` over the character `byte` is, an
    /// ASCII one: the next stop for a tab, else one cell, since every other
    /// ASCII character — a control character's 0 floored — is one. Told from
    /// the byte, without the character's comparison and width lookup, which
    /// were most of what a row of ASCII cost to draw and to wrap (EDMEM-2).
    static func advance(from column: Int, overASCII byte: UInt8, tabWidth: TabWidth) -> Int {
        byte == 0x09 ? tabWidth.advance(from: column) : column + 1
    }

    /// `advance(from:over:tabWidth:)` over the character at `index` of
    /// `line`: told from its byte where it is one ASCII byte, as a row's
    /// drawing tells it (`_TextEditorCore.glyph(at:of:column:tabWidth:)`).
    static func advance(from column: Int, at index: Int, of line: TextCharacters, tabWidth: TabWidth) -> Int {
        if let byte = line.asciiByte(at: index) { return advance(from: column, overASCII: byte, tabWidth: tabWidth) }
        return advance(from: column, over: line[index], tabWidth: tabWidth)
    }

    /// The display column at which the character at `charIndex` begins
    /// (`charIndex == chars.count` gives the line's total display width).
    static func displayColumn(
        ofCharIndex charIndex: Int, in chars: TextCharacters, tabWidth: TabWidth
    ) -> Int {
        guard !isPlain(chars) else { return min(charIndex, chars.count) }
        var column = 0
        for index in 0..<min(charIndex, chars.count) {
            column = advance(from: column, over: chars[index], tabWidth: tabWidth)
        }
        reportWalk(min(charIndex, chars.count))
        return column
    }

    /// The character index containing display column `displayColumn` — any
    /// column within a character's span (a tab's stop run, a wide character's
    /// cells) maps to that character. Columns at or past the end of the line
    /// map to the end-of-line insertion point (`chars.count`), matching a
    /// click beyond the last character.
    static func charIndex(
        forDisplayColumn displayColumn: Int, in chars: TextCharacters, tabWidth: TabWidth
    ) -> Int {
        guard !isPlain(chars) else { return min(max(0, displayColumn), chars.count) }
        var column = 0
        for (index, character) in chars.enumerated() {
            let next = advance(from: column, over: character, tabWidth: tabWidth)
            if displayColumn < next {
                reportWalk(index + 1)
                return index
            }
            column = next
        }
        reportWalk(chars.count)
        return chars.count
    }
}

// MARK: - Environment

private struct TabWidthKey: EnvironmentKey {
    static let defaultValue: TabWidth = .periodic(4)
}

extension EnvironmentValues {
    /// How literal tab characters advance the column in text-editing views.
    public var tabWidth: TabWidth {
        get { self[TabWidthKey.self] }
        set { self[TabWidthKey.self] = newValue }
    }
}

extension View {
    /// Sets how literal tab characters are laid out in text-editing views in
    /// this view's subtree (``TextEditor``): snapped to periodic column stops
    /// (`.periodic(4)`, the default — the text-system/terminal behaviour) or
    /// a constant advance (`.fixed(n)`).
    ///
    /// TUI-specific: SwiftUI's `TextEditor` exposes no tab-stop control (the
    /// underlying text system does, via `NSParagraphStyle`, but not through
    /// SwiftUI), so this is kept separate from the SwiftUI-parity surface.
    nonisolated public func tabWidth(_ width: TabWidth) -> some View {
        environment(\.tabWidth, width)
    }
}
