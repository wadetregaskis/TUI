//  🖥️ TUI — A Terminal UI framework for Swift
//  BuiltInTransitions.swift
//
//  The built-in transitions as `Transition` types: each a real body, made of
//  the one animatable modifier below, and each erasing to the `AnyTransition`
//  effects it is drawn with.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIStyling
import TUIView

// MARK: - The modifier every built-in body is made of

/// ``AnyTransition``'s effects as an animatable modifier: how present the view
/// is on its way in, and on its way out, each `1` at rest.
///
/// What lets a built-in transition's body be scrubbed like any other (see
/// ``Transition``): its phases differ only in this pair, so drawing the body
/// part-way interpolates the pair, and the effect is applied at the
/// interpolated presence — exactly what the buffer path does with the arrival
/// and departure phases. Two numbers rather than one signed one, so an
/// arriving spring's overshoot (presence above 1) stays the insertion's.
struct _TransitionEffectModifier: BufferModifier, Animatable {
    /// Its content stays where it is laid out — a transition draws its view displaced, but lays it out where it is, as an offset does — so a guide inside it
    /// passes unmoved (``BufferModifier/_keepsContentGeometry``).
    static var _keepsContentGeometry: Bool { true }

    let insertion: AnyTransition.Effect
    let removal: AnyTransition.Effect

    /// How present the view is arriving, then leaving.
    var animatableData: AnimatablePair<Double, Double>

    init(insertion: AnyTransition.Effect, removal: AnyTransition.Effect, phase: TransitionPhase) {
        self.insertion = insertion
        self.removal = removal
        animatableData = AnimatablePair(
            phase == .willAppear ? 0 : 1, phase == .didDisappear ? 0 : 1)
    }

    init(_ effect: AnyTransition.Effect, phase: TransitionPhase) {
        self.init(insertion: effect, removal: effect, phase: phase)
    }

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        var drawn = buffer
        if animatableData.first != 1 {
            drawn = insertion.apply(to: drawn, phase: animatableData.first, context: context)
                .slotBuffer()
        }
        if animatableData.second != 1 {
            drawn = removal.apply(to: drawn, phase: animatableData.second, context: context)
                .slotBuffer()
        }
        return drawn
    }
}

// MARK: - Identity

/// A transition that returns the input view, unmodified, as the output view.
public struct IdentityTransition: Transition {
    /// Creates the identity transition.
    public init() {}

    /// The content, unchanged.
    public func body(content: Content, phase: TransitionPhase) -> Content {
        content
    }

    /// No motion.
    public static let properties = TransitionProperties(hasMotion: false)

    public var _erased: AnyTransition { .identity }
}

extension Transition where Self == IdentityTransition {
    /// A transition that returns the input view, unmodified, as the output
    /// view.
    public static var identity: IdentityTransition { Self() }
}

// MARK: - Opacity

/// A transition from transparent to opaque on insertion, and from opaque to
/// transparent on removal.
///
/// A cell has no alpha: the view's colours are composited toward what is
/// behind it, as ``View/opacity(_:)`` does.
public struct OpacityTransition: Transition {
    /// Creates an opacity transition.
    public init() {}

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(_TransitionEffectModifier(.opacity, phase: phase))
    }

    /// No motion.
    public static let properties = TransitionProperties(hasMotion: false)

    public var _erased: AnyTransition { .opacity }
}

extension Transition where Self == OpacityTransition {
    /// A transition from transparent to opaque on insertion, and from opaque
    /// to transparent on removal.
    public static var opacity: OpacityTransition { Self() }
}

// MARK: - Move

/// A transition that moves the view away, towards the specified edge of the
/// view — by the view's own width or height, in whole cells.
public struct MoveTransition: Transition {
    /// The edge to move the view towards.
    public var edge: Edge

    /// Creates a transition that moves the view away, towards the specified
    /// edge of the view.
    public init(edge: Edge) {
        self.edge = edge
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(_TransitionEffectModifier(.move(edge: edge), phase: phase))
    }

    public var _erased: AnyTransition { .move(edge: edge) }
}

extension Transition where Self == MoveTransition {
    /// Returns a transition that moves the view away, towards the specified
    /// edge of the view.
    public static func move(edge: Edge) -> Self {
        Self(edge: edge)
    }
}

// MARK: - Offset

/// A transition that offsets the view by the specified amount, in cells.
public struct OffsetTransition: Transition {
    /// The amount to offset the view by.
    public var offset: CellSize

