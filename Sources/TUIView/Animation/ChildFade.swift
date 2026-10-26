//  🖥️ TUI — A Terminal UI framework for Swift
//  ChildFade.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// The default transition for the children a container places itself: a child
// the change puts in fades in where it lands, as SwiftUI's does with no
// `.transition` written — an `if`/`else` whose branch flips, a `switch`, a
// `ForEach`'s rows (measured, `Tools/SwiftUIProbes/Transitions/tr1.out`
// T1–T3). One the change takes out goes at once, unless it carries a
// transition of its own, which plays its removal where it was.
//
// ## Why the container, and not the view that changed
//
// An `if` reports for itself (`OptionalPresence`): it renders both ways, so
// it can say what it held and that it is empty. A branch, a case and a row
// cannot — the branch that is not taken is not rendered, and a row that has
// gone has no `ForEach` element left to render it. What sees all three is the
// container that places them: on the frame of the change it is handed
// children it has never seen and is not handed ones it had, and it remembers
// where each was (`PlacementStore`).
//
// ## Why one that goes does not fade out
//
// SwiftUI fades it out where it was. Here that needs the picture it drew on
// its last frame — the one thing a child that has gone leaves — kept by its
// container on every frame, settled or not, since the frame a child goes is
// the first that does not draw it. Lane TRANSITIONS2 kept them (decisions
// B-TRANSITIONS2-1), and the A/B of 2026-10-19 priced that with nothing
// animating at all: up to +7.2% a frame (`tables-scroll`), +2–3.5% across
// a dozen scenarios, and `deep`'s footprint 17.1 → 32.6 MB, each level of a
// nested page keeping what every level below it drew. Keeping only the
// pictures of children that can go still keeps a branch's, which is what a
// nested page's levels are (decisions TR2PERF). So by the owner's rule of
// 2026-10-14 — fade both ways, falling back to fading in only at a
// significant cost, above all with no animation — it fades in only
// (Deliberate deviations A10). A transition of the view's own leaves its own
// picture in the `DepartureStore` on each frame it renders, and plays it.
//
// A child's presence, `0` gone through `1` there, is an animated value in the
// `AnimationStore`, keyed under the container as a glide is, so a
// `withAnimation` completion waits for it as it waits for a glide. A fade is
// not motion, so reduce motion leaves it alone.
//
// ## What stands aside
//
// - A view with a transition of its own (`_TransitionView`) arrives by it, and
//   leaves by it: its removal is played from what it left in the
//   `DepartureStore`, where the container saw it go. That is how the branch an
//   `if`/`else` leaves, and a row, play a transition written on them.
// - An `if` fading its view in itself, and an `if`'s removal, which its `nil`
//   plays (`DepartureSlot`).
// - A container seen for the first time, whose children are an appearance,
//   not an arrival: SwiftUI transitions the view that was inserted, not each
//   view inside it.

/// The owner a child's presence is keyed by in the ``AnimationStore``, as a
/// glide's is by `ChildGlide`.
private enum ChildPresence {}

/// One frame's worth of a container's children coming and going.
@MainActor
struct ChildFade {
    let context: RenderContext
    let storage: StateStorage
    /// The animation the frame's change runs under: the default transition is
    /// a fade, which reduce motion does not hold still.
    let animation: Animation?
    let nowNanos: Int64

    init(context: RenderContext, storage: StateStorage) {
        self.context = context
        self.storage = storage
        let frame = context.environment.animationFrame
        nowNanos = frame.nowNanos
        animation = frame.canAnimate ? context.environment.transaction.effectiveAnimation : nil
    }

    /// The key the presence of the child written as `step` is kept at.
    private func key(_ step: ChildIdentityStep) -> AnimationStore.Key {
        AnimationStore.Key(identity: context.identity, owner: ObjectIdentifier(ChildPresence.self), slot: step.hashValue)
    }

    // MARK: - Arriving

    /// Which of `children` are fading in after this frame's change: those
    /// that were (`wasArriving`, by the old entry each matches), and those the
    /// change put here and nothing else brings in.
    func arrivals(
        of children: [ChildView], drawing buffers: [FrameBuffer?], matches: [Int?], wasArriving: [Bool]?
    ) -> [Bool]? {
        var flags = [Bool](repeating: false, count: children.count)
        var any = false
        for index in children.indices {
            if let previous = matches[index] {
                flags[index] = wasArriving.map { previous < $0.count && $0[previous] } ?? false
            } else {
                flags[index] = startsArriving(children[index], drawing: buffers[index])
            }
            any = any || flags[index]
        }
        return any ? flags : nil
    }

