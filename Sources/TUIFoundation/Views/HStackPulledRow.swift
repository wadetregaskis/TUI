//  🖥️ TUI — A Terminal UI framework for Swift
//  HStackPulledRow.swift
//
//  SCROLL-FIT's parallel shape through a row (design B-SCROLLFIT-12): an
//  `HStack` holding a pulled view — `HStack { gutter; LazyVStack(10k) }` in
//  scroll content — hands the scroll view's request to each pulled child at
//  its place in the row and draws the band of every child, each laid out
//  across as the row lays it out (`ScrollParallelFill.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// `StateStorage` property indices for `_HStackCore` (file-scope: a generic
/// type cannot hold static storage).
private enum HStackStateIndex {
    /// The pulled row's positions (``PulledParallelState``). Negative: the
    /// box lives at the row's own identity, at which a lone composite child is
    /// drawn. Range -220, claimed in ``StateStorage/StateKey``'s table.
    static let pulledRow = -220
}

/// A lazy stack in a row is pulled because the row hands its request on.
/// Both overflows: a `LazyHStack` holding a pulled view places its columns as
/// the eager row does while it does, since a type cannot say which it is.
extension _HStackCore: ScrollPlacing {}

@MainActor extension _HStackCore {
    /// The band a request asks of this row, when it holds a pulled view and a
    /// request reaches it (its own measure filed it, `notePulledContainer`);
    /// `nil` otherwise, and the row draws its children whole.
    ///
    /// Laid out across as the eager row is (`resolvedLayout`), each child
    /// standing at its alignment's place at its measured height. What the
    /// eager row adds for a glide, a z-index or an explicit alignment guide is
    /// left out: a row holding a lazy stack of thousands of rows is drawn
    /// against its band instead.
    func renderPulledRow(context: RenderContext) -> FrameBuffer? {
        guard !context.isMeasuring, let window = context.environment.scrollContentWindow, window.reply != nil,
            window.isAtOrigin(context.identity),
            let cache = context.renderCache, cache.pullConsumers.kind(of: context.identity) == .pullsChildren
        else { return nil }
        let children = stackChildren(of: content, context: context).laidOut
        guard !children.isEmpty else { return nil }
        let gaps = gaps(between: children, context: context)
        let layout = resolvedLayout(children, gaps: gaps, availableWidth: context.availableWidth, context: context)
        let rowHeight = max(1, layout.height)
        let placed = children.indices.map { index -> PulledParallelChild in
            let height = layout.childHeights[index]
            let slack = max(0, rowHeight - height)
            let y =
                switch alignment {
                case .top: 0
                case .bottom: slack
                default: slack / 2
                }
            let identity = children[index].identity(under: context)
            return PulledParallelChild(
                identity: identity, y: y, height: height,
                isPulled: !children[index].isSpacer && cache.pullConsumers.holdsConsumer(below: identity))
        }
        guard
            let pieces = PulledParallel.fill(
                window: window, children: placed, state: pulledRowState(context: context), context: context,
                render: { index, childContext, height in
                    children[index].isSpacer
                        ? FrameBuffer(emptyWithWidth: layout.widths[index], height: 0)
                        : children[index].render(width: layout.widths[index], height: height, context: childContext)
                })
        else { return nil }
        let bandHeight = pieces.lazy.compactMap { $0?.height }.first ?? 0
        var result = FrameBuffer()
        var walk = StackGapWalk(gaps)
        for index in children.indices {
            let piece = pieces[index] ?? FrameBuffer(emptyWithWidth: layout.widths[index], height: bandHeight)
            result.appendHorizontally(piece, spacing: walk.gap(before: index, extent: piece.width))
            walk.place(index, extent: piece.width)
        }
        return result.clamped(toWidth: context.availableWidth, height: max(bandHeight, context.availableHeight))
    }

    /// The pulled row's positions, kept at its own identity.
    private func pulledRowState(context: RenderContext) -> PulledParallelState {
        let stateStorage = context.stateStorage!
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: HStackStateIndex.pulledRow)
        let box: StateBox<PulledParallelState> = stateStorage.storage(for: key, default: PulledParallelState())
        // Nothing else marks the row's own identity active (as for a column's
        // window state, `uniformWindowState`).
        stateStorage.markActive(context.identity)
        return box.value
    }
}
