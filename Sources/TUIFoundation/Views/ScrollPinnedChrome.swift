//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPinnedChrome.swift
//
//  Pinned section headers and footers, drawn where a scroll view shows them.
//  A pinned section emits a copy of its header (or footer) as a layer carrying
//  a scroll pin (`OverlayLayer.ScrollPin`); the layer rides every combining
//  operation to the nearest scroll view along its edge's axis — vertical for a
//  column's sections, horizontal for a row's — which is the one thing that
//  knows where its viewport is, and which moves the header to the viewport's
//  edge while the section's content is under it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Where a scroll view's viewport lies in its content buffer, as pinning asks.
struct PinnedChromeViewport {
    /// The buffer's line the viewport starts at.
    var top: Int

    /// The viewport's height.
    var height: Int

    /// The lines at the viewport's top that the scroll view draws over — the
    /// "N more above" line, when it shows — which a pinned header goes below
    /// rather than under.
    var topInset: Int

    /// The same at the bottom, for a pinned footer.
    var bottomInset: Int

    /// The viewport row a pinned layer is drawn at, or `nil` when it stays
    /// where the flow drew it or none of it would show.
    ///
    /// SwiftUI's rule, measured on macOS 15.8: a header stays at the top edge
    /// while its section's content is under it, and the content's last row
    /// pushes it up and away — so the next section's header takes over; a
    /// footer stays at the bottom edge, and never above its section's first
    /// row.
    func pinnedRow(of layer: OverlayLayer, pin: OverlayLayer.ScrollPin) -> Int? {
        let chromeHeight = layer.content.height
        guard chromeHeight > 0 else { return nil }
        let natural = layer.offsetY - top
        let row: Int
        switch pin.edge {
        case .top:
            guard natural < topInset else { return nil }
            row = min(topInset, natural + pin.travel)
        case .bottom:
            let edge = height - bottomInset
            guard natural + chromeHeight > edge else { return nil }
            row = max(edge - chromeHeight, natural - pin.travel)
        case .leading, .trailing:
            return nil
        }
        guard row != natural, row + chromeHeight > 0, row < height else { return nil }
        return row
    }
}

/// Where a horizontal scroll view's viewport lies in its content buffer, as
/// pinning asks — the leading and trailing edges a row's sections pin to.
struct PinnedChromeHorizontalViewport {
    /// The buffer's column the viewport starts at.
    var left: Int

    /// The viewport's width.
    var width: Int

    /// The viewport column a pinned layer is drawn at, or `nil` when it stays
    /// where the flow drew it or none of it would show.
    ///
    /// The vertical rule turned on its side, as SwiftUI's horizontal stacks
    /// and grids pin (measured on macOS 15.8): a header stays at the leading
    /// edge while its section's content is under it, pushed off by the
    /// content's last column; a footer stays at the trailing edge, never left
    /// of its section's first column.
    func pinnedColumn(of layer: OverlayLayer, pin: OverlayLayer.ScrollPin) -> Int? {
        let chromeWidth = layer.content.width
        guard chromeWidth > 0 else { return nil }
        let natural = layer.offsetX - left
        let column: Int
        switch pin.edge {
        case .leading:
            guard natural < 0 else { return nil }
            column = min(0, natural + pin.travel)
        case .trailing:
            guard natural + chromeWidth > width else { return nil }
            column = max(width - chromeWidth, natural - pin.travel)
        case .top, .bottom:
            return nil
        }
        guard column != natural, column + chromeWidth > 0, column < width else { return nil }
        return column
    }
}

/// A pinned layer, and the buffer position a viewport draws it at instead of
/// where the flow drew it.
struct PinnedChromePlacement {
    let layer: OverlayLayer

    /// The buffer row its first line is drawn at.
    let row: Int

    /// The buffer column its first cell is drawn at.
    let column: Int

    /// The buffer rows the flow drew it on.
    var naturalRows: Range<Int> { layer.offsetY..<(layer.offsetY + layer.content.height) }

    /// The buffer columns the flow drew it on.
    var naturalColumns: Range<Int> { layer.offsetX..<(layer.offsetX + layer.content.width) }
}

