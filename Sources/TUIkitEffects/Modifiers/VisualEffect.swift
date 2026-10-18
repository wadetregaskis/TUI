//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VisualEffect.swift
//
//  `visualEffect(_:)`: effects that change how a view is drawn, computed from
//  where it was laid out, without changing the layout.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

/// Visual Effects change the visual appearance of a view without changing its
/// ancestors or descendents.
///
/// Because effects do not impact layout, they are safe to use in situations
/// where layout modification is not allowed. For example, effects may be
/// applied as a function of position, accessed through a geometry proxy:
///
/// ```swift
/// var body: some View {
///     ContentRow()
///         .visualEffect { content, geometryProxy in
///             content.offset(x: geometryProxy.frame(in: .global).origin.y)
///         }
/// }
/// ```
///
/// You don't conform to this protocol yourself. Instead, visual effects are
/// created by calling modifier functions (such as `.offset(x:y:)`) on other
/// effects, as seen in the example above.
///
/// The effects a cell can show are here: `offset` (in whole cells),
/// `opacity`, and the colour effects `brightness`, `contrast`, `saturation`,
/// `grayscale` and `hueRotation`, each drawing exactly what the `View`
/// modifier of the same name draws. Rotation, scale and arbitrary transforms
/// move a view by less than a cell, and blur, blend modes and shaders address
/// pixels; none of them is offered, so asking for one fails to compile.
///
/// An effect is ``Animatable``: a change to one under an animated transaction
/// moves through every frame between the two, as a modifier's does — except
/// its offsets where ``EnvironmentValues/accessibilityReduceMotion`` is on:
/// those jump to their end, while its opacity and colours still animate.
public protocol VisualEffect: Sendable, Animatable {
    /// `buffer` — the view as drawn — with this effect applied. Not to be
    /// implemented by hand: effects are made by the modifier functions.
    func _applied(to buffer: FrameBuffer, context: RenderContext) -> FrameBuffer

    /// This effect part-way through an animation, with its motion — every
    /// offset in it — at `target`'s instead, and the rest as it is: what it
    /// draws under reduce motion. Not to be implemented by hand.
    func _holdingMotion(at target: Self) -> Self
}

extension VisualEffect {
    /// An effect with no offset in it holds nothing still.
    public func _holdingMotion(at target: Self) -> Self { self }
}

/// The base visual effect that you apply additional effect to.
///
/// `EmptyVisualEffect` does not change the appearance of the view that it is
/// applied to.
public struct EmptyVisualEffect: VisualEffect {
    /// Creates the empty effect.
    public init() {}

    /// The data to animate: none.
    public typealias AnimatableData = EmptyAnimatableData

    /// The view, unchanged.
    public func _applied(to buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        buffer
    }
}

extension View {
    /// Applies effects to this view, while providing access to layout
    /// information through a geometry proxy.
    ///
    /// You return new effects by calling functions on the first argument
    /// provided to the `effect` closure. In this example, `ContentView` is
    /// offset by its own size, causing its top left corner to appear where the
    /// bottom right corner was originally located:
    ///
    /// ```swift
    /// ContentView()
    ///     .visualEffect { content, geometryProxy in
    ///         content.offset(geometryProxy.size)
    ///     }
    /// ```
    ///
    /// The proxy describes the view as it was laid out: its ``GeometryProxy/size``
    /// in cells, and its frame in every space — `.global`, a name a view around
    /// it declared, the nearest scroll view's — answered as a `GeometryReader`'s
    /// is: predicted before the effect is drawn, and drawn once more by the
    /// space's owner when the prediction missed (design study A2). The effect
    /// never moves where the view is in any of them.
    ///
    /// - Parameter effect: A closure that returns the effect to be applied. The
    ///   first argument provided to the closure is a placeholder representing
    ///   this view. The second argument is a `GeometryProxy`.
    /// - Returns: A view with the effect applied.
    public func visualEffect<Effect: VisualEffect>(
        _ effect: @escaping @MainActor @Sendable (EmptyVisualEffect, GeometryProxy) -> Effect
    ) -> some View {
        _VisualEffectView(content: self, effect: effect)
    }
}

/// Draws its content, then the effect a closure computed from the content's
/// size. See ``View/visualEffect(_:)``.
struct _VisualEffectView<Content: View, Effect: VisualEffect>: View {
    let content: Content
    let effect: @MainActor @Sendable (EmptyVisualEffect, GeometryProxy) -> Effect

    var body: Never {
        fatalError("_VisualEffectView renders via Renderable")
    }
}

