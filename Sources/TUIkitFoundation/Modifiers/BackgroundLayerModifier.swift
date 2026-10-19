//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BackgroundLayerModifier.swift
//
//  `background(alignment:content:)`: views layered behind a view, in its
//  frame — `.overlay`'s mirror.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Layers a view behind the base content, laid out in the base's frame.
///
/// The base dominates layout exactly as under `.overlay`: the background is
/// offered the size the base came back at, placed in it by `alignment`, and cut
/// to it, and the result is the base's size. See
/// ``compositeLayer(_:under:alignment:context:modifierType:)`` for what "behind"
/// means in a cell grid.
struct BackgroundLayerModifier<Base: View, Background: View>: View {
    /// The base content.
    let base: Base

    /// The view drawn behind it.
    let background: Background

    /// The alignment of the background within the base's bounds.
    let alignment: Alignment

    var body: Never {
        fatalError("BackgroundLayerModifier renders via Renderable")
    }
}

extension BackgroundLayerModifier: Renderable {
    /// Nothing on an `EmptyView`, as under `.overlay` (``OverlayModifier``).
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard Base.self != EmptyView.self else { return FrameBuffer() }
        return compositeLayer(
            background, under: TUIkitView.renderToBuffer(base, context: context), alignment: alignment,
            context: context, modifierType: Self.self)
    }
}

extension BackgroundLayerModifier: Layoutable {
    /// The base's size, as ``OverlayModifier``'s is.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard Base.self != EmptyView.self else { return ViewSize.fixed(0, 0) }
        return layeredSize(
            background, baseSize: measureChild(base, proposal: proposal, context: context),
            proposal: proposal, context: context, modifierType: Self.self)
    }
}

extension View {
    /// Layers the views that you specify behind this view.
    ///
    /// ```swift
    /// Text("Hello")
    ///     .padding(.horizontal, 1)
    ///     .background(alignment: .leading) {
    ///         Color.blue.frame(width: progress)
    ///     }
    /// ```
    ///
    /// This view dominates layout: the background is offered this view's size,
    /// placed in it by `alignment`, and cut to it. Every cell this view leaves
    /// without a background colour of its own shows the background's — a
    /// translucent one included, composited. A background *glyph* shows only
    /// where this view draws no cell at all, since a cell holds one glyph and
    /// this view's, a space included, is in front. SwiftUI lets a background
    /// larger than the view draw outside it; a terminal buffer has no outside,
    /// so it is cut, as `.overlay`'s is.
    ///
    /// - Parameters:
    ///   - alignment: Where the background goes in this view's frame. Default
    ///     `.center`.
    ///   - content: The views to draw behind this view.
    /// - Returns: A view with the background behind it.
    public func background<V: View>(
        alignment: Alignment = .center, @ViewBuilder content: () -> V
    ) -> some View {
        BackgroundLayerModifier(base: self, background: content(), alignment: alignment)
    }
}

/// A background written on a form row goes behind the row the form lays out,
/// which keeps its place, as SwiftUI's does (measured).
extension BackgroundLayerModifier: FormRowRewrapping {
    var formRowContent: Base { base }

    func rewrappingFormRow<V: View>(_ row: V) -> any View {
        BackgroundLayerModifier<V, Background>(base: row, background: background, alignment: alignment)
    }
}
