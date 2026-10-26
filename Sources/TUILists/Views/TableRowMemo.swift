//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowMemo.swift
//
//  Keeping a `Table`'s composed row lines across frames, without inventing a
//  way for drawn content to be stale.
//
//  A `Table` composes every drawn row from scratch on every frame where a
//  `List` serves its rows from a memo. Closing that is worth a quarter of a
//  frame — measured, by making rows free in a deliberately wrong build — and
//  the obvious way to close it is not available. The render cache's own
//  invalidation drops every entry BENEATH an identity whose state was written,
//  which is exactly the frame a live table's data arrives on: the write that
//  changes two per cent of the rows clears a hundred per cent of the cache. A
//  memo that survived that sweep would be fast and occasionally wrong, and a
//  cell showing last frame's value is a worse defect than a slow one.
//
//  So this does not survive the sweep by being trusted. It sits outside the
//  sweep — on the table's own `ItemListHandler`, which is `@State` and which
//  already keeps the scroll extent's profile this way — and earns that by
//  keying on the INPUTS themselves rather than on a proxy for them:
//
//  * a row's CELLS are compared, not the row. A closure column may capture a
//    search term, a formatter, a units toggle — none of which the row carries —
//    so an equal row proves nothing about its text. But once the closure has
//    RUN, what it produced is not a proxy for the text: it IS the text, and a
//    line built from equal cells under an equal frame key is the same line.
//    That costs the app's own closures, which is the part nobody can skip, and
//    saves everything downstream of them.
//  * unless every column NAMES its value (``TableColumn/namesAProperty``), in
//    which case the cells are a pure function of the row and an equal row is
//    enough — so a key-path table skips even the property reads. That is an
//    optimisation on top of the rule above, not the rule itself.
//  * everything the FRAME settles that reaches a row's bytes is compared once
//    per frame in ``TableRowFrameKey`` — the widths, the geometry, the resolved
//    ink and selection marks, each column's alignment and truncation and limit,
//    the colour depth, and the two generations that make a colour or a width
//    mean something different than it did.
//  * everything the ROW settles is compared per row: the row value itself, and
//    whether it is selected, which decides its mark and background.
//  * except for the one row whose look is not settled by the row at all: the
//    CURSOR row of a focused table breathes or holds still as the indicator
//    style and the window say, neither of which a key here carries, so it is
//    never kept. It is one row a frame, and it was never kept while it
//    breathed anyway.
//
//  What is left uncovered is global mutable state read through a computed
//  property — a `static` formatter, a `Date()`. That hole is older than this
//  file and is not widened by it: `fitWidth`, the scroll extent profile and
//  every value memo in the framework already have it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIStyling
import TUIView

// MARK: - The frame's half of the key

