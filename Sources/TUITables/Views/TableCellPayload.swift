//  🖥️ TUI — A Terminal UI framework for Swift
//  TableCellPayload.swift
//
//  What a table's view cells carry besides their characters — the hit regions
//  their controls registered and the overlays they raised — placed where the
//  cells are drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

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
    /// That gap is all that moves it: a view cell is rendered at its column's
    /// width and clamped there, as every rendered buffer is, so its line is
    /// never wider than the column and the column's truncation — which would
    /// cut a `.head`-truncated line at the front — never applies to it
    /// (pinned by `TableViewCellPointerTests`).
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
        // The cell's geometry markers come with its regions: a marker is a
        // point, not an area (it rides through the clip below unchanged), so
        // it takes no click, and carried, the frame's owners find the views
        // in the cell — a reader there is answered where it is drawn
        // (decisions D5G, B-D5G-2). A layer's markers stay behind: an open
        // menu's content is found where the menu is drawn, not the cell.
        for region in cell.hitTestRegions {
            if let placed = region.shifted(byX: lineStart(region.offsetY), y: 0)
                .clipped(toColumns: columns, rows: rows)
            {
                hitTestRegions.append(placed)
            }
        }
        for var overlay in cell.overlays {
            overlay.content.removeGeometryMarkers()
            let placed = overlay.shifted(byX: lineStart(overlay.offsetY), y: 0)
            // What a placement drew past its region (`OverlayLayer.isOverflow`:
            // a view a guide put outside its frame, a transition's overshoot)
            // stays in the cell, as a table's content always has: drawn past
            // it, it would cover the next column, the separators and the
            // border, which the stacking order cannot put back over it here.
            guard placed.isOverflow else {
                overlays.append(placed)
                continue
            }
            if let kept = placed.cropped(x: x, y: 0, width: max(0, width), height: max(0, lines)) {
                overlays.append(kept)
            }
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

    /// This payload with its regions trimmed to the columns `columns` — what
    /// the rows still show where a scrollbar is drawn over their last column.
    /// Overlays are kept, as ``clipped(toRows:)`` keeps them.
    func clipped(toColumns columns: Range<Int>) -> Self {
        guard !hitTestRegions.isEmpty else { return self }
        return Self(
            hitTestRegions: hitTestRegions.compactMap {
                $0.clipped(toColumns: columns, rows: $0.offsetY..<($0.offsetY + $0.height))
            },
            overlays: overlays)
    }
}

// MARK: - Markers

extension FrameBuffer {
    /// Removes every geometry marker this buffer carries, in its regions and in
    /// every layer's content — what a table cell's LAYERS leave behind
    /// (``_TableRowPayload/absorb(_:atColumn:width:lines:alignment:)``); the
    /// cell's own regions' markers come up with the row, where it is drawn.
    ///
    /// Every layer, not only those ``forEachGeometryMarker(offsetX:offsetY:_:)``
    /// reads: a surface's markers (a cell's open menu) are found by the screen
    /// root once it composites the surface, which would locate the cell's view
    /// a second time, where the menu is. Copies nothing that holds no marker.
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
