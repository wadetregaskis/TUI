//  🖥️ TUI — A Terminal UI framework for Swift
//  ClippedModifier.swift
//
//  SwiftUI's `clipped(antialiased:)`: a view's drawing cut to its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension View {
    /// Clips this view to its bounding rectangular frame — mirrors SwiftUI's
    /// `clipped(antialiased:)`.
    ///
    /// A view's frame is used only for layout, and what it draws past the
    /// frame — moved by ``View/offset(x:y:)-(Int,Int)`` or ``position(x:y:)``, or overshooting
    /// on its way in with a transition — still shows, over its neighbours.
    /// This cuts it at the frame:
    ///
    /// ```swift
    /// Text("Sliding")
    ///     .offset(x: slide)
    ///     .frame(width: 20)
    ///     .clipped()
    /// ```
    ///
    /// A presentation is not content and is never clipped: a menu, a drop-down
    /// or a popover opened from inside still draws whole, as SwiftUI's do.
    ///
    /// - Parameter antialiased: Whether to smooth the clip's edges. A cell
    ///   grid's edges are whole cells, which SwiftUI's antialiasing leaves
    ///   unchanged too, so either value clips the same.
    /// - Returns: A view whose drawing stops at its frame.
    nonisolated public func clipped(antialiased: Bool = false) -> some View {
        _ClippedView(content: self)
    }
}

/// A view's drawing cut to its frame: the floating layers that are pieces of
/// its content, as a scroll view cuts its own.
nonisolated struct _ClippedView<Content: View>: View {
    let content: Content

    @MainActor var body: Never {
        fatalError("_ClippedView renders via Renderable")
    }
}

@MainActor extension _ClippedView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // What a glass container draws is not clipped as this is, so the
        // glass in here draws itself.
        var contentContext = context
        contentContext.environment.leaveGlassEffectContainer()
        var buffer = TUIView.renderToBuffer(content, context: contentContext)
        guard !buffer.overlays.isEmpty else { return buffer }
        // A surface (`isOpaque`) is a window over the page, not content: the
        // rule a scroll view's clip keeps (`ScrollView+Content.swift`).
        buffer.overlays = buffer.overlays.compactMap { layer in
            layer.isOpaque ? layer : layer.clipped(toWidth: buffer.width, height: buffer.height)
        }
        return buffer
    }
}

@MainActor extension _ClippedView: Layoutable {
    /// Clipping changes what draws, never the frame.
    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// The content's traits are the clipped view's: a z-index, a tag, a row badge,
/// a layout priority and a spacing preference written before `.clipped()`
/// reach the container that reads them, as SwiftUI's do (measured,
/// `Tools/SwiftUIProbes/Traits through layers and menus (H-63)/traits.out`;
/// hunt H-63). Read-only: not ``ContentRewrapping``, so a clip round several
/// views is one clip. ``SingleContentWrapper/_keepsContentGeometry`` stays
/// `false`, so a guide inside stops here, as before.
@MainActor extension _ClippedView: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}
