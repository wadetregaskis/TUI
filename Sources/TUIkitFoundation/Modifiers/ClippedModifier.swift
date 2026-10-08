//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClippedModifier.swift
//
//  SwiftUI's `clipped(antialiased:)`: a view's drawing cut to its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Clips this view to its bounding rectangular frame — mirrors SwiftUI's
    /// `clipped(antialiased:)`.
    ///
    /// A view's frame is used only for layout, and what it draws past the
    /// frame — moved by ``offset(x:y:)`` or ``position(x:y:)``, or overshooting
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
    public func clipped(antialiased: Bool = false) -> some View {
        _ClippedView(content: self)
    }
}

/// A view's drawing cut to its frame: the floating layers that are pieces of
/// its content, as a scroll view cuts its own.
struct _ClippedView<Content: View>: View {
    let content: Content

    var body: Never {
        fatalError("_ClippedView renders via Renderable")
    }
}

extension _ClippedView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkitView.renderToBuffer(content, context: context)
        guard !buffer.overlays.isEmpty else { return buffer }
        // A surface (`isOpaque`) is a window over the page, not content: the
        // rule a scroll view's clip keeps (`ScrollView+Content.swift`).
        buffer.overlays = buffer.overlays.compactMap { layer in
            layer.isOpaque ? layer : layer.clipped(toWidth: buffer.width, height: buffer.height)
        }
        return buffer
    }
}

extension _ClippedView: Layoutable {
    /// Clipping changes what draws, never the frame.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
