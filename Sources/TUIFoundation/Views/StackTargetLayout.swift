//  🖥️ TUI — A Terminal UI framework for Swift
//  StackTargetLayout.swift
//
//  How a stack marked with `scrollTargetLayout()` reports its rows or columns
//  to the scroll view whose content it is, for a scroll target behaviour to
//  settle on (`ScrollContentReply.targetLayoutRows` / `targetLayoutColumns`).
//  Asked only by a scroll view with a behaviour
//  (`ScrollContentWindow.reportsTargetLayout`), so every other stack pays a
//  test of its context, or of the window it already holds, and reads nothing
//  from the environment for it. The same extents, marked or not and with how
//  to name each, for a scroll view an `onScrollTargetVisibilityChange` is
//  stated above (`ScrollContentWindow.reportsTargetVisibility`).
//
//  Created by Wade Tregaskis
//  License: MIT

@MainActor extension _VStackCore {
    /// The rows of an EAGER (`.clip`) stack, from the heights its layout just
    /// gave them, placed as `appendVertically` places them — a gap only
    /// between rows that occupy a line. Spacers are not views to settle on.
    ///
    /// `window` is the one the stack consumes this render, already in hand
    /// (`resolveEagerSeek`).
    func reportEagerTargetLayout(
        heights: [Int], children: [ChildView], window: ScrollContentWindow?, context: RenderContext
    ) {
        guard let window, let reply = window.reply, let request = targetSpanRequest(window: window, context: context)
        else { return }
        var spans: [TargetLayoutSpans.Span] = []
        var cursor = 0
        var placedAny = false
        for (index, height) in heights.enumerated() where height > 0 {
            if placedAny { cursor += spacing }
            if !children[index].isSpacer { spans.append(.init(origin: cursor, length: height, ordinal: index)) }
            cursor += height
            placedAny = true
        }
        reply.deliverTargetRows(TargetLayoutSpans(placed: spans), for: request) { targetRowIDs(context: context) }
    }

    /// The row an EAGER stack shows at the report anchor
    /// (``ScrollContentWindow/reportsIDAt``), for `.scrollPosition(id:)` to read
    /// back: the stack is drawn whole, so every row's place is known from the
    /// heights its layout just gave them, placed as `appendVertically` places
    /// them. Asked only by a scroll view with a position bound, so every other
    /// stack pays a test of the window it already holds. Reported whether or
    /// not the stack is marked, as a windowed stack's rows are (decisions B29).
    func reportEagerSample(heights: [Int], window: ScrollContentWindow?, context: RenderContext) {
        guard let window, let unit = window.reportsIDAt, let reply = window.reply else { return }
        var rows: [(ordinal: Int, bottom: Int)] = []
        var cursor = 0
        for (ordinal, height) in heights.enumerated() where height > 0 {
            if !rows.isEmpty { cursor += spacing }
            cursor += height
            rows.append((ordinal, cursor))
        }
        guard let last = rows.last else { return }
        // Sampled where the frame shows the stack: at the offset a seek this
        // render resolved (`resolveEagerSeek`), which the scroll view adopts
        // without drawing the stack again. Sampled at the window's own, the
        // seek's frame wrote back the row the view was leaving, and the next
        // frame the row it showed: two writes for one request.
        var shown = window
        if let resolved = reply.seekResolvedOffset { shown.offset = resolved }
        let line = shown.sampleY(at: unit, contentBelow: shown.hasContentBelow(stackBottom: last.bottom))
        // The first row whose bottom lies past the sampled line (a line in an
        // inter-row gap belongs to the row below it), clamped to the last row.
        let ordinal = rows.first { line < $0.bottom }?.ordinal ?? last.ordinal
        var childContext = context
        childContext.environment.scrollContentWindow = nil
        reply.anchorID = resolveChildViewCollection(from: content, context: childContext)
            .reportedID(at: ordinal, content: content, sectionsWhole: childContext.keepsSectionsWhole)
    }

    /// The rows of the full walk (a lazy stack under the anchored threshold):
    /// its slots carry every row's true place.
    func reportTargetLayout(slots: [RowSlot], window: ScrollContentWindow, context: RenderContext) {
        guard let reply = window.reply, let request = targetSpanRequest(window: window, context: context)
        else { return }
        let spans = TargetLayoutSpans(
            placed: slots.enumerated().map { .init(origin: $1.y, length: $1.height, ordinal: $0) })
        reply.deliverTargetRows(spans, for: request) { targetRowIDs(context: context) }
    }

