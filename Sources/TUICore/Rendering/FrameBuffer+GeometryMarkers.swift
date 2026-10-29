//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+GeometryMarkers.swift
//
//  Reading back where the geometry markers a buffer carries ended up.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Finding Markers

extension FrameBuffer {
    /// Calls `body` with each geometry marker this buffer carries and where it
    /// sits, in this buffer's coordinates moved by (`offsetX`, `offsetY`) — see
    /// ``HitTestRegion/geometryMarker(_:)``.
    ///
    /// The in-flow regions, and the regions of the layers that are this
    /// buffer's own DRAWING displaced — `.offset`, `.position`, a transition's
    /// overshoot — at those layers' offsets: a view moved by `.offset` is
    /// carried up as a layer, and a marker inside it is where that view is
    /// drawn. Three kinds of layer are not descended into:
    ///
    /// - a SURFACE (``OverlayLayer/isOpaque``): a sheet, a popover, a menu, a
    ///   tooltip is drawn over the page, not in it, and SwiftUI's named spaces
    ///   do not reach across a presentation into its content. The screen root
    ///   finds those after it composites them, where they finally are.
    /// - a pinned section header's COPY (`OverlayLayer.scrollPin`): what it
    ///   holds is already in the flow, at its own place; read here, a marker
    ///   in the header would answer for the pinned copy instead.
    /// - overflow (`OverlayLayer.isOverflow`): it is content past its region,
    ///   a scroll view's past the viewport, whose markers the window already
    ///   carries (a clip keeps a marker whole), so it would only answer twice.
    ///
    /// - Parameters:
    ///   - offsetX: Added to every column reported.
    ///   - offsetY: Added to every row reported.
    ///   - body: Receives each marker's id and its position.
    public func forEachGeometryMarker(
        offsetX: Int = 0, offsetY: Int = 0, _ body: (HitTestRegion.HandlerID, _ x: Int, _ y: Int) -> Void
    ) {
        for region in hitTestRegions where region.isGeometryMarker {
            body(region.handlerID, offsetX + region.offsetX, offsetY + region.offsetY)
        }
        for layer in overlays where layer.carriesDisplacedDrawing {
            layer.content.forEachGeometryMarker(
                offsetX: offsetX + layer.offsetX, offsetY: offsetY + layer.offsetY, body)
        }
    }

    /// Whether this buffer carries any geometry marker that
    /// ``forEachGeometryMarker(offsetX:offsetY:_:)`` would report.
    public var carriesGeometryMarkers: Bool {
        hitTestRegions.contains(where: \.isGeometryMarker)
            || overlays.contains { $0.carriesDisplacedDrawing && $0.content.carriesGeometryMarkers }
    }

    /// Removes every hit-test TARGET, keeping the geometry markers and the
    /// text frames (``HitTestRegion/HandlerID/textFrame``).
    ///
    /// For a view that makes what it wraps inert — `.allowsHitTesting(false)`,
    /// the page under a modal — rather than a view that removes it: an inert
    /// view is still drawn where it is drawn, and a reader inside it still asks
    /// where that is, and a selection over its text still keeps to the text.
    /// Clearing ``hitTestRegions`` outright took the markers with the targets.
    public mutating func removeHitTargets() {
        guard !hitTestRegions.isEmpty else { return }
        hitTestRegions.removeAll { !$0.isGeometryMarker && !$0.isTextFrame }
    }
}

extension OverlayLayer {
    /// Whether this layer is its carrier's own drawing, displaced — where a
    /// geometry marker inside it is where its view is drawn. See
    /// ``FrameBuffer/forEachGeometryMarker(offsetX:offsetY:_:)``.
    var carriesDisplacedDrawing: Bool {
        !isOpaque && scrollPin == nil && !isOverflow
    }
}
