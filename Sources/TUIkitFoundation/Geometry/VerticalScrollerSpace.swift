//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VerticalScrollerSpace.swift
//
//  A vertical scroller other than `ScrollView` — a `List` — as the owner of
//  `.scrollView` for the views it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension RenderContext {
    /// The spaces a scroller that scrolls up and down answers for the views
    /// in it: `.scrollView`, and `.scrollView(axis: .vertical)`.
    private static var verticalScrollerSpaces: [CoordinateSpace] {
        [.named(ScrollViewSpaceName(axis: nil)), .named(ScrollViewSpaceName(axis: .vertical))]
    }

    /// `draw` — the whole frame of a vertical scroller other than a
    /// `ScrollView`, a `List`'s — drawn as the owner of `.scrollView` and
    /// `.scrollView(axis: .vertical)` for the views in it, as SwiftUI's list
    /// is itself the scroll view its rows are in: a view there asking either
    /// is answered in the viewport `draw` reports, the content window inside
    /// its chrome, which it fills as it scrolls.
    ///
    /// Answered as a `coordinateSpace(_:)` declaration answers: the frame is
    /// drawn, the views asking found in it, and where one drew from an answer
    /// that turned out wrong — its first frame, or one its row moved on — the
    /// walk is put back and the frame drawn once more (decisions B-D5G-9).
    /// The rows are not placed before they are drawn, so a reader's answer is
    /// the one it was found at last, corrected where its row has moved: a
    /// scrolled list with a reader in its rows costs one more drawing a frame.
    /// A view only draws twice there; nothing is drawn wrong.
    ///
    /// With nothing asking, which is nearly every frame of nearly every list,
    /// it costs the walk's checkpoint and one test of the geometry's waiting
    /// count.
    ///
    /// - Parameter draw: Draws the frame, returning it and its viewport —
    ///   `nil` for none, where nothing is answered.
    /// - Returns: The frame.
    package func drawingAsVerticalScroller(
        _ draw: () -> (buffer: FrameBuffer, viewport: CellRect?)
    ) -> FrameBuffer {
        guard !isMeasuring, let geometry = geometryCoordinator else { return draw().buffer }
        let spaces = Self.verticalScrollerSpaces
        let checkpoint = RenderWalkCheckpoint(context: self)
        // Opened, as a scroll view opens it, only where an origin is carried
        // here for the readers inside to be predicted from.
        let scope =
            carriesGeometryOrigin
            ? geometry.enterOwner(of: spaces, from: self, in: self, size: nil, scrollAxis: .vertical) : nil
        func drawn() -> (buffer: FrameBuffer, misled: Bool) {
            if let scope { geometry.reenterOwner(scope) }
            let frame = draw()
            if let scope { geometry.leaveOwner(scope) }
            guard let viewport = frame.viewport else { return (frame.buffer, false) }
            let misled = geometry.resolve(
                spaces, in: frame.buffer, size: CellSize(width: viewport.width, height: viewport.height),
                shift: CellPoint(x: -viewport.x, y: -viewport.y), scrollAxis: .vertical)
            return (frame.buffer, misled)
        }
        let first = drawn()
        guard first.misled else { return first.buffer }
        geometry.noteCorrection(.scrollView)
        checkpoint.rollBack(context: self)
        let second = drawn()
        if second.misled { geometry.noteResidual() }
        return second.buffer
    }
}