    /// The uniform window (`renderUniformSeekWindow`), and, when it drew the
    /// stack, its rows reported: every row is the hypothesis's height at a
    /// constant pitch, so its place is arithmetic, drawn or not.
    func renderUniformWindowReporting(
        _ children: ChildViewCollection, window: ScrollContentWindow, context: RenderContext
    ) -> FrameBuffer? {
        guard let drawn = renderUniformSeekWindow(children, window: window, context: context) else { return nil }
        guard let request = targetSpanRequest(window: window, context: context),
            let reply = window.reply, let extent = uniformWindowState(context: context).hypothesisExtent
        else { return drawn }
        let spans = TargetLayoutSpans(
            uniform: .init(origin: 0, pitch: extent + spacing, length: extent, total: children.count))
        reply.deliverTargetRows(spans, for: request) {
            StackRowIDs(children, content: content, sectionsWhole: context.keepsSectionsWhole)
        }
        return drawn
    }

    /// The rows of the anchored window's band, as it placed them — `nil` when
    /// no scroll view asked for them (``targetSpanRequest(window:context:)``).
    /// The path knows no row's place outside the band.
    func reportTargetLayout(
        _ spans: [TargetLayoutSpans.Span]?, request: TargetSpanRequest?, children: ChildViewCollection,
        into reply: ScrollContentReply, context: RenderContext
    ) {
        guard let spans, let request else { return }
        reply.deliverTargetRows(TargetLayoutSpans(placed: spans), for: request) {
            StackRowIDs(children, content: content, sectionsWhole: context.keepsSectionsWhole)
        }
    }

    /// What this stack reports its rows into `window` for, or `nil` for
    /// nothing: a behaviour's settling — the window asks, tested first, a
    /// field, and the stack is marked — and the visibility observers, which
    /// take any stack's rows (the rows `.scrollPosition` reads back are any
    /// stack's too, deviation R6).
    func targetSpanRequest(window: ScrollContentWindow, context: RenderContext) -> TargetSpanRequest? {
        guard window.reportsTargetLayout || window.reportsTargetVisibility else { return nil }
        let layout = window.reportsTargetLayout && context.environment.isScrollTargetLayout
        guard layout || window.reportsTargetVisibility else { return nil }
        return TargetSpanRequest(layout: layout, visibility: window.reportsTargetVisibility)
    }

    /// The ids of this stack's children, for the visibility observers.
    func targetRowIDs(context: RenderContext) -> StackRowIDs {
        var childContext = context
        childContext.environment.scrollContentWindow = nil
        return StackRowIDs(
            resolveChildViewCollection(from: content, context: childContext), content: content,
            sectionsWhole: childContext.keepsSectionsWhole)
    }
}

/// What a stack reports its rows or columns for (``_VStackCore/targetSpanRequest(window:context:)``).
struct TargetSpanRequest {
    /// For a scroll target behaviour to settle on: the stack is marked.
    let layout: Bool
    /// For `onScrollTargetVisibilityChange`, marked or not.
    let visibility: Bool
}

extension ScrollContentReply {
    /// Delivers a stack's rows for what `request` asked, with `ids` to name
    /// them made only when the visibility observers asked.
    @MainActor
    func deliverTargetRows(_ spans: TargetLayoutSpans, for request: TargetSpanRequest, ids: () -> StackRowIDs) {
        if request.layout { targetLayoutRows = spans }
        guard request.visibility else { return }
        targetVisibleRows = spans
        let resolver = ids()
        targetIDs = { resolver.id(at: $0) }
    }

    /// The same for a horizontal stack's columns.
    @MainActor
    func deliverTargetColumns(_ spans: TargetLayoutSpans, for request: TargetSpanRequest, ids: () -> StackRowIDs) {
        if request.layout { targetLayoutColumns = spans }
        guard request.visibility else { return }
        targetVisibleColumns = spans
        let resolver = ids()
        targetIDs = { resolver.id(at: $0) }
    }
}

extension RenderContext {
    /// Whether a view here is at the scroll content's origin — reached from a
    /// scroll view's content by single-child steps — answered from the context
    /// alone: what a horizontal stack tests before it reads the scroll window
    /// from the environment to ask whether its columns are wanted, which they
    /// almost never are. A necessary condition of
    /// ``ScrollContentWindow/isAtOrigin(_:)``, which compares the lineage too.
    var mayConsumeScrollWindow: Bool {
        let origin = scrollContentOriginDepth
        guard origin != 0, origin != Self.belowScrollContentOrigin else { return false }
        return identity.isDirectDescent(fromDepth: Int(origin) - 1)
    }

