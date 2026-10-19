//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChildGlide.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The owner a child's glide is keyed by in the ``AnimationStore``: the
/// container's identity, this type, and the child's ``ChildIdentityStep`` as
/// the slot. Keyed under the CONTAINER rather than at the child's own identity
/// so that asking needs no identity built for the child; the container's is in
/// hand.
private enum ChildGlide {}

/// Where a container's children are drawn on a frame some of them are moving
/// on, or a child that has left is still being drawn — see
/// ``RenderContext/glidingPlacements(of:at:departing:)``.
package struct GlidingPlacements {
    /// Where each child laid out is drawn, in the order the container gave
    /// them: its target, or part of the way there from where it was.
    package var presented: [ChildPlacement]

    /// Where each departing child's parting picture is drawn and at what
    /// z-index, in the order the container gave them, or `nil` for one whose
    /// last placement this container never saw — which is then not drawn.
    package var departing: [(placement: ChildPlacement, zIndex: Double)?]
}

extension RenderContext {
    /// Where to draw `children`, which this container lays out at `targets`
    /// this frame, and `departing`, which it lays out nowhere — or `nil` when
    /// every child is drawn at its target and nothing is leaving, which is the
    /// answer on every frame but the ones something moves on.
    ///
    /// SwiftUI's model, measured (`plan/fb16/samples.txt`): a change of layout
    /// takes effect at once, and under an animation every view whose place
    /// changed glides from its old place to its new one — siblings of an
    /// inserted or removed view included, whatever its transition. A child seen
    /// for the first time is placed directly: that is an insertion, and its
    /// transition is what animates it. A child that has gone is drawn where it
    /// last was while its removal plays (`DepartureStore`), taking no room.
    ///
    /// A glide is the child's placement as an animated value in the
    /// ``AnimationStore``, asked about only while it moves, so it is interrupted
    /// (merged or added to, decisions O3), held still by reduce motion — a
    /// glide is motion, owner decision A-D3M-1 — and waited on by a
    /// `withAnimation` completion as every other animated value is. Where each
    /// child was is the container's ``PlacementStore`` record.
    ///
    /// A child that draws nothing in the container — no rows or no columns —
    /// has no picture of its own to move: what it shows is what it carries
    /// past its frame, a view leaving it or one arriving in it. So one that
    /// comes to draw nothing is held where it was while its glide runs, and
    /// one that comes to draw something is placed directly, as a view seen
    /// for the first time is. `VStack { if show { Card() } }` in a stack with
    /// gaps is the shape: emptied, the inner stack takes no gap (a child with
    /// no extent takes no stack spacing, compatibility guide §3) and its
    /// place moves by one, which a glide would have carried the card's
    /// removal along — a view leaving plays where it was. It stands at its
    /// new place from the frame its glide lands, so a removal that outlasts
    /// the change's animation (a transition with an animation of its own)
    /// finishes there.
    ///
    /// The render walk only: a measure, and a transition body being scrubbed
    /// (``AnimationStore/scrub``), draw everything at its target.
    ///
    /// - Parameters:
    ///   - children: The children laid out, in declaration order.
    ///   - buffers: What each of them drew, `nil` for a spacer.
    ///   - targets: Where the layout put each of them, in this container's
    ///     cells.
    ///   - departing: The slots of views still leaving (``ChildView/isDeparting``).
    @MainActor
    package func glidingPlacements(
        of children: [ChildView], drawing buffers: [FrameBuffer?], at targets: [ChildPlacement],
        departing: [ChildView]
    ) -> GlidingPlacements? {
        guard !isMeasuring, let storage = stateStorage, storage.animations.scrub == nil else { return nil }
        let store = storage.placements
        guard let record = store.record(at: identity) else {
            store.remember(
                Self.entries(children, buffers, targets), at: identity, walk: storage.animations.currentWalk)
            guard !departing.isEmpty else { return nil }
            return GlidingPlacements(presented: targets, departing: departing.map { _ in nil })
        }
        let unchanged = Self.record(record, matches: children, drawing: buffers, at: targets)
        // The settled frame: the layout it had, nothing moving, nothing
        // leaving. Every container on every frame nothing animates in it.
        if unchanged, record.gliding == nil, departing.isEmpty { return nil }

        // A change nothing animates, with nothing moving and nothing leaving:
        // every child is where the layout put it, and all the record needs is
        // the layout, for the change after this one. Matching the children
        // and asking the animation store about each of them is the glide's
        // price, which a stack whose rows change on every frame — `churn` —
        // paid on every frame for nothing (4–6% of its frame, profiled
        // 2026-10-18).
        if !unchanged, record.gliding == nil, departing.isEmpty, !Self.changeAnimates(in: self) {
            record.entries = Self.entries(children, buffers, targets)
            record.departed = [:]
            record.held = [:]
            return nil
        }

        var glide = Glide(context: self, storage: storage, targets: targets, held: record.held)
        if unchanged {
            glide.continueMoving(record.entries, flags: record.gliding)
        } else {
            let appearing = store.appearedEarlierThisPass(record, walk: storage.animations.currentWalk)
            let old = appearing ? [] : record.entries
            let matches = glide.matches(of: children, among: old)
            glide.startMoving(children, drawing: buffers, from: old, matches: matches)
            record.departed = glide.departures(departing, kept: record.departed, from: old, matches: matches)
            record.entries = Self.entries(children, buffers, targets)
        }
        record.gliding = glide.anyMoving ? glide.moving : nil
        record.held = glide.anyMoving ? glide.held : [:]
        // Landed, and nothing leaving: drawn as a settled container is, so the
        // last frame of a glide is the picture every frame after it is.
        guard glide.anyMoving || !departing.isEmpty else { return nil }
        // The picture is a function of the clock, which no memo can reproduce
        // from a buffer it kept: stored, the glide would freeze on this frame.
        // The declaration `animatedValue` makes.
        environment.volatileReadTracker?.recordRenderSideEffect()
        return GlidingPlacements(
            presented: glide.presented,
            departing: departing.map { record.departed[$0.identityStep] })
    }