/// Everything a frame settles that reaches a row's bytes and is not the row.
///
/// Compared ONCE per frame rather than per row: it is the same value for every
/// row, and carrying an array of column widths into each row's key cost more
/// than the memo saved on the tables it could not serve. A frame whose key
/// differs from the last one drops the whole store, which is correct and is
/// also the common case whenever anything about the table's shape moves.
package struct TableRowFrameKey: Equatable {
    package let columnWidths: [Int]
    package let columnSpacing: Int
    package let gutter: Int
    package let rowWidth: Int
    /// The colour a cell's text resolves to, which the environment and the
    /// palette both reach. Resolved rather than named, so a palette that
    /// changed what `foreground` means changes this.
    package let ink: Color
    /// What the gutter of a row the cursor is not on draws, selected and not: an
    /// unfocused selection's ● — the accent dimmed over the page, or a blank under
    /// `.unfocusedSelectionVisibility(.hidden)` — and the blank every other row
    /// spells in a colour of its own. Resolved, as `ink` is, and for the same
    /// reason: the accent, the page and that visibility all reach these bytes and
    /// none of them is the row. Keyed on the ink alone, a palette with the same
    /// text and another accent — Silver Aerogel to Solid Colors, neighbours in the
    /// palette cycle — went on serving the old ● on every kept selected row, and
    /// hiding the unfocused selection left the marks it had.
    package let selectedMark: RowSelectionIndicator
    package let unselectedMark: RowSelectionIndicator
    /// What a striped row paints behind itself (``RowBackground/alternatingStripe(palette:over:)``),
    /// or `nil` for no stripe. Resolved, as `ink` is, because the accent, the
    /// depth AND the surface the table sits on all reach it
    /// (``EnvironmentValues/enclosingSurface``), and the surface reaches nothing
    /// else this key carries: a table whose surface moved under it — a palette
    /// that changed only the tone a `TabView` lifts its body onto — went on
    /// serving every kept striped row in the old surface's stripe.
    package let stripe: Color?
    package let alignments: [HorizontalAlignment]
    package let truncations: [TruncationMode]
    package let lineLimits: [Int]
    /// How many colour channels a cell's SGR will be spelled in. Not covered by
    /// `ink`: the same `Color` renders to different bytes at a different depth,
    /// and unlike the two generations below there is no counter for it.
    package let colorDepth: ColorDepth
    package let colorGeneration: Int
    package let widthGeneration: Int
    /// What the style cascade gives a string cell's text (`Table.cellTextAttributes`):
    /// `.bold()` on the table reaches a cell drawn from a `String` key path,
    /// and nothing the row carries changes with it.
    package let cellText: StyleAttributes

    /// The memberwise initializer, written out: a synthesized one is internal,
    /// and a table in TUITables makes these (module split, step C2).
    package init(
        columnWidths: [Int], columnSpacing: Int, gutter: Int, rowWidth: Int, ink: Color,
        selectedMark: RowSelectionIndicator, unselectedMark: RowSelectionIndicator, stripe: Color?,
        alignments: [HorizontalAlignment], truncations: [TruncationMode], lineLimits: [Int], colorDepth: ColorDepth,
        colorGeneration: Int, widthGeneration: Int, cellText: StyleAttributes
    ) {
        self.columnWidths = columnWidths
        self.columnSpacing = columnSpacing
        self.gutter = gutter
        self.rowWidth = rowWidth
        self.ink = ink
        self.selectedMark = selectedMark
        self.unselectedMark = unselectedMark
        self.stripe = stripe
        self.alignments = alignments
        self.truncations = truncations
        self.lineLimits = lineLimits
        self.colorDepth = colorDepth
        self.colorGeneration = colorGeneration
        self.widthGeneration = widthGeneration
        self.cellText = cellText
    }
}

// MARK: - The row's half, and what was kept

