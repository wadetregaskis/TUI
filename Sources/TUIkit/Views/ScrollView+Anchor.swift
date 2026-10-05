//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Anchor.swift
//
//  How a `ScrollView` honours the EDGE anchor modes of
//  `Documentation/Scroll-anchoring.md` §1.1 — Bottom (follow-the-log) and Top —
//  from the declared `defaultScrollAnchor` and, equally, from a bound
//  `.anchorPosition`, which §3.2 defines as the code-side `anchor(to:)`.
//
//  Both are POSITIONAL policies: engagement is "the offset is already at that
//  edge", never a stored flag, so scrolling away releases them by construction
//  and scrolling back re-engages. The one thing that must be remembered across
//  frames is a *newly written* bound edge — see `adoptWrittenAnchor`.
//
//  And the third role, `ScrollAnchorRole.alignment`: where content shorter
//  than the viewport is drawn in it — see `alignmentShift`.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _ScrollViewCore {

    /// Bottom edge affinity (defaultScrollAnchor(.bottom), §5c/§6c): being
    /// AT the bottom is the engagement — no stored flag. If last frame's
    /// numbers say the offset sits at (or past) the tail — BOTH of them,
    /// content and viewport, which is what `tailAsLastDrawn` records — the
    /// view is glued: the frame renders at the previous tail, the post-render
    /// re-glue lands on the real new maximum, and `coverSnappedViewport`
    /// re-renders — O(window) — when the band's margin doesn't already
    /// cover the difference (it does for the common one-row append).
    /// Scrolling up breaks the condition (offset < max) and appends stop
    /// moving the view; any scroll that lands back at the bottom
    /// re-engages. Vertical only.
    ///
    /// The OPENING frame is glued by definition, not by those numbers: that is
    /// the initial at-the-tail placement. It used to follow from them — a view
    /// that has never been drawn has a content height of 0, so an offset of 0
    /// is its maximum — until every app's first frame began to run a measuring
    /// walk first (to size the app header), which records the real height. The
    /// render after it then saw an offset of 0 far short of the maximum, and a
    /// bottom-anchored view opened at its TOP in every app. Tests rendering the
    /// view directly never ran that walk; `HeadlessApp` does.
    ///
    /// Deliberately NO pre-render tail estimate: this used to measure the
    /// whole content tree every glued frame to pre-position the offset, and
    /// that estimate systematically disagreed with the post-render reply
    /// total (they come from different estimators), so the coverage
    /// re-render fired EVERY frame — a full measure plus two band renders
    /// per frame, 23% of the scrollfollow profile in the second render
    /// alone.
    func isGluedToBottom(handler: ScrollViewHandler, context: RenderContext) -> Bool {
        // The EFFECTIVE anchor, not just the declaration: a bound
        // `.anchorPosition` of `.bottom` must follow the tail even with no
        // `defaultScrollAnchor` (that is §3.2's `anchor(to:)`), and a bound
        // `.window` / `.top` / `.row` must override a declared `.bottom` — a
        // release the user made by scrolling away has to actually stop the
        // follow, or `.window` would be a read-out with no behaviour behind it.
        // The OPENING frame consults the `.initialOffset` anchor and every
        // frame after it the `.sizeChanges` one — the same value for any view
        // that used the unlabelled modifier. See `ScrollAnchorMode.governing`.
        let modes = context.environment.declaredAnchorModes
        let declared = ScrollAnchorMode.governing(
            opening: modes.opening, standing: modes.standing, hasOpened: handler.hasOpened)
        let followsBottom = !context.isMeasuring
            && ScrollAnchorMode.effective(
                boundAnchor: context.environment.anchorPosition?.wrappedValue,
                declared: declared) == .bottom
        // A pending scrollTo supersedes the glue this frame: the explicit
        // programmatic scroll is exactly the "scrolling away releases the
        // follow" interaction, expressed in code.
        // A change made under `.scrollContentOffsetAdjustmentBehavior =
        // .disabled` is not followed; the view then sits short of the new tail,
        // which is the follow released, as a user scroll releases it. The
        // opening placement is not an adjustment and is kept.
        let suspended =
            handler.hasOpened && context.environment.transaction.disablesScrollContentOffsetAdjustment
        return followsBottom && handler.pendingScrollTo == nil && !suspended
            && (!handler.hasOpened || handler.scrollOffset >= handler.tailAsLastDrawn)
    }

    /// Adopts a bound anchor the app just *wrote*: `.top` jumps to the top,
    /// `.bottom` to the tail. §3.2 promises that writing an edge into the
    /// binding is `anchor(to:)`, and only the CHANGE can mean that — holding
    /// the edge unconditionally every frame would nail an unbound
    /// `.defaultScrollAnchor(.top)` view to the top and make it unscrollable.
    /// After the jump the edge is held positionally, exactly as a declared one
    /// is (bottom re-glues while the offset sits at `maxOffset`; top needs
    /// nothing, since no data change moves an offset of 0).
    ///
    /// Render passes only, and before the glue is evaluated: `.bottom` sets
    /// `seekingTail` rather than an offset, so the post-render re-glue lands on
    /// the real tail instead of a pre-render estimate of it.
    func adoptWrittenAnchor(handler: ScrollViewHandler, context: RenderContext) {
        guard !context.isMeasuring else { return }
        let bound = context.environment.anchorPosition?.wrappedValue
        guard handler.lastBoundAnchor != .some(bound) else { return }
        let isFirstSighting = handler.lastBoundAnchor == nil
        handler.lastBoundAnchor = .some(bound)
        // A first sighting is the view appearing, not the app writing: leave the
        // initial placement to the declared anchor's own machinery.
        guard !isFirstSighting else { return }
        switch bound {
        case .top: handler.scrollOffset = 0
        case .bottom: handler.seekingTail = true
        default: break
        }
    }

    /// How many lines down the viewport this frame draws content SHORTER than
    /// it: the ``ScrollAnchorRole/alignment`` anchor's `y` of the room left
    /// over, rounded down to a line — `0` for content that fills the viewport,
    /// for a view with no alignment anchor, and for one that does not scroll
    /// vertically.
    ///
    /// SwiftUI places short content this way, and its unlabelled
    /// `.defaultScrollAnchor(.bottom)` states this role too (measured): three
    /// rows of a chat sit at the bottom of its view. Not quantised to the edges
    /// as the other two roles are — those choose a policy, and this a place.
    ///
    /// The shift is a slide of the drawn viewport (`applyOverscroll`), not an
    /// offset: content that fits has a scroll offset of 0 and a maximum of 0,
    /// and both stay so. That keeps every piece of arithmetic that maps the
    /// offset to a row — a seek, the reveal, the follow, the reported position
    /// — exactly as it is, and the slide carries the hit regions, the layers
    /// and the animated runs down with the lines, so what is clicked is what
    /// is drawn there. The geometry reports it as SwiftUI does, as a top inset
    /// with the offset above it (`scrollGeometry`).
    func alignmentShift(
        handler: ScrollViewHandler, viewportHeight: Int, context: RenderContext
    ) -> Int {
        // The room first: content that overflows — most of what a scroll view
        // holds — pays no environment read.
        let room = viewportHeight - handler.contentHeight
        guard room > 0, axes.contains(.vertical),
            let anchor = context.environment.scrollAnchor(for: .alignment), anchor.y > 0
        else { return 0 }
        return min(room, Int((anchor.y * Double(room)).rounded(.down)))
    }
}
