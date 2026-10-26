//  🖥️ TUI — A Terminal UI framework for Swift
//  PictureMarkers.swift
//
//  Where a picture is on screen: two geometry markers at its corners, which
//  ride every shift and clip with the cells, read back off the finished page
//  by what treats a picture's cells as pixels rather than text.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension HitTestRegion.HandlerID {
    /// The marker a picture puts at its top-left cell (``HitTestRegion/pictureCorners(width:height:)``).
    ///
    /// Fixed rather than minted: every picture's corners carry the same pair,
    /// paired by order, so a picture served from a memo needs nothing filed
    /// again. Both sit at the very top of the geometry bit's range, which the
    /// marker mint — counting up from the bit — never reaches.
    package static let pictureTopLeft = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFFE)

    /// The marker a picture puts one cell past its bottom-right cell.
    package static let pictureBottomRight = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFFF)
}

extension HitTestRegion {
    /// A picture's two corner markers, for a picture `width` × `height` cells
    /// at the carrying buffer's origin: zero-area regions, so no pointer ever
    /// lands on them (``geometryMarker(_:)``), appended together so that order
    /// pairs them wherever the buffer is carried.
    package static func pictureCorners(width: Int, height: Int) -> [Self] {
        [
            Self(offsetX: 0, offsetY: 0, width: 0, height: 0, handlerID: .pictureTopLeft),
            Self(offsetX: width, offsetY: height, width: 0, height: 0, handlerID: .pictureBottomRight),
        ]
    }
}

extension Array where Element == HitTestRegion {
    /// The rectangles the pictures in these regions cover, in the regions'
    /// coordinates: each top-left marker with the bottom-right one after it.
    ///
    /// A clip keeps a marker whole, so a picture scrolled part-way out of a
    /// viewport reads as the whole picture; the reader asks about cells that
    /// are on screen, and those are the picture's.
    package var pictureRects: [CellRect] {
        var rects: [CellRect] = []
        var open: HitTestRegion?
        for region in self {
            if region.handlerID == .pictureTopLeft {
                open = region
            } else if region.handlerID == .pictureBottomRight, let corner = open {
                rects.append(
                    CellRect(
                        x: corner.offsetX, y: corner.offsetY,
                        width: Swift.max(0, region.offsetX - corner.offsetX),
                        height: Swift.max(0, region.offsetY - corner.offsetY)))
                open = nil
            }
        }
        return rects
    }
}
