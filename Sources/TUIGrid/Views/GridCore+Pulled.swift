//  🖥️ TUI — A Terminal UI framework for Swift
//  GridCore+Pulled.swift
//
//  SCROLL-FIT's pull through a `Grid` (design §1c, P8's leftovers): a grid
//  holding a pulled view in a cell — `Grid { GridRow { gutter; LazyVStack(10k)
//  }; GridRow { … } }` in scroll content — is served by its lattice's places,
//  as an app's `Layout` is by its placements (`LayoutCore+Pulled.swift`): the
//  cells beside the pulled one in the parallel shape, the rows wholly below
//  it following where its drawing ends, not where the lattice's estimate put
//  them. A grid whose places cannot be served that way — pulled cells one
//  above another — is drawn whole, its lazy stacks drawn whole in it, as
//  before.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// `StateStorage` property indices for `_GridCore` (file-scope: a generic
/// type cannot hold static storage).
private enum GridStateIndex {
    /// The pulled grid's positions. Negative: a lone composite cell is drawn
    /// at the grid's own identity. Range -220, claimed in
    /// ``StateStorage/StateKey``'s table.
    static let pulledGrid = -223
}

/// A lazy stack in a grid's cell is pulled because the grid hands its
/// request on, unless its places say it cannot, when it is filed as drawn
/// whole (``LayoutPull/serves(context:placed:)``) and its stacks are not.
extension _GridCore: ScrollPlacing {}

/// A row's cells are laid out among the grid's, as an `if`'s view is among
/// its container's children: a row is no container of its own, so a pulled
/// view in one of its cells is pulled by whatever lays the cells out — the
/// grid, or the stack a row stands in outside one.
extension GridRow: ScrollPlacing {}

@MainActor extension _GridCore {
    /// Whether this grid, measured as holding a pulled view in a cell, can be
    /// served by the lattice's places (``LayoutPull/serves(context:placed:)``);
    /// `true` when it holds none. When not, it is filed as drawn whole, and
    /// the caller measures again.
    func servesPull(_ rows: [Row], lattice: GridLattice, context: RenderContext) -> Bool {
        guard context.notePulledContainer(holding: { rows.flatMap(\.cells).map { $0.identity(under: context) } })
        else { return true }
        return LayoutPull.serves(context: context) { placedCells(rows, lattice: lattice, context: context) }
    }

    /// The band a request asks of this grid, when it holds a pulled view and
    /// a request reaches it (``LayoutPull/band(_:stateIndex:context:render:)``);
    /// `nil` otherwise, and the grid draws its cells whole. Each piece is
    /// drawn where the lattice places its cell across, and down where the
    /// fill put it in the band, through the eager drawing's glide and z-order.
    func renderPulledGrid(_ rows: [Row], lattice: GridLattice, context: RenderContext) -> FrameBuffer? {
        guard LayoutPull.isHandedRequest(context: context) else { return nil }
        let placed = placedCells(rows, lattice: lattice, context: context)
        let width = lattice.totalWidth
        let gradientFrame = context.gradientContentFrame(
            width: width, height: lattice.totalHeight(spacing: verticalSpacing))
        guard
            let band = LayoutPull.band(
                placed, stateIndex: GridStateIndex.pulledGrid, context: context,
                render: { index, childContext, height in
                    let cell = placed[index]
                    let drawn =
                        context.placesChildren
                        ? childContext.placingChild(gradient: gradientFrame, x: cell.x, y: cell.y) : childContext
                    return cell.child.render(width: cell.width, height: height, context: drawn)
                })
        else { return nil }
        var result = FrameBuffer(emptyWithWidth: width, height: band.height)
        for (index, piece) in band.pieces.enumerated() {
            guard let piece else { continue }
            result.composite(with: piece.buffer, at: (x: placed[index].x, y: piece.y))
        }
        let clampHeight = max(band.height, context.availableHeight)
        let targets = placed.indices.map { ChildPlacement(x: placed[$0].x, y: band.pieces[$0]?.y ?? 0) }
        let pictures = band.pieces.map { $0?.buffer }
        if let layered = context.glidingStackBuffer(
            placed.map(\.child), buffers: pictures, at: targets, departing: [], width: width, height: band.height)
            ?? context.zOrderedStackBuffer(
                placed.map(\.child), buffers: pictures, at: targets, width: width, height: band.height)
        {
            return layered.clamped(toWidth: context.availableWidth, height: clampHeight)
        }
        return result.clamped(toWidth: context.availableWidth, height: clampHeight)
    }

    /// Each cell where the lattice places it, at the size it is drawn at: its
    /// box's width, and its measured height within its row's. Its place in
    /// its box is the one the eager drawing gives it, from the same measure.
    private func placedCells(_ rows: [Row], lattice: GridLattice, context: RenderContext) -> [LayoutPlacedSubview] {
        let heights = lattice.heights
        let rowTops = lattice.rowTops(spacing: verticalSpacing)
        let origins = lattice.columnOrigins
        let width = lattice.totalWidth
        var placed: [LayoutPlacedSubview] = []
        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = max(1, heights[rowIndex])
            var index = 0
            for (cell, span) in zip(row.cells, row.spans) {
                let boxWidth = max(0, row.spansFullWidth ? width : lattice.boxWidth(fromColumn: index, span: span))
                let box = CellRect(x: row.spansFullWidth ? 0 : origins[index], y: 0, width: boxWidth, height: rowHeight)
                let measured = cell.measure(
                    proposal: ProposedViewSize(width: boxWidth, height: rowHeight), context: context)
                let seat = placement(
                    width: measured.width, height: measured.height, in: box, cell: cell, rowAlignment: row.alignment,
                    columnAlignment: row.spansFullWidth ? nil : lattice.columnAlignment[index])
                placed.append(
                    LayoutPlacedSubview(
                        child: cell, x: seat.x, y: rowTops[rowIndex] + seat.y, width: boxWidth,
                        height: min(rowHeight, max(0, measured.height))))
                index += span
            }
        }
        return placed
    }
}