extension FrameBuffer {
    /// This scroll content as `viewport` shows it: every pinned section header
    /// that has scrolled above the viewport's top edge drawn at that edge, and
    /// every pinned footer below its bottom edge drawn at that one, as far as
    /// their sections reach — and every pinned layer taken off the buffer,
    /// drawn or not. One whose section is not under its edge stays where the
    /// flow drew it.
    ///
    /// A moved header takes everything it carries with it: its hit-test
    /// regions, so a control in it is clicked where it is drawn; its animated
    /// runs and its fades; and any presentation anchored on it, a drop-down
    /// opened from a pinned header's picker. Where it is drawn it covers the
    /// rows beneath — their glyphs, their runs, their fades and their regions,
    /// so a click on the header never reaches a row no one can see. The cells
    /// it leaves blank keep their field, so a row's background shows through
    /// them as SwiftUI's transparent header lets the row show.
    ///
    /// A vertical viewport resolves the top and bottom pins, a horizontal one
    /// the leading and trailing pins; a pin along an axis this scroll view does
    /// not scroll stays on the buffer, for one further out that does.
    func resolvingScrollPins(
        in viewport: PinnedChromeViewport?, horizontal: PinnedChromeHorizontalViewport? = nil
    ) -> FrameBuffer {
        guard overlays.contains(where: { $0.scrollPin != nil }) else { return self }
        var result = self
        result.overlays = overlays.filter { layer in
            guard let pin = layer.scrollPin else { return true }
            return pin.edge.isHorizontal ? horizontal == nil : viewport == nil
        }
        for placement in scrollPinPlacements(in: viewport, horizontal: horizontal) {
            result.move(pinned: placement)
        }
        return result
    }

    /// Where the viewports draw each pinned layer this buffer carries — every
    /// one that leaves the place the flow drew it and shows.
    func scrollPinPlacements(
        in viewport: PinnedChromeViewport?, horizontal: PinnedChromeHorizontalViewport? = nil
    ) -> [PinnedChromePlacement] {
        guard overlays.contains(where: { $0.scrollPin != nil }) else { return [] }
        return overlays.compactMap { layer in
            guard let pin = layer.scrollPin else { return nil }
            if pin.edge.isHorizontal {
                guard let horizontal, let column = horizontal.pinnedColumn(of: layer, pin: pin)
                else { return nil }
                return PinnedChromePlacement(
                    layer: layer, row: layer.offsetY, column: horizontal.left + column)
            }
            guard let viewport, let row = viewport.pinnedRow(of: layer, pin: pin) else { return nil }
            return PinnedChromePlacement(layer: layer, row: viewport.top + row, column: layer.offsetX)
        }
    }

    /// Draws a pinned layer where `placement` puts it, moving everything that
    /// rode on the header it copies there with it, and covering what it lands
    /// on.
    private mutating func move(pinned placement: PinnedChromePlacement) {
        let layer = placement.layer
        let content = layer.content
        let (dx, dy) = (placement.column - layer.offsetX, placement.row - layer.offsetY)
        let (naturalColumns, naturalRows) = (placement.naturalColumns, placement.naturalRows)
        let pinnedColumns = placement.column..<(placement.column + content.width)
        let pinnedRows = placement.row..<(placement.row + content.height)

        // The header's own regions leave with it: drawn where the flow put it,
        // a control in it would be found there too. The cells that stay behind
        // under the header lose theirs.
        hitTestRegions = hitTestRegions.flatMap { region -> [HitTestRegion] in
            if Self.lies(region, within: naturalColumns, naturalRows) { return [] }
            return Self.subtracting(pinnedColumns, pinnedRows, from: region)
        }
        // A presentation opened from the header — a picker's drop-down — is
        // anchored on the row it was opened from, and goes with it.
        overlays = overlays.map { overlay in
            guard !overlay.centered, naturalRows.contains(overlay.offsetY - overlay.anchorHeight),
                naturalColumns.contains(overlay.offsetX)
            else { return overlay }
            return overlay.shifted(byX: dx, y: dy)
        }

        // The copy carries no presentations of its own: they are the header's,
        // and were just moved.
        var drawn = content
        drawn.overlays = []
        // Covers the glyphs, runs and fades it lands on, and brings its own.
        composite(with: drawn, at: (x: placement.column, y: placement.row))
    }

    /// Whether `region` lies entirely inside `columns` × `rows`.
    private static func lies(
        _ region: HitTestRegion, within columns: Range<Int>, _ rows: Range<Int>
    ) -> Bool {
        region.offsetX >= columns.lowerBound && region.offsetX + region.width <= columns.upperBound
            && region.offsetY >= rows.lowerBound && region.offsetY + region.height <= rows.upperBound
    }

    /// `region` less the rectangle `columns` × `rows`: up to four pieces, the
    /// rows above it and below it, and the columns either side of it on the
    /// rows between.
    private static func subtracting(
        _ columns: Range<Int>, _ rows: Range<Int>, from region: HitTestRegion
    ) -> [HitTestRegion] {
        let regionRows = region.offsetY..<(region.offsetY + region.height)
        let regionColumns = region.offsetX..<(region.offsetX + region.width)
        guard regionRows.overlaps(rows), regionColumns.overlaps(columns) else { return [region] }
        let everyColumn = Int.min..<Int.max
        return [
            region.clipped(toColumns: everyColumn, rows: Int.min..<rows.lowerBound),
            region.clipped(toColumns: everyColumn, rows: rows.upperBound..<Int.max),
            region.clipped(toColumns: Int.min..<columns.lowerBound, rows: rows),
            region.clipped(toColumns: columns.upperBound..<Int.max, rows: rows),
        ].compactMap { $0 }
    }
}

// MARK: - What a Reveal Allows For

