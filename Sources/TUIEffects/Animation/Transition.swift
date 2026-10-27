//  🖥️ TUI — A Terminal UI framework for Swift
//  Transition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// A description of view changes to apply when a view is added to and removed
/// from the view hierarchy.
///
/// A transition is made by applying modifiers to the `content` it is handed.
/// For a symmetric transition, read the phase's `isIdentity`; for an
/// asymmetric one, the phase itself:
///
/// ```swift
/// struct SlideAndFade: Transition {
///     func body(content: Content, phase: TransitionPhase) -> some View {
///         content
///             .opacity(phase.isIdentity ? 1 : 0)
///             .offset(x: Int(phase.value) * 4)
///     }
/// }
///
/// if showDetail {
///     Detail().transition(SlideAndFade())
/// }
/// ```
///
/// Don't change the structure of `content` between phases — no `.id`, `if` or
/// `switch` on it — since what animates is each modifier's value between one
/// phase and the next, and a modifier that is there in one phase and not the
/// other has nothing to animate between.
///
/// ## How the body is drawn
///
/// A view appearing under an animated change is drawn with its body at
/// ``TransitionPhase/willAppear`` and moves to ``TransitionPhase/identity``; one
/// leaving moves from `.identity` to ``TransitionPhase/didDisappear``. What
/// moves is every animatable value the body produces — an ``Animatable`` view
/// or modifier's data (`.opacity`, `.offset`, `.padding`, a modifier of your
/// own) and the colours `.foregroundStyle`, `.background` and `.border` paint —
/// each interpolated from its value at one phase to its value at the other,
/// exactly as SwiftUI interpolates them. An unanimated change, as everywhere,
/// is instant. At rest the body is drawn at `.identity`, for as long as the
/// view is shown.
///
/// Three things differ from SwiftUI, each because a terminal frame is rebuilt
/// from the tree:
///
/// - **While a view leaves, its content is the picture it last drew.** The
///   view no longer exists — see `View.transition(_:)` — so the body's own
///   modifiers move around the cells the content left behind, and nothing the
///   body changes INSIDE the content changes any more.
/// - **The view keeps the size its body has at `.identity`** while it comes and
///   goes. A body that changes the view's size between phases is drawn inside
///   that size rather than re-laying its siblings out on every frame, which is
///   the rule ``AnyTransition``'s own effects follow.
/// - **A body that is not an identity at `.identity`** — SwiftUI says it
///   "should generally" be — is still drawn every frame, so a custom
///   transition costs a body evaluation per frame at rest, as a `ViewModifier`
///   does, and two while it plays.
///
/// The built-in transitions — ``OpacityTransition``, ``MoveTransition``,
/// ``OffsetTransition``, ``ScaleTransition``, ``SlideTransition``,
/// ``PushTransition``, ``IdentityTransition`` and ``AsymmetricTransition`` —
/// have bodies of their own, so they can be composed into yours with
/// ``apply(content:phase:)``; applied with `View.transition(_:)` they cost
/// what ``AnyTransition``'s effects always have.
@MainActor @preconcurrency
public protocol Transition {
    /// The type of view representing the body.
    associatedtype Body: View

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    @ViewBuilder
    func body(content: Content, phase: TransitionPhase) -> Body

    /// Returns the properties this transition type has.
    ///
    /// Defaults to `TransitionProperties()`.
    static var properties: TransitionProperties { get }

    /// The content view type passed to ``body(content:phase:)``.
    typealias Content = PlaceholderContentView<Self>

    /// This transition as an ``AnyTransition``. Not to be implemented by hand:
    /// a transition of your own is drawn through its body, and the built-in
    /// ones answer with the buffer effects they are made of.
    var _erased: AnyTransition { get }
}

extension Transition {
    /// A transition has motion unless it says otherwise.
    public static var properties: TransitionProperties { TransitionProperties() }

    /// A transition of the app's own is drawn through its body.
    public var _erased: AnyTransition {
        AnyTransition(custom: _AnyTransitionBox(self))
    }

    /// This transition's body, built around `content` at `phase` — how one
    /// transition is composed into another's body.
    ///
    /// ```swift
    /// func body(content: Content, phase: TransitionPhase) -> some View {
    ///     OpacityTransition().apply(content: content, phase: phase)
    ///         .padding(.leading, phase.isIdentity ? 0 : 2)
    /// }
    /// ```
    public func apply<V: View>(content: V, phase: TransitionPhase) -> some View {
        body(content: PlaceholderContentView(source: PlaceholderSource(view: content)), phase: phase)
    }

