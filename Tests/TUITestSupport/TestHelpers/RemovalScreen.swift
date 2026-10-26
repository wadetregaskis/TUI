//  🖥️ TUI — A Terminal UI framework for Swift
//  RemovalScreen.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIFoundation

/// A view drawn frame by frame, the frames a clock apart and every one of them
/// under `animation` — what a removal transition is tested on.
///
/// Each frame is one render pass, fenced the way the render loop fences it
/// (`DepartureStore.beginRenderPass` / `endRenderPass`), so a view that is not
/// re-declared is gone and a `nil` can play out what it left behind.
@MainActor
final class RemovalScreen<Content: View> {
    private var context: RenderContext
    private let content: (Bool) -> Content

    /// - Parameters:
    ///   - animation: The animation every frame is drawn under, or `nil` for
    ///     none: a removal then snaps.
    ///   - width: The width the view is offered.
    ///   - content: The view, with what comes and goes there or not.
    init(
        animation: Animation?, width: Int = 8,
        content: @escaping (_ showing: Bool) -> Content
    ) {
        self.content = content
        context = makeRenderContext(width: width, height: 6)
        context.environment.canAnimate = true
        if let animation {
            context.environment.transaction = Transaction(animation: animation)
        }
    }

    /// The view at `millis` on the frame clock, with what comes and goes there
    /// or not, styling stripped — and what is drawn past a stack drawn in
    /// (``FrameBuffer/withLayersDrawn()``): a removed view's room goes at once,
    /// so while it leaves it, and the siblings gliding into its room, are
    /// drawn past the stack that has closed up (`StackGlide`).
    func draw(_ showing: Bool, atMillis millis: Int) -> [String] {
        buffer(showing, atMillis: millis).withLayersDrawn().lines.map(\.stripped)
    }

    /// The strengths of the fades the frame at `millis` still carries — those
    /// over nothing, which no compositor in the tree resolved — its layers'
    /// included, to two places.
    func fades(_ showing: Bool, atMillis millis: Int) -> [Double] {
        func strengths(_ buffer: FrameBuffer) -> [Double] {
            buffer.opacityRegions.map { ($0.opacity * 100).rounded() / 100 }
                + buffer.overlays.flatMap { strengths($0.content) }
        }
        return strengths(buffer(showing, atMillis: millis))
    }

    /// The frame at `millis`, as drawn.
    private func buffer(_ showing: Bool, atMillis millis: Int) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(content(showing), context: context)
    }
}

#endif
