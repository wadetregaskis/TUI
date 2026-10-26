//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollView+Glide.swift
//
//  The `ScrollView` half of an animated programmatic scroll: starting a
//  glide when a request made inside `withAnimation` resolves, stepping it on
//  the frames after, and landing it (decisions B27-ANIMATING; the stepping
//  itself is `ScrollGlide.swift`'s, shared by every scrollable).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

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
        let keyboard = handler.glide?.isKeyboard == true
        guard let landing = handler.advanceGlide(viewport: viewport, context: context) else { return }
        handler.noteGlideLanded()
        // A key's glide is the user's scroll, quiet from its landing.
        if keyboard { handler.lastUserScrollNanos = handler.phaseNow() }
        switch landing {
        case .distance, .rowPosition, .listSeek:
            break
        case .seek(let request):
            parkLandingSeek(request, handler: handler)
        case .offset(let y):
            handler.jumpProgrammatically(to: max(0, min(y, handler.maxOffset)))
        case .top:
            handler.jumpProgrammatically(to: 0)
        case .bottom:
            handler.jumpProgrammatically(to: handler.maxOffset)
            handler.seekingTail = true
        }
    }

    /// The same for the columns of a view that scrolls horizontally: a column
    /// `scrollTo` on a purely horizontal view, or a ``ScrollPosition``'s `x`
    /// or leading or trailing edge. Its landing is sought again as a row's
    /// is, by the column seek; an offset or an edge is clamped to the extent
    /// the last frame measured, as the jump would have been.
    func settleHorizontalGlide(handler: ScrollViewHandler, viewport: CellSize, context: RenderContext) {
        let axis = handler.horizontal
        guard let landing = axis.advanceGlide(viewport: viewport, context: context) else { return }
        handler.noteGlideLanded()
        switch landing {
        case .seek(let request): parkLandingSeek(request, handler: handler)
        case .offset(let x): axis.scrollToOffset(max(0, min(x, axis.maxOffset)))
        case .top: axis.scrollToOffset(0)
        case .bottom: axis.scrollToOffset(axis.maxOffset)
        case .distance, .rowPosition, .listSeek: break
        }
    }

    /// Parks a landing glide's request for this frame's own seek, sought again
    /// unanimated — unless a `scrollTo` made since the last frame has taken
    /// its place, which supersedes it.
    private func parkLandingSeek(_ request: ScrollToRequest, handler: ScrollViewHandler) {
        guard handler.pendingScrollTo == nil else { return }
        handler.pendingScrollTo = request
        handler.pendingScrollToIsLanding = true
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
    /// cancels it. `horizontally` moves the view's columns instead of its
    /// rows; their jump is clamped to the extent the last frame measured, as
    /// it always was.
    @discardableResult
    func moveProgrammatically(
        handler: ScrollViewHandler, horizontally: Bool = false, to offset: Int, landing: ScrollGlide.Landing,
        viewport: CellSize, context: RenderContext
    ) -> Bool {
        let glides = glideIfAnimated(
            handler: handler, horizontally: horizontally, to: offset, landing: landing, viewport: viewport,
            context: context)
        if glides { return true }
        handler.stopGlide(horizontally: horizontally)
        if horizontally {
            handler.horizontal.scrollToOffset(offset)
        } else {
            handler.jumpProgrammatically(to: offset)
        }
        return false
    }

    /// Starts a glide to `offset` when this frame's transaction animates, and
    /// the view is ``ScrollPhase/animating`` from this frame to the landing's;
    /// answers whether it started one. A glide in flight is replaced, so the
    /// new one starts from the line the old one is drawn on this frame, at
    /// rest. Nothing starts when the view is already there. `horizontally`
    /// glides the columns, on the horizontal axis's own glide, so a view that
    /// scrolls both ways can glide along both at once.
    func glideIfAnimated(
        handler: ScrollViewHandler, horizontally: Bool = false, to offset: Int, landing: ScrollGlide.Landing,
        viewport: CellSize, context: RenderContext
    ) -> Bool {
        guard let animation = context.scrollGlideAnimation else { return false }
        let axis: any ScrollableOffsetState = horizontally ? handler.horizontal : handler
        guard axis.beginGlide(to: offset, animation: animation, landing: landing, viewport: viewport, context: context)
        else { return false }
        handler.phase = .animating
        return true
    }
}

extension ScrollViewHandler {
    /// Whether either axis is gliding: the rows, or the columns.
    var isGliding: Bool { glide != nil || horizontal.glide != nil }

    /// Stops a glide in flight where it stands, with no landing — the rows',
    /// or with `horizontally` the columns' — and returns the view to
    /// ``ScrollPhase/idle`` if it was ``ScrollPhase/animating`` and the other
    /// axis is not gliding either. What stops it moves the view itself: a jump
    /// to another request, or the reveal of a control the focus moved to.
    func stopGlide(horizontally: Bool = false) {
        if horizontally {
            guard horizontal.glide != nil else { return }
            horizontal.glide = nil
        } else {
            guard glide != nil else { return }
            glide = nil
        }
        noteGlideLanded()
    }

    /// Returns the view to ``ScrollPhase/idle`` from
    /// ``ScrollPhase/animating`` once neither axis glides: a view gliding
    /// both ways is animating until both have landed.
    func noteGlideLanded() {
        if phase == .animating, !isGliding { phase = .idle }
    }
}
