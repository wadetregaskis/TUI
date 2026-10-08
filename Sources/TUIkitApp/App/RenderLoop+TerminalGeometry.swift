//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+TerminalGeometry.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The terminal's size and cell geometry, each frame

/// Separate from `RenderLoop.swift` because that file is at its length limit,
/// the bargain `RenderLoop+Scene.swift` and `RenderLoop+TerminalColors.swift`
/// make too; it is why ``publishTerminalGeometry(into:width:height:)`` is not
/// `fileprivate`.
extension RenderLoop {
    /// Publishes the terminal's size and its cell's geometry, as the terminal
    /// reports them this frame, at the root of the environment.
    ///
    /// The size (`width` × `height` cells) is the true screen, so an overlay —
    /// a `Picker`'s drop-down — can size to the visible area. Unlike a
    /// context's `availableHeight`, which a ScrollView inflates to a tall
    /// measure budget, it is set once at the root and never overridden, so it
    /// survives intact however deep the consumer sits.
    ///
    /// The aspect keeps an image undistorted and a centred ramp round;
    /// terminals that don't report their pixel size keep the 2.0 default (or a
    /// `.imageCellAspect(_:)` override deeper in the tree). The undivided pixel
    /// size is what an image transmitted to the terminal's own graphics
    /// protocol is resampled to, and in points — where the host's pixels are
    /// measured (``CellPointsCalibration``) — what an image's natural size is
    /// counted in. A capability, not part of the protocol every
    /// host must implement: see `CellGeometryReporting`.
    ///
    /// BEFORE ``invalidateCacheIfEnvironmentChanged(environment:)``, which is
    /// the point: a font change moves the geometry, and a resize the size, with
    /// nothing a memo keys on moving — a view in a frame of its own size is
    /// offered the same cells at every terminal size — so the snapshot has to
    /// see them. Each was published inside `renderContent`, after the snapshot
    /// had been taken, and a memoized row that read one went on drawing for the
    /// terminal before the change.
    func publishTerminalGeometry(into environment: inout EnvironmentValues, width: Int, height: Int) {
        environment.terminalWidth = width
        environment.terminalHeight = height
        let geometry = terminal as? any CellGeometryReporting
        if let cellAspect = geometry?.cellPixelAspect() {
            environment.imageCellAspect = cellAspect
        }
        if let cellPixels = geometry?.cellPixelSize() {
            environment.publishCell(pixels: cellPixels, calibration: TerminalClient.cellPointsCalibration)
        }
    }
}
