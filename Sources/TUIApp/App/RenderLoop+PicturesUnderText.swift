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
    ///   hold (``PictureUnderTextLayer/place(on:startRow:)``).
    func preparePicturesUnderText() -> Bool {
        let drawn = KittyGraphics.isPictureUnderTextSupported
        guard drawn || !picturesUnderText.isIdle else { return false }
        picturesUnderText.prepare(rows: drawn ? diffWriter.pictureUnderTextRows : [])
        return true
    }

    /// What the terminal is owed for the pictures under text before the app
    /// lets go of it — a suspend, a quit: every placement deleted. See
    /// ``PictureUnderTextLayer/farewell()``.
    func handBackPicturesUnderText() -> String {
        picturesUnderText.farewell()
    }
}
