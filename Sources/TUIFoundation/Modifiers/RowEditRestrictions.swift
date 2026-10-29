//  🖥️ TUI — A Terminal UI framework for Swift
//  RowEditRestrictions.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// Which edits — and whether selection — a row has refused, gathered as the
/// rows render.
///
/// A collector rather than a value on the row because the flag is stated INSIDE
/// the row's subtree — `Text(…).deleteDisabled(true).padding()` puts the
/// padding outermost — so reading it structurally would depend on modifier
/// order. Reporting on render does not.
///
/// One per `List` per frame. Absence means allowed, which is what makes a row
/// that never rendered (off the window) harmless for delete/move: the only
/// rows a user can delete or move are the focused one and the grabbed one,
/// and both are on screen by construction. Selection is the one restriction
/// here that is not so contained — Up/Down can land the cursor on a row that
/// has never rendered — so a `.selectionDisabled()` row is only skipped by
/// navigation once a frame has drawn it and reported it here; see
/// ``ItemListHandler/selectionDisabledRows``.
/// `@usableFromInline`: the type of an `@inlinable` environment accessor (module split step A3).
@MainActor
@usableFromInline
package final class RowEditRestrictions {
    /// LIST ROWS that refused deletion this frame.
    package var deleteDisabled: Set<Int> { _deleteDisabled }

    /// List rows that refused to be moved this frame.
    package var moveDisabled: Set<Int> { _moveDisabled }

    /// List rows that refused to be selected this frame.
    package var selectionDisabled: Set<Int> { _selectionDisabled }

    /// The LIST ROW currently rendering, stamped by the List's row
    /// materialisation just before each row renders — the only code that knows
    /// it, since the modifier is written on the row's content and has no idea
    /// where in the list it sits.
    ///
    /// A list row, not the row's offset in its own `ForEach`'s collection: the
    /// handler compares these sets against the focused row and the grabbed
    /// row, and both of those are list rows. The two are the same number only
    /// in a flat `List { ForEach … }`. Inside a `Section` they differ by
    /// ``rowIndexBase``, and with two Sections the offsets COLLIDE — each
    /// section counts its own rows from 0, so `.deleteDisabled()` on the
    /// second section's second row named the first section's second row as
    /// well as (in fact, instead of) its own.
    ///
    /// A field on this (per-List, per-frame) collector rather than an
    /// environment value because the environment is a copy-on-write
    /// dictionary: stamping a per-row Int into it copied the WHOLE dictionary
    /// — every environment entry rehashed, reboxed and retained — once per
    /// visible row per frame, which a windowed List pays for every row it
    /// shows. Writing a property on the already-installed collector is free,
    /// and rows render strictly one at a time, so the single slot cannot be
    /// observed with a neighbour's value. A nested List installs its own
    /// collector for its subtree, so the inner rows stamp the inner one and
    /// the outer row's stamp stays good for the rest of its own render.
    package var currentRowIndex: Int? { get { _currentRowIndex } set { _currentRowIndex = newValue } }

    /// The list row at which the `ForEach` now being extracted draws its first
    /// element — what its per-element index is counted from to reach
    /// ``currentRowIndex``.
    ///
    /// Zero for a flat `List { ForEach … }`, where the two numberings coincide.
    /// Set by `_ListCore` around each `Section`'s extraction, and READ when a
    /// row's deferred content box is built (which for a Section's rows is
    /// during that same extraction), not when the box later renders — by then
    /// another section may have moved it.
    package var rowIndexBase: Int { get { _rowIndexBase } set { _rowIndexBase = newValue } }

    /// Each list row's separator preference, as `.listRowSeparator(_:edges:)`
    /// and `.listRowSeparatorTint(_:edges:)` reported it while the row
    /// rendered (decisions A47) — the same collector, stamped the same way,
    /// since a separator is one more thing a row tells its list about itself.
    package var separators: [Int: ListSeparatorPreference] { _separators }

    /// Each list row's own separator guides
    /// (``HorizontalAlignment/listRowSeparatorLeading`` and `…Trailing`), where
    /// its view sets either, in cells from its content's leading edge.
    package var separatorGuides: [Int: (leading: Int?, trailing: Int?)] { _separatorGuides }

    // The storage under the `package` accessors: private (CONTRIBUTING.md,
    // "Crossing a module boundary"). The sets and tables are written here
    // only, through the methods below.
    private var _deleteDisabled: Set<Int> = []
    private var _moveDisabled: Set<Int> = []
    private var _selectionDisabled: Set<Int> = []
    private var _currentRowIndex: Int?
    private var _rowIndexBase = 0
    private var _separators: [Int: ListSeparatorPreference] = [:]
    private var _separatorGuides: [Int: (leading: Int?, trailing: Int?)] = [:]
    private var _rowMenus: [Int: @MainActor () -> Void] = [:]

    /// What opens each list row's own `.contextMenu`, by list row, as the menus
    /// reported while their rows rendered: what the list's Shift+F10 opens on
    /// the cursor row. A context menu in a list row is no focus stop of its
    /// own — the row is reached through the list, as SwiftUI's is.
    package var rowMenus: [Int: @MainActor () -> Void] { _rowMenus }

    /// Reports that list row `row` carries a context menu, opened by `open`.
    package func reportRowMenu(row: Int, open: @escaping @MainActor () -> Void) {
        _rowMenus[row] = open
    }

    /// Each list row's drag, by list row, as its `.draggable` reported it
    /// while the row rendered: what the list's Copy and pick-up chord take
    /// from the cursor row (``RowDrag``). A `.draggable` in a list row is no
    /// focus stop of its own, as its context menu is none.
    package var rowDrags: [Int: RowDrag] { _rowDrags }
    private var _rowDrags: [Int: RowDrag] = [:]

    /// Reports that list row `row` is dragged as `drag`. The outermost
    /// `.draggable` of a row wins, as it wins a press: it reports last.
    package func reportRowDrag(row: Int, _ drag: RowDrag) {
        _rowDrags[row] = drag
    }

    /// Each list row's swipe actions, by list row and edge, as
    /// `.swipeActions(edge:allowsFullSwipe:content:)` reported them while the
    /// row rendered: whether a full swipe on that edge performs its first
    /// action. What the list's swipe keys reveal on the cursor row.
    package var swipeEdges: [Int: [HorizontalEdge: Bool]] { _swipeEdges }
    private var _swipeEdges: [Int: [HorizontalEdge: Bool]] = [:]

    /// Reports that list row `row` has swipe actions on `edge`.
    package func reportSwipeActions(row: Int, edge: HorizontalEdge, allowsFullSwipe: Bool) {
        _swipeEdges[row, default: [:]][edge] = allowsFullSwipe
    }

    /// The row whose swipe actions are revealed, and at which edge — set by
    /// the list before its rows render, from its handler, for the row's own
    /// `.swipeActions` to draw them. On this collector for
    /// ``currentRowIndex``'s reason: the one row it names compares it with its
    /// own index, so no other row's environment changes.
    package var swipeReveal: ListRowSwipeReveal? { get { _swipeReveal } set { _swipeReveal = newValue } }
    private var _swipeReveal: ListRowSwipeReveal?

    /// Which edge a key reveals, as the list's row shortcuts bind the swipe
    /// keys — `nil` for a key that reveals none. Set by the list for its rows,
    /// so revealed actions know the chord that revealed them (again, the full
    /// swipe) and the other edge's (which slides them away). Here rather than
    /// in the environment, where a closure would leave every row of every list
    /// with an environment no memo can compare.
    package var swipeKeys: (@MainActor (KeyEvent) -> HorizontalEdge?)? {
        get { _swipeKeys }
        set { _swipeKeys = newValue }
    }
    private var _swipeKeys: (@MainActor (KeyEvent) -> HorizontalEdge?)?

    /// Presses the revealed swipe actions' first, reported by the revealed row
    /// as it draws them: what the list's horizontal wheel calls for a full
    /// swipe, outside the render, where a press belongs.
    package var swipeFullSwipe: (@MainActor () -> Void)? { get { _swipeFullSwipe } set { _swipeFullSwipe = newValue } }
    private var _swipeFullSwipe: (@MainActor () -> Void)?

    /// What decides, as the list extracts its sections, whether a section's
    /// actions are drawn (owner ruling B78-VISIBILITY): the list row of the
    /// cursor while the list holds the focus, and the first row of the section
    /// under the pointer. Set by `_ListCore` before it extracts its rows; on
    /// this collector for ``rowIndexBase``'s reason — the extraction is
    /// several calls deep and reads the list only through its rows' context.
    package var sectionsInUse: (cursorRow: Int?, hoveredSectionRow: Int?) {
        get { _sectionsInUse }
        set { _sectionsInUse = newValue }
    }

    /// The rows of each section with actions this frame, header to footer —
    /// what the pointer is found in. Gathered as the sections are extracted.
    package var sectionActionSpans: [Range<Int>] { _sectionActionSpans }

    /// Reports that the section spanning list rows `rows` carries actions.
    package func reportSectionActions(rows: Range<Int>) { _sectionActionSpans.append(rows) }

    private var _sectionsInUse: (cursorRow: Int?, hoveredSectionRow: Int?) = (nil, nil)
    private var _sectionActionSpans: [Range<Int>] = []

    /// No arguments, spelled out because the implicit initializer is internal
    /// and TUILists makes these, for its lists.
    package init() {}

    package func reportSeparator(row: Int, _ change: ListSeparatorChange) {
        change.apply(to: &_separators[row, default: ListSeparatorPreference()])
    }

    func reportSeparatorGuides(row: Int, _ guides: (leading: Int?, trailing: Int?)) {
        _separatorGuides[row] = guides
    }

    package func disableDelete(row: Int) { _deleteDisabled.insert(row) }
    package func disableMove(row: Int) { _moveDisabled.insert(row) }
    package func disableSelection(row: Int) { _selectionDisabled.insert(row) }
}

extension EnvironmentValues {
    /// Where a row states the edits (and selection) it refuses. Installed by
    /// `_ListCore`.
    @inlinable
    package var listRowEditRestrictions: RowEditRestrictions? {
        get { self[RowEditRestrictionsKey.self] }
        set { self[RowEditRestrictionsKey.self] = newValue }
    }
}

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct RowEditRestrictionsKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    @usableFromInline static let defaultValue: RowEditRestrictions? = nil
}

/// A list row's swipe actions revealed: which row, which edge, and how to
/// slide them away again.
package struct ListRowSwipeReveal {
    /// The list row whose actions are revealed.
    package let row: Int
    /// The edge revealed.
    package let edge: HorizontalEdge
    /// Slides the actions away and gives the list its keys back.
    package let hide: @MainActor () -> Void

    package init(row: Int, edge: HorizontalEdge, hide: @escaping @MainActor () -> Void) {
        self.row = row
        self.edge = edge
        self.hide = hide
    }
}
