//  🖥️ TUI — A Terminal UI framework for Swift
//  StackPulledColumn+LoopRows.swift
//
//  What a column of several views (`_ImplicitColumnOfSeveral`) tells its
//  scroll view of its rows: each row of a loop among its views, as the flat
//  stack the column stands in for tells it, not the loop's lazy stack as one
//  view. A pulled column reports its own children (`reportPulledTargets`),
//  which for `LazyVStack { heading; ForEach(rows) }` drawn as the column
//  were the heading and the loop's stack: `.scrollPosition(id:)` was handed
//  no row id, `onScrollTargetVisibilityChange` listed none, and a
//  `.viewAligned` behaviour over a stack marked `scrollTargetLayout()`
//  settled on the stack's top. So content read back that way could not take
//  the column below the lazy stack's threshold, and changed identity as a
//  filtered loop crossed it (H-71). Now the column asks each loop's stack for
//  its rows, as a visibility observer would, and reports them in its own
//  lines beside its other views: what the flat stack reports, at any count
//  (the owner's O-14 (c), 2026-11-21). Below the threshold the loop's stack
//  draws every row and is not pulled, and the column draws as an eager stack;
//  it lays the loop's rows out to report them, and to find a row a request
//  names (`resolveEagerSeek`), which it did not find before.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// The rows one loop's lazy stack reported, among a column of several's
/// views: in the column's lines, each named by `ids` from its ordinal among
/// the stack's rows.
struct PulledLoopRows {
    var spans: TargetLayoutSpans
    let ids: @MainActor (Int) -> AnyHashable?

    init(spans: TargetLayoutSpans, ids: @escaping @MainActor (Int) -> AnyHashable?) {
        self.spans = spans
        self.ids = ids
    }

    /// The rows a pulled loop's reply holds, its line 0 at column line `zero`.
    @MainActor
    init?(_ reply: ScrollContentReply, zero: Int) {
        guard let spans = reply.targetVisibleRows, let ids = reply.targetIDs else { return nil }
        self.spans = spans.shifted(by: zero)
        self.ids = ids
    }

    /// These rows `delta` lines further down the column.
    func shifted(by delta: Int) -> Self {
        var rows = self
        rows.spans = spans.shifted(by: delta)
        return rows
    }
}

/// One of a column's views as its fill placed it, for ``ColumnOfSeveralRows``:
/// its lines in the column, and its loop's rows when it is a loop.
struct ColumnRowPiece {
    let ordinal: Int
    let origin: Int
    let end: Int
    let loopRows: PulledLoopRows?
}

/// The rows of a column of several as its scroll view reads them back: each
/// view of the column the fill placed, a loop's by its rows. Ordinals are the
/// report's own: the placed views and rows first, in the column's order, then
/// a uniform loop's rows (``TargetLayoutSpans/Uniform/firstOrdinal``); each
/// is named by the view or the row it stands for.
@MainActor
struct ColumnOfSeveralRows {
    let spans: TargetLayoutSpans
    let ids: @MainActor (Int) -> AnyHashable?

    /// `pieces`, in the column's order; `viewIDs` names a view of the column
    /// that is no loop.
    init(_ pieces: [ColumnRowPiece], viewIDs: StackRowIDs) {
        var placed: [TargetLayoutSpans.Span] = []
        var named: [(view: Int, row: Int?)] = []
        var loopIDs: [Int: @MainActor (Int) -> AnyHashable?] = [:]
        var uniform: (rows: TargetLayoutSpans.Uniform, ids: @MainActor (Int) -> AnyHashable?)?
        for piece in pieces {
            guard let loop = piece.loopRows else {
                if piece.end > piece.origin {
                    placed.append(.init(origin: piece.origin, length: piece.end - piece.origin, ordinal: named.count))
                    named.append((piece.ordinal, nil))
                }
                continue
            }
            loopIDs[piece.ordinal] = loop.ids
            // One loop's uniform rows keep their arithmetic, every row of
            // them; any other loop's are the rows it drew.
            if uniform == nil, let rows = loop.spans.uniform, loop.spans.placed.isEmpty {
                uniform = (rows, loop.ids)
                continue
            }
            let lines = piece.origin...max(piece.origin, piece.end - 1)
            for span in loop.spans.spans(overlapping: lines) where span.ordinal >= 0 {
                placed.append(.init(origin: span.origin, length: span.length, ordinal: named.count))
                named.append((piece.ordinal, span.ordinal))
            }
        }
        var spans = TargetLayoutSpans(placed: placed)
        let firstUniform = named.count
        if var rows = uniform?.rows {
            rows.firstOrdinal = firstUniform
            spans.uniform = rows
        }
        self.spans = spans
        let uniformIDs = uniform?.ids
        ids = { ordinal in
            guard ordinal >= 0 else { return nil }
            guard ordinal < named.count else { return uniformIDs?(ordinal - firstUniform) }
            let (view, row) = named[ordinal]
            guard let row else { return viewIDs.id(at: view) }
            return loopIDs[view]?(row)
        }
    }

    /// The ordinal of the row at column line `line`, the sample `.scrollPosition`
    /// reads back: the first row whose end lies past it — a line in a gap
    /// between rows belongs to the row below, as a stack drawn flat samples
    /// it — or, past them all, the last row of the band, the lines `band`.
    func sampled(at line: Int, band: ClosedRange<Int>) -> Int? {
        if line <= band.upperBound,
            let row = spans.spans(overlapping: line...band.upperBound).first(where: { line < $0.origin + $0.length })
        {
            return row.ordinal
        }
        return spans.spans(overlapping: band).last?.ordinal
    }
}