    /// Whether a change of layout on this frame would move anything: the
    /// frame can animate, its transaction carries an animation, and reduce
    /// motion does not hold still what moves in X and Y — the answer
    /// ``Glide``'s own `animation` gives.
    @MainActor
    private static func changeAnimates(in context: RenderContext) -> Bool {
        let frame = context.environment.animationFrame
        guard frame.canAnimate, context.environment.transaction.effectiveAnimation != nil else { return false }
        return !context.environment.accessibilityReduceMotion
    }

    /// `children` at `targets`, drawing `buffers`, as a record keeps them.
    @MainActor
    private static func entries(
        _ children: [ChildView], _ buffers: [FrameBuffer?], _ targets: [ChildPlacement]
    ) -> [ChildPlacementEntry] {
        children.indices.map {
            ChildPlacementEntry(
                step: children[$0].identityStep, placement: targets[$0], zIndex: children[$0].zIndex,
                drawsNothing: drawsNothing(buffers[$0]))
        }
    }

    /// Whether `record` holds exactly `children` at `targets`: the same
    /// children in the same order, each where it was, stacked as it was and
    /// drawing something or nothing as it did. Asked of every container on
    /// every frame, so it builds nothing.
    @MainActor
    private static func record(
        _ record: PlacementStore.Record, matches children: [ChildView], drawing buffers: [FrameBuffer?],
        at targets: [ChildPlacement]
    ) -> Bool {
        let entries = record.entries
        guard entries.count == children.count else { return false }
        for index in entries.indices {
            let entry = entries[index]
            guard entry.placement == targets[index], entry.zIndex == children[index].zIndex,
                entry.drawsNothing == drawsNothing(buffers[index]), children[index].hasIdentityStep(entry.step)
            else { return false }
        }
        return true
    }
}

