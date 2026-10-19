//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PositionModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Places this view's centre at a point in its parent's coordinate space.
    ///
    /// The absolute counterpart of ``offset(x:y:)``, and it differs from it in
    /// layout as well as in arithmetic: an offset keeps the view's natural
    /// place and displaces the drawing, while a positioned view **takes the
    /// space it is offered** and draws itself at the point given. That is
    /// SwiftUI's rule too, and it is what makes `.position` the thing to reach
    /// for inside a `ZStack` or a `GeometryReader` and `.offset` the thing to
    /// nudge with.
    ///
    /// ```swift
    /// GeometryReader { proxy in
    ///     Text("×").position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    /// }
    /// ```
    ///
    /// The centre of an even-sized view falls between cells; it rounds down, so
    /// a two-cell-wide view centred at column 10 occupies columns 9 and 10.
    ///
    /// - Parameters:
    ///   - x: The column its centre sits on.
    ///   - y: The row its centre sits on.
    /// - Returns: A view drawn at that position, filling the space offered.
    public func position(x: Int = 0, y: Int = 0) -> some View {
        PositionView(content: self, x: x, y: y)
    }

    /// Places this view's centre at `position` — the same modifier as
    /// ``position(x:y:)``, spelled the way SwiftUI spells it when the point is
    /// already a value.
    ///
    /// - Parameter position: Where its centre sits.
    /// - Returns: A view drawn at that position, filling the space offered.
    public func position(_ position: CellSize) -> some View {
        self.position(x: position.width, y: position.height)
    }
}

/// Draws its content centred on a point, and fills the space it was offered.
/// See ``View/position(x:y:)``.
public struct PositionView<Content: View>: View {
    let content: Content
    var x: Int
    var y: Int

    public var body: Never {
        fatalError("PositionView renders via Renderable")
    }
}

extension PositionView: Animatable {
    /// The point is what moves, so a change to it inside
    /// ``withAnimation(_:_:)`` glides rather than jumps — except where
    /// ``EnvironmentValues/accessibilityReduceMotion`` is on, where it jumps:
    /// a position is motion.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(Double(x), Double(y)) }
        set {
            x = Int(newValue.first.rounded())
            y = Int(newValue.second.rounded())
        }
    }
}

/// Motion: under reduce motion an animated change of position jumps to its
/// end (owner decision A-D3M-1).
extension PositionView: SpatialAnimatable {}

extension PositionView: Renderable, Layoutable {
    /// Fills what it is offered: a positioned view's own size says nothing
    /// about where it sits, and its parent must reserve the whole space for
    /// the coordinates to mean anything.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(
            width: proposal.width ?? context.availableWidth,
            height: proposal.height ?? context.availableHeight,
            isWidthFlexible: true, isHeightFlexible: true)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let rendered = TUIkitView.renderToBuffer(content, context: placedContent(context))
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        guard !context.isMeasuring else { return rendered }

        // Drawn as `.offset` draws: only the cells the content paints, at
        // this view's place in the stacking order, not a full-size blank field
        // (a terminal has no transparency, so one would erase whatever is
        // beneath). The footprint — rows that exist and a declared width,
        // both load-bearing — is this view's whole space.
        return rendered.drawnDisplaced(
            by: (x: x - rendered.width / 2, y: y - rendered.height / 2), footprintWidth: width,
            footprintHeight: height)
    }
}

extension PositionView {
    /// `context` with the content's carried geometry origin moved to where
    /// its centre lands on the position — from its MEASURED size, worked out
    /// only when an origin is carried. The ramp a gradient spans stays put, as
    /// for `.offset`.
    func placedContent(_ context: RenderContext) -> RenderContext {
        guard context.carriesGeometryOrigin, !context.isMeasuring else { return context }
        let size = measureChild(
            content, proposal: ProposedSize(width: context.availableWidth, height: context.availableHeight),
            context: context)
        return context.placingChild(gradient: nil, x: x - size.width / 2, y: y - size.height / 2)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension PositionView: SingleContentWrapper {
    public var wrappedContent: Content { content }

    /// A positioned view fills what it is offered and places its content in
    /// it, so a priority written inside it is not its own: a layout
    /// modifier, as a frame and padding are.
    public static var _providesLayoutValues: Bool { false }
}