/// One row's composed line, and the row state it was composed for.
///
/// `@usableFromInline`, with its stored properties, and its members
/// `@inlinable` (module split, set T): a table's row code in TUITables
/// builds, challenges and re-draws one of these for every row it draws, and
/// across the module boundary each of those would otherwise be a call.
@usableFromInline
package struct TableRowMemoLine {
    /// The row this line was last PROVED to answer for, when its type could be
    /// compared at all. `nil` for a row type that is not `Equatable`, which
    /// `Table` does not require — those rows are answered by their CELLS alone.
    ///
    /// `var`, and re-pointed by ``TableRowMemoStore/refresh(row:for:)``: a row
    /// that changed in a way its columns do not show passes the cell test and
    /// fails the row test, and leaving it pointing at the row the line was
    /// COMPOSED for would fail that test again every frame thereafter. See the
    /// note on `refresh`.
    @usableFromInline package var row: AnyEquatableBox?
    /// What every column produced for this row, in column order.
    ///
    /// The soundness of a closure column rests entirely on this. A closure may
    /// capture a search term, a formatter, a units toggle — none of which the
    /// row carries — so an equal row proves nothing about its text. But once
    /// the closure has RUN, what it produced is not a proxy for the text: it IS
    /// the text, and a line built from equal cells under an equal frame key is
    /// the same line.
    @usableFromInline package let cells: [String]
    /// Whether the row was selected. Not whether it was the cursor: the cursor
    /// row of a focused table is never kept (see `Table.renderRow`), so every
    /// entry is a row the cursor was not on.
    @usableFromInline let isSelected: Bool
    /// Whether the row drew faint, refusing selection
    /// (`.selectionDisabled()`), which its cells do not say.
    @usableFromInline let isDimmed: Bool
    /// The row as drawn without a stripe and with one, each kept once the row
    /// has been drawn at that parity: composed there, or drawn there again
    /// from ``cells`` (`Table.renderRow`'s `atParity`).
    ///
    /// A table stripes by default (decisions A29), and a stripe follows the
    /// row's POSITION (`.alternatingRowBackgrounds()`): one row inserted or
    /// removed above the window moves every row below it to the other parity,
    /// a newest-first log on every entry it gains, and a row that keeps moving
    /// goes back and forth — every row of a table tailing a log changes parity
    /// on every entry the log gains. Each of those rows has the cells it had;
    /// only its background moved. Running its cell closures again is what the
    /// memo exists to avoid, so the row is drawn again from the cells kept
    /// here, once per parity it reaches, and served as kept there thereafter —
    /// for the price of one more line per kept row that has worn both.
    ///
    /// From the CELLS, not from a copy of the line kept unpainted beside the
    /// painted one, as it once was: that copy was a second string for every
    /// striped row of every table, kept whether or not the row ever moved, and
    /// most never do. The cells are kept anyway (they are what ``answers(cells:isSelected:isDimmed:)``
    /// compares), and a line drawn from them is the line a compose of them
    /// draws, by construction.
    ///
    /// Internal and `@usableFromInline`, not private, for the `@inlinable`
    /// members below.
    @usableFromInline var plain: TableRowDrawnLine?
    @usableFromInline var striped: TableRowDrawnLine?

    /// - Parameters:
    ///   - isStriped: Whether `drawn` wears the stripe — which of the two
    ///     parities it is kept as.
    ///   - drawn: The row as composed.
    @inlinable
    package init(
        row: AnyEquatableBox?, cells: [String], isSelected: Bool, isStriped: Bool, isDimmed: Bool,
        drawn: TableRowDrawnLine
    ) {
        self.row = row
        self.cells = cells
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        if isStriped { striped = drawn } else { plain = drawn }
    }

    /// The row as kept at this parity, or `nil` where it has not been drawn
    /// there yet.
    @inlinable
    package func drawn(striped isStriped: Bool) -> TableRowDrawnLine? {
        isStriped ? striped : plain
    }

    /// Keeps `drawn` as the row at this parity too.
    @inlinable
    package mutating func keep(_ drawn: TableRowDrawnLine, striped isStriped: Bool) {
        if isStriped { striped = drawn } else { plain = drawn }
    }

    /// Whether this entry answers for a row whose cells are `cells`, at either
    /// parity (see ``drawn(striped:)``).
    @inlinable
    package func answers(cells other: [String], isSelected: Bool, isDimmed: Bool) -> Bool {
        self.isSelected == isSelected && self.isDimmed == isDimmed && cells == other
    }

    /// Whether this entry answers for `row` WITHOUT computing its cells — only
    /// for a table whose every column names its value, where the cells are a
    /// pure function of the row. At either parity, as the cell test.
    @inlinable
    package func answers(row other: AnyEquatableBox, isSelected: Bool, isDimmed: Bool) -> Bool {
        self.isSelected == isSelected && self.isDimmed == isDimmed && self.row == other
    }
}

/// One parity's drawing of a kept table row: the line, and the claims it owes
/// (``SelectableRowClaims``). See ``TableRowMemoLine``.
///
/// `@usableFromInline`, as ``TableRowMemoLine`` is (module split, set T).
@usableFromInline
package struct TableRowDrawnLine {
    @usableFromInline package let line: String
    @usableFromInline package let claims: [OpacityRegion]

    /// The memberwise initializer, written out: a synthesized one is internal,
    /// and a table's row code in TUITables builds one per row it keeps.
    @inlinable
    package init(line: String, claims: [OpacityRegion]) {
        self.line = line
        self.claims = claims
    }
}

