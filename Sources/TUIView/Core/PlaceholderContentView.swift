//  🖥️ TUI — A Terminal UI framework for Swift
//  PlaceholderContentView.swift
//
//  The stand-in for "the view this is applied to" that a transition's
//  `body(content:phase:)`, and `View.transaction(_:body:)` and its siblings,
//  are handed to build around.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// A placeholder used to construct an inline modifier, transition, or other
/// helper type.
///
/// You don't use this type directly. Instead TUI creates it on your behalf:
/// it is the `content` a `Transition`'s `body(content:phase:)` receives, and the
/// one `View.transaction(_:body:)` hands its `body` closure. Apply modifiers to
/// it as you would to any view; what it draws is the view it stands for.
///
/// Generic over the type it is a placeholder FOR rather than the view it draws,
/// as SwiftUI's is, so one transition has one `Content` type whatever view it is
/// applied to.
///
/// ## Where the view it stands for is drawn
///
/// At the identity the framework pins it to, not one step inside the body that
/// holds the placeholder. A transition's body is drawn around the view in
/// several shapes — at rest, recorded at an end phase, drawn part-way — and the
/// view's `@State` must not move between them, nor be anywhere other than where
/// it would be with no transition at all.
nonisolated public struct PlaceholderContentView<Value>: View {
    /// What the placeholder draws.
    let source: PlaceholderSource

    /// Creates a placeholder that draws what `source` draws.
    package init(source: PlaceholderSource) {
        self.source = source
    }

    /// Never called — the placeholder draws its view directly.
    @MainActor public var body: Never {
        fatalError("PlaceholderContentView renders via Renderable")
    }
}

/// What a ``PlaceholderContentView`` draws, and how it measures.
///
/// A class rather than a pair of closures in the placeholder's value: the
/// per-pass memos tell two values of one view type apart by their bytes, and a
/// reference that lives for the whole of the body it is drawn in is a
/// discriminator no other placeholder at the same place can share.
package final class PlaceholderSource {
    private let drawing: any PlaceholderDrawing

    /// Creates a source from what it draws.
    package init(drawing: any PlaceholderDrawing) {
        self.drawing = drawing
    }

    /// Creates a source from its two halves.
    package convenience init(
        render: @escaping @MainActor (RenderContext) -> FrameBuffer,
        measure: @escaping @MainActor (ProposedSize, RenderContext) -> ViewSize
    ) {
        self.init(drawing: PlaceholderClosures(render: render, measure: measure))
    }

    /// `view`, drawn where the placeholder stands — the source of a
    /// placeholder built around an arbitrary view (`Transition.apply(content:phase:)`).
    package convenience init<V: View>(view: V) {
        self.init(drawing: PlaceholderView(view: view))
    }

    /// Draws the view the placeholder stands for, in the context the
    /// placeholder was given.
    @MainActor func render(_ context: RenderContext) -> FrameBuffer { drawing.render(context) }

    /// Measures it.
    @MainActor func measure(_ proposal: ProposedSize, _ context: RenderContext) -> ViewSize {
        drawing.measure(proposal, context)
    }
}

/// What a ``PlaceholderSource`` keeps. Its requirements alone are on the main
/// actor, where the placeholder is drawn: a value of it can be made anywhere,
/// as a view can, where a `@MainActor` closure could not capture that view.
package protocol PlaceholderDrawing {
    @MainActor func render(_ context: RenderContext) -> FrameBuffer
    @MainActor func measure(_ proposal: ProposedSize, _ context: RenderContext) -> ViewSize
}

private struct PlaceholderClosures: PlaceholderDrawing {
    let renderClosure: @MainActor (RenderContext) -> FrameBuffer
    let measureClosure: @MainActor (ProposedSize, RenderContext) -> ViewSize

    init(
        render: @escaping @MainActor (RenderContext) -> FrameBuffer,
        measure: @escaping @MainActor (ProposedSize, RenderContext) -> ViewSize
    ) {
        renderClosure = render
        measureClosure = measure
    }

    @MainActor func render(_ context: RenderContext) -> FrameBuffer { renderClosure(context) }

    @MainActor func measure(_ proposal: ProposedSize, _ context: RenderContext) -> ViewSize {
        measureClosure(proposal, context)
    }
}

private struct PlaceholderView<V: View>: PlaceholderDrawing {
    let view: V

    @MainActor func render(_ context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(view, context: context)
    }

    @MainActor func measure(_ proposal: ProposedSize, _ context: RenderContext) -> ViewSize {
        measureChild(view, proposal: proposal, context: context)
    }
}

@MainActor extension PlaceholderContentView: Renderable {
    /// Draws the view the placeholder stands for — which, inside a transition
    /// body being drawn part-way, is not derived from the modifiers around it
    /// (see `TransitionScrub`).
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let scrub = context.stateStorage?.animations.scrub else { return source.render(context) }
        return scrub.independently { source.render(context) }
    }
}

@MainActor extension PlaceholderContentView: Layoutable {
    /// Measures as the view the placeholder stands for.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let scrub = context.stateStorage?.animations.scrub else {
            return source.measure(proposal, context)
        }
        return scrub.independently { source.measure(proposal, context) }
    }
}
