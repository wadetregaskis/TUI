//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCapabilities.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - Cell Geometry

/// A terminal that can say how big its cells are in pixels.
///
/// A capability of its own rather than a requirement of ``TerminalProtocol``:
/// reporting the cell's pixel size is something a real terminal does through
/// `TIOCGWINSZ`, not something every host must implement. The render loop asks
/// for it by conformance rather than by casting to the concrete `Terminal`, so
/// a test's terminal can report a geometry, and change it between frames as a
/// font change does, and the loop publishes it as it publishes a real one.
@MainActor
protocol CellGeometryReporting: AnyObject {
    /// The cell's height-to-width ratio, or `nil` where it is not reported.
    func cellPixelAspect() -> Double?

    /// The cell's size in pixels, or `nil` where it is not reported.
    func cellPixelSize() -> TerminalCellPixels?
}

extension Terminal: CellGeometryReporting {}

// MARK: - Synchronized Output

/// A terminal that can hold its display while a frame is drawn: DEC mode
/// 2026, synchronized output.
///
/// A capability of its own, as ``CellGeometryReporting`` is, rather than a
/// requirement of the public ``TerminalProtocol``: it is how the real terminal
/// writes a frame, not something every host must implement. The render loop
/// looks for it once, when it is made.
@MainActor
protocol SynchronizedUpdating: AnyObject {
    /// Begins the frame being buffered's synchronized update here: after
    /// whatever draws nothing (image transmissions), before the first cell.
    /// See `Terminal.beginSynchronizedUpdate()`.
    func beginSynchronizedUpdate()
}

extension Terminal: SynchronizedUpdating {}