    /// Creates a transition that offsets the view by the specified amount.
    public init(_ offset: CellSize) {
        self.offset = offset
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(
            _TransitionEffectModifier(.offset(x: offset.width, y: offset.height), phase: phase))
    }

    public var _erased: AnyTransition { .offset(offset) }
}

extension Transition where Self == OffsetTransition {
    /// Returns a transition that offsets the view by the specified amount.
    public static func offset(_ offset: CellSize) -> Self {
        Self(offset)
    }

    /// Returns a transition that offsets the view by the specified x and y
    /// values, in columns and rows.
    public static func offset(x: Int = 0, y: Int = 0) -> Self {
        Self(CellSize(width: x, height: y))
    }
}

// MARK: - Scale

/// A transition that scales the view.
///
/// A cell grid cannot draw a view smaller than its cells, so the view is
/// uncovered from the anchor instead, a whole cell at a time: `scale` is how
/// much of it shows at the start. See ``AnyTransition/scale(scale:anchor:)``,
/// including what a scale above 1 draws.
public struct ScaleTransition: Transition {
    /// The amount to scale the view by.
    public var scale: Double

    /// The anchor point to scale the view around.
    public var anchor: UnitPoint

    /// Creates a transition that scales the view by the specified amount.
    public init(_ scale: Double, anchor: UnitPoint = .center) {
        self.scale = scale
        self.anchor = anchor
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(
            _TransitionEffectModifier(.scale(factor: scale, anchor: anchor), phase: phase))
    }

    public var _erased: AnyTransition { .scale(scale: scale, anchor: anchor) }
}

extension Transition where Self == ScaleTransition {
    /// Returns a transition that scales the view.
    public static var scale: ScaleTransition { Self(AnyTransition.defaultScale) }

    /// Returns a transition that scales the view by the specified amount.
    public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> Self {
        Self(scale, anchor: anchor)
    }
}

// MARK: - Slide

/// A transition that inserts by moving in from the leading edge, and removes
/// by moving out towards the trailing edge.
public struct SlideTransition: Transition {
    /// Creates a slide transition.
    public init() {}

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(
            _TransitionEffectModifier(
                insertion: .move(edge: .leading), removal: .move(edge: .trailing), phase: phase))
    }

    public var _erased: AnyTransition { .slide }
}

extension Transition where Self == SlideTransition {
    /// A transition that inserts by moving in from the leading edge, and
    /// removes by moving out towards the trailing edge.
    public static var slide: SlideTransition { Self() }
}

// MARK: - Push

/// A transition that when added to a view will animate the view's insertion by
/// moving it in from the specified edge while fading it in, and animate its
/// removal by moving it out towards the opposite edge and fading it out.
public struct PushTransition: Transition {
    /// The edge from which the view will be animated in.
    public var edge: Edge

    /// Creates a transition that animates a view by moving and fading it.
    public init(edge: Edge) {
        self.edge = edge
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        let pushed = AnyTransition.push(from: edge)
        return content.modifier(
            _TransitionEffectModifier(
                insertion: pushed.insertion, removal: pushed.removal, phase: phase))
    }

    public var _erased: AnyTransition { .push(from: edge) }
}

extension Transition where Self == PushTransition {
    /// Creates a transition that when added to a view will animate the view's
    /// insertion by moving it in from the specified edge while fading it in,
    /// and animate its removal by moving it out towards the opposite edge and
    /// fading it out.
    ///
    /// - Parameter edge: The edge from which the view will be animated in.
    /// - Returns: A transition that animates a view by moving and fading it.
    public static func push(from edge: Edge) -> Self {
        Self(edge: edge)
    }
}

// MARK: - Blur replace

/// A transition that animates the insertion or removal of a view by
/// combining blurring and scaling effects.
///
/// SwiftUI scales the view between 0.9 and its full size from its centre,
/// fades it, and blurs it (measured, `Tools/SwiftUIProbes/Transitions/tr4.out`).
/// A cell has no sub-cell detail to soften, so here **the blur is drawn as a
/// fade**: at a cell's resolution a blurred view reads as one that has faded,
/// and the opacity compositor already dissolves its colours toward what is
/// behind it (decisions A34). The scale is ``ScaleTransition``'s reveal from
/// the centre, a whole cell at a time, from 0.9 of the view.
///
/// ``Configuration-swift.struct/upUp`` scales the view up as it leaves, which
/// a reveal cannot draw — it would be the view larger than its slot — so its
/// removal is the fade alone.
public struct BlurReplaceTransition: Transition {
    /// Configuration properties for a transition that animates the insertion
    /// or removal of a view by combining blurring and scaling effects.
    public struct Configuration: Equatable, Sendable {
        /// Whether the view scales up, rather than down, as it leaves.
        let scalesUpOnRemoval: Bool

