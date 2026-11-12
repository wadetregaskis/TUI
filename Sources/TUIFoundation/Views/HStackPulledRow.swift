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
    /// Laid out as the eager row is (`resolvedLayout`): across by its widths,
    /// down by the alignment — or the explicit guides' run — at each child's
    /// measured height; each child's band then drawn where the eager row puts
    /// it, through the same z-order and glide the eager row draws with
    /// (`glidingStackBuffer`, `zOrderedStackBuffer`).
    func renderPulledRow(context: RenderContext) -> FrameBuffer? {
        guard !context.isMeasuring, let window = context.environment.scrollContentWindow, window.reply != nil,
            window.isAtOrigin(context.identity),
            let cache = context.renderCache, cache.pullConsumers.kind(of: context.identity) == .pullsChildren
        else { return nil }
        let split = stackChildren(of: content, context: context)
        let children = split.laidOut
        guard !children.isEmpty else { return nil }
        let gaps = gaps(between: children, context: context)
        let layout = resolvedLayout(children, gaps: gaps, availableWidth: context.availableWidth, context: context)
        let rowHeight = max(1, layout.height)
        // An explicit guide's run names a top for each child the row places
        // (spacers have none), as the eager row's placement reads it.
        var guided: [Int: Int] = [:]
        if let run = layout.guideRun {
            for (placedIndex, index) in children.indices.filter({ !children[$0].isSpacer }).enumerated() {
                guided[index] = run.offsets[placedIndex]
            }
        }
        let placed = children.indices.map { index -> PulledParallelChild in
            let height = layout.childHeights[index]
            let slack = max(0, rowHeight - height)
            let y =
                guided[index]
                ?? {
                    switch alignment {
                    case .top: 0
                    case .bottom: slack
                    default: slack / 2
                    }
                }()
            let identity = children[index].identity(under: context)
            return PulledParallelChild(
                identity: identity, y: y, height: height,
                isPulled: !children[index].isSpacer && cache.pullConsumers.holdsConsumer(below: identity))
        }
        guard
            let band = PulledParallel.fill(
                window: window, children: placed, state: pulledRowState(context: context), context: context,
                holder: { PulledParallel.holder(of: $0, count: children.count, child: { children[$0] }, context: context) },
                place: { index, seek in
                    PulledParallel.place(
                        of: seek, in: children[index], width: layout.widths[index],
                        height: layout.childHeights[index], context: context)
                },
                render: { index, childContext, height in
                    children[index].isSpacer
                        ? FrameBuffer(emptyWithWidth: layout.widths[index], height: 0)
                        : children[index].render(width: layout.widths[index], height: height, context: childContext)
                })
        else { return nil }
        let pieces = children.indices.map { index in children[index].isSpacer ? nil : band.pieces[index] }
        let columns = pieces.map { $0?.column }
        // Across, where the eager row puts each child; down, where the fill
        // put it in the band.
        let row = rowPlacements(
            buffers: columns, widths: layout.widths, gaps: gaps, rowHeight: band.height, guideRun: nil)
        let clampHeight = max(band.height, context.availableHeight)
        // In z-order, or gliding, each piece is drawn as it is at its place,
        // its blank lines above and below the band's no cover over a sibling.
        let targets = children.indices.map { index in
            ChildPlacement(x: row.targets[index].x, y: pieces[index]?.y ?? 0)
        }
        let drawn = pieces.map { $0?.buffer }
        if let layered = context.glidingStackBuffer(
            children, buffers: drawn, at: targets, departing: split.departing, width: row.width,
            height: row.height)
            ?? context.zOrderedStackBuffer(children, buffers: drawn, at: targets, width: row.width, height: row.height)
        {
            return layered.clamped(toWidth: context.availableWidth, height: clampHeight)
        }
        var result = FrameBuffer()
        var walk = StackGapWalk(gaps)
        for index in children.indices {
            let piece = columns[index] ?? FrameBuffer(emptyWithWidth: layout.widths[index], height: band.height)
            result.appendHorizontally(piece, spacing: walk.gap(before: index, extent: piece.width))
            walk.place(index, extent: piece.width)
        }
        return result.clamped(toWidth: context.availableWidth, height: clampHeight)
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
