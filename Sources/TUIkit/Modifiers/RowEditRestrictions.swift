//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowEditRestrictions.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

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
final class RowEditRestrictions {
    /// LIST ROWS that refused deletion this frame.
    private(set) var deleteDisabled: Set<Int> = []

    /// List rows that refused to be moved this frame.
    private(set) var moveDisabled: Set<Int> = []

    /// List rows that refused to be selected this frame.
    private(set) var selectionDisabled: Set<Int> = []

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
    var currentRowIndex: Int?

    /// The list row at which the `ForEach` now being extracted draws its first
    /// element — what its per-element index is counted from to reach
    /// ``currentRowIndex``.
    ///
    /// Zero for a flat `List { ForEach … }`, where the two numberings coincide.
    /// Set by `_ListCore` around each `Section`'s extraction, and READ when a
    /// row's deferred content box is built (which for a Section's rows is
    /// during that same extraction), not when the box later renders — by then
    /// another section may have moved it.
    var rowIndexBase = 0

    /// Each list row's separator preference, as `.listRowSeparator(_:edges:)`
    /// and `.listRowSeparatorTint(_:edges:)` reported it while the row
    /// rendered (decisions A47) — the same collector, stamped the same way,
    /// since a separator is one more thing a row tells its list about itself.
    private(set) var separators: [Int: ListSeparatorPreference] = [:]

    /// Each list row's own separator guides
    /// (``HorizontalAlignment/listRowSeparatorLeading`` and `…Trailing`), where
    /// its view sets either, in cells from its content's leading edge.
    private(set) var separatorGuides: [Int: (leading: Int?, trailing: Int?)] = [:]

    func reportSeparator(row: Int, _ change: ListSeparatorChange) {
        change.apply(to: &separators[row, default: ListSeparatorPreference()])
    }

    func reportSeparatorGuides(row: Int, _ guides: (leading: Int?, trailing: Int?)) {
        separatorGuides[row] = guides
    }

    func disableDelete(row: Int) { deleteDisabled.insert(row) }
    func disableMove(row: Int) { moveDisabled.insert(row) }
    func disableSelection(row: Int) { selectionDisabled.insert(row) }
}

extension EnvironmentValues {
    /// Where a row states the edits (and selection) it refuses. Installed by
    /// `_ListCore`.
    @inlinable
    var listRowEditRestrictions: RowEditRestrictions? {
        get { self[RowEditRestrictionsKey.self] }
        set { self[RowEditRestrictionsKey.self] = newValue }
    }
}

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct RowEditRestrictionsKey: EnvironmentKey {
    @usableFromInline static let defaultValue: RowEditRestrictions? = nil
}
