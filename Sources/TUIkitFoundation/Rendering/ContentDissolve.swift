//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentDissolve.swift
//
//  A leaf's content transition: a `Text` or an `Image` whose drawing changes
//  under an animation dissolves from its old drawing to its new one, where an
//  ancestor's `contentTransition(_:)` names a transition that dissolves
//  (decisions B61).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Environment

/// Environment key for whether a leaf here dissolves a change of its drawing.
private struct ContentDissolvesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a ``Text`` or an ``Image`` here dissolves a change of its
    /// drawing made under an animation: whether the content transition in
    /// force (`\.contentTransition`, TUIkitEffects) is one that dissolves —
    /// anything but `.identity` and the unset default.
    ///
    /// Written by `\.contentTransition`'s setter, and only by it, so the two
    /// cannot disagree however the transition was set: the modifier, or
    /// `.environment(\.contentTransition, …)`. A `Bool` of its own because the
    /// leaves are in this module and `ContentTransition` is not.
    package var contentDissolves: Bool {
        get { self[ContentDissolvesKey.self] }
        set { self[ContentDissolvesKey.self] = newValue }
    }
}

// MARK: - The dissolve

/// What a leaf keeps between frames while it dissolves its changes: its last
/// drawing, and the dissolve under way.
///
/// Kept only where ``EnvironmentValues/contentDissolves`` is set: a leaf
/// anywhere else reads that one value and keeps nothing (A40 measured keeping
/// a drawing for every `Text` at up to +500%). Kept at an identity of its own
/// under the leaf's, which only it marks live: kept at the leaf's own and
/// marked live there, it would keep alive the state of whatever else draws at
/// that identity (A40's prototype found a view the text replaced at the root
/// keeping its `@State`).
struct ContentDissolve {
    /// The leaf's drawing on the last frame it was drawn.
    var shown: FrameBuffer?
    /// The drawing dissolving away, and how.
    var outgoing: FrameBuffer?
    var animation: Animation?
    var startNanos: Int64 = 0

    /// `buffer`, the leaf's drawing this frame — with the drawing it replaced
    /// dissolving away beneath it while a change made under an animation plays
    /// out, where the content transition in force dissolves.
    ///
    /// Elsewhere it is `buffer`, after one environment read: the whole price
    /// of the per-leaf design on a page that writes no content transition.
    @MainActor
    static func drawn(_ buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, context.environment.contentDissolves else { return buffer }
        return dissolved(buffer, context: context)
    }

    @MainActor
    private static func dissolved(_ buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard let storage = context.stateStorage else { return buffer }
        let place = context.withChildIdentity(erasedType: Self.self, index: 0)
        storage.markActive(place.identity)
        let key = StateStorage.StateKey(identity: place.identity, propertyIndex: 0)
        var record: Self = storage.trackedValue(for: key) ?? Self()
        let frame = context.environment.animationFrame
        let now = frame.nowNanos

        // A change dissolves from the last drawing — not from the picture on
        // screen, which during a dissolve is the old glyphs blended toward
        // the new and hands its glyphs over only half way. Started from that
        // picture, a burst of changes faster than half the animation (a held
        // key's auto-repeat on a counter) restarted from the old glyphs every
        // time, and the number stood still until the burst ended. From the
        // last drawing it follows the burst, one change behind.
        if let shown = record.shown, shown.lines != buffer.lines || shown.width != buffer.width,
            frame.canAnimate, let animation = context.environment.transaction.effectiveAnimation
        {
            record.outgoing = shown
            record.animation = animation
            record.startNanos = now
            storage.animationCompletions.noteStarted(animation, at: now, key: nil)
        }
        let result = record.drawn(over: buffer, at: now, context: context)
        record.shown = buffer
        // A finished dissolve lets its picture go.
        if let animation = record.animation,
            animation.isFinished(at: Double(now - record.startNanos) / 1_000_000_000)
        {
            (record.outgoing, record.animation) = (nil, nil)
        }
        storage.setTrackedValue(record, for: key)
        return result
    }

    /// `buffer` with the outgoing drawing dissolving away beneath it, or
    /// `buffer` alone when nothing is dissolving.
    @MainActor
    private func drawn(over buffer: FrameBuffer, at now: Int64, context: RenderContext) -> FrameBuffer {
        guard let outgoing, let animation else { return buffer }
        let elapsed = Double(now - startNanos) / 1_000_000_000
        guard !animation.isFinished(at: elapsed) else { return buffer }
        // Frames until it is done, on the lattice every view animation shares.
        context.requestAnimation(
            token: "content-dissolve-\(context.identity.path)",
            frameTicks: AnimationRequest.viewAnimations.frameTicks)
        let presence = min(1, max(0, animation.fraction(at: elapsed)))
        // The new drawing over the old at `presence`: the compositor blends
        // each cell's colours and hands over its glyph half way, so the old
        // shows through at 1 − presence. Drawn at a second identity of its
        // own, apart from the record's, with animations off, and with the
        // dissolve off, so nothing in it dissolves again.
        var quiet = context.withChildIdentity(erasedType: Self.self, index: 1)
        quiet.environment.transaction.disablesAnimations = true
        quiet.environment.contentDissolves = false
        let dissolved = TUIkitView.renderToBuffer(
            ZStack(alignment: .topLeading) {
                BufferView(buffer: outgoing)
                BufferView(buffer: buffer).opacity(presence)
            },
            context: quiet)
        return dissolved.clamped(toWidth: buffer.width, height: buffer.height)
    }
}
