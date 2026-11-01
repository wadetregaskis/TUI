//  🖥️ TUI — A Terminal UI framework for Swift
//  BranchTransition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// The default transition for an `if`/`else` — and so a `switch`, which is
// nested ones — drawn WHOLE: a view's whole body, a modifier's content. The
// branch taken under an animated change fades in; the branch left goes at
// once, unless it carries a transition of its own, which plays its removal
// at the same origin. A conditional inside a stack is not drawn whole: the
// stack takes it apart, and its branches come and go as the stack's children
// do (`ChildFade`, which says why what goes does not fade out, where
// SwiftUI's does: measured, `Tools/SwiftUIProbes/Transitions/tr1.out` T8).
//
// ## Where the leaving branch is drawn
//
// Past the conditional's frame, as content drawn past a view's region is
// (`FrameBuffer.drawnPastSlot`): the layout is the new branch's, at once, and
// the old picture has no room in it. Drawn there it lands over the new
// branch's cells rather than beneath them, as only a container composites
// what it draws against what is behind it, and that compositor is above this
// module. Its hit regions are dropped: what is leaving takes no clicks.
//
// ## What it costs
//
// The record the conditional already kept of the branch it took — a `Bool`
// until lane TRANSITIONS2 — is a few flags and the pass that wrote it,
// written in one in-place access (`ConditionalRecord`). It keeps no picture:
// that was what the fade-out cost, a nested page keeping at each level what
// every level below it drew (decisions B-TRANSITIONS2-1, TR2PERF). Nothing
// else happens on a frame nothing changes.

/// What a conditional did when it last rendered: the branch it took, and
/// what of that is still playing.
///
/// The pass first, then the flags: eight bytes, with no padding between.
struct ConditionalRecord {
    /// The render pass that last wrote it (`StateStorage.currentPass`): a
    /// record a pass went by without is of a conditional that went and has
    /// come back, whose branch is a first sight, not a flip to play
    /// (`StateStorage.wasOnScreenLastPass(writtenOn:at:)`).
    var pass: UInt32 = 0
    /// The branch it took: `true` for `.trueContent`.
    var isTrueBranch: Bool
    /// Whether it had rendered before: `false` on a record made just now, a
    /// first sight, which is never a flip.
    var seen = false
    /// Whether the branch it took is fading in.
    var arriving = false
    /// The branch it left — `true` for `.trueContent` — while that branch
    /// plays a transition of its own, from what it left in the
    /// `DepartureStore` at its branch's identity.
    var leavingBranch: Bool?

    init(isTrueBranch: Bool) {
        self.isTrueBranch = isTrueBranch
    }
}

/// The owner a branch's presence is keyed by in the ``AnimationStore``, under
/// the conditional's identity, with the branch as the slot.
private enum BranchPresence {}

@MainActor extension ConditionalView {
    /// The branch labelled `isTrueBranch`, as the conditional's identity steps
    /// to it — the labels ``identityBranchLabel`` and the render agree on.
    static func branchLabel(_ isTrueBranch: Bool) -> String {
        isTrueBranch ? "true" : "false"
    }

    /// The type of view whose parting picture the branch labelled
    /// `isTrueBranch` leaves.
    @MainActor
    static func pictureType(ofBranch isTrueBranch: Bool) -> Any.Type {
        departingPictureType(heldAs: isTrueBranch ? TrueContent.self : FalseContent.self)
    }

    /// `buffer`, which the branch labelled `isTrueBranch` drew, as this
    /// conditional draws it this frame, and whether the branch flipped since
    /// the last render — recorded, in one access to the record.
    ///
    /// The render walk only.
    @MainActor
    func present(_ buffer: FrameBuffer, isTrueBranch: Bool, context: RenderContext, storage: StateStorage) -> (
        flipped: Bool, drawn: FrameBuffer
    ) {
        let identity = context.identity
        let pass = storage.currentPass
        return storage.recordingConditionalBranch(identity, isTrueBranch: isTrueBranch) { record in
            // Flipped since it last rendered — the branch left loses its state
            // whatever happened in between — and, unless the conditional has
            // come back after a pass unseen, since the last frame anyone saw,
            // which is what plays: one that has come back is a new view.
            let flipped = record.seen && record.isTrueBranch != isTrueBranch
            let cameBack =
                (flipped || record.arriving || record.leavingBranch != nil)
                && !storage.wasOnScreenLastPass(writtenOn: record.pass, at: identity)
            record.isTrueBranch = isTrueBranch
            record.seen = true
            record.pass = pass
            if cameBack {
                record.arriving = false
                record.leavingBranch = nil
            }
            // The settled frame — every render of every conditional drawn
            // whole — ends here: what the animator reads of the environment,
            // and the closure it is handed, are paid only by a frame something
            // comes or goes on.
            let plays = flipped && !cameBack
            guard plays || record.arriving || record.leavingBranch != nil else { return (flipped, buffer) }
            let animator = BranchAnimator(context: context, storage: storage, pictureType: Self.pictureType(ofBranch:))
            if plays {
                record.leavingBranch = animator.playsRemoval(ofBranch: !isTrueBranch) ? !isTrueBranch : nil
                record.arriving = animator.startsArriving(isTrueBranch)
            }
            guard record.arriving || record.leavingBranch != nil else { return (flipped, buffer) }
            return (flipped, animator.drawn(buffer, isTrueBranch: isTrueBranch, record: &record))
        }
    }
}

