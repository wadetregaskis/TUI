//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShadowModifier.swift
//
//  `.shadow(color:radius:x:y:)`: a drop shadow in whole cells, composited
//  beneath the view's own cells and over what is behind it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

/// The modifier behind ``View/shadow(color:radius:x:y:)``: the view's drawing
/// with its shadow composited, beneath it for a drop shadow and over it for an
/// inner one (``ShadowStyle``).
///
/// Layout is untouched, as in SwiftUI: the view reports its own size, and a
/// drop shadow that reaches past it is drawn past it at the view's place in
/// the stacking order.
struct ShadowModifier: BufferModifier, Equatable {
    /// The shadow.
    var style: ShadowStyle

    /// Draws at this modifier's own type, which is the right animation owner
    /// only when nothing encloses it — a direct call, never the render path.
    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        _modify(buffer: buffer, context: context, owner: Self.self)
    }

    func _modify(buffer: FrameBuffer, context: RenderContext, owner: Any.Type) -> FrameBuffer {
        // A measure draws nothing that is kept, and a shadow changes no size.
        guard !context.isMeasuring else { return buffer }
        // The colour through the animator, so a change inside `withAnimation`
        // fades rather than jumping; the radius and the offset are substituted
        // before this runs (`animatableData`), under the same owner, so the
        // colour takes a slot of its own.
        var drawn = style
        drawn.color = ColorAnimation.resolving(
            style.color, owner: owner, slot: AnimationSlot.colour, context: context)
        switch style.kind {
        case .drop:
            return buffer.castingDropShadow(drawn, context: context, owner: owner)
        case .inner:
            return buffer.castingInnerShadow(drawn, palette: context.environment.palette)
        }
    }
}

/// Where the shadow's animations are kept in the animation store, under the
/// one key its view and owner make.
private enum AnimationSlot {
    /// The colour's. Slot `0` is the radius and the offset's: the store key's
    /// default, which `animatedValue` takes for every animatable modifier's
    /// data. Sharing it, each overwrote the other's record at every render, a
    /// value of another type, and neither ever animated.
    static let colour = 1
}

/// The radius and the offset move, in whole cells, so a change of either
/// inside ``withAnimation(_:_:)`` grows or slides the shadow rather than
/// jumping it, as SwiftUI's does.
///
/// The offset is motion and the radius is not: where motion is reduced a
/// change of the offset alone jumps to its end and starts nothing, as an
/// `.offset` beside it does, and a change of the radius still grows the
/// shadow, with the offset at its end meanwhile (owner decision A-D3M-1).
extension ShadowModifier: PartlySpatialAnimatable {
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(Double(style.radius), AnimatablePair(Double(style.x), Double(style.y))) }
        set {
            style.radius = max(0, Self.cells(newValue.first))
            style.x = Self.cells(newValue.second.first)
            style.y = Self.cells(newValue.second.second)
        }
    }

    /// This shadow with its offset at `target`'s and its radius as it is.
    func holdingMotion(at target: Self) -> Self {
        var held = self
        held.style.x = target.style.x
        held.style.y = target.style.y
        return held
    }

    /// This modifier where its animation has got to, its offset at its end
    /// where motion is reduced.
    @MainActor
    static func _animated(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        animatedValueHoldingMotion(of: modifier, owner: owner, context: context, isMeasuring: isMeasuring)
    }

    /// `value` rounded to whole cells, held to ±2^30 — past every screen, and
    /// inside `Int` — so a frame between two outlandish values cannot trap the
    /// conversion; NaN is no cells.
    private static func cells(_ value: Double) -> Int {
        let bound = Double(1 << 30)
        guard !value.isNaN else { return 0 }
        return Int(min(max(value.rounded(), -bound), bound))
    }
}

extension View {
    /// Adds a shadow to this view — mirrors SwiftUI's
    /// `shadow(color:radius:x:y:)`, in whole cells.
    ///
    /// The cells the view paints — its glyphs, and the cells it gives a field of
    /// its own — are moved `x` columns right and `y` rows down, and darken what
    /// they fall on by compositing `color` over it at the colour's alpha. Behind
    /// the view: where it paints a field of its own the shadow is hidden, and
    /// past its edges, and under the cells it leaves clear, what is behind is
    /// darkened and the view's own glyphs are drawn over that. `radius` softens
    /// the edge: the alpha falls off across that many cells beyond it, a step of
    /// `1 / (radius + 1)` a cell, so `0` is a hard shadow the shape of the view.
    ///
    /// ```swift
    /// Text("Saved")
    ///     .padding(1)
    ///     .background(.blue)
    ///     .shadow(radius: 1, x: 2, y: 1)
    /// ```
    ///
    /// **The units are cells.** A ported `.shadow(radius: 8)` is eight cells —
    /// as wide, across, as `.padding(8)` — where SwiftUI's is eight points, so
    /// a ported shadow is far larger and wants its numbers cut down; a radius of
    /// 1 or 2 with an offset of a cell or two reads as a shadow
    /// (`Deliberate deviations from SwiftUI.md`, C10).
    ///
    /// Layout is unaffected, as in SwiftUI: the view reports its own size, and
    /// the shadow past its edges is drawn there at the view's place in the
    /// stacking order — over the views before it and under the ones after it,
    /// which hide it where they paint. A container that clips, a `ScrollView`
    /// among them, cuts it at its edge, as SwiftUI's does.
    ///
    /// A shadow needs a backdrop with a colour to darken: over a page whose
    /// colour the terminal has not reported, a blend snaps to the heavier side
    /// (`Opacity as composition.md` §75), so a shadow lighter than half shows
    /// nothing there.
    ///
    /// - Parameters:
    ///   - color: The shadow's color: black at a third by default, as in
    ///     SwiftUI.
    ///   - radius: How many cells the shadow's alpha falls off across beyond its
    ///     edge. A radius of zero is a sharp shadow; one past 32 is drawn as 32,
    ///     since a shadow costs the square of its radius.
    ///   - x: How many columns right the shadow is drawn (negative: left).
    ///   - y: How many rows down the shadow is drawn (negative: up).
    /// - Returns: A view that adds a shadow to this view.
    public func shadow(
        color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: Int, x: Int = 0, y: Int = 0
    ) -> some View {
        modifier(ShadowModifier(style: .drop(color: color, radius: radius, x: x, y: y)))
    }
}
