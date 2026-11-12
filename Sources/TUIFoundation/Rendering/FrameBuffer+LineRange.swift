//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+LineRange.swift
//
//  Some of a buffer's lines as a buffer of their own: what a container that
//  draws chrome round a scroll band keeps of itself (SCROLL-FIT's forward
//  and parallel shapes), the lines its band holds.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension FrameBuffer {
    /// Lines `rows` of this buffer as a buffer of their own, everything that
    /// rides on them — hit regions, animated runs, translucent claims — cut to
    /// them and moved up with them (`OverlayLayer.cropped(x:y:width:height:)`).
    ///
    /// The regions of the lines left out are carried at their place outside
    /// the buffer, as a section carries a header its band leaves out: a focus
    /// move onto a control there still finds where to scroll. Floating layers
    /// travel whole, moved up: they float free of the lines already.
    package func lines(in rows: Range<Int>) -> FrameBuffer {
        let kept = rows.clamped(to: 0..<height)
        guard kept != 0..<height else { return self }
        var bare = self
        bare.overlays = []
        let whole = OverlayLayer(offsetX: 0, offsetY: 0, content: bare, clampsToScreen: false, isOpaque: false)
        var part =
            whole.cropped(x: 0, y: kept.lowerBound, width: width, height: kept.count)?.content
            ?? FrameBuffer(emptyWithHeight: kept.count)
        let dy = -kept.lowerBound
        for region in hitTestRegions
        where region.offsetY + region.height <= kept.lowerBound || region.offsetY >= kept.upperBound {
            part.hitTestRegions.append(region.shifted(byX: 0, y: dy))
        }
        if !overlays.isEmpty { part.overlays = shiftedOverlays(byX: 0, y: dy) }
        return part
    }
}
