//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentShapeModifier.swift
//
//  A shape as a view's hit area, and as the preview a drag of it carries:
//  `contentShape(_:eoFill:)` and `contentShape(_:_:eoFill:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIkitCore
import TUIkitView

extension View {
    /// Defines the content shape for hit testing.
    ///
    /// The shape fills the view's frame, and the view takes the pointer only
    /// on the cells the shape covers at least half of — the ½ rule a clip
    /// keeps a cell by (``View/clipShape(_:style:)``). A click, a hover, a
    /// context menu or a drag of the view, whether its own controls' or a
    /// gesture's around it, answers only there; a click elsewhere in the frame
    /// reaches what is behind the view.
    ///
    /// ```swift
    /// Text("●")
    ///     .frame(width: 9, height: 5)
    ///     .contentShape(Circle())
    ///     .onTapGesture { toggle() }
    /// ```
    ///
    /// A ``Rectangle`` keeps the whole frame, which is what a view's hit area
    /// already is here — a click on a spacer or a padding inside a tappable
    /// stack reaches it — so the common `.contentShape(Rectangle())` changes
    /// nothing, as it changes no pixel on macOS (refusal review P3).
    ///
    /// A shape reaches the modifiers whose frame is its own: `.contentShape`
    /// then `.onTapGesture`, or a `Button` whose label it shapes; a
    /// `.padding()` between the two gives the gesture a frame the shape does
    /// not cover, and the gesture its whole frame.
    ///
    /// - Parameters:
    ///   - shape: The hit testing shape for the view.
    ///   - eoFill: Whether the shape is read with the even-odd rule.
    /// - Returns: A view that uses the given shape for hit testing.
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        _ContentShapeView(content: self, kinds: .interaction, shape: shape, eoFill: eoFill)
    }

    /// Sets the content shape for this view, for the kinds named.
    ///
    /// ``ContentShapeKinds/interaction`` is the hit area, as
    /// ``View/contentShape(_:eoFill:)`` sets it.
    /// ``ContentShapeKinds/dragPreview`` cuts the preview a `.draggable` view
    /// carries to the shape — a cell kept where the shape covers half of it —
    /// and leaves where a drag can start alone.
    ///
    /// ```swift
    /// Text(card.title)
    ///     .padding(1)
    ///     .background(.blue, in: RoundedRectangle(cornerRadius: 2))
    ///     .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 2))
    ///     .draggable(card.title)
    /// ```
    ///
    /// - Parameters:
    ///   - kind: The kinds to apply to this content shape.
    ///   - shape: The shape to use.
    ///   - eoFill: Whether the shape is read with the even-odd rule.
    /// - Returns: A view that uses the given shape for the specified kinds.
    public func contentShape<S: Shape>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View {
        _ContentShapeView(content: self, kinds: kind, shape: shape, eoFill: eoFill)
    }
}

/// ``View/contentShape(_:eoFill:)``'s view: its content drawn as it is, with
/// the cells the shape keeps written into the buffer for the modifiers around
/// it, and the content's own hit regions cut to them.
///
/// The cells are carried as geometry markers (`ContentShapeMarkers.swift`), so
/// a buffer served from a memo carries them as it was drawn, and nothing about
/// a view with no content shape changes: the modifiers that register a region
/// over a view's frame ask for its cut (`FrameBuffer.frameHitRegions`), which
/// is the whole frame where there is none.
struct _ContentShapeView<Content: View, S: Shape>: View {
    let content: Content
    let kinds: ContentShapeKinds
    let shape: S
    let eoFill: Bool

    var body: Never { fatalError("_ContentShapeView renders via Renderable") }
}

extension _ContentShapeView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkitView.renderToBuffer(content, context: context)
        let (columns, rows) = (buffer.width, buffer.height)
        guard columns > 0, rows > 0, !kinds.isDisjoint(with: [.interaction, .dragPreview]) else { return buffer }
        let drawn = resolvedShape(shape, in: context, columns: columns, rows: rows)
        // A rectangle keeps the frame, which is what every hit area and every
        // drag preview already is.
        if let rectangle = drawn as? Rectangle, rectangle.insetAmount == 0 { return buffer }
        let kept = FrameBuffer.cellsKept(
            by: drawn, columns: columns, rows: rows, aspect: context.environment.imageCellAspect, evenOdd: eoFill)
        var markers: [HitTestRegion] = []
        if kinds.contains(.interaction) {
            buffer.hitTestRegions = buffer.hitTestRegions.flatMap { $0.cut(to: kept) }
            markers += HitTestRegion.contentShapeMarkers(.interaction, keeping: kept, width: columns, height: rows)
        }
        if kinds.contains(.dragPreview) {
            markers += HitTestRegion.contentShapeMarkers(.dragPreview, keeping: kept, width: columns, height: rows)
        }
        // In front, so a modifier around this one finds this shape before any
        // its content carries.
        buffer.hitTestRegions.insert(contentsOf: markers, at: 0)
        return buffer
    }
}

extension _ContentShapeView: Layoutable {
    /// A content shape changes what takes the pointer, never the frame.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