    /// This transition and `other`, applied together: this one to the view,
    /// and `other` to the result.
    public func combined<T: Transition>(with other: T) -> some Transition {
        _CombinedTransition(first: self, second: other)
    }

    /// Attaches an animation to this transition: it runs with `animation`
    /// whatever the change that caused it was made under — or, with `nil`, at
    /// once, even inside `withAnimation`. An animation this transition already
    /// names for a phase is kept: the one nearest the view wins, as
    /// ``AnyTransition/animation(_:)`` says.
    public func animation(_ animation: Animation?) -> some Transition {
        _AnimatedTransition(base: self, animation: animation)
    }
}

// MARK: - Phases and properties

/// An indication of which the current stage of a transition.
///
/// When a view is appearing with a transition, the transition is first shown
/// with the ``willAppear`` phase, then immediately moved to the ``identity``
/// phase. When a view is being removed, its transition is changed from the
/// `identity` phase to the ``didDisappear`` phase. If a view is removed while
/// it is still transitioning in, its phase changes to `didDisappear` from
/// wherever it had got to.
///
/// In the `identity` phase a transition should generally make no visual change
/// to the view, since what it does there is applied for as long as the view is
/// visible. In the other two, it should apply a change that will be animated
/// to create the transition; if no animatable change is applied, the
/// transition is a no-op.
@frozen
public enum TransitionPhase: Hashable, Sendable {
    /// The transition is being applied to a view that is about to be inserted
    /// into the view hierarchy.
    ///
    /// In this phase, a transition should show the appearance that will be
    /// animated from to make the appearance transition.
    case willAppear

    /// The transition is being applied to a view that is in the view
    /// hierarchy.
    ///
    /// In this phase, a transition should show its steady state appearance,
    /// which will generally not make any visual change to the view.
    case identity

    /// The transition is being applied to a view that has been requested to be
    /// removed from the view hierarchy.
    ///
    /// In this phase, a transition should show the appearance that will be
    /// animated to make the disappearance transition.
    case didDisappear

    /// A Boolean that indicates whether the transition should have an identity
    /// effect, i.e. not change the appearance of its view.
    ///
    /// This is true in the `identity` phase.
    public var isIdentity: Bool { self == .identity }

    /// A value that can be used to multiply effects that are applied
    /// differently depending on the phase.
    ///
    /// Zero when in the `identity` case, -1.0 for `willAppear`, and 1.0 for
    /// `didDisappear`.
    public var value: Double {
        switch self {
        case .willAppear: -1
        case .identity: 0
        case .didDisappear: 1
        }
    }
}

/// The properties a ``Transition`` can have.
///
/// A transition's properties are high-level information about it, which can
/// decide how it interacts with other features.
public struct TransitionProperties: Sendable, Equatable {
    /// Whether the transition includes motion.
    ///
    /// When it does, the transition is replaced by `.opacity` wherever
    /// ``EnvironmentValues/accessibilityReduceMotion`` is `true` — as SwiftUI
    /// replaces it when Reduce Motion is on. In a terminal that is the user's
    /// `TUI_REDUCE_MOTION=1` or the app's `Scene.reduceMotion(_:)`; the
    /// replacement keeps the transition's own animation, if it has one.
    ///
    /// Defaults to `true`.
    public var hasMotion: Bool

    /// Creates the properties of a transition.
    public init(hasMotion: Bool = true) {
        self.hasMotion = hasMotion
    }
}

// MARK: - Composition

/// Two transitions applied together — what ``Transition/combined(with:)``
/// returns.
struct _CombinedTransition<First: Transition, Second: Transition>: Transition {
    let first: First
    let second: Second

    func body(content: Content, phase: TransitionPhase) -> some View {
        second.apply(content: first.apply(content: content, phase: phase), phase: phase)
    }

    /// Motion if either half has it (measured on SwiftUI: opacity with move
    /// has motion, opacity with opacity has none).
    static var properties: TransitionProperties {
        TransitionProperties(
            hasMotion: First.properties.hasMotion || Second.properties.hasMotion)
    }

    var _erased: AnyTransition {
        first._erased.combined(with: second._erased)
    }
}

/// A transition with an animation of its own — what
/// ``Transition/animation(_:)`` returns.
struct _AnimatedTransition<Base: Transition>: Transition {
    let base: Base
    let animation: Animation?

    func body(content: Content, phase: TransitionPhase) -> some View {
        base.apply(content: content, phase: phase)
    }

    static var properties: TransitionProperties { Base.properties }

    var _erased: AnyTransition {
        base._erased.animation(animation)
    }
}
