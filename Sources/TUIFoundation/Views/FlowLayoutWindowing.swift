//  🖥️ TUI — A Terminal UI framework for Swift
//  FlowLayoutWindowing.swift
//
//  SCROLL-FIT P8 for `FlowLayout` (design §1c, the owner's A-SCROLLFIT-5 (a)):
//  past the lazy stack's threshold, in scroll content, a flow measures every
//  item, breaks its lines from the top as it always has, and draws those
//  lines as the rows of a lazy stack — so the scroll view's request pulls it
//  as it pulls a column, and only the items on the lines on screen are drawn.
//
//  Measuring every item is what a line break needs: a line's first item
//  depends on every item before it. A loop over equatable data keeps each
//  row's measure from frame to frame (`measureValueMemoized`), so a frame that
//  changes neither the data nor the width builds no item to measure it; the
//  first frame, and one after a change, measures them all, with no `onAppear`
//  (a measure runs none). Lines are always the ones a top-down wrap makes.
//
//  Each item draws at the identity it draws at when the flow is drawn whole,
//  under the flow, not under its line: a line break that moves when the data
//  or the width changes moves no item's state or focus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// One line of a windowed flow: its items, where each sits in the line, and
/// the line's size, every line as wide as the flow.
@MainActor
struct FlowLineRun: Identifiable {
    /// The line's place among the flow's lines.
    let id: Int
    let members: [(child: ChildView, x: Int, y: Int, size: ViewSize)]
    let width: Int
    let height: Int
}

/// A windowed flow's line drawn as a lazy stack's row: its items at their
/// places, each at the identity it has under the flow at `parent`.
nonisolated struct _FlowLine: View, Renderable, Layoutable {
    let run: FlowLineRun
    let parent: ViewIdentity

    @MainActor var body: Never {
        fatalError("_FlowLine renders via Renderable")
    }

    @MainActor func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(run.width, run.height)
    }

    @MainActor func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The items are the flow's children, not the line's.
        var items = context
        items.identity = parent
        var result = FrameBuffer(emptyWithWidth: run.width, height: run.height)
        let environment = CompositeEnvironment(context.environment)
        for member in run.members {
            let picture = member.child.render(
                width: member.size.width, height: member.size.height,
                context: items.placingChild(gradient: nil, x: member.x, y: member.y))
            result.compositeCarryingClaimsOverNothing(with: picture, at: (x: member.x, y: member.y), in: environment)
        }
        return result
    }
}

@MainActor extension _LayoutCore {
    /// The height a windowed flow measures its items' lines at
    /// (``windowedFlow(width:context:)``).
    static var flowItemMeasureHeight: Int { 1 << 16 }

    /// The lazy stack a `FlowLayout` of more items than a lazy stack draws
    /// whole is drawn as in scroll content, its lines broken at `width`;
    /// `nil` for any other layout, a smaller flow, or one outside scroll
    /// content, which is laid out whole as before.
    func windowedFlow(width: Int, context: RenderContext) -> _VStackCore<ForEach<[FlowLineRun], Int, _FlowLine>>? {
        guard let flow = layout as? FlowLayout, context.scrollContentOriginDepth != 0,
            !context.environment.drawsContainerRowsWhole,
            resolveChildViewCollection(from: content, context: context).count
                > _VStackCore<EmptyView>.anchoredWindowThreshold
        else { return nil }
        // The items are measured for their lines at one height whatever the
        // pass: the scroll view's measures and its render offer the content
        // different heights, and an item's measure kept from frame to frame is
        // keyed by the height offered, so each pass would measure them all
        // again. An item's size at `.unspecified` is its own.
        var measuring = context
        measuring.availableHeight = Self.flowItemMeasureHeight
        // Those measures are kept for items that are not drawn, and an entry
        // whose view no pass marked is pruned (`RenderCache.removeInactive`):
        // the flow keeps its subtree's, as a lazy stack keeps its rows' state.
        if !context.isMeasuring {
            context.renderCache?.retainSubtree(context.identity)
            context.stateStorage?.retainSubtree(context.identity)
        }
        let subviews = LayoutSubviews(
            children: resolveChildViews(from: content, context: measuring), context: measuring,
            placements: LayoutPlacements(), rowIDs: FlattenedRowIDs<AnyHashable>(content: content, children: []),
            mayStateSpacing: Content._statesSpacingPreference)
        let lines = flow.lines(of: subviews, width: width)
        let widest = lines.map(\.width).max() ?? 0
        let flowWidth = min(widest, width)
        let runs = lines.enumerated().map { ordinal, line in
            let lineX = flow.alignment.horizontal.childOffset(childWidth: line.width, in: flowWidth)
            return FlowLineRun(
                id: ordinal,
                members: line.members.map { member in
                    (
                        child: subviews.children[member.index], x: lineX + member.x,
                        y: flow.alignment.vertical.childOffset(childHeight: member.size.height, in: line.height),
                        size: member.size
                    )
                },
                width: flowWidth, height: line.height)
        }
        let parent = context.identity
        return _VStackCore(
            alignment: .leading, spacing: flow.lineGap, overflow: .window,
            content: ForEach(runs) { _FlowLine(run: $0, parent: parent) })
    }
}
