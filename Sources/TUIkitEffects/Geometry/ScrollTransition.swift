//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTransition.swift
//
//  `scrollTransition`: a visual effect driven by where a view is in its scroll
//  view's visible region.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Applies the given transition, animating between the phases of the
    /// transition as this view appears and disappears within the visible
    /// region of the containing scroll view.
    ///
    /// ```swift
    /// ScrollView {
    ///     LazyVStack {
    ///         ForEach(items) { item in
    ///             Row(item)
    ///                 .scrollTransition { content, phase in
    ///                     content.opacity(phase.isIdentity ? 1 : 0.3)
    ///                 }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// The view is placed where its containers PREDICT it will be in the
    /// scroll view's viewport before it is drawn — exactly, for rows of a stack
    /// under a scroll view — and the scroll view checks that against where it
    /// drew the view, drawing its content once more when they differ (design
    /// study A2, the owner's answer 5). The effect never moves the view's
    /// place in the layout. Effects that need less than a cell (scale,
    /// rotation, blur) are not offered; see ``VisualEffect``.
    ///
    /// - Parameters:
    ///   - configuration: The configuration controlling how the transition
    ///     will be applied. The configuration will be applied both while the
    ///     view is coming into view and while it is disappearing (the
    ///     transition is symmetrical).
    ///   - axis: The axis of the containing scroll view over which the
    ///     transition will be applied. The default value of `nil` uses the
    ///     axis of the innermost containing scroll view, or `.vertical` if the
    ///     innermost scroll view is scrollable along both axes.
    ///   - transition: A closure that applies visual effects as a function of
    ///     the provided phase.
    /// - Returns: A view with the transition applied.
    public func scrollTransition<Effect: VisualEffect>(
        _ configuration: ScrollTransitionConfiguration = .interactive, axis: Axis? = nil,
        transition: @escaping @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect
    ) -> some View {
        _ScrollTransitionView(
            content: self, topLeading: configuration, bottomTrailing: configuration, axis: axis,
            transition: transition)
    }

    /// Applies the given transition, animating between the phases of the
    /// transition as this view appears and disappears within the visible
    /// region of the containing scroll view.
    ///
    /// - Parameters:
    ///   - topLeading: The configuration that drives the transition when the
    ///     view is about to appear at the top edge of a vertical scroll view,
    ///     or the leading edge of a horizontal scroll view.
    ///   - bottomTrailing: The configuration that drives the transition when
    ///     the view is about to appear at the bottom edge of a vertical scroll
    ///     view, or the trailing edge of a horizontal scroll view.
    ///   - axis: The axis of the containing scroll view over which the
    ///     transition will be applied. The default value of `nil` uses the
    ///     axis of the innermost containing scroll view, or `.vertical` if the
    ///     innermost scroll view is scrollable along both axes.
    ///   - transition: A closure that applies visual effects as a function of
    ///     the provided phase.
    /// - Returns: A view with the transition applied.
    public func scrollTransition<Effect: VisualEffect>(
        topLeading: ScrollTransitionConfiguration, bottomTrailing: ScrollTransitionConfiguration,
        axis: Axis? = nil,
        transition: @escaping @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect
    ) -> some View {
        _ScrollTransitionView(
            content: self, topLeading: topLeading, bottomTrailing: bottomTrailing, axis: axis,
            transition: transition)
    }
}

// MARK: - The View

/// Draws its content, then the effect its transition gives for where the
/// content is in the scroll view's viewport — see
/// ``View/scrollTransition(_:axis:transition:)``.
struct _ScrollTransitionView<Content: View, Effect: VisualEffect>: View {
    let content: Content
    let topLeading: ScrollTransitionConfiguration
    let bottomTrailing: ScrollTransitionConfiguration
    let axis: Axis?
    let transition: @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect

    var body: Never {
        fatalError("_ScrollTransitionView renders via Renderable")
    }
}

