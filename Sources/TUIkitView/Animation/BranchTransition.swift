//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BranchTransition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// The default transition for an `if`/`else` — and so a `switch`, which is
// nested ones — drawn WHOLE: a view's whole body, a modifier's content. The
// branch taken under an animated change fades in, and the branch left fades
// out from the picture it drew last, at the same origin, as SwiftUI draws the
// two (measured, `Tools/SwiftUIProbes/Transitions/tr1.out` T8). A conditional
// inside a stack is not drawn whole: the stack takes it apart, and its
// branches come and go as the stack's children do (`ChildFade`).
//
// ## Where the leaving branch is drawn
//
// Past the conditional's frame, as content drawn past a view's region is
// (`FrameBuffer.drawnPastSlot`): the layout is the new branch's, at once, and
// the old picture has no room in it. Drawn there it is composited by the
// compositor that resolves fades against what is behind them, which this
// module does not have; it lands over the new branch's cells rather than
// beneath them, which for two fades crossing is the same blend with the
// weights the other way round. Its hit regions are dropped: what is leaving
// takes no clicks.
//
// ## What it costs
//
// The record the conditional already keeps of the branch it took
// (`ConditionalRecord`) holds the picture as well, written in the one access
// the record already took: a lookup and a store before, one in-place access
// now. Nothing else happens on a frame nothing changes.

/// What a conditional did when it last rendered: the branch it took, and —
/// where it was drawn whole — what that branch drew and what is still
/// playing.
struct ConditionalRecord {
    /// The branch it took: `true` for `.trueContent`.
    var isTrueBranch: Bool
    /// Whether it had rendered before: `false` on a record made just now, a
    /// first sight, which is never a flip.
    var seen = false
    /// The render pass that last wrote it (`StateStorage.currentPass`): a
    /// record a pass went by without is of a conditional that went and has
    /// come back, whose branch is a first sight, not a flip to play
    /// (`StateStorage.wasOnScreenLastPass(writtenOn:at:)`).
    var pass: UInt32 = 0
    /// Whether the branch it took is fading in.
    var arriving = false
    /// What the branch drew when the conditional was last drawn whole, or
    /// `nil` where it was only asked which branch it took.
    var picture: FrameBuffer?
    /// The branch it left, while that is still leaving.
    var leaving: LeavingBranch?

    init(isTrueBranch: Bool) {
        self.isTrueBranch = isTrueBranch
    }
}

/// The branch a conditional left, while it leaves.
enum LeavingBranch {
    /// Fading out from the picture it drew last.
    case fading(FrameBuffer, isTrueBranch: Bool)
    /// Playing a transition of its own, from what it left in the
    /// `DepartureStore` at its branch's identity.
    case playing(isTrueBranch: Bool)

    var isTrueBranch: Bool {
        switch self {
        case .fading(_, let isTrueBranch), .playing(let isTrueBranch): isTrueBranch
        }
    }
}

/// The owner a branch's presence is keyed by in the ``AnimationStore``, under
/// the conditional's identity, with the branch as the slot.
private enum BranchPresence {}

extension ConditionalView {
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
                (flipped || record.arriving || record.leaving != nil)
                && !storage.wasOnScreenLastPass(writtenOn: record.pass, at: identity)
            let left = record.picture
            record.isTrueBranch = isTrueBranch
            record.seen = true
            record.pass = pass
            record.picture = buffer
            if cameBack {
                record.arriving = false
                record.leaving = nil
            }
            // The settled frame — every render of every conditional drawn
            // whole — ends here: what the animator reads of the environment,
            // and the closure it is handed, are paid only by a frame something
            // comes or goes on.
            let plays = flipped && !cameBack
            guard plays || record.arriving || record.leaving != nil else { return (flipped, buffer) }
            let animator = BranchAnimator(context: context, storage: storage, pictureType: Self.pictureType(ofBranch:))
            if plays {
                record.leaving = animator.leaver(left, isTrueBranch: !isTrueBranch)
                record.arriving = animator.startsArriving(isTrueBranch)
            }
            guard record.arriving || record.leaving != nil else { return (flipped, buffer) }
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

    /// How the branch labelled `isTrueBranch`, which drew `picture` last and
    /// has just been left, leaves — or `nil` where it simply goes. A
    /// transition of its own that names an animation plays under it whether
    /// or not the change is animated, as ``ChildFade/leaver(from:picture:at:)``
    /// says.
    func leaver(_ picture: FrameBuffer?, isTrueBranch: Bool) -> LeavingBranch? {
        let departures = storage.departures
        let identity = identity(ofBranch: isTrueBranch)
        if departures.hasEntry(at: identity, leftBy: pictureType(isTrueBranch)) {
            // A transition of its own, which plays unless it says it goes at
            // once.
            guard
                departures.hasDeparture(
                    at: identity, ofType: pictureType(isTrueBranch), nowNanos: nowNanos, frameAnimation: animation)
            else { return nil }
            return .playing(isTrueBranch: isTrueBranch)
        }
        guard let animation, let picture, !picture.isEmpty else { return nil }
        let key = key(isTrueBranch)
        // From where it is if it was still on its way in.
        storage.animations.settle(key, at: 1.0, nowNanos: nowNanos)
        _ = storage.animations.value(for: key, target: 0.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
        return .fading(picture, isTrueBranch: isTrueBranch)
    }

    /// Whether the branch labelled `isTrueBranch`, just taken, fades in:
    /// under an animation, unless a transition of its own brings it in.
    func startsArriving(_ isTrueBranch: Bool) -> Bool {
        guard let animation, !storage.departures.isPresent(at: identity(ofBranch: isTrueBranch)) else { return false }
        let key = key(isTrueBranch)
        // From where it is if it was on its way out.
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
        if let leaving = record.leaving {
            if var picture = picture(of: leaving) {
                // What is leaving takes no clicks, and is not where anything is.
                picture.hitTestRegions = []
                // Where a matched view in it is carried, with the one
                // arriving in its place (`DepartureStore.carrying`).
                let carry = storage.departures.carriedOffset(within: identity(ofBranch: leaving.isTrueBranch))
                let past = picture.drawnPastSlot(width: 0, height: 0, offsetX: carry?.x ?? 0, offsetY: carry?.y ?? 0)
                drawn.overlays = past.overlays + drawn.overlays
            } else {
                record.leaving = nil
            }
        }
        if record.arriving || record.leaving != nil {
            // A function of the clock, which no memo may keep.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
        }
        return drawn
    }

    /// The picture of `leaving` on this frame, or `nil` once it has gone.
    private func picture(of leaving: LeavingBranch) -> FrameBuffer? {
        switch leaving {
        case .fading(let picture, let isTrueBranch):
            let key = key(isTrueBranch)
            let presence = storage.animations.value(
                for: key, target: 0.0, animation: animation, nowNanos: nowNanos, isMeasuring: false)
            guard storage.animations.isAnimating(at: key, nowNanos: nowNanos) else { return nil }
            return DefaultTransition.faded(picture, by: min(1, max(0, presence)))
        case .playing(let isTrueBranch):
            return storage.departures.departing(
                at: identity(ofBranch: isTrueBranch), ofType: pictureType(isTrueBranch), nowNanos: nowNanos,
                frameAnimation: animation)
        }
    }
}
