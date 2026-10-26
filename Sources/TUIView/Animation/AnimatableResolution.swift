//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimatableResolution.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Substitutes the animated value into an ``Animatable`` view before its body is
/// evaluated, so the subtree is built from where the picture *is* rather than
/// from where the tree says the value has got to.
///
/// This is the general case, and the expensive one: the body is re-evaluated on
/// every frame of the animation, because a terminal has no render server to
/// hand an interpolation to. That is affordable for the length of a change and
/// is not affordable forever — see <doc:AnimatingYourOwnView>.
///
/// - Parameters:
///   - view: The view about to be rendered or measured.
///   - context: Its render context.
///   - isMeasuring: Whether this is the measure walk, which must not write to
///     the store. Passed rather than read from `context.isMeasuring`, because
///     that flag means something narrower — a *render* performed only in order
///     to measure — and is false on the ordinary structural measure walk, where
///     writing would be just as wrong.
/// - Returns: A copy at this frame's value, or **`nil` when there is nothing to
///   substitute** — which is the answer for every view but the animating ones,
///   and is why it is an `Optional` rather than the view itself. Returning
///   `view` would make every caller rebind it, and rebinding copies the struct
///   on every render of every view in the tree. That copy, not the check, was
///   the +1% a paired A/B kept finding.
@MainActor
func resolvingAnimation<V: View>(
    _ view: V, context: RenderContext, isMeasuring: Bool
) -> V? {
    V._animated(view, context: context, isMeasuring: isMeasuring)
}

/// An ``Animatable`` kind whose data is where something is drawn or how much
/// room it takes — an offset, a position, a fixed frame, a padding — so that
/// animating it moves things in X and Y.
///
/// Under ``EnvironmentValues/accessibilityReduceMotion`` a change to one of
/// these jumps to its end value instead of animating: reduce motion means
/// spatial motion (owner decision A-D3M-1, 2026-10-05). A colour, an opacity,
/// a breath, a spinner or a caret is not motion here, and animates as before;
/// so does an ``Animatable`` view of the app's own, which reads the flag
/// itself if it moves things, as in SwiftUI.
package protocol SpatialAnimatable: Animatable {}

/// An ``Animatable`` kind only part of whose data is motion: a visual effect
/// chain, one animated value whose offsets move things in X and Y and whose
/// opacity and colours do not.
///
/// Under ``EnvironmentValues/accessibilityReduceMotion`` a change that moves
/// only its motion — where the picture is and where it is going differ in
/// nothing else — jumps to its end, as a ``SpatialAnimatable`` change does: no
/// animation is started, so a `withAnimation` completion waiting on nothing
/// else fires at once and the loop draws no frames for it. A change that
/// moves anything else animates, and its drawer holds the motion at the
/// target meanwhile (``holdingMotion(at:)``).
package protocol PartlySpatialAnimatable: Animatable {
    /// This value — where the picture is — with its motion at `target`'s and
    /// the rest as it is.
    func holdingMotion(at target: Self) -> Self
}

extension PartlySpatialAnimatable {
    /// Whether the picture at `presented` and the value `target` differ in
    /// motion alone. `Any`-typed so it can be asked of the existential
    /// metatype `animatedValue` holds; each is cast back to this type's own.
    static func changeIsMotionOnly(to target: Any, from presented: Any) -> Bool {
        guard let target = target as? Self, let presented = presented as? AnimatableData else { return false }
        var picture = target
        picture.animatableData = presented
        return picture.holdingMotion(at: target).animatableData == target.animatableData
    }
}

extension View where Self: Animatable {
    /// An ``Animatable`` view nominates something continuous about itself, so
    /// the render and measure walks must ask the animation store what to draw
    /// it at. See ``View/_isAnimatable``.
    @inlinable
    public static var _isAnimatable: Bool { true }

    /// This view at the value the store says to draw, or `nil` when that is
    /// exactly what the tree already says.
    ///
    /// Generic in `Self`, so nothing is boxed and nothing is cast back — see
    /// ``View/_animated(_:context:isMeasuring:)``.
    @MainActor
    public static func _animated(
        _ view: Self, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        animatedValue(of: view, owner: Self.self, context: context, isMeasuring: isMeasuring)
    }
}