/// Whether a child drew nothing in its container: no rows or no columns. A
/// spacer (`nil`) is not asked about; it draws nothing anywhere.
private func drawsNothing(_ buffer: FrameBuffer?) -> Bool {
    guard let buffer else { return false }
    return buffer.width == 0 || buffer.height == 0
}

// MARK: - Moving the children

/// One frame's worth of glides for one container: the store calls it makes,
/// and what they answered.
@MainActor
private struct Glide {
    let context: RenderContext
    let animations: AnimationStore
    let targets: [ChildPlacement]
    let nowNanos: Int64
    /// The animation a change on this frame moves things with: the frame's,
    /// unless reduce motion holds still what moves in X and Y.
    let animation: Animation?
    var presented: [ChildPlacement]
    var moving: [Bool]
    var anyMoving = false
    /// Where each child that has come to draw nothing was held until this
    /// frame (``PlacementStore/Record/held``).
    let wasHeld: [ChildIdentityStep: ChildPlacement]
    /// The same, as this frame leaves it.
    var held: [ChildIdentityStep: ChildPlacement]

    init(
        context: RenderContext, storage: StateStorage, targets: [ChildPlacement],
        held: [ChildIdentityStep: ChildPlacement]
    ) {
        self.context = context
        self.animations = storage.animations
        self.targets = targets
        wasHeld = held
        self.held = held
        let frame = context.environment.animationFrame
        nowNanos = frame.nowNanos
        let animation = frame.canAnimate ? context.environment.transaction.effectiveAnimation : nil
        self.animation = animation != nil && context.environment.accessibilityReduceMotion ? nil : animation
        presented = targets
        moving = [Bool](repeating: false, count: targets.count)
    }

    /// The key a glide of the child written as `step` is kept at.
    func key(_ step: ChildIdentityStep) -> AnimationStore.Key {
        AnimationStore.Key(identity: context.identity, owner: ObjectIdentifier(ChildGlide.self), slot: step.hashValue)
    }

    /// Where the picture of the child kept at `key` is, if it is in flight.
    func inFlight(_ key: AnimationStore.Key) -> ChildPlacement? {
        animations.presentedValue(at: key, as: AnimatablePair<Double, Double>.self, nowNanos: nowNanos)
            .map(ChildPlacement.init)
    }

    /// Asks the store where child `index`'s glide at `key` has got to, and
    /// notes whether it is still moving.
    mutating func ask(_ key: AnimationStore.Key, for index: Int) {
        let value = animations.value(
            for: key, target: targets[index].animatable, animation: animation, nowNanos: nowNanos,
            isMeasuring: false)
        presented[index] = ChildPlacement(value)
        if animations.isAnimating(at: key, nowNanos: nowNanos) {
            moving[index] = true
            anyMoving = true
        }
    }

    /// A frame of a layout that has not changed: the children that were
    /// moving move on.
    mutating func continueMoving(_ entries: [ChildPlacementEntry], flags: [Bool]?) {
        guard let flags else { return }
        for index in flags.indices where flags[index] {
            let step = entries[index].step
            ask(key(step), for: index)
            guard let place = held[step] else { continue }
            if moving[index] { presented[index] = place } else { held[step] = nil }
        }
    }