        /// A configuration that requests a transition that scales the view
        /// down while removing it and up while inserting it.
        public static let downUp = Self(scalesUpOnRemoval: false)

        /// A configuration that requests a transition that scales the view up
        /// while both removing and inserting it.
        public static let upUp = Self(scalesUpOnRemoval: true)
    }

    /// The transition configuration.
    public var configuration: Configuration

    /// Creates a new transition.
    ///
    /// - Parameter configuration: the transition configuration.
    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(
            _TransitionEffectModifier(
                insertion: Self.insertion, removal: removal, phase: phase))
    }

    public var _erased: AnyTransition {
        AnyTransition(insertion: Self.insertion, removal: removal)
    }

    /// How much of the view SwiftUI's scale starts from, and ends at on a
    /// `.downUp` removal (measured: 180×90 of a 200×100 view, `tr4.out`).
    static let startingScale = 0.9

    /// In from 0.9 of the view at its centre, fading in.
    private static let insertion = AnyTransition.Effect.combined(
        .scale(factor: startingScale, anchor: .center), .opacity)

    /// Out to 0.9 of the view, fading; or, scaling up, the fade alone.
    private var removal: AnyTransition.Effect {
        configuration.scalesUpOnRemoval ? .opacity : Self.insertion
    }
}

extension Transition where Self == BlurReplaceTransition {
    /// Returns a transition that animates the insertion or removal of a view
    /// by combining blurring and scaling effects. The blur is drawn as a fade;
    /// see ``BlurReplaceTransition``.
    public static func blurReplace(_ config: BlurReplaceTransition.Configuration = .downUp) -> Self {
        Self(configuration: config)
    }

    /// A transition that animates the insertion or removal of a view by
    /// combining blurring and scaling effects. The blur is drawn as a fade;
    /// see ``BlurReplaceTransition``.
    public static var blurReplace: BlurReplaceTransition {
        blurReplace(.downUp)
    }
}

// MARK: - Asymmetric

/// A composite `Transition` that uses a different transition for insertion
/// versus removal.
///
/// Both halves are in the body at every phase, each at `.identity` except the
/// one whose turn it is — so the body's structure is the same throughout, and
/// what each half leaves at rest stays there.
public struct AsymmetricTransition<Insertion: Transition, Removal: Transition>: Transition {
    /// The `Transition` defining the insertion phase of `self`.
    public var insertion: Insertion

    /// The `Transition` defining the removal phase of `self`.
    public var removal: Removal

    /// Creates a composite `Transition` that uses a different transition for
    /// insertion versus removal.
    public init(insertion: Insertion, removal: Removal) {
        self.insertion = insertion
        self.removal = removal
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        removal.apply(
            content: insertion.apply(
                content: content, phase: phase == .willAppear ? .willAppear : .identity),
            phase: phase == .didDisappear ? .didDisappear : .identity)
    }

    /// Motion if either half has it (measured on SwiftUI).
    public static var properties: TransitionProperties {
        TransitionProperties(
            hasMotion: Insertion.properties.hasMotion || Removal.properties.hasMotion)
    }

    public var _erased: AnyTransition {
        .asymmetric(insertion: insertion._erased, removal: removal._erased)
    }
}

// MARK: - Between two modifiers

extension AnyTransition {
    /// Returns a transition defined between an active modifier and an
    /// identity modifier.
    ///
    /// The view is drawn with `active` while it is away and `identity` while
    /// it is shown, and the modifier's animatable data is interpolated between
    /// the two as the view comes and goes — so the modifier should be
    /// ``Animatable``, or there is nothing between them to draw. This is a
    /// ``Transition`` body like any other; see there for how one is drawn.
    @MainActor
    public static func modifier<E: ViewModifier>(active: E, identity: E) -> AnyTransition {
        AnyTransition(_ModifierTransition(active: active, identity: identity))
    }
}

/// A transition between two values of one modifier — what
/// ``AnyTransition/modifier(active:identity:)`` builds.
struct _ModifierTransition<Modifier: ViewModifier>: Transition {
    let active: Modifier
    let identity: Modifier

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(phase.isIdentity ? identity : active)
    }
}
