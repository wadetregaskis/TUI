//  🖥️ TUI — A Terminal UI framework for Swift
//  TextRenderer.swift
//
//  SwiftUI's `TextRenderer`, `TextProxy` and `View.textRenderer(_:)`: a value
//  that draws the texts beneath it from their layout (lines, runs, glyphs)
//  into a `GraphicsContext` — the extensible text effects the owner asked
//  for (TEXT-EFFECTS, 2026-10-28; `TextRenderer design study, O16`).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import TUICore
import TUIView

/// A value that can replace the default text view rendering behavior —
/// mirrors SwiftUI's `TextRenderer`.
///
/// ```swift
/// struct Wave: TextRenderer {
///     var time: Double
///     var animatableData: Double {
///         get { time }
///         set { time = newValue }
///     }
///
///     func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
///         for line in layout {
///             for run in line {
///                 for (index, glyph) in run.enumerated() {
///                     var copy = ctx
///                     copy.translateBy(x: 0, y: -sin(Double(index) * 0.6 - time).rounded())
///                     copy.draw(glyph)
///                 }
///             }
///         }
///     }
/// }
///
/// Text("Hello, world").textRenderer(Wave(time: t))
/// ```
///
/// Positions are in cells, and a glyph lands on whole cells (see
/// ``GraphicsContext``). A renderer that draws outside the text's frame —
/// a wave lifting glyphs a row — draws over the views around it, as
/// SwiftUI's does: the text floats over its neighbours, as `.offset(x:y:)`
/// draws a view away from its place.
public protocol TextRenderer: Animatable {
    /// Draws `layout` into `ctx`.
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext)

    /// The size of the text in `proposal`. The default is the text's own.
    func sizeThatFits(proposal: ProposedSize, text: TextProxy) -> ViewSize

    /// How far past the text's frame the renderer draws, on each edge. The
    /// default is none. A cell has no rasterizing layer for padding to size:
    /// what is drawn past the frame is drawn wherever it lands.
    var displayPadding: EdgeInsets { get }
}

extension TextRenderer {
    /// The text's own size: what it lays itself out at.
    public func sizeThatFits(proposal: ProposedSize, text: TextProxy) -> ViewSize {
        text.sizeThatFits(proposal)
    }

    /// None: the renderer draws within the text's frame.
    public var displayPadding: EdgeInsets { EdgeInsets() }
}

/// A proxy for a text view that custom text renderers use — mirrors
/// SwiftUI's `TextProxy`.
public struct TextProxy {
    let measure: (ProposedSize) -> ViewSize

    /// The space the text needs for `proposal`, as it lays itself out.
    public func sizeThatFits(_ proposal: ProposedSize) -> ViewSize {
        measure(proposal)
    }
}

extension View {
    /// Draws every text view within this one with `renderer` — mirrors
    /// SwiftUI's `textRenderer(_:)`. A nearer one replaces it.
    ///
    /// - Parameter renderer: What draws the texts.
    /// - Returns: A view whose texts `renderer` draws.
    public func textRenderer<T: TextRenderer>(_ renderer: T) -> some View {
        environment(\.textRenderer, AnyTextRenderer(renderer))
    }
}

// MARK: - The environment

/// A text renderer in the environment, compared by value where its type is
/// `Equatable` (so a subtree under an unchanging renderer can be served from
/// the render memo), and unequal otherwise.
///
/// `@unchecked Sendable`: a `TextRenderer` need not be `Sendable`, as
/// SwiftUI's need not; it is read and drawn with on the main actor only.
package struct AnyTextRenderer: Equatable, @unchecked Sendable {
    let renderer: any TextRenderer
    private let isEqual: (any TextRenderer) -> Bool

    init<T: TextRenderer>(_ renderer: T) {
        self.renderer = renderer
        isEqual = { other in
            guard let other = other as? T else { return false }
            return Self.equal(renderer, other)
        }
    }

    package static func == (lhs: Self, rhs: Self) -> Bool { lhs.isEqual(rhs.renderer) }

    /// `a == b` where `T` is `Equatable`, else `false`.
    private static func equal<T>(_ a: T, _ b: T) -> Bool {
        guard let a = a as? any Equatable else { return false }
        return a.isEqual(to: b)
    }
}

extension Equatable {
    /// Whether `other` is this type's and equal to this.
    fileprivate func isEqual(to other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

private struct TextRendererKey: EnvironmentKey {
    static let defaultValue: AnyTextRenderer? = nil
}

extension EnvironmentValues {
    /// The renderer the texts beneath draw with (``View/textRenderer(_:)``),
    /// or `nil` for their own drawing.
    package var textRenderer: AnyTextRenderer? {
        get { self[TextRendererKey.self] }
        set { self[TextRendererKey.self] = newValue }
    }
}

// MARK: - Drawing a text with one

extension Text {
    /// The size this text needs: a text renderer in force says it, asking the
    /// text's own through its proxy unless it knows better; with none, one
    /// environment read and the text's own (``ownSize(proposal:context:)``).
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let renderer = context.environment.textRenderer?.renderer else {
            return ownSize(proposal: proposal, context: context)
        }
        return renderer.sizeThatFits(
            proposal: proposal, text: TextProxy { self.ownSize(proposal: $0, context: context) })
    }

    /// `drawn`, this text's own drawing, redrawn by the renderer in force, or
    /// itself where there is none — one environment read for every text that
    /// has none.
    func renderedThroughRenderer(_ drawn: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard let renderer = context.environment.textRenderer?.renderer, !context.isMeasuring else { return drawn }
        return redrawn(drawn, by: renderer, context: context)
    }

    /// `drawn` redrawn by `renderer`, animated toward it where its value
    /// changed under an animation, as an animatable modifier's is.
    private func redrawn<R: TextRenderer>(_ drawn: FrameBuffer, by renderer: R, context: RenderContext) -> FrameBuffer {
        let shown = animatedValue(of: renderer, owner: R.self, context: context, isMeasuring: false) ?? renderer
        let layout = layout(of: drawn, context: context)
        let canvas = GraphicsContext.Canvas(width: drawn.width, height: drawn.height)
        var graphics = GraphicsContext(canvas: canvas)
        shown.draw(layout: layout, in: &graphics)
        let extent = canvas.extent(including: drawn.width, drawn.height)
        var redrawn = canvas.buffer(covering: extent)
        // Links and other regions stay where the words were laid out.
        redrawn.hitTestRegions = drawn.hitTestRegions.map { region in
            var region = region
            region.offsetX -= extent.minX
            region.offsetY -= extent.minY
            return region
        }
        guard extent.minX != 0 || extent.minY != 0 || extent.maxX != drawn.width || extent.maxY != drawn.height
        else { return redrawn }
        // Drawn past the frame: the text floats over its neighbours, laid
        // out where it was, as `.offset` draws a view away from its place.
        return redrawn.drawnDisplaced(
            by: (x: extent.minX, y: extent.minY), footprintWidth: drawn.width, footprintHeight: drawn.height)
    }
}