    /// This context with its scroll window as content drawn `leading`
    /// columns further right sees it (``ScrollContentWindow/across(leading:)``):
    /// written only where a column is sampled for the read-back, the one
    /// thing the window says across.
    func withScrollWindowAcross(leading: Int) -> RenderContext {
        guard leading != 0, let window = environment.scrollContentWindow, window.columnReport != nil else { return self }
        var context = self
        context.environment.scrollContentWindow = window.across(leading: leading)
        return context
    }
}

@MainActor extension _HStackCore {
    /// The lazy row's report: its columns as its walk placed them, each after
    /// the gap the walk gave it.
    func reportTargetLayout(collected: [(FrameBuffer, Int, ChildView?)], context: RenderContext) {
        guard let (reply, request) = targetLayoutReply(context: context) else { return }
        var spans: [TargetLayoutSpans.Span] = []
        var cursor = 0
        var ordinal = 0
        // The walk decided each entry's gap: a column after its gap, and a
        // spacer or a clipped tail's gap no view to settle on.
        for (buffer, gap, child) in collected {
            cursor += gap
            if child != nil {
                if buffer.width > 0 { spans.append(.init(origin: cursor, length: buffer.width, ordinal: ordinal)) }
                ordinal += 1
            }
            cursor += buffer.width
        }
        reply.deliverTargetColumns(TargetLayoutSpans(placed: spans), for: request) { targetColumnIDs(context: context) }
    }

    /// The columns of an EAGER (`.clip`) row: each child's rendered buffer —
    /// a spacer's (`nil`) the width the layout gave it — placed as
    /// `appendHorizontally` places it, a gap only once a column has drawn cells
    /// and none for one that draws none. Spacers are not views to settle on.
    func reportTargetLayout(
        buffers: [FrameBuffer?], spacerWidths: [Int], gaps: StackGaps, context: RenderContext
    ) {
        guard let (reply, request) = targetLayoutReply(context: context) else { return }
        var spans: [TargetLayoutSpans.Span] = []
        var cursor = 0
        var walk = StackGapWalk(gaps)
        for (index, buffer) in buffers.enumerated() {
            let width = buffer?.width ?? spacerWidths[index]
            guard width > 0 else { continue }
            cursor += walk.gap(before: index, extent: width)
            walk.place(index, extent: width)
            if buffer != nil { spans.append(.init(origin: cursor, length: width, ordinal: index)) }
            cursor += width
        }
        reply.deliverTargetColumns(TargetLayoutSpans(placed: spans), for: request) { targetColumnIDs(context: context) }
    }

    /// The reply this row reports its columns into, and what for, or `nil`
    /// when none asks: a render pass at the scroll content's origin (the
    /// context's test, read first), whose window asks (a field), for a
    /// behaviour of a row marked with `scrollTargetLayout()` (the
    /// environment, read last) or for the visibility observers.
    private func targetLayoutReply(context: RenderContext) -> (ScrollContentReply, TargetSpanRequest)? {
        guard !context.isMeasuring, context.mayConsumeScrollWindow,
            let window = context.environment.scrollContentWindow,
            window.reportsTargetLayout || window.reportsTargetVisibility,
            window.isAtOrigin(context.identity), let reply = window.reply
        else { return nil }
        let layout = window.reportsTargetLayout && context.environment.isScrollTargetLayout
        guard layout || window.reportsTargetVisibility else { return nil }
        return (reply, TargetSpanRequest(layout: layout, visibility: window.reportsTargetVisibility))
    }

    /// The ids of this row's children, for the visibility observers.
    private func targetColumnIDs(context: RenderContext) -> StackRowIDs {
        var childContext = context
        childContext.environment.scrollContentWindow = nil
        return StackRowIDs(
            resolveChildViewCollection(from: content, context: childContext), content: content,
            sectionsWhole: childContext.keepsSectionsWhole)
    }
}

// MARK: - A Column Sought

@MainActor extension _HStackCore {
    /// Where the column a purely horizontal scroll view seeks sits in a LAZY
    /// row (``ScrollContentWindow/columnSeek``): its place as the walk put it,
    /// for the scroll view to move to. Placed as ``reportTargetLayout(collected:context:)``
    /// places columns.
    func resolveColumnSeek(collected: [(FrameBuffer, Int, ChildView?)], context: RenderContext) {
        guard let (reply, seek) = columnSeekReply(context: context) else { return }
        var cursor = 0
        for (buffer, gap, child) in collected {
            cursor += gap
            if let child, buffer.width > 0, child.matchesSeekKey(seek.key) {
                reply.seekResolvedColumn = .init(origin: cursor, length: buffer.width)
                return
            }
            cursor += buffer.width
        }
    }

