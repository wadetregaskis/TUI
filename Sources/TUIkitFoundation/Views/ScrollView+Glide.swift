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
    ///
    /// Landed, the view is idle again (``ScrollPhase/animating`` ends), as
    /// SwiftUI's is when its animated `scrollTo` arrives (measured, B27).
    func settleGlide(handler: ScrollViewHandler, viewport: CellSize, context: RenderContext) {
        guard let landing = handler.advanceGlide(viewport: viewport, context: context) else { return }
        if handler.phase == .animating { handler.phase = .idle }
        switch landing {
        case .seek(let request):
            // A `scrollTo` made since the last frame supersedes the re-seek.
            guard handler.pendingScrollTo == nil else { return }
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
    /// a glide began, in which case the offset has not moved — the frame
    /// shows the glide's start, drawn again there where the band drawn at the
    /// request does not reach it (`coverSnappedViewport`) — and the view is
    /// ``ScrollPhase/animating`` from this frame to the landing's. A jump
    /// changes no phase, as an unanimated `scrollTo` changes none in SwiftUI
    /// (measured, B27).
    ///
    /// The target is clamped to the content as this frame measured it: a
    /// row near the end is shown at the last screenful, as the clamp after a
    /// jump would put it, and a glide that aims past the end would spend its
    /// last frames pressed against it.
    @discardableResult
    func adoptSeek(
        _ offset: Int, request: ScrollToRequest?, isLanding: Bool, handler: ScrollViewHandler,
        viewport: CellSize, context: RenderContext
    ) -> Bool {
        guard let request, !isLanding else {
            handler.jumpProgrammatically(to: offset)
            return false
        }
        return moveProgrammatically(
            handler: handler, to: max(0, min(offset, handler.maxOffset)), landing: .seek(request),
            viewport: viewport, context: context)
    }

    /// Moves the view to `offset` for a programmatic request: glides there
    /// when it was made inside an animation, answering `true`, and otherwise
    /// stops any glide in flight and jumps — a second request mid-glide
    /// retargets from where the first had got to, and an unanimated one
    /// cancels it.
    @discardableResult
    func moveProgrammatically(
        handler: ScrollViewHandler, to offset: Int, landing: ScrollGlide.Landing, viewport: CellSize,
        context: RenderContext
    ) -> Bool {
        if glideIfAnimated(handler: handler, to: offset, landing: landing, viewport: viewport, context: context) {
            return true
        }
        handler.stopGlide()
        handler.jumpProgrammatically(to: offset)
        return false
    }

    /// Starts a glide to `offset` when this frame's transaction animates, and
    /// the view is ``ScrollPhase/animating`` from this frame to the landing's;
    /// answers whether it started one. A glide in flight is replaced, so the
    /// new one starts from the line the old one is drawn on this frame, at
    /// rest. Nothing starts when the view is already there.
    func glideIfAnimated(
        handler: ScrollViewHandler, to offset: Int, landing: ScrollGlide.Landing, viewport: CellSize,
        context: RenderContext
    ) -> Bool {
        guard let animation = context.scrollGlideAnimation,
            handler.beginGlide(to: offset, animation: animation, landing: landing, viewport: viewport, context: context)
        else { return false }
        handler.phase = .animating
        return true
    }
}

extension ScrollViewHandler {
    /// Stops a glide in flight where it stands, with no landing, and returns
    /// the view to ``ScrollPhase/idle`` if it was ``ScrollPhase/animating``.
    /// What stops it moves the view itself: a jump to another request, or
    /// the reveal of a control the focus moved to.
    func stopGlide() {
        guard glide != nil else { return }
        glide = nil
        if phase == .animating { phase = .idle }
    }
}
