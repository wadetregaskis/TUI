//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCacheStats.swift
//
//  What the render cache counts about itself: its hit, miss, store and clear
//  totals, and the row-shaped work the controls that draw rows report into it.
//
//  Split out of `RenderCache.swift`, which had reached the file-length ceiling.
//  Neither type reads anything of the cache's own.
//
//  Created by Wade Tregaskis
//  License: MIT

extension RenderCache {
    /// What a frame's row-shaped work cost, for the controls that draw rows.
    ///
    /// The numbers the question "should `Table` memoise its rows?" is actually
    /// about, and which nothing reported: `List` rows reach `_MemoizedRow` and
    /// so can be SERVED, `Table` composes every drawn row from scratch every
    /// frame, and the aggregate cache line cannot tell those apart because it
    /// sums the buffer memo, the size memo and the row memo together.
    ///
    /// ``cellValues`` is the one an app feels directly: it counts calls into a
    /// `TableColumn`'s own value closure, which is the app's code, not the
    /// framework's. A row memo's whole purpose is to drive it to zero for rows
    /// that did not change.
    public struct RowWork: Equatable, Sendable {
        /// Rows (or memoized subtrees) composed from scratch.
        public var rendered = 0
        /// Rows (or memoized subtrees) served from a memo instead.
        public var served = 0
        /// Of ``served``, those served while drawing rather than measuring:
        /// only these replay a subtree's registrations, so a test of what a
        /// served row still registers needs these, not measure serves.
        public var servedDrawing = 0
        /// Calls into an app's own cell value closures.
        public var cellValues = 0
        /// Of ``served``, the `Table` rows served at a stripe parity they were
        /// not kept at, and so drawn again there from the cells kept for them
        /// — no cell closure runs, and they are not counted as ``rendered``.
        /// A row drawn at a parity is kept there too, so a table whose rows
        /// keep changing parity (a log tailing into it) draws each row again
        /// once per parity, not once per frame.
        public var repainted = 0
        /// Composite bodies evaluated: every `body` of a `View` (a modifier's
        /// `body(content:)` included, through its `ModifiedContent`) the
        /// measure or the render walk ran, counted where the walk settles a
        /// `_printChanges()` request (`BodyChangeReport.noteBodyEvaluated`).
        /// A body served from `BodyKeep`, or skipped because a memo served
        /// its subtree, is not counted: this is the work a memo exists to
        /// save, as ``rendered`` is for rows. Not row-shaped, but here beside
        /// them because it is read the same way, as a delta per frame
        /// (`Stress --check-counts`, the perf-case table's `bodies` column).
        public var bodies = 0
        /// Row boxes a `List` made: one per row a loop or an outline
        /// described to the list (`LazyListRowContent`), drawn or not. A
        /// windowed list makes them for the rows it walks, about a screenful;
        /// a list that describes every row makes one a row, every frame —
        /// which is what this is here to show (the perf-case table's `listed`
        /// column). Not ``rendered``: a box draws nothing until it is read.
        ///
        /// And the rows of a `Table` whose tree is row content — a
        /// `DisclosureTableRow`, an `OutlineGroup` of table rows — that a
        /// pass's outline lists, each built by the app's row builders, drawn
        /// or not. A `Table(_:children:)` keeps its outline from pass to pass
        /// and builds no row content to make it: it counts the rows an
        /// outline it makes lists, which a pass that changes neither its roots
        /// nor its open branches makes none of.
        public var listed = 0

        public init(
            rendered: Int = 0, served: Int = 0, servedDrawing: Int = 0, cellValues: Int = 0, repainted: Int = 0,
            bodies: Int = 0, listed: Int = 0
        ) {
            self.rendered = rendered
            self.served = served
            self.servedDrawing = servedDrawing
            self.cellValues = cellValues
            self.repainted = repainted
            self.bodies = bodies
            self.listed = listed
        }

        /// This minus `earlier`, for a per-frame reading rather than a total.
        public func delta(since earlier: Self) -> Self {
            Self(
                rendered: rendered - earlier.rendered, served: served - earlier.served,
                servedDrawing: servedDrawing - earlier.servedDrawing,
                cellValues: cellValues - earlier.cellValues, repainted: repainted - earlier.repainted,
                bodies: bodies - earlier.bodies, listed: listed - earlier.listed)
        }
    }

    /// Aggregated cache performance statistics.
    ///
    /// Tracks hit/miss/store/clear counts. Use ``stats`` for cumulative
    /// totals, or `frameStats` (after ``logFrameStats()``) for the
    /// delta since the last ``beginRenderPass()``.
    public struct Stats: Equatable {
        /// Number of successful cache lookups (view and size matched).
        public var hits: Int = 0

        /// Number of failed cache lookups (identity missing, view changed, or size changed).
        public var misses: Int = 0

        /// Number of entries stored (including overwrites).
        public var stores: Int = 0

        /// Number of times ``clearAll()`` was called.
        public var clears: Int = 0

        /// Number of subtree clears: one for every call of
        /// ``clearAffected(by:keepingSizes:includingDescendants:)``, and one for
        /// every writer the frame-start drain clears for, however many it clears
        /// for in one walk.
        public var subtreeClears: Int = 0

        /// Number of cached entries — buffers and sizes — that subtree clears
        /// have asked whether they reach: each table's entries once per walk.
        /// What a clear COSTS, where ``subtreeClears`` is how many there were.
        public var clearVisits: Int = 0

        /// Creates a new Stats instance with default values.
        public init(
            hits: Int = 0,
            misses: Int = 0,
            stores: Int = 0,
            clears: Int = 0,
            subtreeClears: Int = 0,
            clearVisits: Int = 0
        ) {
            self.hits = hits
            self.misses = misses
            self.stores = stores
            self.clears = clears
            self.subtreeClears = subtreeClears
            self.clearVisits = clearVisits
        }

        /// The total number of lookups (hits + misses).
        public var lookups: Int { hits + misses }

        /// The cache hit rate as a value between 0 and 1, or 0 if no lookups occurred.
        public var hitRate: Double {
            lookups > 0 ? Double(hits) / Double(lookups) : 0
        }

        /// Returns the per-element difference between this snapshot and an earlier one.
        public func delta(since earlier: Self) -> Self {
            Self(
                hits: hits - earlier.hits,
                misses: misses - earlier.misses,
                stores: stores - earlier.stores,
                clears: clears - earlier.clears,
                subtreeClears: subtreeClears - earlier.subtreeClears,
                clearVisits: clearVisits - earlier.clearVisits
            )
        }
    }
}
