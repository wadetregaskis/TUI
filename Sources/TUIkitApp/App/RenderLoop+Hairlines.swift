//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+Hairlines.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The lines between list rows, each frame

/// Separate from `RenderLoop.swift`, which is at its length limit, as
/// `RenderLoop+TerminalGeometry.swift` is.
extension RenderLoop {
    /// Hands this frame's hairline runs (``FrameDiffWriter/hairlineRows``) to
    /// ``hairlines`` and writes what must go before the frame's hold: the
    /// strips to send, and the deletes an invalidation owes.
    ///
    /// A static read and nothing else on a host that draws no hairlines —
    /// unless it drew some before an override turned them off, when the layer
    /// is handed no runs and takes its lines away.
    ///
    /// - Returns: Whether the layer has placements and deletes to write in the
    ///   hold (``HairlineLayer/place(on:startRow:)``).
    func prepareHairlines(environment: EnvironmentValues, terminalWidth: Int) -> Bool {
        let drawn = KittyGraphics.isHairlineSupported
        guard drawn || !hairlines.isIdle else { return false }
        let cell = environment.imageCellPixels
        let before = hairlines.prepare(
            rows: drawn ? diffWriter.hairlineRows : [],
            geometry: HairlineLayer.Geometry(cellWidth: cell.width, cellHeight: cell.height, columns: terminalWidth),
            compressed: KittyGraphics.isCompressionSupported)
        if !before.isEmpty { terminal.write(before) }
        return true
    }

    /// What the terminal is owed for the hairlines before the app lets go of
    /// it — a suspend, a quit: every strip deleted, with its lines. See
    /// ``HairlineLayer/farewell()``.
    func handBackHairlines() -> String {
        hairlines.farewell()
    }
}
