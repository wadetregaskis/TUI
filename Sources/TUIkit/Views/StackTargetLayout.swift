//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackTargetLayout.swift
//
//  How a stack marked with `scrollTargetLayout()` reports its rows or columns
//  to the scroll view whose content it is, for a scroll target behaviour to
//  settle on (`ScrollContentReply.targetLayoutRows` / `targetLayoutColumns`).
//  Asked only by a scroll view with a behaviour
//  (`ScrollContentWindow.reportsTargetLayout`), so every other stack pays the
//  one test.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _VStackCore {
    /// The rows of an EAGER (`.clip`) stack, from the heights its layout just
    /// gave them, placed as `appendVertically` places them — a gap only
    /// between rows that occupy a line. Spacers are not views to settle on.
    func reportEagerTargetLayout(heights: [Int], children: [ChildView], context: RenderContext) {
        guard !context.isMeasuring, context.environment.isScrollTargetLayout,
            let window = consumableScrollWindow(context: context), window.reportsTargetLayout,
            let reply = window.reply
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

    /// The rows of the full walk (a lazy stack under the anchored threshold):
    /// its slots carry every row's true place.
    func reportTargetLayout(slots: [RowSlot], window: ScrollContentWindow, context: RenderContext) {
        guard window.reportsTargetLayout, context.environment.isScrollTargetLayout else { return }
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
        guard window.reportsTargetLayout, context.environment.isScrollTargetLayout,
            let reply = window.reply, let extent = uniformWindowState(context: context).hypothesisExtent
        else { return drawn }
        reply.targetLayoutRows = TargetLayoutSpans(
            uniform: .init(origin: 0, pitch: extent + spacing, length: extent, total: children.count))
        return drawn
    }

    /// The rows of the anchored window's band, as it placed them: the path
    /// knows no row's place outside the band.
    func reportTargetLayout(
        _ spans: [TargetLayoutSpans.Span], into reply: ScrollContentReply, window: ScrollContentWindow,
        context: RenderContext
    ) {
        guard window.reportsTargetLayout, context.environment.isScrollTargetLayout else { return }
        reply.targetLayoutRows = TargetLayoutSpans(placed: spans)
    }
}

extension _HStackCore {
    /// The lazy row's report: its columns as its walk placed them, each after
    /// the gap the walk gave it.
    func reportTargetLayout(collected: [(FrameBuffer, Int, ChildView?)], context: RenderContext) {
        guard !context.isMeasuring, context.environment.isScrollTargetLayout,
            let window = context.environment.scrollContentWindow, window.reportsTargetLayout,
            window.isAtOrigin(context.identity), let reply = window.reply
        else { return }
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
    func reportTargetLayout(buffers: [FrameBuffer?], spacerWidths: [Int], context: RenderContext) {
        guard !context.isMeasuring, context.environment.isScrollTargetLayout,
            let window = context.environment.scrollContentWindow, window.reportsTargetLayout,
            window.isAtOrigin(context.identity), let reply = window.reply
        else { return }
        var spans: [TargetLayoutSpans.Span] = []
        var cursor = 0
        for (index, buffer) in buffers.enumerated() {
            let width = buffer?.width ?? spacerWidths[index]
            guard width > 0 else { continue }
            if cursor > 0 { cursor += spacing }
            if buffer != nil { spans.append(.init(origin: cursor, length: width)) }
            cursor += width
        }
        reply.targetLayoutColumns = TargetLayoutSpans(placed: spans)
    }
}
