//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaintAnimation.swift
//
//  Fading a whole paint — a colour, or a ramp — that changed inside
//  `withAnimation`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

/// Moves a ``Paint`` that changed inside ``withAnimation(_:_:)`` toward its new
/// value instead of jumping to it.
///
/// ## What a ramp animates as
///
/// Not as one value. A gradient is a handful of independent quantities — each
/// stop's colour, each stop's position, and the geometry's four numbers — and
/// each of them animates **on its own store entry**, exactly as a colour does.
///
/// That is the whole design, and everything else falls out of it:
///
/// - **A ramp of a different length still works.** Growing a two-stop ramp into
///   a five-stop one animates the two that were already there and shows the
///   three that were not at their final colours, because the store's rule for a
///   value it has never seen is that an appearance is not a change. There is no
///   "how does a two-stop ramp become a five-stop one" to answer, which was the
///   question that kept this unbuilt.
/// - **Semantic colours work**, because ``ColorAnimation`` already resolves
///   them against the palette at the moment it is asked.
/// - **A stop that slides, slides.** A location is a `Double`, and the store is
///   generic over `VectorArithmetic`.
///
/// ## What snaps, and why
///
/// A change of KIND — a colour becoming a ramp, a linear ramp becoming a radial
/// one — snaps. The two ends have nothing in common to interpolate: the four
/// numbers a linear geometry carries are two points, and the four a radial one
/// carries are a centre and two radii, so moving between them would interpolate
/// a radius toward an ordinate. Each geometry gets its own slot range, so the
/// store sees a change of kind as a value it has never seen, and shows it.
///
/// The extent named by ``ShapeStyle/in(_:)`` snaps too: it is a statement about
/// what the ramp is measured against rather than about the ramp.
enum PaintAnimation {
    /// The paint to draw for `target` this frame.
    ///
    /// - Parameters:
    ///   - target: What the view tree says the paint is now.
    ///   - owner: The type that paints with it — the discriminator the
    ///     animation store uses everywhere, so two painting modifiers at one
    ///     identity do not collide.
    ///   - context: The render context.
    /// - Returns: `target` unchanged when nothing is moving, otherwise the
    ///   paint partway between where it was and where it is going.
    @MainActor
    static func resolving(_ target: Paint, owner: Any.Type, context: RenderContext) -> Paint {
        switch target {
        case .color(let colour):
            return .color(ColorAnimation.resolving(colour, owner: owner, context: context))
        case .gradient(let ramped):
            return .gradient(resolving(ramped, owner: owner, context: context))
        case .mesh(let mesh):
            return .mesh(resolving(mesh, owner: owner, context: context))
        case .shadowed(let base, let shadow):
            // What is drawn moves; the shadow is the one asked for now, so a
            // shadow changed inside `withAnimation` jumps (decisions W1B,
            // B-W1B-1). The base keeps the slots it has unshadowed, so adding
            // or removing a shadow does not restart a colour's fade.
            return .shadowed(resolving(base, owner: owner, context: context), shadow)
        case .blended(let base, let mode):
            // A mode does not move between two: what is drawn does.
            return .blended(resolving(base, owner: owner, context: context), mode)
        case .frosted(let base):
            // A frost does not move between two: what is drawn does.
            return .frosted(resolving(base, owner: owner, context: context))
        case .image:
            // A picture does not move between two: a new one shows at once.
            return target
        }
    }

    /// A mesh with every vertex — its colour, its position and any control
    /// points it states — and its background moved to where they are this frame.
    ///
    /// As SwiftUI moves one, measured on macOS 15.8: a mesh whose middle column
    /// moved inside `withAnimation(.linear(duration: 2))` drew it at 50, 82,
    /// 118 and 150 of 200 points at each 0.4 s, and its colours stepped exactly
    /// as a `LinearGradient`'s stops did beside it. The `points:` form's implied
    /// control points are not animated: they follow the moving vertices, worked
    /// out afresh each frame, which is what a mesh that only states positions
    /// means.
    ///
    /// A mesh of another shape — another width or height, or the other form of
    /// locations — snaps, its slots being others (``Slot/mesh(_:)``).
    @MainActor
    private static func resolving(_ target: MeshPaint, owner: Any.Type, context: RenderContext) -> MeshPaint {
        var moved = target
        let base = Slot.mesh(target)
        @MainActor
        func scalar(_ value: Float, vertex: Int, component: Int) -> Float {
            let drawn = Self.scalar(
                Double(value), owner: owner, slot: base - vertex * Slot.perVertex - 1 - component, context: context)
            return Float(drawn)
        }
        @MainActor
        func point(_ value: SIMD2<Float>, vertex: Int, _ which: Int) -> SIMD2<Float> {
            SIMD2(
                scalar(value.x, vertex: vertex, component: 2 * which),
                scalar(value.y, vertex: vertex, component: 2 * which + 1))
        }
        moved.colors = target.colors.enumerated().map { vertex, colour in
            ColorAnimation.resolving(colour, owner: owner, slot: base - vertex * Slot.perVertex, context: context)
        }
        moved.background = ColorAnimation.resolving(target.background, owner: owner, slot: base + 1, context: context)
        switch target.locations {
        case .points(let points):
            moved.locations = .points(points.enumerated().map { point($1, vertex: $0, 0) })
        case .bezierPoints(let points):
            moved.locations = .bezierPoints(
                points.enumerated().map { vertex, bezier in
                    MeshGradient.BezierPoint(
                        position: point(bezier.position, vertex: vertex, 0),
                        leadingControlPoint: point(bezier.leadingControlPoint, vertex: vertex, 1),
                        topControlPoint: point(bezier.topControlPoint, vertex: vertex, 2),
                        trailingControlPoint: point(bezier.trailingControlPoint, vertex: vertex, 3),
                        bottomControlPoint: point(bezier.bottomControlPoint, vertex: vertex, 4))
                })
        }
        return moved
    }

