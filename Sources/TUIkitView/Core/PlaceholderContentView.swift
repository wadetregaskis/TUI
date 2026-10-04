//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PlaceholderContentView.swift
//
//  The stand-in for "the view this is applied to" that a transition's
//  `body(content:phase:)`, and `View.transaction(_:body:)` and its siblings,
//  are handed to build around.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A placeholder used to construct an inline modifier, transition, or other
/// helper type.
///
/// You don't use this type directly. Instead TUIkit creates it on your behalf:
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
public struct PlaceholderContentView<Value>: View {
    /// What the placeholder draws.
    let source: PlaceholderSource

    /// Creates a placeholder that draws what `source` draws.
    package init(source: PlaceholderSource) {
        self.source = source
    }

    /// Never called — the placeholder draws its view directly.
    public var body: Never {
        fatalError("PlaceholderContentView renders via Renderable")
    }
}

/// What a ``PlaceholderContentView`` draws, and how it measures.
///
/// A class rather than a pair of closures in the placeholder's value: the
/// per-pass memos tell two values of one view type apart by their bytes, and a
/// reference that lives for the whole of the body it is drawn in is a
/// discriminator no other placeholder at the same place can share.
@MainActor
package final class PlaceholderSource {
    /// Draws the view the placeholder stands for, in the context the
    /// placeholder was given.
    let render: @MainActor (RenderContext) -> FrameBuffer

    /// Measures it.
    let measure: @MainActor (ProposedSize, RenderContext) -> ViewSize

    /// Creates a source from its two halves.
    package init(
        render: @escaping @MainActor (RenderContext) -> FrameBuffer,
        measure: @escaping @MainActor (ProposedSize, RenderContext) -> ViewSize
    ) {
        self.render = render
        self.measure = measure
    }

    /// `view`, drawn where the placeholder stands — the source of a
    /// placeholder built around an arbitrary view (`Transition.apply(content:phase:)`).
    package convenience init<V: View>(view: V) {
        self.init(
            render: { TUIkitView.renderToBuffer(view, context: $0) },
            measure: { measureChild(view, proposal: $0, context: $1) })
    }
}

extension PlaceholderContentView: Renderable {
    /// Draws the view the placeholder stands for.
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        source.render(context)
    }
}

extension PlaceholderContentView: Layoutable {
    /// Measures as the view the placeholder stands for.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        source.measure(proposal, context)
    }
}