extension _VisualEffectView: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // What the effect asks about the spaces around the view goes through
        // this, and is held to by the spaces' owners, as a reader's is — the
        // effect is built from the answer (`GeometryAsk.Role.reader`).
        // Claimed BEFORE the content renders, for the reason
        // `OnGeometryChangeModifier` claims first: the marker's id is the
        // ordinal of this claim at this identity, and content drawn at the
        // same identity (an `AnyView`, an `if`) that stamps a marker of its
        // own one frame and not the next would move a claim made after it —
        // and with it what was found for this view.
        let ask = context.makeGeometryAsk(role: .reader)
        let buffer = TUIkitView.renderToBuffer(content, context: context)
        let applied = animatedEffect(
            effect(EmptyVisualEffect(), GeometryProxy(width: buffer.width, height: buffer.height, ask: ask)),
            owner: Self.self, context: context, isMeasuring: context.isMeasuring)
        var drawn = applied._applied(to: buffer, context: context)
        // An effect that asked another space stamps where the view is laid out
        // — the drawing's own frame, which no effect moves — for that space's
        // owner to find; one that asked only its size stamps nothing.
        if let ask {
            ask.finishRecording(size: buffer.cellSize)
            if context.geometryCoordinator?.register(ask) == true {
                drawn.hitTestRegions.append(.geometryMarker(ask.id))
            }
        }
        return drawn
    }

    /// Effects do not change layout: this measures as its content.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// `effect` where its animation has got to: the effect animates as an
/// animatable modifier does, keyed by this place and `owner`, and substituted
/// with where its picture has got to.
///
/// Under reduce motion a change of its offsets alone jumps there and starts
/// nothing (`PartlySpatialAnimatable`); a change of anything else animates, the
/// colours and opacity moving and the offsets at their end at once (owner
/// decision A-D3M-1): one animation runs for the whole chain, and its motion is
/// read from the target. Asked only while the effect is changing.
///
/// - Parameters:
///   - effect: The effect the view asks for now — the animation's target.
///   - owner: The type whose place keys the animation.
///   - context: The context whose transaction animates a change.
///   - isMeasuring: Whether this is a measure, which reads but never starts one.
@MainActor
func animatedEffect<Effect: VisualEffect>(
    _ effect: Effect, owner: Any.Type, context: RenderContext, isMeasuring: Bool
) -> Effect {
    animatedValueHoldingMotion(
        of: _AnimatedEffect(effect: effect), owner: owner, context: context, isMeasuring: isMeasuring
    )?.effect ?? effect
}

/// An effect chain as the animation store sees it: the chain's data, and the
/// part of it that is motion — its offsets (``VisualEffect/_holdingMotion(at:)``).
/// One wrapper for every chain, so an effect added later is covered by its
/// own witness.
private struct _AnimatedEffect<Effect: VisualEffect>: PartlySpatialAnimatable {
    var effect: Effect

    var animatableData: Effect.AnimatableData {
        get { effect.animatableData }
        set { effect.animatableData = newValue }
    }

    func holdingMotion(at target: Self) -> Self {
        Self(effect: effect._holdingMotion(at: target.effect))
    }
}

/// `view` — an effect's `View` modifier around the buffer it applies to —
/// drawn one identity step in, keyed by the effect's own type so two effects
/// of a chain never share an animation-store entry, and with animations
/// disabled: the effect's value is already the one to draw.
@MainActor
private func drawEffect<V: View>(_ view: V, owner: Any.Type, context: RenderContext) -> FrameBuffer {
    var quiet = context.withChildIdentity(erasedType: owner, index: 0)
    quiet.environment.transaction.disablesAnimations = true
    return TUIkitView.renderToBuffer(view, context: quiet)
}

// MARK: - The effects

extension VisualEffect {
    /// Offsets the view by the horizontal and vertical amount specified in the
    /// offset parameter, in cells.
    ///
    /// - Parameter offset: The distance to offset the view.
    /// - Returns: An effect that offsets the view by `offset`.
    public func offset(_ offset: CellSize) -> some VisualEffect {
        _OffsetEffect(base: self, x: Double(offset.width), y: Double(offset.height))
    }

    /// Offsets the view by the specified horizontal and vertical distances, in
    /// columns and rows.
    ///
    /// - Parameters:
    ///   - x: The horizontal distance to offset the view.
    ///   - y: The vertical distance to offset the view.
    /// - Returns: An effect that offsets the view by `x` and `y`.
    public func offset(x: Int = 0, y: Int = 0) -> some VisualEffect {
        _OffsetEffect(base: self, x: Double(x), y: Double(y))
    }

    /// Sets the transparency of the view.
    ///
    /// When applying the `opacity(_:)` effect to a view that has already had
    /// its opacity transformed, the effect of the underlying opacity
    /// transformation is multiplied.
    ///
    /// - Parameter opacity: A value between 0 (fully transparent) and 1 (fully
    ///   opaque).
    /// - Returns: An effect that sets the transparency of the view.
    public func opacity(_ opacity: Double) -> some VisualEffect {
        _OpacityEffect(base: self, opacity: opacity)
    }

    /// Brightens the view by the specified amount.
    ///
    /// - Parameter amount: A value between 0 (no effect) and 1 (full white
    ///   brightening) that represents the intensity of the brightness effect.
    /// - Returns: An effect that brightens the view by the specified amount.
    public func brightness(_ amount: Double) -> some VisualEffect {
        _ColorVisualEffect(base: self, kind: .brightness, amount: amount)
    }

