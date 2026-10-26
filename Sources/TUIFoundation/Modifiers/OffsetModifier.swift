//  🖥️ TUI — A Terminal UI framework for Swift
//  OffsetModifier.swift
//
//  `.offset(x:y:)` — draw a view displaced from its natural position,
//  floating over its siblings, modelled on SwiftUI's `offset`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The view wrapper created by ``View/offset(x:y:)``.
///
/// The content is measured at its natural place (layout is unaffected, as in
/// SwiftUI) but DRAWN `x` columns right and `y` rows down of it, floating
/// over whatever it lands on. Terminal-forced deviations from SwiftUI,
/// documented on the modifier: the vacated cells show the layer beneath
/// (there is no transparency, so nothing is painted there), and the
/// displaced content composites above its siblings.
public struct OffsetView<Content: View>: View {
    let content: Content
    var x: Int
    var y: Int

    public var body: Never {
        fatalError("OffsetView renders via Renderable")
    }
}

extension OffsetView: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Layout keeps the content's natural size — the offset displaces
        // only the drawing (SwiftUI semantics).
        measureChild(content, proposal: proposal, context: context)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The content is drawn displaced, and the carried geometry origin is
        // moved with it: a view under an offset is where it is drawn (as in
        // SwiftUI, whose offset moves a view's frame in every space). The ramp
        // a gradient spans stays where the layout put it.
        let rendered = TUIView.renderToBuffer(
            content, context: context.isMeasuring ? context : context.placingChild(gradient: nil, x: x, y: y))
        // An offset of nothing draws the view where it is, in its place among
        // its siblings: floated, it was drawn over every one of them —
        // whatever their order and z-index — for a displacement of no cells,
        // which an offset that animates back home always ends on.
        guard !context.isMeasuring, x != 0 || y != 0 else { return rendered }
        return rendered.drawnDisplaced(by: (x: x, y: y))
    }
}

extension View {
    /// Offsets this view's DRAWN position by `x` columns and `y` rows,
    /// leaving layout untouched — the view still occupies its natural place
    /// for sizing, but paints displaced, at its own place in the stacking
    /// order, as SwiftUI's does: over the views before it, under the views
    /// after it, clicked where it is drawn. Geometry read inside it is where
    /// it is drawn, as SwiftUI's offset moves a view's frame in every space.
    ///
    /// The vacated cells show whatever is beneath them: nothing is painted at
    /// the natural position, and only the cells the view paints are drawn
    /// where it lands (the blanks at either end of each line are left out), a
    /// terminal cell having no transparency. A scroll view, a `List`, a
    /// `Table`'s cell, a surface (a menu, a sheet) and `.clipped()` cut it at
    /// their box, as they cut any view drawn past its region. An offset of
    /// zero displaces nothing.
    ///
    /// - Parameters:
    ///   - x: Columns to shift right (negative shifts left).
    ///   - y: Rows to shift down (negative shifts up).
    /// - Returns: A view drawn at the offset position.
    public func offset(x: Int = 0, y: Int = 0) -> some View {
        OffsetView(content: self, x: x, y: y)
    }

    /// Offsets this view's drawn position by a size — SwiftUI's
    /// `offset(_ offset: CGSize)`, in whole cells.
    ///
    /// The same modifier as ``offset(x:y:)``, spelled the way SwiftUI spells it
    /// when the displacement is already a value rather than two numbers. A size
    /// used as a displacement is SwiftUI's own idiom, not this framework's
    /// invention; ``CellSize`` is the counterpart of the `CGSize` it takes,
    /// because a terminal counts cells where SwiftUI counts points.
    ///
    /// - Parameter offset: Columns to shift right in `width`, rows to shift
    ///   down in `height` (negative shifts the other way).
    /// - Returns: A view drawn at the offset position.
    public func offset(_ offset: CellSize) -> some View {
        self.offset(x: offset.width, y: offset.height)
    }
}

// MARK: - Animating the offset

extension OffsetView: Animatable {
    /// The displacement is what moves, so a change to it inside
    /// ``withAnimation(_:_:)`` slides rather than jumps — except where
    /// ``EnvironmentValues/accessibilityReduceMotion`` is on, where it jumps:
    /// an offset is motion.
    ///
    /// The cheapest kind of animated geometry here: an offset does not change
    /// layout — the view keeps its natural place for sizing — so a frame of
    /// this animation re-renders the subtree but re-measures nothing.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(Double(x), Double(y)) }
        set {
            x = Int(newValue.first.rounded())
            y = Int(newValue.second.rounded())
        }
    }
}

/// Motion: under reduce motion an animated change of offset jumps to its end
/// (owner decision A-D3M-1).
extension OffsetView: SpatialAnimatable {}

// MARK: - Seeing Through the Wrapper

/// - Note: Layout is unaffected either way (the content is measured at its
///   natural place), so shifting each member by `(x, y)` puts the same cells
///   in the same places as shifting the pair by `(x, y)`.
extension OffsetView: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<V: View>(_ view: V) -> any View {
        OffsetView<V>(content: view, x: x, y: y)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension OffsetView: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension OffsetView: GridRowProviding where Content: GridRowProviding {}
