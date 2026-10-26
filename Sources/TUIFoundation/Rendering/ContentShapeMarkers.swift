//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentShapeMarkers.swift
//
//  A content shape as geometry markers: the cells a `contentShape(_:_:eoFill:)`
//  keeps, carried in its buffer to the gesture, hover and drag modifiers
//  around it, which cut the region they register over the view to them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension HitTestRegion.HandlerID {
    /// The marker an interaction content shape puts at its frame's top-left
    /// cell, paired with ``contentShapeFrameEnd`` one cell past its
    /// bottom-right, the runs it keeps after them (``contentShapeRunStart``,
    /// ``contentShapeRunEnd``).
    ///
    /// Fixed rather than minted, as a picture's corners are
    /// (``pictureTopLeft``): every content shape carries the same ids, paired
    /// by order, so a buffer served from a memo needs nothing filed again. In
    /// the geometry bit's range, below the pictures', which the marker mint —
    /// counting up from the bit — never reaches.
    package static let contentShapeFrameStart = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFF8)

    /// The marker one cell past an interaction content shape's frame.
    package static let contentShapeFrameEnd = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFF9)

    /// The marker a drag-preview content shape puts at its frame's top-left
    /// cell, paired with ``dragPreviewShapeFrameEnd``: what `.draggable` cuts
    /// the preview it carries to.
    package static let dragPreviewShapeFrameStart = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFFA)

    /// The marker one cell past a drag-preview content shape's frame.
    package static let dragPreviewShapeFrameEnd = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFFB)

    /// The marker at the first cell of a run of cells a content shape keeps.
    package static let contentShapeRunStart = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFFC)

    /// The marker one cell past the run's last cell, on the run's row.
    package static let contentShapeRunEnd = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFFD)
}

extension HitTestRegion {
    /// Which content shape a group of markers is: what it cuts.
    package enum ContentShapeRole: Sendable {
        /// The hit area: the regions registered over the view.
        case interaction
        /// The preview a drag of the view carries.
        case dragPreview

        var frameMarkers: (start: HandlerID, end: HandlerID) {
            switch self {
            case .interaction: (.contentShapeFrameStart, .contentShapeFrameEnd)
            case .dragPreview: (.dragPreviewShapeFrameStart, .dragPreviewShapeFrameEnd)
            }
        }
    }

    /// The markers that carry `kept` — the runs of cells a content shape of
    /// `role` keeps in a frame `width` × `height` at the carrying buffer's
    /// origin, one list a row — up to the modifiers around it: zero-area
    /// regions, so no pointer lands on them (``geometryMarker(_:)``), the
    /// frame's two corners first and each run's two ends after them, in order.
    package static func contentShapeMarkers(
        _ role: ContentShapeRole, keeping kept: [[Range<Int>]], width: Int, height: Int
    ) -> [Self] {
        func marker(_ id: HandlerID, _ x: Int, _ y: Int) -> Self {
            Self(offsetX: x, offsetY: y, width: 0, height: 0, handlerID: id)
        }
        var markers = [marker(role.frameMarkers.start, 0, 0), marker(role.frameMarkers.end, width, height)]
        for (row, runs) in kept.enumerated() {
            for run in runs {
                markers.append(marker(.contentShapeRunStart, run.lowerBound, row))
                markers.append(marker(.contentShapeRunEnd, run.upperBound, row))
            }
        }
        return markers
    }

    /// This region cut to `kept` — runs of cells, one list a row, in the
    /// coordinates the region is in — as rectangles, the rows whose runs are
    /// alike joined; each piece keeps the region's handler, and records what
    /// was cut away above and before it, so a handler is still handed points
    /// from where the region begins (``clipped(toColumns:rows:)``).
    package func cut(to kept: [[Range<Int>]]) -> [Self] {
        guard !isGeometryMarker else { return [self] }
        var pieces: [Self] = []
        var row = max(0, offsetY)
        let bottom = min(offsetY + height, kept.count)
        while row < bottom {
            var next = row + 1
            while next < bottom, kept[next] == kept[row] { next += 1 }
            for run in kept[row] {
                if let piece = clipped(toColumns: run, rows: row..<next) { pieces.append(piece) }
            }
            row = next
        }
        return pieces
    }
}

extension FrameBuffer {
    /// The runs of cells the content shape of `role` that covers this
    /// buffer's whole frame keeps, one list a row — `nil` where no content
    /// shape covers exactly this frame, so the frame is the shape.
    ///
    /// Only a shape whose frame is this buffer's: one set on a view inside it,
    /// smaller or moved by a padding, is that view's, not this one's.
    package func contentShapeRuns(_ role: HitTestRegion.ContentShapeRole) -> [[Range<Int>]]? {
        let (start, end) = role.frameMarkers
        let regions = hitTestRegions
        guard
            let first = regions.firstIndex(where: {
                $0.handlerID == start && $0.offsetX == 0 && $0.offsetY == 0
            }),
            regions.index(after: first) < regions.endIndex,
            regions[first + 1].handlerID == end, regions[first + 1].offsetX == width,
            regions[first + 1].offsetY == height
        else { return nil }
        var kept = [[Range<Int>]](repeating: [], count: height)
        var index = first + 2
        while index + 1 < regions.endIndex, regions[index].handlerID == .contentShapeRunStart,
            regions[index + 1].handlerID == .contentShapeRunEnd
        {
            let (from, to) = (regions[index], regions[index + 1])
            if kept.indices.contains(from.offsetY), to.offsetX > from.offsetX {
                kept[from.offsetY].append(from.offsetX..<to.offsetX)
            }
            index += 2
        }
        return kept
    }

    /// The regions a modifier registers over this buffer's frame for
    /// `handlerID`: one rectangle `width` × `height` — or, where a content
    /// shape covers the frame (``View/contentShape(_:eoFill:)``), the cells it
    /// keeps, so a gesture, a hover or a drag answers only inside the shape.
    ///
    /// - Parameters:
    ///   - handlerID: The handler the regions are for.
    ///   - focusID: The focus id they carry, if any.
    ///   - width: The rectangle's width, the buffer's unless said.
    ///   - height: The rectangle's height, the buffer's unless said.
    /// - Returns: The regions, in the order to register them.
    package func frameHitRegions(
        handlerID: HitTestRegion.HandlerID, focusID: String? = nil, width: Int? = nil, height: Int? = nil
    ) -> [HitTestRegion] {
        let whole = HitTestRegion(
            offsetX: 0, offsetY: 0, width: width ?? self.width, height: height ?? self.height,
            handlerID: handlerID, focusID: focusID)
        guard let kept = contentShapeRuns(.interaction) else { return [whole] }
        return whole.cut(to: kept)
    }
}
