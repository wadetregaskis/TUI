//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentationBackground.swift
//
//  `presentationBackground(_:)` and `presentationBackground(alignment:content:)`:
//  what fills a presentation behind its content.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - Modifiers

extension View {
    /// Sets the presentation background of the enclosing sheet using a shape
    /// style. Mirrors SwiftUI's `presentationBackground(_:)`.
    ///
    /// Apply it to the presented **content**, as with
    /// ``View/presentationDetents(_:)``:
    ///
    /// ```swift
    /// .sheet(isPresented: $showSettings) {
    ///     SettingsView()
    ///         .presentationBackground(.blue)
    /// }
    /// ```
    ///
    /// Unlike `background(_:)`, it fills the whole presentation: a
    /// sheet's box (its detent's height included), a full-screen cover's whole
    /// content area, a popover's panel in place of the page's background. A
    /// translucent style composites over the page beneath, as opacity does
    /// everywhere here. (macOS draws a sheet's background opaque; a terminal
    /// sheet shows what it is given.)
    ///
    /// - Parameter style: The shape style to fill the presentation with.
    nonisolated public func presentationBackground<S: ShapeStyle>(_ style: S) -> some View {
        _PresentationBackgroundView(content: self, fill: .style(AnyShapeStyle(style)), alignment: .center)
    }

    /// Sets the presentation background of the enclosing sheet to a custom
    /// view. Mirrors SwiftUI's `presentationBackground(alignment:content:)`.
    ///
    /// The view is drawn behind the presentation, sized to the whole of it and
    /// placed by `alignment`, as ``View/background(alignment:content:)`` places
    /// a background.
    ///
    /// - Parameters:
    ///   - alignment: Where the background view sits in the presentation.
    ///   - content: The view to fill the presentation with.
    nonisolated public func presentationBackground<V: View>(
        alignment: Alignment = .center, @ViewBuilder content: () -> V
    ) -> some View {
        _PresentationBackgroundView(content: self, fill: .view(AnyView(content())), alignment: alignment)
    }
}

/// The wrapper the two modifiers produce. Renders and measures as its content;
/// the presenter, which knows how big the presentation is, draws the fill.
nonisolated struct _PresentationBackgroundView<Content: View>: View, PresentationBackgroundProviding {
    /// What fills the presentation.
    enum Fill {
        case style(AnyShapeStyle)
        case view(AnyView)
    }

    let content: Content
    let fill: Fill
    let alignment: Alignment

    @MainActor var body: Never {
        fatalError("_PresentationBackgroundView renders via Renderable")
    }

    /// The presented view with the fill behind it. A background view goes on
    /// in TUIFoundation (`erasedBackground(alignment:_:)`): built here,
    /// `background(alignment:content:)`'s result names a type only that module
    /// can see, so this module would look its type up at run time on every
    /// frame the presentation is open (CONTRIBUTING.md, "Crossing a module
    /// boundary"). A style's background names no such type.
    @MainActor func presentationBackground<V: View>(behind view: V) -> AnyView {
        switch fill {
        case .style(let style):
            AnyView(view.background(style))
        case .view(let background):
            view.erasedBackground(alignment: alignment, background)
        }
    }
}

@MainActor extension _PresentationBackgroundView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: context)
    }
}

@MainActor extension _PresentationBackgroundView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

@MainActor extension _PresentationBackgroundView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
@MainActor extension _PresentationBackgroundView: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension _PresentationBackgroundView: DrawsContentUnchanged {}
