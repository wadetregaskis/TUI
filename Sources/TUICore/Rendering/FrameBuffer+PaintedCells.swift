//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+PaintedCells.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension FrameBuffer {
    /// Composites `picture` at `position`, **only where it paints**: each block
    /// of its painted cells (``paintedBlocks(inRows:)`` — a glyph, or a blank
    /// styled to show), with the unstyled blank cells around and between them
    /// left out, so what is under those cells stays as it was.
    ///
    /// Not ``composite(with:at:)``, which is opaque per cell, blanks included:
    /// that is right for a view laid out in its own room, whose blank cells
    /// are its room. It is wrong for a picture drawn over content that already
    /// holds that room — a lazy stack's row playing its own removal where the
    /// row below has moved up (`WindowedRowFade`) — where a row as wide as the
    /// stack, a label and a spacer, hid the row beneath for the whole removal.
    /// It is what ``OverlayLayer/drawnParts()`` does for a layer drawn over
    /// other content, cut to the runs of painted cells rather than from a
    /// line's first to its last, as content drawn after an overflow cuts it
    /// (``coverOverflow(under:at:)``): the blanks between two words show what
    /// is beneath, as they do between SwiftUI's glyphs.
    ///
    /// Every payload that rides on the cells — opacity regions, animated runs,
    /// hit regions — is cut to the cells drawn, so a cell the picture does not
    /// draw is neither faded, repainted nor clicked through it. What rides on
    /// the picture whole is lifted once: its floating layers and its geometry
    /// markers, which are points, not cells.
    package mutating func composite(paintedCellsOf picture: FrameBuffer, at position: (x: Int, y: Int)) {
        var bare = picture
        bare.overlays = []
        bare.hitTestRegions.removeAll(where: \.isGeometryMarker)
        let whole = OverlayLayer(
            offsetX: 0, offsetY: 0, content: bare, clampsToScreen: false, isOpaque: false)
        for block in picture.paintedBlocks() {
            guard
                let part = whole.cropped(
                    x: block.columns.lowerBound, y: block.rows.lowerBound,
                    width: block.columns.count, height: block.rows.count)
            else { continue }
            composite(with: part.content, at: (x: position.x + part.offsetX, y: position.y + part.offsetY))
        }
        appendOverlays(of: picture, shiftedByX: position.x, y: position.y)
        hitTestRegions.appendShifted(
            picture.hitTestRegions.filter(\.isGeometryMarker), byX: position.x, y: position.y)
    }
}
