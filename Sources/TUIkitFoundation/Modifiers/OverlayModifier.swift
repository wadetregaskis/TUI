//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Internal modifier that layers an overlay view on top of the base content.
///
/// The overlay is laid out **inside the base's frame**: the base is rendered
/// with the space this modifier was given, the overlay is then offered the size
/// the base came back at, positioned in it by `alignment`, and cut to it. The
/// result is the base's size on both axes — an overlay never resizes what it is
/// laid over, which is the whole difference between `.overlay` and a `ZStack`.
///
/// The exception is an axis the base has no extent on at all: there is no frame
/// to lay the overlay in, so the overlay is drawn whole and is what the
/// modifier measures. `EmptyView().overlay { … }` is that case, and so is a
/// base whose entire payload floats (an `OffsetView` renders no in-flow lines).
public struct OverlayModifier<Base: View, Overlay: View>: View {
    /// The base content.
    let base: Base

    /// The overlay content.
    let overlay: Overlay

    /// The alignment of the overlay within the base bounds.
    let alignment: Alignment

    public var body: Never {
        fatalError("OverlayModifier renders via Renderable")
    }
}

// MARK: - Equatable Conformance

extension OverlayModifier: @preconcurrency Equatable where Base: Equatable, Overlay: Equatable {
    public static func == (lhs: OverlayModifier<Base, Overlay>, rhs: OverlayModifier<Base, Overlay>) -> Bool {
        lhs.base == rhs.base && lhs.overlay == rhs.overlay && lhs.alignment == rhs.alignment
    }
}

// MARK: - Renderable

extension OverlayModifier: Renderable {
    /// The base at this modifier's identity, then the overlay laid out in its
    /// frame and composited over it — `compositeLayer(_:over:alignment:context:modifierType:)`.
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        compositeLayer(
            overlay, over: TUIkitView.renderToBuffer(base, context: context), alignment: alignment,
            context: context, modifierType: Self.self)
    }
}

// MARK: - Layoutable

extension OverlayModifier: Layoutable {
    /// The base's size, flexibility and all: the overlay is laid out inside it
    /// and ``renderToBuffer(context:)`` cuts the composite back to it, so the
    /// overlay cannot contribute a cell — see `layeredSize(_:baseSize:proposal:context:modifierType:)`
    /// for the axis the base has no extent on.
    ///
    /// This answered `max(base, overlay)` on each axis until 2026-09-20, which
    /// is a `ZStack`'s rule rather than an overlay's: a badge wider than the
    /// thing it badges widened the view it was laid on, and with it every
    /// sibling in the enclosing stack.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        layeredSize(
            overlay, baseSize: measureChild(base, proposal: proposal, context: context),
            proposal: proposal, context: context, modifierType: Self.self)
    }
}
