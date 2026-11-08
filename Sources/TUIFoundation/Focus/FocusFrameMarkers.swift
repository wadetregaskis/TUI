//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusFrameMarkers.swift
//
//  Where a focusable control a scroll view has clipped really is: two geometry
//  markers at the corners of the frame it had before the clip, carrying its
//  focus id, which ride every later shift and clip up to the screen root.
//  Emitted only under `TUI_ARROW_FOCUS=geometric`, whose arrows go by them
//  (`FocusManagerGeometricArrows.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension HitTestRegion.HandlerID {
    /// The marker at the top-left of a clipped focusable control's frame,
    /// paired with ``focusFrameEnd`` one cell past its bottom-right
    /// (``Swift/Array/appendFocusFrameCorners(of:clippedTo:rows:)``).
    ///
    /// Fixed rather than minted, as a picture's corners are
    /// (``pictureTopLeft``): every frame's corners carry the same pair and are
    /// told apart by the focus id they carry, so a buffer served from a memo
    /// needs nothing filed again. In the geometry bit's range, below the
    /// content shapes', which the marker mint, counting up from the bit, never
    /// reaches.
    package static let focusFrameStart = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFF6)

    /// The marker one cell past a clipped focusable control's bottom-right.
    package static let focusFrameEnd = Self(geometryMarkerBit | 0x3FFF_FFFF_FFFF_FFF7)
}

extension RenderContext {
    /// Whether a scroll view's clip keeps the frames of the focusable controls
    /// it cuts (``Swift/Array/appendFocusFrameCorners(of:clippedTo:rows:)``):
    /// only while the arrows go by geometry, the one reader of them. Under the
    /// default the clip is as it was, and the frame carries nothing more.
    var keepsFocusFrames: Bool { environment.focusManager?.arrowFocus == .geometric }
}

extension Array where Element == HitTestRegion {
    /// Clips every region to `columns` × `rows`, dropping each that nothing of
    /// survives, and — with `keepingFocusFrames` — leaving corners where it cut
    /// a focusable control (``appendFocusFrameCorners(of:clippedTo:rows:)``).
    package mutating func clip(toColumns columns: Range<Int>, rows: Range<Int>, keepingFocusFrames: Bool) {
        let unclipped = self
        self = unclipped.compactMap { $0.clipped(toColumns: columns, rows: rows) }
        if keepingFocusFrames { appendFocusFrameCorners(of: unclipped, clippedTo: columns, rows: rows) }
    }

    /// Appends, for each focusable control's region in `regions` that a clip
    /// to `columns` × `rows` trims or drops, two corner markers carrying its
    /// focus id: the frame the region had before the clip.
    ///
    /// A scroll view's clip is the one caller. It draws its whole content (or
    /// a windowed stack's band of it) and keeps only what the viewport shows,
    /// so a control scrolled out of sight has a frame in the content and none
    /// on screen. These markers keep that frame, and being geometry markers
    /// they are kept whole by every later clip (an enclosing scroll view's, the
    /// screen's), so at the root they say where the control is in the layout,
    /// on screen or not. Zero-area, so nothing hit-tests them, and nothing that
    /// reads a control's regions by its focus id — a reveal, the caret, a
    /// keyboard drag — takes them for the control's drawn cells.
    ///
    /// - Parameters:
    ///   - regions: The clip's input, already in the clipped buffer's
    ///     coordinates.
    ///   - columns: The surviving column range.
    ///   - rows: The surviving row range.
    package mutating func appendFocusFrameCorners(
        of regions: [HitTestRegion], clippedTo columns: Range<Int>, rows: Range<Int>
    ) {
        for region in regions where region.focusID != nil && !region.isGeometryMarker {
            let right = region.offsetX + region.width
            let bottom = region.offsetY + region.height
            guard region.width > 0, region.height > 0,
                region.offsetX < columns.lowerBound || right > columns.upperBound
                    || region.offsetY < rows.lowerBound || bottom > rows.upperBound
            else { continue }
            append(
                HitTestRegion(
                    offsetX: region.offsetX, offsetY: region.offsetY, width: 0, height: 0,
                    handlerID: .focusFrameStart, focusID: region.focusID))
            append(
                HitTestRegion(
                    offsetX: right, offsetY: bottom, width: 0, height: 0,
                    handlerID: .focusFrameEnd, focusID: region.focusID))
        }
    }
}