    /// The frame a layout changed on: each child that was here before moves
    /// from where its picture is — its old place, where a glide in flight has
    /// got to, or where it is held — and one seen for the first time is
    /// placed directly. So is one that drew nothing and now draws something;
    /// one that drew something and now draws nothing is held where it was
    /// while its glide runs (see ``RenderContext/glidingPlacements(of:drawing:at:departing:)``).
    mutating func startMoving(
        _ children: [ChildView], drawing buffers: [FrameBuffer?], from old: [ChildPlacementEntry], matches: [Int?]
    ) {
        held = [:]
        for index in children.indices {
            guard let previous = matches[index] else { continue }
            let blank = drawsNothing(buffers[index])
            let wasBlank = old[previous].drawsNothing
            if wasBlank, !blank { continue }
            let step = children[index].identityStep
            let key = key(step)
            // Written differently from last frame (a `ForEach` that began
            // resolving its rows ahead): its glide is under the old step.
            let oldStep = old[previous].step
            let hasRecord = animations.hasRecord(at: key)
            let holding = wasHeld[oldStep]
            let picture = holding ?? inFlight(hasRecord ? key : self.key(oldStep)) ?? old[previous].placement
            if !hasRecord {
                // Not moving, or a change nothing animates: drawn at its target.
                guard picture != targets[index], animation != nil else { continue }
                animations.settle(key, at: picture.animatable, nowNanos: nowNanos)
            }
            ask(key, for: index)
            guard blank, moving[index], !wasBlank || holding != nil else { continue }
            held[step] = picture
            presented[index] = picture
        }
    }

    /// For each of `children`, which of `old` it is: by step, in order where
    /// the children are the same ones in the same order (a layout that only
    /// moved), and otherwise by step and then by identity.
    func matches(of children: [ChildView], among old: [ChildPlacementEntry]) -> [Int?] {
        guard !old.isEmpty else { return [Int?](repeating: nil, count: children.count) }
        if old.count == children.count, old.indices.allSatisfy({ children[$0].hasIdentityStep(old[$0].step) }) {
            return Array(old.indices)
        }
        var byStep: [ChildIdentityStep: Int] = [:]
        var ambiguous: Set<ChildIdentityStep> = []
        for (index, entry) in old.enumerated() where byStep.updateValue(index, forKey: entry.step) != nil {
            ambiguous.insert(entry.step)
        }
        var matches = children.map { child -> Int? in
            let step = child.identityStep
            return ambiguous.contains(step) ? nil : byStep[step]
        }
        let unmatchedOld = Set(old.indices).subtracting(matches.compactMap { $0 })
        guard !unmatchedOld.isEmpty, matches.contains(nil) else { return matches }
        // The same child written another way: matched by where it renders.
        var byIdentity: [ViewIdentity: Int] = [:]
        for index in unmatchedOld {
            byIdentity[old[index].step.identity(under: context.identity)] = index
        }
        for index in children.indices where matches[index] == nil {
            let identity = children[index].identityStep.identity(under: context.identity)
            if let found = byIdentity.removeValue(forKey: identity) { matches[index] = found }
        }
        return matches
    }

    /// Where each of `departing` is drawn while it leaves: where it was when
    /// it went — its old place, or where a glide in flight had got to — kept
    /// from then on, and stacked as it was.
    func departures(
        _ departing: [ChildView], kept: [ChildIdentityStep: (placement: ChildPlacement, zIndex: Double)],
        from old: [ChildPlacementEntry], matches: [Int?]
    ) -> [ChildIdentityStep: (placement: ChildPlacement, zIndex: Double)] {
        guard !departing.isEmpty else { return [:] }
        var stillHere = Set(matches.compactMap { $0 })
        var departed: [ChildIdentityStep: (placement: ChildPlacement, zIndex: Double)] = [:]
        for child in departing {
            let step = child.identityStep
            if let placed = kept[step] {
                departed[step] = placed
                continue
            }
            // The slot is addressed as the view it stands for was — written
            // the same way where a splice resolved both, and otherwise found
            // by where it renders: a stack's only content is resolved ahead
            // when present and not when it is a slot.
            let unclaimed = old.indices.filter { !stillHere.contains($0) }
            var previous = unclaimed.first { old[$0].step == step }
            if previous == nil {
                let identity = step.identity(under: context.identity)
                previous = unclaimed.first { old[$0].step.identity(under: context.identity) == identity }
            }
            guard let previous else { continue }
            stillHere.insert(previous)
            let placement = wasHeld[old[previous].step] ?? inFlight(key(old[previous].step)) ?? old[previous].placement
            departed[step] = (placement, old[previous].zIndex)
        }
        return departed
    }
}