    /// Starts `child`, which the change put here, fading in — unless nothing
    /// animates the change, it draws nothing, or something else brings it in.
    private func startsArriving(_ child: ChildView, drawing buffer: FrameBuffer?) -> Bool {
        guard let animation, let buffer, buffer.width > 0, buffer.height > 0 else { return false }
        let identity = child.identityStep.identity(under: context.identity)
        // A transition of its own, declared at its address as it drew.
        if storage.departures.isPresent(at: identity) { return false }
        // An `if` that fades its view in itself.
        if child.isDefaultTransitioned, let scope = identity.parent, storage.isArrivingOptional(at: scope) {
            return false
        }
        let key = key(child.identityStep)
        // From nothing, whatever an arrival before it had got to.
        storage.animations.settle(key, at: 0.0, nowNanos: nowNanos)
        _ = storage.animations.value(for: key, target: 1.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
        return true
    }

    /// How present each of `children` is drawn this frame — `1` for all but
    /// those fading in — or `nil` when none is; `flags` loses each that has
    /// arrived.
    func presence(of children: [ChildView], arriving flags: inout [Bool]?) -> [Double]? {
        guard var current = flags else { return nil }
        let animations = storage.animations
        var presence = [Double](repeating: 1, count: children.count)
        var any = false
        for index in current.indices where current[index] {
            let key = key(children[index].identityStep)
            let value = animations.value(
                for: key, target: 1.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
            guard animations.isAnimating(at: key, nowNanos: nowNanos) else {
                current[index] = false
                continue
            }
            presence[index] = min(1, max(0, value))
            any = true
        }
        flags = current.contains(true) ? current : nil
        return any ? presence : nil
    }

    // MARK: - Leaving

    /// What `entry`, which has gone, leaves as while this frame's change
    /// plays, drawn at `placement` — or `nil` where it simply goes: it drew
    /// nothing, it was a removal's slot already played, it carries no
    /// transition of its own whose picture is all it drew, or that
    /// transition says it goes at once.
    ///
    /// A transition that names an animation of its own plays under it with
    /// no animated change at all, as SwiftUI's does (measured,
    /// `Tools/SwiftUIProbes/Transitions/tr1.out` T6), and as an `if`'s view
    /// does where its `nil` plays the removal. One with something drawn round
    /// it (`X.transition(t).padding()`) goes at once: its picture would lose
    /// what was drawn round it, and no picture of the whole is kept.
    func leaver(from entry: ChildPlacementEntry, at placement: ChildPlacement) -> LeavingChild? {
        guard !entry.isDeparting, !entry.drawsNothing else { return nil }
        let departures = storage.departures
        guard !departures.isEmpty else { return nil }
        let identity = entry.step.identity(under: context.identity)
        let type = departingPictureType(heldAs: entry.step.type ?? entry.viewType)
        guard departures.hasEntry(at: identity, leftBy: type),
            departures.hasDeparture(at: identity, ofType: type, nowNanos: nowNanos, frameAnimation: animation)
        else { return nil }
        return LeavingChild(
            step: entry.step, placement: placement, zIndex: entry.zIndex, identity: identity, type: type)
    }

    /// The pictures of `leaving` on this frame, each where it was; `leaving`
    /// loses each that has gone for good.
    func pictures(of leaving: inout [LeavingChild]) -> [(picture: FrameBuffer, placement: ChildPlacement, zIndex: Double)] {
        guard !leaving.isEmpty else { return [] }
        var drawn: [(picture: FrameBuffer, placement: ChildPlacement, zIndex: Double)] = []
        var still: [LeavingChild] = []
        for leaver in leaving {
            guard
                let picture = storage.departures.departing(
                    at: leaver.identity, ofType: leaver.type, nowNanos: nowNanos, frameAnimation: animation)
            else { continue }
            drawn.append((carried(picture, leaver), leaver.placement, leaver.zIndex))
            still.append(leaver)
        }
        leaving = still
        return drawn
    }

    /// `picture` of `leaver` where it is carried: a matched view among what
    /// left moves with the one arriving in its place
    /// (`DepartureStore.carrying(_:leftFrom:)`).
    private func carried(_ picture: FrameBuffer, _ leaver: LeavingChild) -> FrameBuffer {
        storage.departures.carrying(picture, leftFrom: leaver.identity)
    }
}