    /// Sets the contrast and separation between similar colors in the view.
    ///
    /// - Parameter amount: The intensity of color contrast to apply. Negative
    ///   values invert colors in addition to applying contrast.
    /// - Returns: An effect that applies color contrast to the view.
    public func contrast(_ amount: Double) -> some VisualEffect {
        _ColorVisualEffect(base: self, kind: .contrast, amount: amount)
    }

    /// Adjusts the color saturation of the view.
    ///
    /// - Parameter amount: The amount of saturation to apply to the view.
    /// - Returns: An effect that adjusts the saturation of the view.
    public func saturation(_ amount: Double) -> some VisualEffect {
        _ColorVisualEffect(base: self, kind: .saturation, amount: amount)
    }

    /// Adds a grayscale effect to the view.
    ///
    /// - Parameter amount: The intensity of grayscale to apply from 0.0 to less
    ///   than 1.0. Values closer to 0.0 are more colorful, and values closer to
    ///   1.0 are less colorful.
    /// - Returns: An effect that reduces the intensity of colors in the view.
    public func grayscale(_ amount: Double) -> some VisualEffect {
        _ColorVisualEffect(base: self, kind: .grayscale, amount: amount)
    }

    /// Applies a hue rotation effect to the view.
    ///
    /// - Parameter angle: The hue rotation angle to apply to the colors in the
    ///   view.
    /// - Returns: An effect that shifts all of the colors in the view.
    public func hueRotation(_ angle: Angle) -> some VisualEffect {
        _ColorVisualEffect(base: self, kind: .hueRotation, amount: angle.degrees)
    }
}

/// An offset after `base`.
struct _OffsetEffect<Base: VisualEffect>: VisualEffect {
    var base: Base
    var x: Double
    var y: Double

    var animatableData: AnimatablePair<Base.AnimatableData, AnimatablePair<Double, Double>> {
        get { AnimatablePair(base.animatableData, AnimatablePair(x, y)) }
        set {
            base.animatableData = newValue.first
            (x, y) = (newValue.second.first, newValue.second.second)
        }
    }

    func _holdingMotion(at target: Self) -> Self {
        Self(base: base._holdingMotion(at: target.base), x: target.x, y: target.y)
    }

    func _applied(to buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        let inner = base._applied(to: buffer, context: context)
        let (columns, rows) = (Int(x.rounded()), Int(y.rounded()))
        guard columns != 0 || rows != 0 else { return inner }
        return drawEffect(
            BufferView(buffer: inner).offset(x: columns, y: rows), owner: Self.self, context: context)
    }
}

/// An opacity after `base`.
struct _OpacityEffect<Base: VisualEffect>: VisualEffect {
    var base: Base
    var opacity: Double

    var animatableData: AnimatablePair<Base.AnimatableData, Double> {
        get { AnimatablePair(base.animatableData, opacity) }
        set {
            base.animatableData = newValue.first
            opacity = newValue.second
        }
    }

    func _holdingMotion(at target: Self) -> Self {
        Self(base: base._holdingMotion(at: target.base), opacity: opacity)
    }

    func _applied(to buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        drawEffect(
            BufferView(buffer: base._applied(to: buffer, context: context)).opacity(opacity),
            owner: Self.self, context: context)
    }
}

/// One of the colour effects after `base`, by the arithmetic the `View`
/// modifiers of the same names use.
struct _ColorVisualEffect<Base: VisualEffect>: VisualEffect {
    /// The colour effects a visual effect offers: the `View` modifiers'
    /// arithmetic, less the two SwiftUI does not offer as effects.
    enum Kind: Sendable {
        case brightness, contrast, saturation, grayscale, hueRotation
    }

    var base: Base
    let kind: Kind
    /// The amount, or for a hue rotation its angle in degrees.
    var amount: Double

    var animatableData: AnimatablePair<Base.AnimatableData, Double> {
        get { AnimatablePair(base.animatableData, amount) }
        set {
            base.animatableData = newValue.first
            amount = newValue.second
        }
    }

    func _holdingMotion(at target: Self) -> Self {
        Self(base: base._holdingMotion(at: target.base), kind: kind, amount: amount)
    }

    func _applied(to buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        let inner = BufferView(buffer: base._applied(to: buffer, context: context))
        return switch kind {
        case .brightness: drawEffect(inner.brightness(amount), owner: Self.self, context: context)
        case .contrast: drawEffect(inner.contrast(amount), owner: Self.self, context: context)
        case .saturation: drawEffect(inner.saturation(amount), owner: Self.self, context: context)
        case .grayscale: drawEffect(inner.grayscale(amount), owner: Self.self, context: context)
        case .hueRotation:
            drawEffect(inner.hueRotation(.degrees(amount)), owner: Self.self, context: context)
        }
    }
}