    /// A ramp with every stop — and the geometry — moved to where it is this
    /// frame.
    @MainActor
    private static func resolving(
        _ target: GradientPaint, owner: Any.Type, context: RenderContext
    ) -> GradientPaint {
        var moved = target
        // The STOPS are replaced, not the gradient: rebuilding it with
        // `Gradient(stops:)` would drop everything else the ramp carries — the
        // colour space, today — so a perceptual ramp would blend in `.device`
        // for the length of the animation and snap back at the end.
        moved.gradient.stops = target.gradient.stops.enumerated().map { index, stop in
            Gradient.Stop(
                color: ColorAnimation.resolving(
                    stop.color, owner: owner, slot: Slot.stopColour(index), context: context),
                location: scalar(
                    stop.location, owner: owner, slot: Slot.stopLocation(index),
                    context: context))
        }
        moved.geometry = resolving(target.geometry, owner: owner, context: context)
        return moved
    }

    /// The geometry's four numbers, moved.
    ///
    /// Every case carries exactly four, which is a coincidence worth NOT
    /// relying on: each gets its own slot range so a case that replaces another
    /// starts afresh rather than interpolating a radius toward an ordinate.
    @MainActor
    private static func resolving(
        _ target: GradientGeometry, owner: Any.Type, context: RenderContext
    ) -> GradientGeometry {
        @MainActor
        func moved(_ value: Double, _ kind: Int, _ component: Int) -> Double {
            scalar(value, owner: owner, slot: Slot.geometry(kind, component), context: context)
        }
        switch target {
        case .linear(let from, let to):
            return .linear(
                from: UnitPoint(x: moved(from.x, 0, 0), y: moved(from.y, 0, 1)),
                to: UnitPoint(x: moved(to.x, 0, 2), y: moved(to.y, 0, 3)))
        case .radial(let centre, let startRadius, let endRadius):
            return .radial(
                center: UnitPoint(x: moved(centre.x, 1, 0), y: moved(centre.y, 1, 1)),
                // Rounded back, because a radius here is a count of cells.
                startRadius: Int(moved(Double(startRadius), 1, 2).rounded()),
                endRadius: Int(moved(Double(endRadius), 1, 3).rounded()))
        case .elliptical(let centre, let startFraction, let endFraction):
            return .elliptical(
                center: UnitPoint(x: moved(centre.x, 2, 0), y: moved(centre.y, 2, 1)),
                startRadiusFraction: moved(startFraction, 2, 2),
                endRadiusFraction: moved(endFraction, 2, 3))
        case .angular(let centre, let startAngle, let endAngle):
            return .angular(
                center: UnitPoint(x: moved(centre.x, 3, 0), y: moved(centre.y, 3, 1)),
                startAngle: .radians(moved(startAngle.radians, 3, 2)),
                endAngle: .radians(moved(endAngle.radians, 3, 3)))
        }
    }

    /// One number, moved — the store lookup ``ColorAnimation`` makes for a
    /// colour, made for a scalar.
    @MainActor
    private static func scalar(
        _ target: Double, owner: Any.Type, slot: Int, context: RenderContext
    ) -> Double {
        guard let storage = context.stateStorage else { return target }
        let drawn = storage.animations.value(
            for: AnimationStore.Key(
                identity: context.identity, owner: ObjectIdentifier(owner), slot: slot),
            target: target,
            animation: context.environment.canAnimate
                ? context.environment.transaction.effectiveAnimation : nil,
            nowNanos: context.environment.frameNowNanos,
            isMeasuring: context.isMeasuring)
        guard drawn != target else { return target }
        // The picture is now a function of time, so a value memo must not cache
        // this subtree — it would freeze the movement on its first frame.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        return drawn
    }

    /// Where each of a ramp's quantities lives in the store's slot space.
    ///
    /// Slot 0 is left to ``ColorAnimation``'s flat colour, so a paint that
    /// changes from a colour to a ramp snaps whole rather than half-fading its
    /// first stop out of the colour that was there.
    private enum Slot {
        static func stopColour(_ index: Int) -> Int { 1 + 2 * index }
        static func stopLocation(_ index: Int) -> Int { 2 + 2 * index }
        /// Negative, so no number of stops can reach it.
        static func geometry(_ kind: Int, _ component: Int) -> Int { -1 - (kind * 4 + component) }

        /// A mesh vertex's slots: its colour, then two numbers for its position
        /// and two for each of the four control points the `bezierPoints:` form
        /// states.
        static let perVertex = 11

        /// Where a mesh's slots start, counting DOWN from it by vertex, with the
        /// background one above. Far below the geometries', and different for
        /// every shape of mesh — width, height and form, each taken modulo 64 —
        /// so a mesh that changes shape starts afresh rather than moving vertex
        /// 4 of a 3 × 3 grid toward vertex 4 of a 2 × 4 one. A shape 64 vertices
        /// wider or taller shares slots, and a mesh past 95,000 vertices runs
        /// into the next shape's; both are far from anything drawn in a
        /// terminal, and the worst they do is start a move from the wrong place.
        static func mesh(_ paint: MeshPaint) -> Int {
            let form = if case .bezierPoints = paint.locations { 1 } else { 0 }
            let shape = (form * 64 + (paint.width & 63)) * 64 + (paint.height & 63)
            return -(1 << 40) - shape * (1 << 20)
        }
    }
}