/// One frame of a conditional's branches coming and going.
@MainActor
private struct BranchAnimator {
    let context: RenderContext
    let storage: StateStorage
    /// The animation the frame's change runs under: a fade is not motion, so
    /// reduce motion does not hold it still.
    let animation: Animation?
    let nowNanos: Int64
    /// The type of view whose parting picture each branch leaves.
    let pictureType: (Bool) -> Any.Type

    init(context: RenderContext, storage: StateStorage, pictureType: @escaping (Bool) -> Any.Type) {
        self.context = context
        self.storage = storage
        self.pictureType = pictureType
        let frame = context.environment.animationFrame
        nowNanos = frame.nowNanos
        animation = frame.canAnimate ? context.environment.transaction.effectiveAnimation : nil
    }

    private func key(_ isTrueBranch: Bool) -> AnimationStore.Key {
        AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(BranchPresence.self), slot: isTrueBranch ? 1 : 0)
    }

    private func identity(ofBranch isTrueBranch: Bool) -> ViewIdentity {
        context.identity.branch(isTrueBranch ? "true" : "false")
    }

    /// Whether the branch labelled `isTrueBranch`, just left, plays a
    /// transition of its own as it goes — or goes at once, as one with none
    /// does. A transition that names an animation plays under it whether or
    /// not the change is animated, as ``ChildFade/leaver(from:at:)`` says.
    func playsRemoval(ofBranch isTrueBranch: Bool) -> Bool {
        let departures = storage.departures
        guard !departures.isEmpty else { return false }
        let identity = identity(ofBranch: isTrueBranch)
        let type = pictureType(isTrueBranch)
        return departures.hasEntry(at: identity, leftBy: type)
            && departures.hasDeparture(at: identity, ofType: type, nowNanos: nowNanos, frameAnimation: animation)
    }

    /// Whether the branch labelled `isTrueBranch`, just taken, fades in:
    /// under an animation, unless a transition of its own brings it in.
    func startsArriving(_ isTrueBranch: Bool) -> Bool {
        guard let animation, !storage.departures.isPresent(at: identity(ofBranch: isTrueBranch)) else { return false }
        let key = key(isTrueBranch)
        // From nothing, whatever an arrival before it had got to.
        storage.animations.settle(key, at: 0.0, nowNanos: nowNanos)
        _ = storage.animations.value(for: key, target: 1.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
        return true
    }

    /// `buffer` as drawn this frame: faded while it arrives, with the branch
    /// leaving drawn past its frame. `record` loses whatever has played out.
    func drawn(_ buffer: FrameBuffer, isTrueBranch: Bool, record: inout ConditionalRecord) -> FrameBuffer {
        let animations = storage.animations
        var drawn = buffer
        if record.arriving {
            let key = key(isTrueBranch)
            let presence = animations.value(
                for: key, target: 1.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
            if animations.isAnimating(at: key, nowNanos: nowNanos) {
                drawn = DefaultTransition.faded(buffer, by: min(1, max(0, presence)))
            } else {
                record.arriving = false
            }
        }
        if let leaving = record.leavingBranch {
            if let picture = storage.departures.departing(
                at: identity(ofBranch: leaving), ofType: pictureType(leaving), nowNanos: nowNanos,
                frameAnimation: animation)
            {
                // A matched view in it carried with the one arriving in its
                // place (`DepartureStore.carrying`).
                var carried = storage.departures.carrying(picture, leftFrom: identity(ofBranch: leaving))
                // What is leaving takes no clicks, and is not where anything is.
                carried.hitTestRegions = []
                let past = carried.drawnPastSlot(width: 0, height: 0, offsetX: 0, offsetY: 0)
                drawn.overlays = past.overlays + drawn.overlays
            } else {
                record.leavingBranch = nil
            }
        }
        if record.arriving || record.leavingBranch != nil {
            // A function of the clock, which no memo may keep.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
        }
        return drawn
    }
}
