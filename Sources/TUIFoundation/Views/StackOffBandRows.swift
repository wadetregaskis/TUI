//  🖥️ TUI — A Terminal UI framework for Swift
//  StackOffBandRows.swift
//
//  The rows a windowed lazy stack draws outside its band — the focused row
//  and its neighbours, a pending focus target, wherever they are — for their
//  side effects: their regions, and their places in the focus ring. Shared by
//  the uniform and the anchored paths (`StackUniformWindow.swift`,
//  `StackAnchoredWindow.swift`), and moved out of the first when drawing a
//  row came apart from grafting it, so that a row above the band is drawn
//  before the band.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

@MainActor extension _VStackCore {
    /// Draws an off-band row — the focused row or a neighbour of it, a pending
    /// focus target — for its side effects, focus registration above all,
    /// for ``graftOffBandRow(_:into:bandLocalY:)`` to graft.
    ///
    /// Drawn apart from its graft so that a row ABOVE the band — the focused
    /// row's neighbour there, the one Shift+Tab goes to next — is drawn before
    /// the band's rows: drawing is where a control files itself in the focus
    /// ring, so a row drawn after the band came after the band's last row in
    /// the ring, though it stands above its first. Shift+Tab from the band's
    /// top row then went past it, out of the stack, to the control before the
    /// scroll view (the brief of 2026-11-10). A row below the band is drawn
    /// after it, where it stands; Tab down was never affected.
    func drawOffBandRow(
        _ child: ChildView, width: Int, viewportHeight: Int, context: RenderContext
    ) -> FrameBuffer {
        child.render(width: width, height: viewportHeight, context: context)
            .horizontallyAligned(toWidth: width, alignment: alignment)
    }

    /// Grafts an off-band row's hit-test regions and overlays, drawn by
    /// ``drawOffBandRow(_:width:viewportHeight:context:)``, into the band
    /// buffer at the row's band-local y, WITHOUT adding any lines.
    /// Materialising the band→row gap as blank lines would cost O(distance)
    /// time and memory every frame the control stays focused off-window (and
    /// the universal render clamp then truncates the lines while keeping the
    /// regions, corrupting the band). Regions are pure rects, so they sit
    /// happily outside the band's line range — negative or far beyond — where
    /// the ScrollView's reveal math reads them and its viewport clip then
    /// drops the invisible ones.
    ///
    /// `result` holds the whole band by then. A row above it comes before
    /// every row in it, so what the row draws past its region
    /// (`OverlayLayer.isOverflow`, a badge hung down by an alignment guide)
    /// is cut where the band paints, as the stack's own combining operation
    /// would cut it: grafted uncut, it drew over the rows the window shows. A
    /// row below the band comes after it, and its overflow is drawn over the
    /// band, as it is.
    func graftOffBandRow(_ drawn: FrameBuffer, into result: inout FrameBuffer, bandLocalY: Int) {
        var aligned = drawn
        result.appendHitTestRegions(of: aligned, shiftedByX: 0, y: bandLocalY)
        if bandLocalY < 0 { aligned.coverOverflow(under: result, at: (x: 0, y: -bandLocalY)) }
        result.appendOverlays(of: aligned, shiftedByX: 0, y: bandLocalY)
    }

    /// Those of the uniform path's off-band `rows` that lie above `band` (or
    /// below it), each drawn off the band (``drawOffBandRow(_:width:viewportHeight:context:)``)
    /// with its ordinal, in the context `rowContext` gives its ordinal and width.
    func drawOffBandRows(
        _ rows: [UniformBandRow], above: Bool, band: [UniformBandRow], width: Int, viewportHeight: Int,
        rowContext: (Int, Int) -> RenderContext
    ) -> [(ordinal: Int, drawn: FrameBuffer)] {
        let bandStart = band.first?.ordinal ?? Int.max
        return rows.filter { ($0.ordinal < bandStart) == above }.map { row in
            (row.ordinal, drawOffBandRow(
                row.child, width: width, viewportHeight: viewportHeight, context: rowContext(row.ordinal, row.width)))
        }
    }

    /// An anchored path's grafted row drawn off the band, placed in the ramp
    /// spanning the content at its estimated `y`.
    func drawAnchoredGraft(
        _ child: ChildView, measuredWidth: Int?, y: Int, gradient: GradientFrame?, width: Int, viewportHeight: Int,
        context: RenderContext
    ) -> FrameBuffer {
        drawOffBandRow(
            child, width: width, viewportHeight: viewportHeight,
            context: context.placingChild(
                gradient: gradient,
                x: Self.gradientX(childWidth: measuredWidth ?? width, extent: width, alignment: alignment), y: y))
    }
}
