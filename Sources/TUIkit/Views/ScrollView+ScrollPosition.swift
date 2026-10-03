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
        guard let box = context.environment.scrollPositionBinding else { return nil }
        let position = box.binding.wrappedValue
        guard let target = position.target else { return nil }

        switch target {
        case .id(let id, let anchor):
            let value = id.value
            let isFresh =
                position.requestToken == 0
                ? handler.lastReportedPositionID != value
                : handler.lastAppliedPositionToken != position.requestToken
            guard isFresh else { return nil }
            handler.lastAppliedPositionToken = position.requestToken
            handler.lastReportedPositionID = value
            // The same stringification `ForEach` derives its keys with, so the
            // comparison in the seek paths is exact.
            return ScrollToRequest(key: identityKey(value.base), anchor: anchor)
        case .edge, .offset:
            // Both are offsets, not rows, so they do not go through the key
            // seek — `applyPositionOffset` moves the scroll view directly.
            return nil
        }
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
    func applyPositionOffset(handler: ScrollViewHandler, context: RenderContext) {
        guard let box = context.environment.scrollPositionBinding else { return }
        let position = box.binding.wrappedValue
        guard let target = position.target,
            handler.lastAppliedPositionToken != position.requestToken, position.requestToken > 0
        else { return }
        switch target {
        case .edge(let edge):
            handler.lastAppliedPositionToken = position.requestToken
            switch edge {
            case .top: handler.jumpProgrammatically(to: 0)
            case .bottom:
                handler.jumpProgrammatically(to: handler.maxOffset)
                // The height this used is last frame's; the tail seek re-pins
                // against the height actually rendered.
                handler.seekingTail = true
            case .leading: handler.horizontal.scrollToOffset(0)
            case .trailing: handler.horizontal.scrollToOffset(handler.horizontal.maxOffset)
            }
        case .offset(let x, let y):
            handler.lastAppliedPositionToken = position.requestToken
            if let y { handler.jumpProgrammatically(to: max(0, min(y, handler.maxOffset))) }
            if let x { handler.horizontal.scrollToOffset(max(0, min(x, handler.horizontal.maxOffset))) }
        case .id:
            break  // Handled by the key seek — see `positionSeek`.
        }
    }

    /// Writes the row now under the anchor back to a bound ``ScrollPosition``.
    ///
    /// Only when it CHANGED. A render pass that wrote its binding every frame
    /// would invalidate its own subtree every frame and never settle — the
    /// same discipline `onPreferenceChange` follows, and for the same reason.
    func reportVisibleID(_ id: AnyHashable, handler: ScrollViewHandler, context: RenderContext) {
        guard let box = context.environment.scrollPositionBinding,
            handler.lastReportedPositionID != id
        else { return }
        handler.lastReportedPositionID = id
        var position = box.binding.wrappedValue
        position.reportVisible(id: id)
        box.binding.wrappedValue = position
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
        guard let box = context.environment.scrollPositionBinding, box.tracksUserPositioning
        else { return }
        var position = box.binding.wrappedValue
        guard position.target != nil || !position.isPositionedByUser else { return }
        position.reportPositionedByUser()
        box.binding.wrappedValue = position
    }
}
