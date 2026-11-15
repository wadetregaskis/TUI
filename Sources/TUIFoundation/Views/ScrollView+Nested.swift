//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollView+Nested.swift
//
//  SCROLL-FIT's nested scroll views (design 2a, P7). A vertical scroll view
//  in a vertical scroll view's content, given no height, is its content's
//  height and scrolls nothing: the scroll view around it does, so it draws no
//  bar of its own and its offset stays 0. It is the forward shape
//  (B-SCROLLFIT-12): its content is drawn in its place, reached by a
//  single-child step, so a request from the column above reaches a lazy
//  stack or a list in it as it reaches one written there plainly. Drawn as a
//  scroll view of its own, it was the viewport's height when its content was
//  shorter (two stacked split it 12/12) and the measuring ladder's first
//  rung, 4,096 lines, when it was taller, every row of that built each frame
//  and the rest scrolled by a bar of its own.
//
//  A scroll view across the outer one's axis (`ScrollView(.horizontal)` in a
//  vertical one's content) still scrolls across, and is its content's height
//  (`naturalHeight(proposal:ideal:context:)`), drawn whole.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension _ScrollViewCore {
    /// The context this scroll view's content is drawn in when the scroll
    /// view forwards it to the scroll view around it (the file header): under
    /// SCROLL-FIT's switch, a vertical, not horizontal, scroll view of the
    /// app's own in a vertical scroll view's content, given no height. `nil`
    /// anywhere else, where it is a scroll view.
    ///
    /// The content keeps the identity it has in a scroll view of its own (its
    /// child step under this view), and takes what a scroll view's content
    /// takes from it but the scrolling: its scroll observers, position
    /// binding and target-layout mark are this view's, not passed on
    /// (``contentContext(_:)``), and the outer scroll view's request passes
    /// through, a single-child step needing no relay.
    func forwardedContentContext(_ context: RenderContext) -> RenderContext? {
        guard axes == .vertical, !isChrome, context.environment.scrollFitsContent,
            context.scrollContentOriginDepth != 0, context.environment.fitsVerticalScrollContent,
            !context.hasExplicitHeight
        else { return nil }
        var forwarded = context.withChildIdentity(type: Content.self)
        if !forwarded.environment.scrollObservers.isEmpty { forwarded.environment.scrollObservers = ScrollObservers() }
        if forwarded.environment.scrollPositionBinding != nil { forwarded.environment.scrollPositionBinding = nil }
        if forwarded.environment.isScrollTargetLayout { forwarded.environment.isScrollTargetLayout = false }
        return forwarded
    }

    /// This view's size when it forwards its content (the file header): its
    /// content's height, at the width it is offered, as a scroll view takes
    /// that; `nil` when it is a scroll view.
    func forwardedSize(proposal: ProposedViewSize, context: RenderContext) -> ViewSize? {
        guard let forwarded = forwardedContentContext(context) else { return nil }
        var size = measureChild(content, proposal: proposal, context: forwarded)
        (size.width, size.isWidthFlexible) = (context.fillingWidth(proposal: proposal), true)
        return size
    }

    /// This view's drawing when it forwards its content: the content's, at
    /// the leading edge of the width it is given, as a scroll view places its
    /// content; `nil` when it is a scroll view.
    func forwardedDrawing(_ context: RenderContext) -> FrameBuffer? {
        guard let forwarded = forwardedContentContext(context) else { return nil }
        return TUIView.renderToBuffer(content, context: forwarded)
            .horizontallyAligned(toWidth: context.availableWidth, alignment: .leading)
    }

    /// This scroll view's height when it is asked how tall it would be with
    /// nothing to stop it — no height proposed, offered the natural-extent
    /// ladder's budget, given none — and does not forward: `.fixedSize`, or a
    /// horizontal scroll view in a vertical one's content. Its content's ideal
    /// height (`ideal`), where it answered the budget, flexibly: 4,096 lines
    /// in a scroll view, and under `.fixedSize` the height it was offered.
    /// `nil` anywhere else.
    func naturalHeight(proposal: ProposedViewSize, ideal: (width: Int, height: Int)?, context: RenderContext) -> Int? {
        guard context.environment.scrollFitsContent, proposal.height == nil, !context.hasExplicitHeight,
            isNaturalExtentBudget(context.availableHeight), let ideal
        else { return nil }
        return ideal.height
    }
}
