//  🖥️ TUI — A Terminal UI framework for Swift
//  View+Shapes.swift
//
//  A shape behind a view, over it, and as its clip. A shape as its hit area
//  is `ContentShapeModifier.swift`'s.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A shape behind, a shape over

extension View {
    /// Sets the view's background to a shape filled with a style.
    ///
    /// The shape fills this view's frame and is drawn behind it, as
    /// ``View/background(alignment:content:)`` draws any view: a cell this view
    /// leaves without a background colour shows the shape's. The shape's glyphs
    /// — a rounded corner's quadrant, a capsule's caps, a circle's rim — show
    /// through this view's blank cells too, so padding round a label does not
    /// square the shape off.
    ///
    /// ```swift
    /// Label("Flag", systemImage: "flag.fill")
    ///     .padding(1)
    ///     .background(.teal, in: RoundedRectangle(cornerRadius: 2))
    /// ```
    ///
    /// - Parameters:
    ///   - style: The style the shape is filled with.
    ///   - shape: The shape to draw behind the view.
    ///   - fillStyle: The fill rule and antialiasing.
    /// - Returns: A view with the shape behind it.
    nonisolated public func background<S: ShapeStyle, T: Shape>(
        _ style: S, in shape: T, fillStyle: FillStyle = FillStyle()
    ) -> some View {
        _ShapeBackground(content: self, shape: shape, style: style, fillStyle: fillStyle)
    }

    /// Sets the view's background to a shape filled with the background
    /// style — the one ``View/backgroundStyle(_:)-(S)`` sets, the palette's
    /// background where none is set.
    ///
    /// - Parameters:
    ///   - shape: The shape to draw behind the view.
    ///   - fillStyle: The fill rule and antialiasing.
    /// - Returns: A view with the shape behind it.
    nonisolated public func background<S: Shape>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View {
        background(BackgroundStyle(), in: shape, fillStyle: fillStyle)
    }

    /// Layers a shape filled with a style over this view, in its frame.
    ///
    /// Where the shape does not reach — its rim's uncovered halves, a circle's
    /// corners — this view shows through.
    ///
    /// - Parameters:
    ///   - style: The style the shape is filled with.
    ///   - shape: The shape to draw over the view.
    ///   - fillStyle: The fill rule and antialiasing.
    /// - Returns: A view with the shape over it.
    nonisolated public func overlay<S: ShapeStyle, T: Shape>(
        _ style: S, in shape: T, fillStyle: FillStyle = FillStyle()
    ) -> some View {
        overlay { shape.fill(style, style: fillStyle) }
    }

    /// Layers a style over this view, filling its frame.
    ///
    /// SwiftUI's `overlay(_:ignoresSafeAreaEdges:)`, minus the argument: a
    /// terminal has no safe area for it to talk about, as for
    /// ``View/background(_:)-(S)``.
    ///
    /// - Parameter style: The style to layer over the view.
    /// - Returns: A view with the style over it.
    nonisolated public func overlay<S: ShapeStyle>(_ style: S) -> some View {
        overlay(style, in: Rectangle())
    }

    /// The colour spelling, so `.overlay(.red)` and `.overlay(.palette.accent)`
    /// both infer, the `@_disfavoredOverload` pair ``View/background(_:)-(Color)``
    /// is.
    @_disfavoredOverload
    nonisolated public func overlay(_ color: Color) -> some View {
        overlay(color, in: Rectangle())
    }
}

// MARK: - A shape as the clip

extension View {
    /// Sets a clipping shape for this view.
    ///
    /// The shape fills the view's frame, and a cell of the view is kept where
    /// the shape covers at least half of it — a cell holds one glyph, so it is
    /// kept or not, by the ½ rule every glyph decision here takes (`Opacity as
    /// composition.md` §6a). A cell clipped away shows what is behind the
    /// view. A ``Rectangle`` keeps the frame, as ``View/clipped(antialiased:)``
    /// does; anything drawn outside the frame is cut with it.
    ///
    /// ```swift
    /// Text("Clipped text in a circle")
    ///     .frame(width: 20, height: 10)
    ///     .background(Color.black)
    ///     .clipShape(Circle())
    /// ```
    ///
    /// - Parameters:
    ///   - shape: The clipping shape.
    ///   - style: The fill rule; antialiasing does not apply to a cell kept
    ///     or not.
    /// - Returns: The view, clipped.
    nonisolated public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        _ShapeClip(content: clipped(), shape: shape, fillStyle: style)
    }
}
