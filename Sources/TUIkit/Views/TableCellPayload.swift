//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableCellPayload.swift
//
//  What a table's view cells carry besides their characters — the hit regions
//  their controls registered and the overlays they raised — placed where the
//  cells are drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Row payload

/// The hit regions and overlays a drawn row's view cells carried, in the row's
/// own coordinates: x from the row line's first cell (the selection gutter
/// included), y from the row's first line.
///
/// A view cell is rendered into a buffer and its LINES go into the row. Until
/// this existed, everything else the buffer carried was dropped with it: a
/// `Button` in a cell drew, took the focus from Tab and pressed on Return, and
/// a click on it selected the row instead; a `.contextMenu` on the cell's view
/// opened on a right-click and drew nowhere, its menu an overlay on a buffer
/// nobody kept. Carried, the control takes the click and the row takes clicks
/// everywhere else — every region a cell holds is offered the click first, and
/// one that declines it (a context-menu trigger declines a left click) passes
/// it down to the table.
///
/// Never kept by the row memo, and never needs to be: a view cell's column
/// cannot NAME its value (``_TableColumnSpec/namesAProperty`` is false for every
/// content closure), so a row holding one always runs its cells — which is when
/// the controls register — and the payload of the cells it ran travels with
/// whichever line the frame draws, kept or composed.
struct _TableRowPayload {
    /// The cells' hit regions, in row coordinates.
    var hitTestRegions: [HitTestRegion] = []

    /// The cells' overlays, in row coordinates. An open context menu on a
    /// cell's view is one.
    var overlays: [OverlayLayer] = []

    /// Whether the row carries nothing — every row of a table without a view
    /// column, and so the case every path keeps free.
    var isEmpty: Bool { hitTestRegions.isEmpty && overlays.isEmpty }

    /// Takes a view cell's payload, placed where its lines are drawn.
    ///
    /// Each line of a cell is aligned into its column on its own (see
    /// `Table.appendAligned`), so a region moves right by the gap its own top
    /// line was given: a `.trailing` column's button sits where its label is.
    /// A region is trimmed to the cell — `width` columns from `x`, `lines` lines
    /// — because the cell's lines are clipped there: a region past the column
    /// would take clicks on the next column's cells. Overlays float free of the
    /// flow, as they do everywhere, and are moved only.
    ///
    /// - Parameters:
    ///   - cell: The cell's rendered buffer.
    ///   - x: The column of the row line the cell's column starts at.
    ///   - width: The column's width.
    ///   - lines: How many of the cell's lines the row draws.
    ///   - alignment: The column's alignment.
    mutating func absorb(
        _ cell: FrameBuffer, atColumn x: Int, width: Int, lines: Int, alignment: HorizontalAlignment
    ) {
        guard !cell.hitTestRegions.isEmpty || !cell.overlays.isEmpty else { return }
        /// Where line `y` of the cell starts in the row: past the column's start
        /// and the gap its alignment leaves before it.
        func lineStart(_ y: Int) -> Int {
            guard y >= 0, y < cell.height else { return x }
            let lineWidth =
                cell.linesAreUniformWidth
                ? cell.width : cell.lineWidths?[y] ?? cell.lines[y].strippedLength
            return x + alignment.childOffset(childWidth: min(width, lineWidth), in: width)
        }
        let columns = x..<(x + max(0, width))
        let rows = 0..<max(0, lines)
        // The cell's geometry markers stay behind, in its regions and in its
        // layers: a table cell is not located (decisions D5G, B-D5G-2), so a
        // reader in one is told the origin on every frame. Not because a
        // marker would take a click — it has no area, and none lands on it —
        // but because carried, it is found: a reader in a cell is then
        // answered exactly from its first frame, which is that decision's to
        // change, with its docs and tests.
        for region in cell.hitTestRegions where !region.isGeometryMarker {
            if let placed = region.shifted(byX: lineStart(region.offsetY), y: 0)
                .clipped(toColumns: columns, rows: rows)
            {
                hitTestRegions.append(placed)
            }
        }
        for var overlay in cell.overlays {
            overlay.content.removeGeometryMarkers()
            overlays.append(overlay.shifted(byX: lineStart(overlay.offsetY), y: 0))
        }
    }

    /// Takes another payload whole.
    mutating func append(_ other: Self) {
        hitTestRegions += other.hitTestRegions
        overlays += other.overlays
    }

    /// This payload moved by `dx` × `dy`.
    func shifted(byX dx: Int, y dy: Int) -> Self {
        guard !isEmpty, dx != 0 || dy != 0 else { return self }
        return Self(
            hitTestRegions: hitTestRegions.map { $0.shifted(byX: dx, y: dy) },
            overlays: overlays.map { $0.shifted(byX: dx, y: dy) })
    }

    /// This payload with its regions trimmed to the lines `rows` — what a row
    /// cut at the top or bottom of the viewport still draws. Overlays are kept:
    /// they float free of the lines, as a clamp keeps them.
    func clipped(toRows rows: Range<Int>) -> Self {
        guard !hitTestRegions.isEmpty else { return self }
        return Self(
            hitTestRegions: hitTestRegions.compactMap {
                $0.clipped(toColumns: $0.offsetX..<($0.offsetX + $0.width), rows: rows)
            },
            overlays: overlays)
    }
}

// MARK: - Markers

extension FrameBuffer {
    /// Removes every geometry marker this buffer carries, in its regions and in
    /// every layer's content — what a table cell leaves behind
    /// (``_TableRowPayload/absorb(_:atColumn:width:lines:alignment:)``).
    ///
    /// Every layer, not only those ``forEachGeometryMarker(offsetX:offsetY:_:)``
    /// reads: a surface's markers (a cell's open menu) are found by the screen
    /// root once it composites the surface, which would locate the cell's view
    /// too. Copies nothing that holds no marker.
    fileprivate mutating func removeGeometryMarkers() {
        if hitTestRegions.contains(where: \.isGeometryMarker) {
            hitTestRegions.removeAll(where: \.isGeometryMarker)
        }
        for index in overlays.indices where overlays[index].content.containsGeometryMarker {
            overlays[index].content.removeGeometryMarkers()
        }
    }

    /// Whether this buffer or any layer in it, at any depth, holds a geometry
    /// marker.
    private var containsGeometryMarker: Bool {
        hitTestRegions.contains(where: \.isGeometryMarker)
            || overlays.contains { $0.content.containsGeometryMarker }
    }
}
