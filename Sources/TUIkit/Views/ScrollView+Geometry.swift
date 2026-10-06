//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Geometry.swift
//
//  The scroll view as the owner of `.scrollView` and `.scrollView(axis:)`:
//  the space of its viewport, which the content moves through as it scrolls.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension _ScrollViewCore {
    /// The spaces this scroll view answers for the views in it: `.scrollView`,
    /// and `.scrollView(axis:)` for each axis it scrolls along.
    var ownedSpaces: [CoordinateSpace] {
        var spaces: [CoordinateSpace] = [.named(ScrollViewSpaceName(axis: nil))]
        if axes.contains(.vertical) { spaces.append(.named(ScrollViewSpaceName(axis: .vertical))) }
        if axes.contains(.horizontal) { spaces.append(.named(ScrollViewSpaceName(axis: .horizontal))) }
        return spaces
    }

    /// Opens this view as the owner of its spaces while its content is drawn,
    /// for the readers there to be told where they are in its viewport before
    /// they are drawn — `nil` in a measure, and where nothing above carries an
    /// origin to measure the viewport's from (`RenderContext.geometryOriginX`):
    /// a scroll view predicts, it does not start the carried origin.
    ///
    /// The viewport's origin is taken as this view's own; the content is
    /// placed at minus the offsets, slid as the window will slide it — the
    /// overscroll excursion, the alignment anchor's shift
    /// (``contentSlide(handler:viewportHeight:context:)``) — so a push past an
    /// edge moves a reader in `.scrollView` and every space around it as the
    /// content moves, with no correction. The "N more" line a reserved
    /// indicator puts above the window moves the window within the view by a
    /// constant the readers' residuals carry, and changes nothing in
    /// `.scrollView` itself, which is measured from the window.
    func enterScrollSpace(viewport: CellSize, context: RenderContext) -> GeometryOwnerScope? {
        guard !context.isMeasuring, context.carriesGeometryOrigin, let geometry = context.geometryCoordinator
        else { return nil }
        return geometry.enterOwner(
            of: ownedSpaces, from: context, in: context, size: viewport, scrollAxis: scrollAxis)
    }

    /// The axis a scroll transition naming none follows here: this view's,
    /// `.vertical` when it scrolls both ways (SwiftUI's rule).
    var scrollAxis: Axis { axes.contains(.vertical) ? .vertical : .horizontal }

    /// Closes what ``enterScrollSpace(viewport:context:)`` opened.
    func leaveScrollSpace(_ scope: GeometryOwnerScope?, context: RenderContext) {
        guard let scope, let geometry = context.geometryCoordinator else { return }
        geometry.leaveOwner(scope)
    }

    /// The content window as the frame shows it, before the chrome is drawn
    /// around it: this view's `.scrollView` space, and the viewport its scroll
    /// visibility observers are measured against.
    ///
    /// As the owner of that space, this finds the readers asking about it in
    /// the window, and when one drew from where this view had it last frame
    /// draws the content once more, at the offset the frame settled on — the
    /// walk put back first (`checkpoint`), so nothing in it registers twice;
    /// and put back again should that drawing refute the content's measure
    /// and be drawn once more (`renderedContent`), or the ids would move.
    func ownedContentWindow(
        drawing: ScrollContentDrawing, checkpoint: RenderWalkCheckpoint?, handler: ScrollViewHandler,
        chrome: ScrollChrome, viewport: CellSize, horizontal: Bool, context: RenderContext
    ) -> FrameBuffer {
        let (width, height) = (viewport.width, viewport.height)
        settlePlacement(of: drawing, handler: handler, viewport: viewport, horizontal: horizontal, context: context)
        var window = drawnViewport(
            full: drawing.buffer, sliceOriginY: drawing.slice?.originY ?? 0, handler: handler, chrome: chrome,
            width: width, height: height, horizontal: horizontal, context: context)
        if let checkpoint, ownScrollSpace(in: window, viewport: viewport, context: context) {
            checkpoint.rollBack(context: context)
            let redrawn = renderedContent(
                contentWidth: width, viewportHeight: height, horizontal: horizontal,
                verticalScrollOffset: handler.scrollOffset, horizontalScrollOffset: handler.horizontal.scrollOffset,
                slide: contentSlide(handler: handler, viewportHeight: height, context: context),
                checkpoint: checkpoint, context: context)
            handler.contentHeight = redrawn.slice?.totalHeight ?? redrawn.buffer.height
            handler.contentHeightIsEstimate = redrawn.slice?.totalIsEstimate ?? false
            handler.clampScrollOffset()
            settlePlacement(
                of: ScrollContentDrawing(
                    buffer: redrawn.buffer, slice: redrawn.slice, drawnLines: redrawn.drawnLines,
                    placement: redrawn.placement),
                handler: handler, viewport: viewport, horizontal: horizontal, context: context)
            window = drawnViewport(
                full: redrawn.buffer, sliceOriginY: redrawn.slice?.originY ?? 0, handler: handler,
                chrome: chrome, width: width, height: height, horizontal: horizontal, context: context)
            settleScrollSpace(in: window, viewport: viewport, context: context)
        }
        context.measureScrollVisibility(in: window, viewport: CellRect(x: 0, y: 0, width: width, height: height))
        return window
    }

    /// How far the window is slid up over the content past the vertical
    /// offset, as drawn (`applyOverscroll`): the overscroll excursion —
    /// negative past the top, the content pushed down — less the alignment
    /// anchor's shift of content shorter than the viewport.
    func contentSlide(handler: ScrollViewHandler, viewportHeight: Int, context: RenderContext) -> Int {
        handler.overscrollState.excursion
            - alignmentShift(handler: handler, viewportHeight: viewportHeight, context: context)
    }

    /// Where the frame shows the content's top-left in the viewport: minus
    /// the offsets it settled on, slid as the window is
    /// (``contentSlide(handler:viewportHeight:context:)``).
    func settledPlacement(
        handler: ScrollViewHandler, viewportHeight: Int, horizontal: Bool, context: RenderContext
    ) -> CellPoint {
        CellPoint(
            x: horizontal ? -handler.horizontal.scrollOffset : 0,
            y: -handler.scrollOffset - contentSlide(handler: handler, viewportHeight: viewportHeight, context: context))
    }

    /// Moves what the readers `drawing` drew were predicted, for the spaces no
    /// owner has answered yet, by how far the content moved after it was drawn.
    ///
    /// The content is drawn at the offset the frame began with (or a band's
    /// redraw at its own), and the offset can move after: the glue to a tail
    /// that grew, a seek the content resolved (which drops an excursion too),
    /// the clamp, the focus snap over eager content. The readers were told where they would be at the offset
    /// they were drawn at, and are found where they are at the one the frame
    /// settled on. That is a wrong answer, and an owner corrects it; but the
    /// prediction is what the next prediction is corrected by (the residual,
    /// ``GeometryAsk``), so it is moved to the settled offset first — kept as
    /// made, the residual would carry the move, and the correction's own
    /// drawing, at the settled offset, would add it once more and draw every
    /// reader off by it.
    func settlePlacement(
        of drawing: ScrollContentDrawing, handler: ScrollViewHandler, viewport: CellSize, horizontal: Bool,
        context: RenderContext
    ) {
        guard !context.isMeasuring, let geometry = context.geometryCoordinator, geometry.unansweredTotal > 0 else {
            return
        }
        let settled = settledPlacement(
            handler: handler, viewportHeight: viewport.height, horizontal: horizontal, context: context)
        guard settled != drawing.placement else { return }
        geometry.movePredictions(
            in: drawing.buffer,
            by: CellPoint(x: settled.x - drawing.placement.x, y: settled.y - drawing.placement.y))
    }

    /// Finds the views asking this scroll view's space in the content window
    /// the frame settled on, and answers whether one of them drew from a wrong
    /// answer — which the caller corrects by drawing the content again.
    ///
    /// The space is the viewport (measured on SwiftUI: a reader forty rows
    /// down a view scrolled forty rows reports `y == 0`, and `bounds(of:)`
    /// the viewport's rectangle), so a view is found where the window shows
    /// it, whether or not it is on screen: a marker keeps its unclipped
    /// origin through the window's clip.
    ///
    /// - Parameters:
    ///   - window: The content window, before the chrome is drawn around it.
    ///   - viewport: The window's size.
    /// - Returns: Whether a reader must be drawn again.
    func ownScrollSpace(in window: FrameBuffer, viewport: CellSize, context: RenderContext) -> Bool {
        guard let geometry = context.geometryCoordinator,
            geometry.resolve(ownedSpaces, in: window, size: viewport, scrollAxis: scrollAxis)
        else { return false }
        geometry.noteCorrection(.scrollView)
        return true
    }

    /// ``ownScrollSpace(in:viewport:context:)`` for the window drawn by the
    /// correction: what it finds is kept, and a reader still wrong is counted.
    func settleScrollSpace(in window: FrameBuffer, viewport: CellSize, context: RenderContext) {
        guard let geometry = context.geometryCoordinator,
            geometry.resolve(ownedSpaces, in: window, size: viewport, scrollAxis: scrollAxis)
        else { return }
        geometry.noteResidual()
    }
}
