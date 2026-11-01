//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowSeparatorModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

/// Carries ``View/listRowSeparator(_:edges:)``'s arguments to the list the row
/// is in, and renders its content unchanged.
///
/// Reported as the row renders, against the list row rendering now — or, written
/// outside any row, the default of the lists below — through
/// `renderReportingSeparator(_:change:sections:context:)`, which the tint and the
/// section modifiers share (`ListSeparators.swift`; decisions A47). The arguments
/// are stored so the modifier compares equal only to itself — an `EquatableView`
/// above it must not treat two differently-configured rows as the same view.
nonisolated package struct ListRowSeparatorModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The visibility of the separator.
    let visibility: Visibility

    /// The edges to apply the separator to.
    let edges: VerticalEdge.Set

    @MainActor public var body: Never {
        fatalError("ListRowSeparatorModifier renders via Renderable")
    }
}

// MARK: - Equatable

extension ListRowSeparatorModifier: Equatable where Content: Equatable {
    package static func == (lhs: ListRowSeparatorModifier<Content>, rhs: ListRowSeparatorModifier<Content>) -> Bool {
        lhs.content == rhs.content && lhs.visibility == rhs.visibility && lhs.edges == rhs.edges
    }
}

// MARK: - Renderable

@MainActor extension ListRowSeparatorModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderReportingSeparator(content, change: .visibility(visibility, edges), sections: false, context: context)
    }
}

// MARK: - Layoutable

@MainActor extension ListRowSeparatorModifier: Layoutable {
    /// Draws `content` unchanged, so it measures as `content`.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index can look through
/// this wrapper instead of stopping at it. Read-only: it does NOT conform to
/// ``ContentRewrapping``, so nothing about it is distributed to the members of
/// multi-view content.
@MainActor extension ListRowSeparatorModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Seeing Through the Wrapper (alignment guides)

/// Answers for the guides its content sets, which it draws unchanged at its own
/// identity — the separator guides above all: Apple's documented row writes
/// `.listRowSeparatorLeading` on a view INSIDE the one this modifier is
/// written on, and a wrapper that does not say it can hold a guide hides every
/// guide below it.
@MainActor extension ListRowSeparatorModifier {
    /// Its content's answer: it draws its content unchanged, so a guide inside
    /// is its own.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

@MainActor extension ListRowSeparatorModifier: AlignmentGuideQuerying {
    package func explicitGuide(_ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext) -> Double? {
        TUIFoundation.explicitGuide(of: content, query, in: dimensions, context: context)
    }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension ListRowSeparatorModifier: DrawsContentUnchanged {}