/// `value` at the value the animation store says to draw it at, keyed by the
/// render identity and `owner`, or `nil` when that is exactly what it already
/// is. The one implementation behind every animatable kind — a view, and a
/// modifier of either protocol — so the settled fast path and the single
/// environment read below are not three copies that could drift.
///
/// - Parameters:
///   - value: The view or modifier about to be drawn.
///   - owner: The type whose identity, with the render identity, keys the
///     store entry. A view passes itself; a modifier passes the view type that
///     encloses it, which tells two of the same modifier around one view apart.
///   - context: The render context.
///   - isMeasuring: Whether this is the measure walk — see
///     ``resolvingAnimation(_:context:isMeasuring:)``.
@MainActor
package func animatedValue<A: Animatable>(
    of value: A, owner: Any.Type, context: RenderContext, isMeasuring: Bool
) -> A? {
    guard let storage = context.stateStorage else { return nil }
    // The measure walk over a store where nothing is moving, asked where no
    // animation is in force: every answer is the target, so the store is not
    // asked (WL-Q3). A measure writes nothing, so nothing is skipped but the
    // lookup — and the lookup is what costs, its key's identity compared node
    // by node up to the root (records keep the nodes of the frame that first
    // saw them, and every frame builds new ones): on `deep` 1,720 such probes
    // a frame, about 187 nodes each. NOT the render walk, which must keep
    // asking: its first sight is the record a later change animates from,
    // and its re-declaration keeps the record alive. And not under an
    // animation, where a change this frame measures at its old value.
    if isMeasuring, storage.animations.presentsEveryTarget, !changesAnimate(in: context) { return nil }
    let key = AnimationStore.Key(identity: context.identity, owner: ObjectIdentifier(owner))
    let target = value.animatableData
    // The common case first, and before the environment is read: a value
    // the store already holds, unchanged, with nothing running. That is
    // every padded, framed and offset view on every frame nothing is
    // animating, and answering it here is what keeps making a modifier
    // `Animatable` free for the views that never are — see
    // ``AnimationStore/isSettled(_:at:isMeasuring:)`` for what it cost
    // when it was not.
    if storage.animations.isSettled(key, at: target, isMeasuring: isMeasuring) { return nil }
    // ONE environment read for both halves: `canAnimate` and `frameNowNanos`
    // are computed properties over the same `AnimationFrame` key, so asking
    // for each separately is two dictionary lookups — a hash, a probe and an
    // `Any` unbox each — for one value. It was the most-read key in the
    // environment (112 reads a frame on a menu tree). Still AFTER the
    // `isSettled` return above, which is where it has to stay: hoisting it
    // would charge every settled view for an animation it is not running.
    // (The measure-walk gate above reads the transaction before the store,
    // but in place of a lookup it saves, and only where nothing is moving.)
    let frame = context.environment.animationFrame
    var animation = frame.canAnimate ? context.environment.transaction.effectiveAnimation : nil
    // Reduce motion holds still what moves in X and Y (owner decision
    // A-D3M-1): a geometry value's change jumps to its end. Asked only of a
    // change that would animate, so a settled or unanimated value — every one
    // but the few changing this frame — pays nothing for it; a colour or an
    // opacity is not motion and is never asked.
    if animation != nil,
        holdsStill(value, at: key, in: storage.animations, nowNanos: frame.nowNanos, context: context)
    {
        animation = nil
    }
    let drawn = storage.animations.value(
        for: key, target: target, animation: animation,
        nowNanos: frame.nowNanos, isMeasuring: isMeasuring)
    guard drawn != target else { return nil }

    // The subtree's appearance is now a function of time, which a value memo
    // cannot reproduce from a cached buffer — it would freeze the animation
    // on its first frame. Same declaration `requestAnimation` makes.
    context.environment.volatileReadTracker?.recordRenderSideEffect()
    var copy = value
    copy.animatableData = drawn
    return copy
}

/// Whether a change made in `context` now would animate: the transaction in
/// force carries an animation and animation is possible this frame — the
/// expression ``animatedValue(of:owner:context:isMeasuring:)`` decides by,
/// before reduce motion, which only takes an animation away.
///
/// The transaction first, the other way round from there: in a running app
/// `canAnimate` is nearly always true and the transaction nearly always
/// carries nothing, so this is one environment read where that order is two.
@MainActor
private func changesAnimate(in context: RenderContext) -> Bool {
    context.environment.transaction.effectiveAnimation != nil && context.environment.animationFrame.canAnimate
}

/// `value` at the value the animation store says to draw it at
/// (``animatedValue(of:owner:context:isMeasuring:)``), with its motion at
/// `value`'s own where motion is reduced: a ``PartlySpatialAnimatable`` change
/// that moves only its motion starts nothing there, and one that moves
/// anything else animates, its picture's motion at the end meanwhile (owner
/// decision A-D3M-1). `nil` when there is nothing to substitute.
@MainActor
package func animatedValueHoldingMotion<A: PartlySpatialAnimatable>(
    of value: A, owner: Any.Type, context: RenderContext, isMeasuring: Bool
) -> A? {
    guard let animated = animatedValue(of: value, owner: owner, context: context, isMeasuring: isMeasuring)
    else { return nil }
    return context.environment.accessibilityReduceMotion ? animated.holdingMotion(at: value) : animated
}

/// Whether reduce motion holds `value`'s change at `key` still: a
/// ``SpatialAnimatable`` change where motion is reduced, or a
/// ``PartlySpatialAnimatable`` one that moves nothing but its motion from
/// where the picture is. Asked only of a change that would animate.
@MainActor
private func holdsStill<A: Animatable>(
    _ value: A, at key: AnimationStore.Key, in store: AnimationStore, nowNanos: Int64, context: RenderContext
) -> Bool {
    if A.self is any SpatialAnimatable.Type { return context.environment.accessibilityReduceMotion }
    // From where the picture IS, not from the last target: an offset moved
    // while an opacity is still fading is not motion alone, and jumping
    // there would cut the fade short.
    guard let partly = A.self as? any PartlySpatialAnimatable.Type,
        context.environment.accessibilityReduceMotion,
        let presented = store.presentedValue(at: key, as: A.AnimatableData.self, nowNanos: nowNanos)
    else { return false }
    return partly.changeIsMotionOnly(to: value, from: presented)
}
