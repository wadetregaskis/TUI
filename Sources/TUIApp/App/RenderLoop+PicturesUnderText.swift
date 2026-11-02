//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderLoop+PicturesUnderText.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - The pictures under glyphs, each frame

/// Separate from `RenderLoop.swift`, which is at its length limit, as
/// `RenderLoop+Hairlines.swift` is.
extension RenderLoop {
    /// Hands this frame's picture runs (``FrameDiffWriter/pictureUnderTextRows``)
    /// to ``picturesUnderText``.
    ///
    /// A static read and nothing else on a host that draws no pictures under
    /// text — unless it drew some before an override turned them off, when the
    /// layer is handed no runs and takes its placements away.
    ///
    /// - Returns: Whether the layer has placements and deletes to write in the
    ///   hold (``PicturePlacementLayer/place(on:startRow:)``).
    func preparePicturesUnderText() -> Bool {
        let drawn = KittyGraphics.isPictureUnderTextSupported
        guard drawn || !picturesUnderText.isIdle else { return false }
        picturesUnderText.prepare(rows: drawn ? diffWriter.pictureUnderTextRows : [])
        return true
    }

    /// Hands the picture cells this frame sent as spaces
    /// (``FrameDiffWriter/imagePlaceholderRows``) to ``classicPictures``, as
    /// rectangles of their images' pixels.
    ///
    /// A static read and nothing else on a host with placeholders.
    ///
    /// On a host that ignores a source rectangle a crop would draw the whole picture
    /// in the crop's cells: over whatever a modal or a clip left beside it. So each
    /// block that is not a whole picture is placed as an image of its own, of just
    /// its pixels, sent here since the frame's other images have already gone
    /// (`Terminal graphics protocols.md` §15).
    ///
    /// - Returns: Whether the layer has placements and deletes to write in the
    ///   hold (``PicturePlacementLayer/place(on:startRow:rewritten:)``).
    func prepareClassicPictures() -> Bool {
        let drawn = KittyGraphics.drawsPicturesByClassicPlacement
        guard drawn || !classicPictures.isIdle else { return false }
        let store = tuiContext.terminalImageStore
        var rows: [[PictureUnderTextMarker.Run]] = []
        if drawn { rows = diffWriter.imagePlaceholderRows.map { $0.compactMap { store.placementRun(for: $0) } } }
        let crops = KittyGraphics.classicPlacementsCrop
        classicPictures.prepare(rows: rows, drawing: crops ? nil : { store.croppedRun($0) })
        if !crops {
            store.endCroppedFrame()
            // Ahead of the cells and outside the hold, as `writeFrame`'s images are.
            let sent = store.takePending()
            if !sent.isEmpty { terminal.write(sent) }
        }
        return true
    }

    /// What the terminal is owed for the pictures this layer and
    /// ``classicPictures`` placed before the app lets go of it — a suspend, a
    /// quit: every placement deleted. See ``PicturePlacementLayer/farewell()``.
    func handBackPicturesUnderText() -> String {
        picturesUnderText.farewell() + classicPictures.farewell()
    }
}
