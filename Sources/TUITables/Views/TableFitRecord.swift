//  🖥️ TUI — A Terminal UI framework for Swift
//  TableFitRecord.swift
//
//  What a `Table` keeps of its `.fit` columns' walks in `@State`, so a row
//  appended costs the row and a tab switched back to costs nothing like a walk
//  (PERFCASE-F1, PERFCASE-F2).
//
//  The render cache's size entry (`fitWidth`) is the first rung and stays: it
//  is exact, and a frame where nothing was written is served from it. But it is
//  in the cache, so the write that brings a row — an `@Observable` the page's
//  body read, a parent's `@State` — sweeps it, and so does the end of a pass the
//  table was not drawn in, which is every pass its tab is hidden. A record that
//  is gone before it can be extended is no record at all; this one is in
//  `@State`, as a lazy stack's content width is (`StackContentWidth.swift`),
//  and it is that design followed rung for rung: the kept answer, the kept
//  prefix extended by the rows that grew it, a challenge of the row that
//  decided it after a write, and the walk.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIView

/// The `.fit` records of one table, by column, and the rows it last drew:
/// one box at the table's identity, changed in place — a `StateBox` write
/// would invalidate the table and ask for another frame, for a cache.
final class _TableFitRecords {
    /// Each `.fit` column's record, by its declaration index.
    var columns: [Int: _TableFitRecord] = [:]
    /// The rows the last render drew, which a challenge of an unchanged
    /// collection reads again: a write that moves what rows draw shows there
    /// first.
    var drawn: Range<Int> = 0..<0
    /// The rows' version, which the columns' render-cache entries are
    /// compared by (`_TableCore.fitMemoKey`): kept here, where the writes that
    /// sweep those entries do not reach it.
    let rowsVersion = DataVersion()

    init() {}
}

/// The widest of one `.fit` column's CELLS over every row of `rows` — the
/// header is measured fresh each time, since a sort indicator or a live title
/// moves it with no row changing — and what made it mean that.
///
/// Filed only for a walk that reached the end: a walk the cap stopped knows a
/// lower bound, not a maximum. So a record answers an ask exactly when its
/// maximum, joined with the header, is under the ask's cap: a walk from the
/// first row would then never have stopped, and would have found the same
/// number.
///
/// In `@State`, so it owns its own invalidation, as
/// `ContentWidthRecord` does and for the same events:
///
/// * ``TerminalWidthTraits/generation``, ``RenderContext/measureGeneration``
///   and ``RenderCache/clearGeneration`` make it stale outright
///   (``isCurrent(in:)``).
/// * A size clear (``RenderCache/sizeClearGeneration``), which every write
///   above the table is, makes it CHALLENGED: the row that decided the
///   maximum is read again, and the drawn rows with it when the collection did
///   not move. The residue is `ContentWidthRecord`'s, stated there: a write
///   that changes what a cell closure draws without changing the rows, and
///   widens some undrawn row past the runner-up, is not seen until a walk.
/// * An `@Observable` change a cell closure read — the scopes the walks armed
///   report at the table's identity, and the record keeps their leases so they
///   live as long as it does — drops every record of the table, and the next
///   ask walks (`refreshFitRecords`). That is exact where the challenge
///   samples.
struct _TableFitRecord {
    /// The rows the maximum was taken over, as compared.
    let rows: AnyEquatableBox
    /// How many there were: what an extension walks on from.
    let covered: Int
    /// The width a `Text` or view cell was laid out at; `nil` for a string
    /// cell, which is not laid out (``isLaidOutAlike(at:wraps:)``).
    let probeWidth: Int?
    /// Whether the cells wrap at ``probeWidth``: a column of more than one line.
    let wraps: Bool
    /// The widest cell, and the row it is in — the one a challenge reads again.
    var widest: Int
    var widestOrdinal: Int?
    /// The second-widest cell: every row but the widest is at most this wide,
    /// so a challenge that finds the widest row narrower but still at least
    /// this wide knows the new maximum exactly.
    var runnerUp: Int
    let widthGeneration: Int
    let measureGeneration: UInt8
    let clearGeneration: Int
    /// ``RenderCache/sizeClearGeneration`` when this record was last known to
    /// hold. Behind it, a challenge runs before the record answers.
    var verifiedGeneration: Int
    /// The leases of the walks that read the rows — the first and every
    /// extension, a flat list so a table appended to every frame builds no
    /// chain — and of the last challenge. The record is kept outside the
    /// render cache, so what those walks observed must live as long as it does.
    var walkLeases: [ObservationLease]
    var challengeLease: ObservationLease?

    /// Whether this record was taken under the same world as `context`.
    func isCurrent(in context: RenderContext) -> Bool {
        widthGeneration == TerminalWidthTraits.generation
            && measureGeneration == context.generationIgnoringIdealWidth
            && clearGeneration == (context.renderCache?.clearGeneration ?? 0)
    }

    /// Whether the cells, laid out at `probeWidth` (`nil`: not laid out), are
    /// the cells this record read.
    ///
    /// A string cell is not laid out at all. A wrapping cell's lines are made
    /// at the width, so only the same width gives the same lines. A one-line
    /// cell is laid out alike at every width wider than it: so where no cell
    /// reached the width the record laid them out at — none was cut to it, and
    /// none fills whatever it is offered — each is as wide at any width past
    /// the widest. That is what lets the one record answer the measures and
    /// the render of a frame, and a table resized, which ask at other widths.
    func isLaidOutAlike(at probeWidth: Int?, wraps: Bool) -> Bool {
        guard let mine = self.probeWidth, let probeWidth else { return self.probeWidth == probeWidth }
        guard wraps == self.wraps else { return false }
        if wraps { return mine == probeWidth }
        return widest < mine && widest < probeWidth
    }

    /// Whether this record's maximum, with `header`, is the answer a walk from
    /// the first row would give under `cap`: one it would not have stopped.
    func answers(header: Int, cap: Int?) -> Bool {
        guard let cap else { return true }
        return max(header, widest) < cap
    }

    /// What this record's answer depends on, held by the computation it is
    /// answering: whatever keeps the answer keeps the scopes behind it.
    @MainActor
    func use(in context: RenderContext) {
        guard let leases = context.renderCache?.leases else { return }
        for lease in walkLeases { leases.use(lease) }
        leases.use(challengeLease)
    }
}

/// One walk over a column's cells: what it found, and where it stopped.
struct _TableFitWalk {
    /// The widest cell walked, and its row; the runner-up.
    var widest = 0
    var widestOrdinal: Int?
    var runnerUp = 0
    /// How many rows had been walked when it stopped.
    var walked = 0
    /// Whether the cap stopped it before the end.
    var stopped = false

    /// Takes in row `ordinal`'s cell, `width` wide.
    mutating func note(_ width: Int, at ordinal: Int) {
        if widestOrdinal == nil || width > widest {
            if widestOrdinal != nil { runnerUp = max(runnerUp, widest) }
            widest = width
            widestOrdinal = ordinal
        } else {
            runnerUp = max(runnerUp, width)
        }
    }
}