extension _ScrollTransitionView: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Claimed BEFORE the content renders, as every marker slot is (see
        // `ScrollVisibilityModifier`): content at this identity that stamps a
        // marker one frame and not the next would otherwise move this one's
        // id, and lose what was found for it. `nil` in a measure, which sizes
        // the view — no effect changes that — and must not claim the marker
        // the render will.
        let ask = context.makeGeometryAsk(role: .reader)
        let buffer = TUIkit.renderToBuffer(content, context: context)
        guard !context.isMeasuring else { return buffer }
        guard let ask else {
            // Nowhere to ask where the view is: the identity phase.
            return effect(at: nil, context: context)._applied(to: buffer, context: context)
        }
        // The view's place in the scroll view's viewport, and the viewport —
        // predicted, and held to by the scroll view (a reader, corrected when
        // wrong), so what is drawn is drawn from where the view really is.
        let space: NamedCoordinateSpace = axis.map { .scrollView(axis: $0) } ?? .scrollView
        let observation = ask.observation(in: space.coordinateSpace, needsSize: true)
        let place = observation.flatMap { found in
            found.spaceSize.map { viewport in
                ScrollTransitionPlace(
                    origin: found.origin, size: buffer.cellSize, viewport: viewport,
                    axis: axis ?? found.scrollAxis ?? .vertical)
            }
        }
        var drawn = effect(at: place, context: context)._applied(to: buffer, context: context)
        // Stamped on the drawing's own frame, which the effect never moves: an
        // offset floats the content, and the view's place in the layout is
        // where it was before.
        ask.finishRecording(size: buffer.cellSize)
        if context.geometryCoordinator?.register(ask) == true {
            drawn.hitTestRegions.append(.geometryMarker(ask.id))
        }
        return drawn
    }

    /// The effect for a view at `place`: the identity phase's where there is
    /// no scroll view's viewport to be in.
    private func effect(at place: ScrollTransitionPlace?, context: RenderContext) -> Effect {
        guard let place else { return transition(EmptyVisualEffect(), .identity) }
        let (edge, depth) = place.approach
        let configuration = edge == .topLeading ? topLeading : bottomTrailing
        let progress = place.progress(depth: depth, threshold: configuration.visibleThreshold)
        var effect: Effect
        switch configuration.kind {
        case .identity:
            effect = transition(EmptyVisualEffect(), .identity)
        case .animated:
            effect = transition(EmptyVisualEffect(), progress >= 1 ? .identity : edge)
        case .interactive(let curve):
            // The two phases' effects, and the point between them the view has
            // reached, paced by the curve: SwiftUI interpolates the effect, not
            // the phase, which only ever has its three values.
            let identity = transition(EmptyVisualEffect(), .identity)
            effect = transition(EmptyVisualEffect(), edge)
            var data = effect.animatableData
            data.interpolate(towards: identity.animatableData, amount: curve.value(at: progress))
            effect.animatableData = data
        }
        // Moved there by the configuration's animation, when it has one — and
        // otherwise drawn where the scroll put it, whatever transaction the
        // scroll came in. As a `visualEffect`'s is: under reduce motion its
        // offsets jump to the phase's and its opacity and colours still
        // animate (owner decision A-D3M-1).
        var animating = context
        animating.environment.transaction.animation = configuration.transitionAnimation
        return animatedEffect(effect, owner: Self.self, context: animating, isMeasuring: context.isMeasuring)
    }

    /// Effects do not change layout: this measures as its content.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Where the View Is

/// A view's place in its scroll view's viewport, along the transition's axis.
struct ScrollTransitionPlace {
    /// Where the view's top-left is in the viewport.
    let origin: CellPoint
    /// The view's size.
    let size: CellSize
    /// The viewport's size.
    let viewport: CellSize
    /// The axis the transition follows.
    let axis: Axis

    /// Which edge the view is nearer — the one it is coming in at or going out
    /// by — and how far it has come in past it: `0` just outside, its own
    /// length just wholly inside.
    var approach: (edge: ScrollTransitionPhase, depth: Double) {
        let (start, length, container) =
            axis == .vertical
            ? (origin.y, size.height, viewport.height)
            : (origin.x, size.width, viewport.width)
        // Nearer the top (leading) edge when its middle is above the
        // viewport's: twice both sides, so nothing is floored.
        if 2 * start + length < container {
            return (.topLeading, Double(start + length))
        }
        return (.bottomTrailing, Double(container - start))
    }

    /// How far from hidden (`0`) to the threshold (`1`) a view `depth` in has
    /// come.
    func progress(depth: Double, threshold: ScrollTransitionConfiguration.Threshold) -> Double {
        let (length, container) =
            axis == .vertical
            ? (Double(size.height), Double(viewport.height))
            : (Double(size.width), Double(viewport.width))
        let target = threshold.point.depth(length: length, container: container)
        guard target > 0 else { return depth > 0 ? 1 : 0 }
        return min(1, max(0, depth / target))
    }
}
