//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackTargetLayout.swift
//
//  How a stack marked with `scrollTargetLayout()` reports its rows or columns
//  to the scroll view whose content it is, for a scroll target behaviour to
//  settle on (`ScrollContentReply.targetLayoutRows` / `targetLayoutColumns`).
//  Asked only by a scroll view with a behaviour
//  (`ScrollContentWindow.reportsTargetLayout`), so every other stack pays a
//  test of its context, or of the window it already holds, and reads nothing
//  from the environment for it.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _VStackCore {
    /// The rows of an EAGER (`.clip`) stack, from the heights its layout just
    /// gave them, placed as `appendVertically` places them — a gap only
    /// between rows that occupy a line. Spacers are not views to settle on.
    ///
    /// `window` is the one the stack consumes this render, already in hand
    /// (`resolveEagerSeek`).
    func reportEagerTargetLayout(
        heights: [Int], children: [ChildView], window: ScrollContentWindow?, context: RenderContext
    ) {
        guard let window, let reply = window.reply, reportsTargetLayout(window: window, context: context)
        else { return }
        var spans: [TargetLayoutSpans.Span] = []
        var cursor = 0
        var placedAny = false
        for (index, height) in heights.enumerated() where height > 0 {
            if placedAny { cursor += spacing }
            if !children[index].isSpacer { spans.append(.init(origin: cursor, length: height)) }
            cursor += height
            placedAny = true
        }
        reply.targetLayoutRows = TargetLayoutSpans(placed: spans)
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
        let line = window.sampleY(at: unit, contentBelow: window.hasContentBelow(stackBottom: last.bottom))
        // The first row whose bottom lies past the sampled line (a line in an
        // inter-row gap belongs to the row below it), clamped to the last row.
        let ordinal = rows.first { line < $0.bottom }?.ordinal ?? last.ordinal
        var childContext = context
        childContext.environment.scrollContentWindow = nil
        reply.anchorID = resolveChildViewCollection(from: content, context: childContext).anyID(at: ordinal)
    }

    /// The rows of the full walk (a lazy stack under the anchored threshold):
    /// its slots carry every row's true place.
    func reportTargetLayout(slots: [RowSlot], window: ScrollContentWindow, context: RenderContext) {
        guard reportsTargetLayout(window: window, context: context) else { return }
        window.reply?.targetLayoutRows = TargetLayoutSpans(
            placed: slots.map { .init(origin: $0.y, length: $0.height) })
    }

    /// The uniform window (`renderUniformSeekWindow`), and, when it drew the
    /// stack, its rows reported: every row is the hypothesis's height at a
    /// constant pitch, so its place is arithmetic, drawn or not.
    func renderUniformWindowReporting(
        _ children: ChildViewCollection, window: ScrollContentWindow, context: RenderContext
    ) -> FrameBuffer? {
        guard let drawn = renderUniformSeekWindow(children, window: window, context: context) else { return nil }
        guard reportsTargetLayout(window: window, context: context),
            let reply = window.reply, let extent = uniformWindowState(context: context).hypothesisExtent
        else { return drawn }
        reply.targetLayoutRows = TargetLayoutSpans(
            uniform: .init(origin: 0, pitch: extent + spacing, length: extent, total: children.count))
        return drawn
    }

    /// The rows of the anchored window's band, as it placed them — `nil` when
    /// no scroll view asked for them (``reportsTargetLayout(window:context:)``).
    /// The path knows no row's place outside the band.
    func reportTargetLayout(_ spans: [TargetLayoutSpans.Span]?, into reply: ScrollContentReply) {
        guard let spans else { return }
        reply.targetLayoutRows = TargetLayoutSpans(placed: spans)
    }

    /// Whether this stack reports its rows into `window`: the window asks —
    /// tested first, a field — and the stack is marked.
    func reportsTargetLayout(window: ScrollContentWindow, context: RenderContext) -> Bool {
        window.reportsTargetLayout && context.environment.isScrollTargetLayout
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
}

extension _HStackCore {
    /// The lazy row's report: its columns as its walk placed them, each after
    /// the gap the walk gave it.
    func reportTargetLayout(collected: [(FrameBuffer, Int, ChildView?)], context: RenderContext) {
        guard let reply = targetLayoutReply(context: context) else { return }
        var spans: [TargetLayoutSpans.Span] = []
        var cursor = 0
        // The walk decided each entry's gap: a column after its gap, and a
        // spacer or a clipped tail's gap no view to settle on.
        for (buffer, gap, child) in collected {
            cursor += gap
            if child != nil, buffer.width > 0 { spans.append(.init(origin: cursor, length: buffer.width)) }
            cursor += buffer.width
        }
        reply.targetLayoutColumns = TargetLayoutSpans(placed: spans)
    }

    /// The columns of an EAGER (`.clip`) row: each child's rendered buffer —
    /// a spacer's (`nil`) the width the layout gave it — placed as
    /// `appendHorizontally` places it, a gap only once a column has drawn cells
    /// and none for one that draws none. Spacers are not views to settle on.
    func reportTargetLayout(
        buffers: [FrameBuffer?], spacerWidths: [Int], gaps: StackGaps, context: RenderContext
    ) {
        guard let reply = targetLayoutReply(context: context) else { return }
        var spans: [TargetLayoutSpans.Span] = []
        var cursor = 0
        var walk = StackGapWalk(gaps)
        for (index, buffer) in buffers.enumerated() {
            let width = buffer?.width ?? spacerWidths[index]
            guard width > 0 else { continue }
            cursor += walk.gap(before: index, extent: width)
            walk.place(index, extent: width)
            if buffer != nil { spans.append(.init(origin: cursor, length: width)) }
            cursor += width
        }
        reply.targetLayoutColumns = TargetLayoutSpans(placed: spans)
    }

    /// The reply this row reports its columns into, or `nil` when none asks:
    /// a render pass at the scroll content's origin (the context's test, read
    /// first), whose window asks (a field), and a row marked with
    /// `scrollTargetLayout()` (the environment, read last).
    private func targetLayoutReply(context: RenderContext) -> ScrollContentReply? {
        guard !context.isMeasuring, context.mayConsumeScrollWindow,
            let window = context.environment.scrollContentWindow, window.reportsTargetLayout,
            window.isAtOrigin(context.identity), let reply = window.reply,
            context.environment.isScrollTargetLayout
        else { return nil }
        return reply
    }
}

// MARK: - A Column Sought

extension _HStackCore {
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
