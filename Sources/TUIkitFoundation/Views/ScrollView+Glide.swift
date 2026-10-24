//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Glide.swift
//
//  The `ScrollView` half of an animated programmatic scroll: starting a
//  glide when a request made inside `withAnimation` resolves, stepping it on
//  the frames after, and landing it (decisions B27-ANIMATING; the stepping
//  itself is `ScrollGlide.swift`'s, shared by every scrollable).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension _ScrollViewCore {

    /// Moves a glide in flight to this frame's line, and lands it when its
    /// animation is done — or at once, when the viewport has changed size
    /// under it. Before anything that reads the offset: the bottom glue, a
    /// position request, the content's drawing.
    ///
    /// The landing applies the request once more, unanimated, through the
    /// path it would have taken unanimated: a seek is parked for this frame's
    /// own seek to resolve, from the target the last step put the view at, so
    /// it moves only as far as rows that arrived between the viewport and the
    /// row, or heights estimated along the way, put it out.
    func settleGlide(handler: ScrollViewHandler, viewport: CellSize, context: RenderContext) {
        guard let landing = handler.advanceGlide(viewport: viewport, context: context) else { return }
        switch landing {
        case .seek(let request):
            handler.pendingScrollTo = request
            handler.pendingScrollToIsLanding = true
        case .offset(let y):
            handler.jumpProgrammatically(to: max(0, min(y, handler.maxOffset)))
        case .top:
            handler.jumpProgrammatically(to: 0)
        case .bottom:
            handler.jumpProgrammatically(to: handler.maxOffset)
            handler.seekingTail = true
        }
    }

    /// Spends the parked `scrollTo` request once the content has been drawn
    /// with it — one-shot, found or not — and answers whether it was a
    /// glide's landing, sought again, which jumps. Render passes only.
    func spendSeekRequest(handler: ScrollViewHandler, context: RenderContext) -> Bool {
        guard !context.isMeasuring else { return false }
        defer { (handler.pendingScrollTo, handler.pendingScrollToIsLanding) = (nil, false) }
        return handler.pendingScrollToIsLanding
    }

    /// Adopts the offset a seek resolved to: glides there when `request` was
    /// made inside an animation, and jumps there otherwise — always when it
    /// is a glide's landing, sought again (`isLanding`), and when there is no
    /// request (`nil`: the offset the top-row hold moved to). Answers whether
    /// a glide began, in which case the offset has not moved and the frame
    /// draws the glide's start.
    ///
    /// The target is clamped to the content as this frame measured it: a
    /// row near the end is shown at the last screenful, as the clamp after a
    /// jump would put it, and a glide that aims past the end would spend its
    /// last frames pressed against it.
    func adoptSeek(
        _ offset: Int, request: ScrollToRequest?, isLanding: Bool, handler: ScrollViewHandler,
        viewport: CellSize, context: RenderContext
    ) -> Bool {
        if let request, !isLanding, let animation = context.scrollGlideAnimation,
            handler.beginGlide(
                to: max(0, min(offset, handler.maxOffset)), animation: animation, landing: .seek(request),
                viewport: viewport, context: context)
        {
            return true
        }
        handler.jumpProgrammatically(to: offset)
        return false
    }
}
