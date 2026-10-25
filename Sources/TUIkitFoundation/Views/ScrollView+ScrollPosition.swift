//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+ScrollPosition.swift
//
//  The `.scrollPosition` half of _ScrollViewCore: turning a bound ScrollPosition
//  into a scroll (which reuses the seek machinery `scrollTo` already drives)
//  and reporting back the row actually on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// The plumbing lives on the core, which is what renders — `ScrollView`
// itself is the public wrapper.
extension _ScrollViewCore {

    /// The seek a bound ``ScrollPosition`` is asking for this frame, or `nil`.
    ///
    /// Acted on once: the token (or, for the plain `id:` binding, the value
    /// differing from what was last reported) is what distinguishes a fresh
    /// request from the same one still sitting in the binding. Without that,
    /// scrolling away by hand would be undone on the very next frame.
    func positionSeek(handler: ScrollViewHandler, context: RenderContext) -> ScrollToRequest? {
        pageScrollPosition(context.environment)?.rowRequest(
            tracking: &handler.positionTracking,
            transactionAnchor: context.environment.transaction.scrollTargetAnchor)
    }

    /// Applies an offset-shaped ``ScrollPosition`` target (an edge or an
    /// offset), which needs no key seek — the destination is arithmetic.
    ///
    /// Every vertical write goes through
    /// `ScrollViewHandler.jumpProgrammatically(to:)`, which drops any
    /// overscroll excursion: the request aims at an exact line, and a push left
    /// standing under it would land it short by the push. A horizontal write is
    /// clamped against the extent the last frame measured, and again by the
    /// render once this frame's is known (`syncHorizontalAxis`); on a view that
    /// does not scroll horizontally that extent fits, so it lands on 0, which
    /// is SwiftUI's clamp to the content.
    ///
    /// Returns whether it placed the view — an edge or an offset — which the
    /// top-row hold must then leave where it is (`topRowHold`).
    ///
    /// Made inside an animation, it glides there instead (decisions
    /// B27-ANIMATING), from `viewport`, the content area: the rows, the
    /// columns, or both at once for an offset with both coordinates. The
    /// bottom edge lands through the tail seek it would have raised.
    func applyPositionOffset(handler: ScrollViewHandler, viewport: CellSize, context: RenderContext) -> Bool {
        guard let placement = pageScrollPosition(context.environment)?.placementRequest(
            tracking: &handler.positionTracking)
        else { return false }
        switch placement {
        case .edge(let edge):
            switch edge {
            case .top:
                moveProgrammatically(handler: handler, to: 0, landing: .top, viewport: viewport, context: context)
            case .bottom:
                // The height this used is last frame's; the tail seek re-pins
                // against the height actually rendered.
                let glides = moveProgrammatically(
                    handler: handler, to: handler.maxOffset, landing: .bottom, viewport: viewport, context: context)
                if !glides { handler.seekingTail = true }
            case .leading:
                moveProgrammatically(
                    handler: handler, horizontally: true, to: 0, landing: .top, viewport: viewport, context: context)
            case .trailing:
                moveProgrammatically(
                    handler: handler, horizontally: true, to: handler.horizontal.maxOffset, landing: .bottom,
                    viewport: viewport, context: context)
            }
        case .offset(let x, let y):
            if let y {
                moveProgrammatically(
                    handler: handler, to: max(0, min(y, handler.maxOffset)), landing: .offset(y), viewport: viewport,
                    context: context)
            }
            if let x {
                moveProgrammatically(
                    handler: handler, horizontally: true, to: max(0, min(x, handler.horizontal.maxOffset)),
                    landing: .offset(x), viewport: viewport, context: context)
            }
        }
        return true
    }

    /// Writes the row now under the anchor back to a bound ``ScrollPosition``.
    ///
    /// Only when it CHANGED. A render pass that wrote its binding every frame
    /// would invalidate its own subtree every frame and never settle — the
    /// same discipline `onPreferenceChange` follows, and for the same reason.
    func reportVisibleID(_ id: AnyHashable, handler: ScrollViewHandler, context: RenderContext) {
        pageScrollPosition(context.environment)?.report(
            id, trackedBy: handler, at: \.positionTracking, context: context)
    }

    /// Tells a bound ``ScrollPosition`` that the user scrolled it since the last
    /// frame: its request is dropped and ``ScrollPosition/isPositionedByUser``
    /// set, as SwiftUI does on the user's first scroll.
    ///
    /// Written at the render rather than at the scroll because the binding is
    /// out of reach at event time, and only when it changes something: a held
    /// wheel scrolls many times between frames, and once the request is gone
    /// and the flag set there is nothing left to write.
    func settleUserPositioning(handler: ScrollViewHandler, context: RenderContext) {
        guard handler.userScrolledSinceRender, !context.isMeasuring else { return }
        handler.userScrolledSinceRender = false
        pageScrollPosition(context.environment)?.reportPositionedByUser()
    }
}