/// What a scroll view's pinned chrome means to a reveal at its current
/// offset: where a control in a pinned header really is, and how many lines
/// at each edge are covered for anything else.
///
/// A row brought to the top edge would sit under the header pinned there:
/// focused, and not seen. So a reveal keeps the focused control clear of the
/// pinned chrome as it keeps it clear of the "N more" lines — a TUI rule;
/// SwiftUI's `scrollTo` leaves a row under the header, and a seek here does
/// too. A control IN a pinned header is found where it is drawn, on screen,
/// so a key it takes does not scroll the view back to its section's top.
struct PinnedChromeCover {
    /// The pinned layers that leave the flow at this offset.
    var placements: [PinnedChromePlacement] = []

    /// The viewport lines below the top inset that pinned headers cover.
    var top = 0

    /// The viewport lines above the bottom inset that pinned footers cover.
    var bottom = 0

    init() {}

    init(_ placements: [PinnedChromePlacement], in viewport: PinnedChromeViewport) {
        self.placements = placements
        for placement in placements {
            let row = placement.row - viewport.top
            let lines = placement.layer.content.height
            switch placement.layer.scrollPin?.edge {
            case .top: top = max(top, row + lines - viewport.topInset)
            case .bottom: bottom = max(bottom, viewport.height - viewport.bottomInset - row)
            case .leading, .trailing, nil: break
            }
        }
    }

    /// `region` — rows of the content buffer — where it is drawn, and whether
    /// it is pinned chrome itself: a control in a header the flow drew on
    /// those rows is drawn where the header is pinned.
    func drawn(_ region: (top: Int, height: Int)) -> (top: Int, height: Int, isChrome: Bool) {
        for placement in placements {
            let rows = placement.naturalRows
            if region.top >= rows.lowerBound, region.top + region.height <= rows.upperBound {
                return (region.top + placement.row - rows.lowerBound, region.height, true)
            }
        }
        return (region.top, region.height, false)
    }
}

extension _ScrollViewCore {
    /// Where this frame's offset puts the viewport in `content`, a buffer
    /// starting at content line `sliceOriginY`, for pinning.
    ///
    /// A pinned header goes below the "N more above" line rather than under
    /// it, as a revealed control does: overwritten by the line, a one-line
    /// header would not be pinned at all. Only where the line is drawn over
    /// the content — reserved, it is outside the viewport.
    private func pinnedChromeViewport(
        handler: ScrollViewHandler, sliceOriginY: Int, overwritesEdgeLines overwrites: Bool
    ) -> PinnedChromeViewport {
        PinnedChromeViewport(
            top: max(0, handler.scrollOffset - sliceOriginY), height: handler.viewportHeight,
            topInset: overwrites && handler.hasContentAbove ? 1 : 0,
            bottomInset: overwrites && handler.hasContentBelow ? 1 : 0)
    }

    /// `content` as this frame's offset shows it, its pinned section headers
    /// and footers at the viewport's edges
    /// (``FrameBuffer/resolvingScrollPins(in:horizontal:)``).
    ///
    /// Along the axes this view scrolls: a column's sections pin to a
    /// vertical scroll view's top and bottom, a row's to a horizontal one's
    /// leading and trailing edges, and a pin along an axis this view does not
    /// scroll is passed on to one that does.
    func pinningSectionChrome(
        in content: FrameBuffer, handler: ScrollViewHandler, sliceOriginY: Int,
        chrome: ScrollChrome, contentWidth: Int, context: RenderContext
    ) -> FrameBuffer {
        guard !context.isMeasuring else { return content }
        let vertical =
            axes.contains(.vertical)
            ? pinnedChromeViewport(
                handler: handler, sliceOriginY: sliceOriginY,
                overwritesEdgeLines: chrome.overwritesEdgeLines)
            : nil
        let horizontal =
            axes.contains(.horizontal)
            ? PinnedChromeHorizontalViewport(left: handler.horizontal.scrollOffset, width: contentWidth)
            : nil
        guard vertical != nil || horizontal != nil else { return content }
        return content.resolvingScrollPins(in: vertical, horizontal: horizontal)
    }

    /// What `content`'s pinned chrome means to a reveal at this frame's
    /// offset (``PinnedChromeCover``), the "N more" lines drawn over the
    /// viewport's edges when `overwritesEdgeLines`.
    func pinnedChromeCover(
        of content: FrameBuffer, handler: ScrollViewHandler, sliceOriginY: Int,
        overwritesEdgeLines: Bool, context: RenderContext
    ) -> PinnedChromeCover {
        guard axes.contains(.vertical), !context.isMeasuring else { return PinnedChromeCover() }
        let viewport = pinnedChromeViewport(
            handler: handler, sliceOriginY: sliceOriginY, overwritesEdgeLines: overwritesEdgeLines)
        let placements = content.scrollPinPlacements(in: viewport)
        guard !placements.isEmpty else { return PinnedChromeCover() }
        return PinnedChromeCover(placements, in: viewport)
    }
}
