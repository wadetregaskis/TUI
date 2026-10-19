//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChildFade.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// The default transition for the children a container places itself: a child
// the change puts in fades in where it lands, and one it takes out fades out
// where it was, beneath its siblings, as SwiftUI's do with no `.transition`
// written — an `if`/`else` whose branch flips, a `switch`, a `ForEach`'s rows
// (measured, `Tools/SwiftUIProbes/Transitions/tr1.out` T1–T3).
//
// ## Why the container, and not the view that changed
//
// An `if` reports for itself (`OptionalPresence`): it renders both ways, so
// it can say what it held and that it is empty. A branch, a case and a row
// cannot — the branch that is not taken is not rendered, and a row that has
// gone has no `ForEach` element left to render it. What sees all three is the
// container that places them: on the frame of the change it is handed
// children it has never seen and is not handed ones it had, and it remembers
// where each was (`PlacementStore`). It also keeps what each drew on its last
// frame (``PlacementStore/Record/pictures``) — the one thing a child that has
// gone leaves — which costs a stored array a frame, the array the container
// already holds.
//
// A child's presence, `0` gone through `1` there, is an animated value in the
// `AnimationStore`, keyed under the container as a glide is, so a child that
// comes back while it leaves turns round from where it is, and a
// `withAnimation` completion waits for it. A fade is not motion, so reduce
// motion leaves it alone.
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
        // From where it is if it was on its way out, and from nothing if not.
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
    /// plays, drawn at `placement` — or `nil` where it simply goes: nothing
    /// animates the change, it drew nothing, it was a removal's slot already
    /// played, or a transition of its own says it goes at once.
    func leaver(from entry: ChildPlacementEntry, picture: FrameBuffer?, at placement: ChildPlacement) -> LeavingChild? {
        guard let animation, !entry.isDeparting, !entry.drawsNothing else { return nil }
        let identity = entry.step.identity(under: context.identity)
        let departures = storage.departures
        if departures.hasEntry(at: identity) {
            let type = departingPictureType(heldAs: entry.step.type ?? entry.viewType)
            // Its own transition's picture, where that is all it drew.
            if departures.hasEntry(at: identity, leftBy: type) {
                guard
                    departures.hasDeparture(
                        at: identity, ofType: type, nowNanos: nowNanos, frameAnimation: animation)
                else { return nil }
                return LeavingChild(
                    step: entry.step, placement: placement, zIndex: entry.zIndex,
                    picture: .playing(identity: identity, type: type))
            }
            // A transition with something drawn round it: its picture would
            // lose that, so the whole picture fades instead.
        }
        guard let picture, !picture.isEmpty else { return nil }
        let key = key(entry.step)
        // From where it is if it was still on its way in.
        storage.animations.settle(key, at: 1.0, nowNanos: nowNanos)
        _ = storage.animations.value(for: key, target: 0.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
        return LeavingChild(step: entry.step, placement: placement, zIndex: entry.zIndex, picture: .fading(picture))
    }

    /// The pictures of `leaving` on this frame, each where it was; `leaving`
    /// loses each that has gone for good.
    func pictures(of leaving: inout [LeavingChild]) -> [(picture: FrameBuffer, placement: ChildPlacement, zIndex: Double)] {
        guard !leaving.isEmpty else { return [] }
        let animations = storage.animations
        var drawn: [(picture: FrameBuffer, placement: ChildPlacement, zIndex: Double)] = []
        var still: [LeavingChild] = []
        for leaver in leaving {
            switch leaver.picture {
            case .fading(let picture):
                let key = key(leaver.step)
                let value = animations.value(
                    for: key, target: 0.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
                guard animations.isAnimating(at: key, nowNanos: nowNanos) else { continue }
                let faded = DefaultTransition.faded(picture, by: min(1, max(0, value)))
                drawn.append((carried(faded, leaver), leaver.placement, leaver.zIndex))
            case .playing(let identity, let type):
                guard
                    let picture = storage.departures.departing(
                        at: identity, ofType: type, nowNanos: nowNanos, frameAnimation: animation)
                else { continue }
                drawn.append((carried(picture, leaver), leaver.placement, leaver.zIndex))
            }
            still.append(leaver)
        }
        leaving = still
        return drawn
    }

    /// `picture` of `leaver` where it is carried: a matched view among what
    /// left moves with the one arriving in its place
    /// (`DepartureStore.carrying(_:leftFrom:)`).
    private func carried(_ picture: FrameBuffer, _ leaver: LeavingChild) -> FrameBuffer {
        let departures = storage.departures
        return departures.carrying(picture, leftFrom: leaver.step.identity(under: context.identity))
    }
}
