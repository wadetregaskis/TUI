//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+CellAspect.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Environment Key

/// Environment key for the terminal cell's height:width ratio (see
/// ``View/imageCellAspect(_:)``). Defaults to `2.0` — Apple Terminal's typical
/// cell — and is republished at the render root from the terminal's reported
/// pixel size when available.
private struct ImageCellAspectKey: EnvironmentKey {
    static let defaultValue: Double = 2.0
}

// MARK: - EnvironmentValues

extension EnvironmentValues {
    /// The terminal cell's height:width ratio, used to size an image so it isn't
    /// distorted. See ``View/imageCellAspect(_:)``.
    ///
    /// Sanitised on the way in, by the same rule `ASCIIConverter.targetSize`
    /// applies to its own argument (TUIStyling's `sanitizedCellAspect(_:)`,
    /// which the converter forwards to), so the environment and the converter
    /// cannot disagree about what a usable ratio is.
    public var imageCellAspect: Double {
        get { self[ImageCellAspectKey.self] }
        set { self[ImageCellAspectKey.self] = sanitizedCellAspect(newValue) }
    }
}

// MARK: - View Modifier

extension View {
    /// Sets the terminal cell's height-to-width ratio for image sizing.
    ///
    /// A terminal cell is taller than it is wide, so an image needs more columns
    /// than rows to look undistorted. This ratio governs by how much: `2.0` (the
    /// default, ~Apple Terminal) means cells are twice as tall as wide, so a
    /// square image is laid out roughly 2 columns per row. The real ratio depends
    /// on the terminal, font, and line spacing — iTerm2's differs from Apple
    /// Terminal's, which is why an image tuned for one looks horizontally
    /// squished or stretched on the other.
    ///
    /// TUI auto-detects the ratio from the terminal's reported pixel cell size
    /// where available; set this explicitly to override it (e.g. to match a
    /// custom font or a terminal that doesn't report its cell size).
    ///
    /// - Parameter ratio: Cell height ÷ cell width. NaN, infinities and values
    ///   ≤ 0 are ignored (the default `2.0` applies); values outside
    ///   `ASCIIConverter.cellAspectRange` (`0.1…10`) are clamped to it.
    /// - Returns: A modified view.
    public func imageCellAspect(_ ratio: Double) -> some View {
        // No `ratio > 0 ? ratio : 2.0` here any more: the environment's setter
        // applies the one copy of the rule (TUIStyling's
        // `sanitizedCellAspect`, which the converter forwards to), and a second
        // copy of it was how this one came to admit `.infinity`.
        environment(\.imageCellAspect, ratio)
    }
}