// MARK: - The eager column

/// A loop among a column of several's views whose rows the column can lay
/// out to report them, where it draws the loop whole: a loop too few to be a
/// pulled lazy stack, which draws every row (`ForEach.windowedColumn`).
@MainActor
protocol ColumnLoopRowsLaying {
    /// The loop's rows as the lazy stack it is drawn as lays them out at
    /// `width`, in its own lines, or `nil` when it is not drawn so; `context`
    /// is the loop's own.
    func laidOutLoopRows(width: Int, context: RenderContext) -> LaidOutLoopRows?
}

/// A loop's rows as laid out whole (``ColumnLoopRowsLaying``): their spans
/// and names, and the row holding a key, for a seek.
struct LaidOutLoopRows {
    let rows: PulledLoopRows
    let row: @MainActor (String) -> (y: Int, height: Int)?
}

@MainActor extension ForEach: ColumnLoopRowsLaying where Content: View {
    func laidOutLoopRows(width: Int, context: RenderContext) -> LaidOutLoopRows? {
        windowedColumn(context: context)?.laidOutRows(width: width, context: context.drawingImplicitColumn())
    }
}

@MainActor extension _VStackCore {
    /// This lazy stack's rows laid out whole at `width`, as its full walk
    /// lays them out (`naturalRowSlots`).
    fileprivate func laidOutRows(width: Int, context: RenderContext) -> LaidOutLoopRows {
        var rowsContext = context
        rowsContext.environment.scrollContentWindow = nil
        rowsContext.leaveScrollOrigin()
        let slots = naturalRowSlots(width: width, context: rowsContext)
        let spans = TargetLayoutSpans(
            placed: slots.enumerated().map { .init(origin: $1.y, length: $1.height, ordinal: $0) })
        let ids = StackRowIDs(
            resolveChildViewCollection(from: content, context: rowsContext), content: content,
            sectionsWhole: rowsContext.keepsSectionsWhole)
        return LaidOutLoopRows(rows: PulledLoopRows(spans: spans, ids: { ids.id(at: $0) })) { key in
            slots.first { $0.child.matchesSeekKey(key) }.map { ($0.y, $0.height) }
        }
    }

    /// The rows of this column of several drawn whole, its loops' by their
    /// rows, the children laid out `heights` tall as `appendVertically` places
    /// them — or `nil` when it is no column of several or holds no loop drawn
    /// so. Every row, as the flat stack's full walk reports them.
    func eagerColumnOfSeveralRows(heights: [Int], children: [ChildView], context: RenderContext)
        -> ColumnOfSeveralRows?
    {
        guard context.identity.isColumnOfSeveral else { return nil }
        var rowContext = context
        rowContext.environment.scrollContentWindow = nil
        var pieces: [ColumnRowPiece] = []
        var cursor = 0
        var placedAny = false
        var sawLoop = false
        for (index, height) in heights.enumerated() where height > 0 {
            if placedAny { cursor += spacing }
            placedAny = true
            let top = cursor
            cursor += height
            let child = children[index]
            guard !child.isSpacer else { continue }
            let loop = laidOutLoop(child, context: rowContext)
            if loop != nil { sawLoop = true }
            pieces.append(
                ColumnRowPiece(ordinal: index, origin: top, end: top + height, loopRows: loop?.rows.shifted(by: top)))
        }
        guard sawLoop else { return nil }
        return ColumnOfSeveralRows(pieces, viewIDs: targetRowIDs(context: context))
    }

    /// The place, in this column's lines, of the row holding `key` in a loop
    /// among a column of several's views drawn whole, laid out as `slots`.
    func columnOfSeveralLoopRow(holding key: String, in slots: [RowSlot], context: RenderContext)
        -> (y: Int, height: Int)?
    {
        guard context.identity.isColumnOfSeveral else { return nil }
        for slot in slots {
            if let row = laidOutLoop(slot.child, context: context)?.row(key) { return (slot.y + row.y, row.height) }
        }
        return nil
    }

    /// `child`'s rows, when it is a loop among a column of several's views.
    private func laidOutLoop(_ child: ChildView, context: RenderContext) -> LaidOutLoopRows? {
        guard child.isLoopAmongColumnOfSeveral, let loop = child.wrappedView as? any ColumnLoopRowsLaying else {
            return nil
        }
        return loop.laidOutLoopRows(width: context.availableWidth, context: child.renderContext(under: context))
    }
}

@MainActor extension ChildView {
    /// Whether this view of a column of several is a loop whose rows the
    /// column reports one by one (`ColumnOfSeveralRows`): a `ForEach`, or an
    /// `if` with one in a branch, which the column draws as a lazy stack of
    /// its own (`ForEach.staysWhole(in:)`).
    var isLoopAmongColumnOfSeveral: Bool { viewMayBeLoop(viewType) }
}

extension ViewIdentity {
    /// Whether this is the step a column of several views is drawn at
    /// (``_ImplicitColumnOfSeveral``).
    var isColumnOfSeveral: Bool {
        leafType.map { ObjectIdentifier($0) == ObjectIdentifier(_ImplicitColumnOfSeveral.self) } == true
    }
}
