//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayCompositingOrderTests.swift
//
//  The order the screen root composites its floating layers in, where the
//  level and the z index tie: content past its region (`isOverflow`) is its
//  view's cells at its place in the stacking order, and goes under a layer
//  that floats over every view, whatever order the tree emitted them in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("Floating layers composited in order")
struct OverlayCompositingOrderTests {
    @Test("A floating layer is over overflow the tree emitted after it, at one level and z index")
    func floatOverLaterOverflow() {
        // A matched view in flight floats over every view (Deliberate
        // deviations A8); a later view's overflow is its cells at its place in
        // the stacking order. Both are `.popover` layers at the displaced
        // drawing z index, emitted float first: "oo" lands on cells 1 and 2,
        // the overflow's "rr" on cells 0 and 1, and the float must win cell 1.
        let float = OverlayLayer(
            offsetX: 1, offsetY: 0, content: FrameBuffer(lines: ["oo"]), level: .popover,
            zIndex: OverlayLayer.displacedDrawingZIndex, clampsToScreen: false, isOpaque: false)
        var overflow = OverlayLayer(
            offsetX: 0, offsetY: 0, content: FrameBuffer(lines: ["rr"]), level: .popover,
            zIndex: OverlayLayer.displacedDrawingZIndex, clampsToScreen: false, isOpaque: false)
        overflow.isOverflow = true
        var page = FrameBuffer(lines: ["      "])
        page.overlays = [float, overflow]
        let drawn = page.compositingOverlays(maxWidth: 6, maxHeight: 1, palette: EnvironmentValues().palette)
        #expect(drawn.lines.first?.stripped.hasPrefix("roo") == true, "\(drawn.lines.map(\.stripped))")
    }
}
