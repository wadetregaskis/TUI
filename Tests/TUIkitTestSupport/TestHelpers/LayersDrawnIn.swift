//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayersDrawnIn.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIkitFoundation

extension FrameBuffer {
    /// This buffer with the layers it floats drawn into it, in the order the
    /// screen root draws them — level, then z-index, then the order they were
    /// emitted in — each over what is there, the buffer growing to hold them.
    ///
    /// What a test reads the whole picture from when something is drawn past
    /// its region: a stack's child gliding in from outside a stack that has
    /// just shrunk, a removed view whose room has gone (`StackGlide`), a
    /// spring's overshoot. `renderToBuffer` leaves those in ``overlays`` for
    /// the root to place, so its lines alone show only what stayed in flow.
    ///
    /// The displaced-drawing subset of the root's compositor
    /// (`FrameBuffer.compositingOverlays`, which this module cannot see): no
    /// dimming, no flipping at the screen's edge, and what lies above or left
    /// of the buffer's origin is cut.
    func withLayersDrawn() -> FrameBuffer {
        var result = self
        result.overlays = []
        let ordered = overlays.enumerated().sorted { lhs, rhs in
            if lhs.element.level != rhs.element.level { return lhs.element.level < rhs.element.level }
            if lhs.element.zIndex != rhs.element.zIndex { return lhs.element.zIndex < rhs.element.zIndex }
            return lhs.offset < rhs.offset
        }
        for (_, layer) in ordered {
            let reach = 1 << 16
            guard let visible = layer.cropped(x: 0, y: 0, width: reach, height: reach) else { continue }
            result = result.composited(
                with: visible.content.withLayersDrawn(), at: (x: visible.offsetX, y: visible.offsetY))
        }
        return result
    }
}

#endif
