//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+TerminalGraphics.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

extension View {

    /// Sets whether ``Image`` views within this view draw with the terminal's
    /// own graphics protocol.
    ///
    /// Where the terminal will place an image in its cell grid, TUIkit draws
    /// the real picture — roughly fifty times the pixels of the glyph
    /// renderer, in full colour, with no palette quantisation and no contrast
    /// floor. Where it will not, nothing changes: the glyph renderer draws
    /// what it always drew. The handshake at startup is what decides, so this
    /// modifier is about **preference**, not availability.
    ///
    /// Turn it off for a subtree that wants the glyphs on purpose — and that
    /// is a real want, not only a fallback. A dashboard built around
    /// ``ASCIICharacterSet/blocks(_:)`` or a `.customRamp` has a look, and an
    /// app should not have that look change on exactly the terminals that can
    /// draw a photograph:
    ///
    /// ```swift
    /// Image(.file("logo.png"))
    ///     .imageCharacterSet(.blocks(.halves))
    ///     .terminalGraphics(false)   // the ramp IS the design
    /// ```
    ///
    /// ## The picture is still made of cells, and that is visible when it is small
    ///
    /// A virtual placement declares its size in **cells** — `c=` columns by
    /// `r=` rows — so an image always occupies a whole number of them. That is
    /// not a limitation working around something: it is the property that lets
    /// the picture be clipped, scrolled, composited and diffed by the code
    /// that already does those things to text.
    ///
    /// The cost shows at small sizes, where rounding to whole cells is a large
    /// fraction of the picture. Shrink an image far enough and it snaps to
    /// 2 cells, then 1, and stops: **one cell is the floor**, because there is
    /// no such thing as half a placement. Between those steps the cell box's
    /// own proportions can differ noticeably from the image's, since a cell is
    /// roughly twice as tall as it is wide and the box is whole cells either
    /// way. The glyph renderer quantises identically — it has always drawn
    /// into whole cells — so this is not a difference between the two
    /// renderers, only one that a real picture makes easy to see.
    ///
    /// - Parameter enabled: Whether images use the terminal's graphics
    ///   protocol where it has one (default `true`).
    /// - Returns: A view whose images honour the setting.
    public func terminalGraphics(_ enabled: Bool = true) -> some View {
        environment(\.terminalGraphics, enabled)
    }

    /// Sets the terminal cell's pixel size for the subtree — what an
    /// ``Image`` is resampled to before it is handed to the terminal.
    ///
    /// Published automatically at startup from `TIOCGWINSZ`, which all four
    /// measured hosts answer. Override it for a terminal that reports nothing
    /// or reports nonsense; the sibling ``View/imageCellAspect(_:)`` is the
    /// one to reach for if the problem is that pictures look *stretched*
    /// rather than *soft*.
    ///
    /// - Parameter pixels: The cell's size.
    /// - Returns: A modified view.
    public func imageCellPixels(_ pixels: TerminalCellPixels) -> some View {
        environment(\.imageCellPixels, pixels)
    }

    /// Sets the terminal cell's size in points for the subtree — what an
    /// ``Image`` that is not resizable divides its natural size by.
    ///
    /// Published automatically on the hosts whose reports have been measured
    /// (see ``EnvironmentValues/imageCellPoints``). Set it for a terminal
    /// TUIkit cannot ask, to give its images their natural size; set `nil` to
    /// have them fit what they are offered instead.
    ///
    /// - Parameter points: The cell's size, in points, or `nil` for unknown.
    /// - Returns: A modified view.
    public func imageCellPoints(_ points: TerminalCellPoints?) -> some View {
        environment(\.imageCellPoints, points)
    }
}
