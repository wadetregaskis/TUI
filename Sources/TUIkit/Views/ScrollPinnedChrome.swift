//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollPinnedChrome.swift
//
//  Pinned section headers and footers, drawn where a scroll view shows them.
//  A pinned section emits a copy of its header (or footer) as a layer carrying
//  a scroll pin (`OverlayLayer.ScrollPin`); the layer rides every combining
//  operation to the nearest vertical scroll view, which is the one thing that
//  knows where its viewport is, and which moves the header to the viewport's
//  edge while the section's content is under it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension FrameBuffer {
    /// This scroll content as a viewport starting at line `viewportTop` of it
    /// shows it: every pinned section header that has scrolled above the
    /// viewport's top edge drawn at that edge, and every pinned footer below
    /// its bottom edge drawn at that one, as far as their sections reach — and
    /// every pinned layer taken off the buffer, drawn or not.
    ///
    /// SwiftUI's rule, measured on macOS 15.8: a header stays at the top edge
    /// while its section's content is under it, and the content's last row
    /// pushes it up and away — so the next section's header takes over; a
    /// footer stays at the bottom edge, and never above its section's first
    /// row. Neither is drawn anywhere else: one whose section is not under the
    /// edge stays where the flow drew it.
    ///
    /// A moved header takes everything it carries with it: its hit-test
    /// regions, so a control in it is clicked where it is drawn and a reveal
    /// finds it there; its animated runs and its fades; and any presentation
    /// anchored on it, a drop-down opened from a pinned header's picker.
    /// Where it is drawn it covers the rows beneath — their glyphs, their
    /// runs, their fades and their regions, so a click on the header never
    /// reaches a row no one can see. The cells it leaves blank keep their
    /// field, so a row's background shows through them as SwiftUI's
    /// transparent header lets the row show.
    ///
    /// - Parameters:
    ///   - viewportTop: The buffer's line the viewport starts at.
    ///   - viewportHeight: The viewport's height.
    ///   - topInset: The lines at the viewport's top that the scroll view
    ///     draws over — the "N more above" line, when it shows — which a
    ///     pinned header goes below rather than under.
    ///   - bottomInset: The same at the bottom, for a pinned footer.
    func resolvingScrollPins(
        viewportTop: Int, viewportHeight: Int, topInset: Int, bottomInset: Int
    ) -> FrameBuffer {
        guard overlays.contains(where: { $0.scrollPin != nil }) else { return self }
        var result = self
        result.overlays = overlays.filter { $0.scrollPin == nil }
        for layer in overlays {
            guard let pin = layer.scrollPin, let row = Self.pinnedRow(
                of: layer, pin: pin, viewportTop: viewportTop, viewportHeight: viewportHeight,
                topInset: topInset, bottomInset: bottomInset)
            else { continue }
            result.move(pinned: layer, toBufferRow: viewportTop + row)
        }
        return result
    }

    /// The viewport row a pinned layer is drawn at, or `nil` when it stays
    /// where the flow drew it or none of it would show.
    private static func pinnedRow(
        of layer: OverlayLayer, pin: OverlayLayer.ScrollPin, viewportTop: Int,
        viewportHeight: Int, topInset: Int, bottomInset: Int
    ) -> Int? {
        let height = layer.content.height
        guard height > 0 else { return nil }
        let natural = layer.offsetY - viewportTop
        let row: Int
        switch pin.edge {
        case .top:
            guard natural < topInset else { return nil }
            row = min(topInset, natural + pin.travel)
        case .bottom:
            let edge = viewportHeight - bottomInset
            guard natural + height > edge else { return nil }
            row = max(edge - height, natural - pin.travel)
        }
        guard row != natural, row + height > 0, row < viewportHeight else { return nil }
        return row
    }

    /// Draws `layer` at buffer row `row`, moving everything that rode on the
    /// header it copies there with it, and covering what it lands on.
    private mutating func move(pinned layer: OverlayLayer, toBufferRow row: Int) {
        let content = layer.content
        let delta = row - layer.offsetY
        let columns = layer.offsetX..<(layer.offsetX + content.width)
        let naturalRows = layer.offsetY..<(layer.offsetY + content.height)
        let pinnedRows = row..<(row + content.height)

        // The header's own regions leave with it: drawn where the flow put it,
        // a control in it would be found there too, and a reveal would scroll
        // the viewport back to the section's top to show what is already on
        // screen. The rows that stay behind under the header lose theirs.
        hitTestRegions = hitTestRegions.flatMap { region -> [HitTestRegion] in
            if Self.lies(region, within: columns, naturalRows) { return [] }
            return Self.subtracting(columns, pinnedRows, from: region)
        }
        // A presentation opened from the header — a picker's drop-down — is
        // anchored on the row it was opened from, and goes with it.
        overlays = overlays.map { overlay in
            guard !overlay.centered, naturalRows.contains(overlay.offsetY - overlay.anchorHeight),
                columns.contains(overlay.offsetX)
            else { return overlay }
            return overlay.shifted(byX: 0, y: delta)
        }

        // The copy carries no presentations of its own: they are the header's,
        // and were just moved.
        var drawn = content
        drawn.overlays = []
        // Covers the glyphs, runs and fades it lands on, and brings its own.
        composite(with: drawn, at: (x: layer.offsetX, y: row))
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

extension _ScrollViewCore {
    /// `content` as this frame's offset shows it, its pinned section headers
    /// and footers at the viewport's edges
    /// (``FrameBuffer/resolvingScrollPins(viewportTop:viewportHeight:topInset:bottomInset:)``).
    ///
    /// A pinned header goes below the "N more above" line rather than under
    /// it, as a revealed control does: overwritten by the line, a one-line
    /// header would not be pinned at all. Only where the line is drawn over
    /// the content — reserved, it is outside the viewport.
    ///
    /// The vertical axis only: a horizontal scroll view has no top edge to
    /// pin to, and passes the layers on to one that does.
    func pinningSectionChrome(
        in content: FrameBuffer, handler: ScrollViewHandler, sliceOriginY: Int,
        chrome: ScrollChrome, context: RenderContext
    ) -> FrameBuffer {
        guard axes.contains(.vertical), !context.isMeasuring else { return content }
        let overwrites = chrome.overwritesEdgeLines
        return content.resolvingScrollPins(
            viewportTop: max(0, handler.scrollOffset - sliceOriginY),
            viewportHeight: handler.viewportHeight,
            topInset: overwrites && handler.hasContentAbove ? 1 : 0,
            bottomInset: overwrites && handler.hasContentBelow ? 1 : 0)
    }
}
