//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCellGeometry.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Real pixels, where the terminal has them

/// A terminal cell's size in pixels, as the terminal reports it.
///
/// The sibling of ``EnvironmentValues/imageCellAspect``, which is this
/// divided out — and the reason both exist is that they answer different
/// questions. The *aspect* stops a circle looking like an ellipse and is
/// needed by every gradient and glyph-drawn image, so it has a sane default
/// and never needs to be right. The *size* decides how many real pixels an
/// image is transmitted with, so being wrong costs sharpness rather than
/// shape.
public struct TerminalCellPixels: Equatable, Sendable {
    /// A cell's width in pixels.
    public var width: Int
    /// A cell's height in pixels.
    public var height: Int

    /// Creates a cell size, clamped to at least one pixel each way.
    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }
}

/// A terminal cell's size in points — the unit SwiftUI sizes an image in.
///
/// What lets an ``Image`` that is not resizable take its natural size, as
/// SwiftUI's does: its pixels over its scale are its size in points, and this
/// says how many cells that is. Unlike ``TerminalCellPixels`` it has no
/// default: a terminal that does not say, or whose pixels are of a kind not
/// measured, leaves it unknown, and an image there fits what it is offered.
/// See ``EnvironmentValues/imageCellPoints``.
public struct TerminalCellPoints: Equatable, Sendable {
    /// A cell's width in points.
    public var width: Double
    /// A cell's height in points.
    public var height: Double

    /// Creates a cell size, in points. A size that is not finite and positive
    /// is a quarter of a point, so that nothing divides by it.
    public init(width: Double, height: Double) {
        self.width = width.isFinite && width > 0 ? width : 0.25
        self.height = height.isFinite && height > 0 ? height : 0.25
    }
}

private struct TerminalCellPointsKey: EnvironmentKey {
    static let defaultValue: TerminalCellPoints? = nil
}

private struct TerminalCellPixelsKey: EnvironmentKey {
    /// A plausible cell on an unscaled display, used where the terminal
    /// reports no pixel size. Transmitting at the wrong resolution is a
    /// quality question and not a correctness one — a virtual placement
    /// declares its size in CELLS, and the terminal fits the picture to them —
    /// so a terminal that will not say gets a reasonable guess rather than no
    /// image.
    ///
    /// Fits and CENTRES, preserving the source aspect ratio; it does not fill.
    /// (kitty's `graphics.c` and Ghostty's `graphics_unicode.zig` each say so
    /// in as many words.) This said "fill" until 2026-09-02, and the error was
    /// invisible because it cannot bite here: the picture handed over has
    /// already been resampled to the box, so the fit is exact and there is
    /// nothing to centre. It would bite the moment an UNRESAMPLED image were
    /// transmitted — see `Documentation/Images and terminal graphics/Compressed image transfer.md` §1.1.
    static let defaultValue = TerminalCellPixels(width: 8, height: 16)
}

private struct TerminalGraphicsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {

    /// The terminal cell's size in pixels, published by the render loop every
    /// frame from `TIOCGWINSZ`. Used to decide how many real pixels an
    /// ``Image`` is transmitted with.
    public var imageCellPixels: TerminalCellPixels {
        get { self[TerminalCellPixelsKey.self] }
        set { self[TerminalCellPixelsKey.self] = newValue }
    }

    /// The terminal cell's size in points, or `nil` where it is not known —
    /// published by the render loop every frame, on the hosts whose reports
    /// have been measured. An ``Image`` that is not resizable takes its
    /// natural size from it: its size in points, over this, in cells.
    ///
    /// Known on Apple Terminal, iTerm2 and Warp, and on Ghostty when the app
    /// runs on the Mac the terminal is on; unknown under tmux, which does not
    /// forward the cell's size, over ssh to Ghostty, and on every host not
    /// measured. Set it with ``View/imageCellPoints(_:)`` for a terminal
    /// TUIkit cannot ask.
    public var imageCellPoints: TerminalCellPoints? {
        get { self[TerminalCellPointsKey.self] }
        set { self[TerminalCellPointsKey.self] = newValue }
    }

    /// Whether ``Image`` draws with the terminal's own graphics protocol where
    /// one is available. Set via ``View/terminalGraphics(_:)``. Default:
    /// `true` — which still draws glyphs on every terminal that did not answer
    /// the startup handshake, because the two conditions are ANDed (see
    /// ``KittyGraphics/isSupported``).
    public var terminalGraphics: Bool {
        get { self[TerminalGraphicsKey.self] }
        set { self[TerminalGraphicsKey.self] = newValue }
    }
}
