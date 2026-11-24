//  🖥️ TUI — A Terminal UI framework for Swift
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
/// modifier measures — a base whose entire payload floats (an `OffsetView`
/// renders no in-flow lines). An `EmptyView` base is not that case but
/// nothing: SwiftUI draws no overlay on one (measured,
/// `Tools/SwiftUIProbes/Alignment guides/layout1.out`, case D), an
/// `EmptyView` being no view at all to the modifier, as it is no member to a
/// container.
nonisolated package struct OverlayModifier<Base: View, Overlay: View>: View {
    /// The base content.
    let base: Base

    /// The overlay content.
    let overlay: Overlay

    /// The alignment of the overlay within the base bounds.
    let alignment: Alignment

    @MainActor public var body: Never {
        fatalError("OverlayModifier renders via Renderable")
    }
}

// MARK: - In a Form

/// An overlay written on a form row is drawn over the row the form lays out,
/// which keeps its place, as SwiftUI's form keeps it (measured,
/// `Tools/SwiftUIProbes/Form rows`).
@MainActor extension OverlayModifier: FormRowRewrapping {
    package var formRowContent: Base { base }

    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        OverlayModifier<V, Overlay>(base: row, overlay: overlay, alignment: alignment)
    }
}

// MARK: - Seeing Through the Wrapper

/// The base's traits are the overlaid view's: a z-index, a tag, a row badge, a
/// layout priority and a spacing preference written on the base reach the
/// container that reads them through `.overlay { }`, as SwiftUI's do (measured,
/// `Tools/SwiftUIProbes/Traits through layers and menus (H-63)/traits.out`;
/// hunt H-63). Read-only, as `OnHoverModifier`'s is: not ``ContentRewrapping``,
/// so an overlay on several views is still drawn once round them all.
///
/// ``SingleContentWrapper/_keepsContentGeometry`` stays `false`: an overlay
/// answers the guide query itself, with its base's guide
/// (`WrapperGuidePropagation.swift`).
@MainActor extension OverlayModifier: SingleContentWrapper {
    package var wrappedContent: Base { base }

    /// Its base is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    package func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Equatable Conformance

extension OverlayModifier: Equatable where Base: Equatable, Overlay: Equatable {
    package static func == (lhs: OverlayModifier<Base, Overlay>, rhs: OverlayModifier<Base, Overlay>) -> Bool {
        lhs.base == rhs.base && lhs.overlay == rhs.overlay && lhs.alignment == rhs.alignment
    }
}

// MARK: - Renderable

@MainActor extension OverlayModifier: Renderable {
    /// The base at this modifier's identity, then the overlay laid out in its
    /// frame and composited over it — `compositeLayer(_:over:alignment:context:modifierType:)`.
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard Base.self != EmptyView.self else { return FrameBuffer() }
        return compositeLayer(
            overlay, over: TUIView.renderToBuffer(base, context: context), alignment: alignment,
            context: context, modifierType: Self.self)
    }
}

// MARK: - Layoutable

@MainActor extension OverlayModifier: Layoutable {
    /// The base's size, flexibility and all: the overlay is laid out inside it
    /// and ``renderToBuffer(context:)`` cuts the composite back to it, so the
    /// overlay cannot contribute a cell — see `layeredSize(_:baseSize:proposal:context:modifierType:)`
    /// for the axis the base has no extent on.
    ///
    /// This answered `max(base, overlay)` on each axis until 2026-09-20, which
    /// is a `ZStack`'s rule rather than an overlay's: a badge wider than the
    /// thing it badges widened the view it was laid on, and with it every
    /// sibling in the enclosing stack.
    public func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        guard Base.self != EmptyView.self else { return ViewSize.fixed(0, 0) }
        return layeredSize(
            overlay, baseSize: measureChild(base, proposal: proposal, context: context),
            proposal: proposal, context: context, modifierType: Self.self)
    }
}
