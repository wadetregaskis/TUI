//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledTableTwin.swift
//
//  The oracle the pulled-table tests compare against (SCROLL-FIT P3, P4 and
//  P6): the same table drawn whole, framed to its full height, with what
//  pinning changes put back. A pulled table pins its header to the scroll
//  view's top edge and its horizontal scrollbar to the bottom edge while its
//  rows are under them (design 2c); drawn whole, framed, it pins nothing. So
//  the pulled screen is its twin's with the header drawn over the top line
//  exactly when that line is one of the table's rows, and the bar over the
//  last on the same condition — the rule `PinnedSectionChromeTests` checks a
//  lazy stack's sections by.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What a pulled table's screen is, given its twin's.
enum PulledTableTwin {
    /// Whether `line` is one of the table's rows: inside its side borders, and
    /// not its header.
    static func isRow(_ line: String, header: String) -> Bool {
        line.drop { $0 == " " }.hasPrefix("│") && line != header
    }

    /// The twin's screen `whole` as the pulled table draws it: `header` over
    /// the top line when that line is a row, and `bar` (where the table has
    /// one) over the last when that is.
    static func pinned(_ whole: [String], header: String, bar: String? = nil) -> [String] {
        var screen = whole
        if let first = screen.first, isRow(first, header: header) { screen[0] = header }
        if let bar, let last = screen.last, isRow(last, header: header), last != bar {
            screen[screen.count - 1] = bar
        }
        return screen
    }

    /// Whether `pulled` is its twin's screen `whole` as the pulled table
    /// draws it — or, after a key moved the cursor up to a row the scroll
    /// view then revealed, that screen a line lower: a revealed row is kept
    /// clear of a pinned header (`PinnedChromeCover`), so it lands under the
    /// header rather than on the top line where the twin, pinning nothing,
    /// puts it, and the header is then drawn where it stands, just above it.
    static func matches(_ pulled: [String], _ whole: [String], header: String, bar: String? = nil) -> Bool {
        if pulled == pinned(whole, header: header, bar: bar) { return true }
        var lower = [header] + whole.dropLast()
        if let bar, let last = lower.last, isRow(last, header: header) { lower[lower.count - 1] = bar }
        return pulled == lower
    }
}