    /// Where the column a purely horizontal scroll view seeks sits in an EAGER
    /// row, placed as ``reportTargetLayout(buffers:spacerWidths:gaps:context:)``
    /// places columns. A spacer is no column to seek.
    func resolveColumnSeek(
        buffers: [FrameBuffer?], spacerWidths: [Int], gaps: StackGaps, children: [ChildView], context: RenderContext
    ) {
        guard let (reply, seek) = columnSeekReply(context: context) else { return }
        var cursor = 0
        var walk = StackGapWalk(gaps)
        for (index, buffer) in buffers.enumerated() {
            let width = buffer?.width ?? spacerWidths[index]
            guard width > 0 else { continue }
            cursor += walk.gap(before: index, extent: width)
            walk.place(index, extent: width)
            if buffer != nil, children[index].matchesSeekKey(seek.key) {
                reply.seekResolvedColumn = .init(origin: cursor, length: width)
                return
            }
            cursor += width
        }
    }

    /// The column an EAGER row shows at a purely horizontal scroll view's report
    /// anchor (``ScrollContentWindow/columnReport``), for `.scrollPosition(id:)`
    /// to read back: placed as ``resolveColumnSeek(buffers:spacerWidths:gaps:children:context:)``
    /// places columns. A spacer is no column to report.
    func reportColumnSample(
        buffers: [FrameBuffer?], spacerWidths: [Int], gaps: StackGaps, context: RenderContext
    ) {
        guard let (reply, report) = columnReportReply(context: context) else { return }
        var columns: [(ordinal: Int, end: Int)] = []
        var cursor = 0
        var walk = StackGapWalk(gaps)
        for (index, buffer) in buffers.enumerated() {
            let width = buffer?.width ?? spacerWidths[index]
            guard width > 0 else { continue }
            cursor += walk.gap(before: index, extent: width)
            walk.place(index, extent: width)
            cursor += width
            if buffer != nil { columns.append((index, cursor)) }
        }
        reportColumn(columns, at: report, into: reply, context: context)
    }

    /// The same for a LAZY row, from the columns it placed — every one, in a
    /// horizontal scroll view, which lays its content out whole and clips it.
    func reportColumnSample(collected: [(FrameBuffer, Int, ChildView?)], context: RenderContext) {
        guard let (reply, report) = columnReportReply(context: context) else { return }
        var columns: [(ordinal: Int, end: Int)] = []
        var cursor = 0
        var ordinal = 0
        for (buffer, gap, child) in collected {
            cursor += gap + buffer.width
            guard child != nil else { continue }
            if buffer.width > 0 { columns.append((ordinal, cursor)) }
            ordinal += 1
        }
        reportColumn(columns, at: report, into: reply, context: context)
    }

    /// Reports the id of the column under the report's sample: the first whose
    /// trailing edge lies past it, clamped to the last.
    private func reportColumn(
        _ columns: [(ordinal: Int, end: Int)], at report: ScrollContentWindow.ColumnReport,
        into reply: ScrollContentReply, context: RenderContext
    ) {
        guard let last = columns.last else { return }
        let x = report.sampleX
        let ordinal = columns.first { x < $0.end }?.ordinal ?? last.ordinal
        var childContext = context
        childContext.environment.scrollContentWindow = nil
        reply.anchorID = resolveChildViewCollection(from: content, context: childContext)
            .reportedID(at: ordinal, content: content, sectionsWhole: childContext.keepsSectionsWhole)
    }

    /// The reply a reported column goes into, with what asks for it, or `nil`
    /// when none is asked for here — as ``columnSeekReply(context:)`` finds a
    /// sought one.
    private func columnReportReply(context: RenderContext) -> (ScrollContentReply, ScrollContentWindow.ColumnReport)? {
        guard !context.isMeasuring, context.mayConsumeScrollWindow,
            let window = context.environment.scrollContentWindow, let report = window.columnReport,
            window.isAtOrigin(context.identity), let reply = window.reply
        else { return nil }
        return (reply, report)
    }

    /// The reply a sought column is reported into, with the request, or `nil`
    /// when none is sought here: a render pass at the scroll content's origin
    /// (the context's test, read first, as ``targetLayoutReply(context:)``
    /// reads it) whose window carries a column seek.
    private func columnSeekReply(context: RenderContext) -> (ScrollContentReply, ScrollToRequest)? {
        guard !context.isMeasuring, context.mayConsumeScrollWindow,
            let window = context.environment.scrollContentWindow, let seek = window.columnSeek,
            window.isAtOrigin(context.identity), let reply = window.reply
        else { return nil }
        return (reply, seek)
    }
}