/// A table's kept row lines, and the frame key they were composed under.
///
/// Held by ``ItemListHandler`` so that it outlives a render-cache sweep, and
/// bounded so that a long scroll cannot grow it without limit: the store is
/// dropped whole once it holds far more rows than a screenful, which costs one
/// frame of re-composition and is simpler than an eviction order nobody would
/// ever read.
///
/// `@usableFromInline`, with the members a table asks per row `@inlinable`
/// (module split, set T): ``keep(_:for:)``, ``entry(for:)`` and
/// ``refresh(row:for:)``. ``lines`` is `@usableFromInline` for them.
@usableFromInline
package struct TableRowMemoStore<ID: Hashable> {
    /// Whether this frame may keep rows at all, settled ONCE by `begin` rather
    /// than per row.
    ///
    /// Asking `columns.allSatisfy(\.namesAProperty)` per row read a
    /// `TableColumn` per column per row, and a `TableColumn` holds closures and
    /// strings — so the question cost 210 retain/release pairs a frame on a
    /// six-column table and showed up as 20% of the frame in `renderRow` even
    /// when 98% of its rows were being served. The answer cannot change within
    /// a frame; asking it once is the whole fix.
    package private(set) var isOpen = false
    /// Whether every column names its value, settled once by `begin` for the
    /// same reason `isOpen` is: asking it reads a `TableColumn` per column, and
    /// a `TableColumn` holds closures and strings.
    package private(set) var namesItsValues = false
    private(set) var frameKey: TableRowFrameKey?
    /// Internal and `@usableFromInline`, not private, for the `@inlinable`
    /// members.
    @usableFromInline var lines: [ID: TableRowMemoLine] = [:]

    /// How many rows may be kept, as a multiple of what is on screen.
    private static var slack: Int { 8 }

    /// Prepares the store for a frame, dropping everything if the frame's own
    /// inputs moved.
    package mutating func begin(frame key: TableRowFrameKey, viewportHeight: Int, namesItsValues: Bool) {
        isOpen = true
        self.namesItsValues = namesItsValues
        if frameKey != key {
            frameKey = key
            lines.removeAll(keepingCapacity: true)
            return
        }
        if lines.count > max(32, viewportHeight * Self.slack) {
            lines.removeAll(keepingCapacity: true)
        }
    }

    /// The kept entry for `id`, whatever it holds — the caller decides how to
    /// challenge it.
    @inlinable
    package func entry(for id: ID) -> TableRowMemoLine? { lines[id] }

    /// Keeps `entry` as the row `id` draws.
    @inlinable
    package mutating func keep(_ entry: TableRowMemoLine, for id: ID) {
        lines[id] = entry
    }

    /// Re-points a kept line at the row it was JUST proved to answer for.
    ///
    /// A model row carries more than it shows — a timestamp, a revision, a
    /// sequence number — so a live snapshot hands over rows that are not equal
    /// to last frame's while drawing identical bytes. Such a row fails the row
    /// test and passes the cell test, which is correct and costs a build per
    /// column. Without this it costs that on EVERY later frame too: the kept
    /// entry still names the row it was composed for, which nothing will ever
    /// equal again, so the table falls permanently to its expensive tier while
    /// drawing the same picture. On cells that come from a formatter, that is
    /// the difference between a frame and ten.
    ///
    /// Sound because it asserts no more than the frame just proved: the line
    /// was built from cells equal to this row's under this frame key, and under
    /// `namesItsValues` the cells are a pure function of the row — so any later
    /// row equal to this one produces those cells and therefore that line.
    @inlinable
    package mutating func refresh(row: AnyEquatableBox, for id: ID) {
        lines[id]?.row = row
    }

    package mutating func removeAll() {
        isOpen = false
        namesItsValues = false
        lines.removeAll(keepingCapacity: true)
        frameKey = nil
    }
}
