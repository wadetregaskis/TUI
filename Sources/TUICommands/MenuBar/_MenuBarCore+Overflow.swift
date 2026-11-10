//  🖥️ TUI — A Terminal UI framework for Swift
//  _MenuBarCore+Overflow.swift
//
//  A menu bar wider than the terminal: the row scrolls to keep the title the
//  keyboard or an open menu lights in view, with « and » where titles are
//  hidden.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _MenuBarCore {
    /// Which titles the row shows, where they are wider together than the
    /// row: from the start with every menu closed, and otherwise from the
    /// first title that keeps the lit one — the open menu's, or the bar
    /// mode's highlight — whole in view. A « in the first column says titles
    /// are hidden before the row, a » in the last that titles follow it; a
    /// press on either opens the hidden title beside it.
    ///
    /// Scrolling, rather than a » that opens the hidden titles as a menu of
    /// their own: the menu engine walks the titles by their places — ← and →
    /// step along them, F10's bar mode highlights them, ⌥ and a letter opens
    /// one — and every one of those already reaches a hidden title. The row
    /// only has to show where the keyboard went, so no key changes meaning,
    /// and the open menu hangs from its own title as it always does. A menu
    /// of menus would have needed submenus the bar's titles don't have, and
    /// a second way through them.
    ///
    /// Titles are never cut in two at the row's end while « or » can say what
    /// is hidden instead. A title cut there is one that cannot fit: the lit
    /// title wider than the row, drawn from its start with no « or », or,
    /// with nothing lit, the first title where it alone is wider. Below
    /// ``indicatorMinimumWidth`` columns there is no room for « or » beside
    /// any of a title.
    struct TitleScroll: Equatable {
        /// The first title shown.
        let first: Int

        /// One past the last title shown.
        let end: Int

        /// Whether the last title shown is cut at the row's end.
        let clipsLast: Bool

        /// Whether « is drawn in the first column.
        let leading: Bool

        /// Whether » is drawn in the last column.
        let trailing: Bool
    }
}

extension _MenuBarCore.TitleScroll {
    /// The narrowest row « and » are drawn in.
    static let indicatorMinimumWidth = 3

    /// The titles shown of those `widths` wide in a row `width` columns wide,
    /// keeping title `lit` in view.
    init(widths: [Int], lit: Int?, width: Int) {
        let count = widths.count
        guard count > 0, width > 0, widths.reduce(0, +) > width else {
            self.init(first: 0, end: count, clipsLast: false, leading: false, trailing: false)
            return
        }
        guard let lit = lit.map({ min(max($0, 0), count - 1) }) else {
            self = Self.laid(widths, from: 0, width: width, lit: nil)
            return
        }
        // From the start, the first that shows the lit title: at worst the
        // lit title first, which always does.
        for first in 0..<lit {
            let candidate = Self.laid(widths, from: first, width: width, lit: lit)
            if lit < candidate.end { self = candidate; return }
        }
        self = Self.laid(widths, from: lit, width: width, lit: lit)
    }

    /// The titles from `first` that fit whole, leaving a column for « where
    /// a title is before them and one for » where a title follows; or, where
    /// not even the first fits, that title cut.
    private static func laid(_ widths: [Int], from first: Int, width: Int, lit: Int?) -> Self {
        let count = widths.count
        let indicators = width >= indicatorMinimumWidth
        let leading = indicators && first > 0
        let room = width - (leading ? 1 : 0)
        var end = first
        var used = 0
        while end < count {
            let reserve = indicators && end + 1 < count ? 1 : 0
            guard used + widths[end] + reserve <= room else { break }
            used += widths[end]
            end += 1
        }
        if end > first {
            return Self(first: first, end: end, clipsLast: false, leading: leading, trailing: indicators && end < count)
        }
        // The lit title alone: as much of it as the whole row holds.
        if first == lit {
            return Self(first: first, end: first + 1, clipsLast: widths[first] > width, leading: false, trailing: false)
        }
        let trailing = indicators && first + 1 < count && room >= 2
        return Self(first: first, end: first + 1, clipsLast: true, leading: leading, trailing: trailing)
    }
}

extension _MenuBarCore {
    /// The row of `drawn` titles, scrolled to keep title `lit` in view in a
    /// row `width` columns wide (``TitleScroll``). A title not shown has a
    /// width of 0, and no region for the pointer.
    func laidOut(
        _ drawn: [String], lit: Int?, width: Int, mnemonics: [Character?], names: [String]
    ) -> TitleRow {
        let natural = drawn.map(\.strippedLength)
        let scroll = TitleScroll(widths: natural, lit: lit, width: width)
        var line = scroll.leading ? "«" : ""
        var columns = Array(repeating: 0, count: drawn.count)
        var widths = Array(repeating: 0, count: drawn.count)
        for index in scroll.first..<scroll.end {
            var title = drawn[index]
            var cells = natural[index]
            if scroll.clipsLast, index == scroll.end - 1 {
                let room = width - (scroll.trailing ? 1 : 0) - line.strippedLength
                let clipped = title.ansiAwarePrefixWithWidth(visibleCount: room)
                // The cut drops the title's own reset with its end.
                title = clipped.prefix + ANSIRenderer.reset
                cells = clipped.visibleWidth
            }
            columns[index] = line.strippedLength
            widths[index] = cells
            line += title
        }
        var indicators: [TitleRow.Indicator] = []
        if scroll.leading { indicators.append(TitleRow.Indicator(column: 0, target: scroll.first - 1)) }
        if scroll.trailing {
            line = line.padToVisibleWidth(width - 1) + "»"
            indicators.append(TitleRow.Indicator(column: width - 1, target: scroll.end))
        }
        return TitleRow(
            line: line, columns: columns, widths: widths, mnemonics: mnemonics, names: names, indicators: indicators)
    }
}

extension _MenuBarCore.TitleRow {
    /// What the pointer's handler at `position` stands for: a title, by its
    /// place in the bar, or a « or » (``indicators``), by the hidden title it
    /// opens. The titles' handlers come first, the indicators' after
    /// (``_MenuBarCore/attachTitleRegions(to:_:state:context:)``).
    func target(ofHandlerAt position: Int) -> (index: Int, isIndicator: Bool) {
        position < columns.count ? (position, false) : (indicators[position - columns.count].target, true)
    }
}
