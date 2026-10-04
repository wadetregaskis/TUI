//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationBackground.swift
//
//  `presentationBackground(_:)` and `presentationBackground(alignment:content:)`:
//  what fills a presentation behind its content.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

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
    /// Unlike ``View/background(_:)``, it fills the whole presentation: a
    /// sheet's box (its detent's height included), a full-screen cover's whole
    /// content area, a popover's panel in place of the page's background. A
    /// translucent style composites over the page beneath, as opacity does
    /// everywhere here. (macOS draws a sheet's background opaque; a terminal
    /// sheet shows what it is given.)
    ///
    /// - Parameter style: The shape style to fill the presentation with.
    public func presentationBackground<S: ShapeStyle>(_ style: S) -> some View {
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
    public func presentationBackground<V: View>(
        alignment: Alignment = .center, @ViewBuilder content: () -> V
    ) -> some View {
        _PresentationBackgroundView(content: self, fill: .view(AnyView(content())), alignment: alignment)
    }
}

// MARK: - The trait

/// Content that has named its presentation's background.
@MainActor
protocol PresentationBackgroundProviding {
    /// `view`, with the background behind it.
    func presentationBackground<V: View>(behind view: V) -> AnyView
}

/// The wrapper the two modifiers produce. Renders and measures as its content;
/// the presenter, which knows how big the presentation is, draws the fill.
struct _PresentationBackgroundView<Content: View>: View, PresentationBackgroundProviding {
    /// What fills the presentation.
    enum Fill {
        case style(AnyShapeStyle)
        case view(AnyView)
    }

    let content: Content
    let fill: Fill
    let alignment: Alignment

    var body: Never {
        fatalError("_PresentationBackgroundView renders via Renderable")
    }

    func presentationBackground<V: View>(behind view: V) -> AnyView {
        switch fill {
        case .style(let style):
            AnyView(view.background(style))
        case .view(let background):
            AnyView(view.background(alignment: alignment) { background })
        }
    }
}

extension _PresentationBackgroundView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _PresentationBackgroundView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationBackgroundView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension _PresentationBackgroundView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _PresentationBackgroundView: DrawsContentUnchanged {}

/// `view` with the background `content` named for its presentation, if it
/// named one.
@MainActor
func withPresentationBackground<V: View>(_ view: V, from content: any View) -> AnyView? {
    presentationTrait(PresentationBackgroundProviding.self, of: content)?
        .presentationBackground(behind: view)
}
