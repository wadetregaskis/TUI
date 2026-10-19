//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpringLoadedRegion.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

// MARK: - A region that spring-loads

/// Makes its content's rectangle spring-load: a drag held still over it for the
/// spring-loading delay runs `activate`.
///
/// For a view that is not itself a control with a region of its own to name —
/// a `.sidebarAdaptable` tab view's rows, which are a list's. A control that
/// already registers a mouse handler (a `Button`, a tab strip's chip) registers
/// its spring-load target under that handler's id instead, and needs no second
/// region.
struct _SpringLoadedRegion<Content: View>: View {
    let content: Content

    /// Whether the region spring-loads at all; off, it registers nothing and
    /// draws its content as it is.
    let isEnabled: Bool

    /// What a pause over the region does.
    let activate: () -> Void

    var body: Never {
        fatalError("_SpringLoadedRegion renders via Renderable")
    }
}

extension _SpringLoadedRegion: Renderable, Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkitView.renderToBuffer(content, context: context)
        guard isEnabled, !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return buffer }
        // An inert region, at the BACK of the dispatch order as a drop zone's
        // is: it takes no event, so a click on the content still reaches the
        // content, and spring-load targeting matches ids rather than taking
        // the innermost region, so it finds this one at any depth.
        let handlerID = dispatcher.registerPassive(in: context) { _ in false }
        buffer.hitTestRegions.insert(contentsOf: buffer.frameHitRegions(handlerID: handlerID), at: 0)
        session.registerSpringLoadTarget(
            DragAndDropSession.SpringLoadTarget(
                handlerID: handlerID, identity: context.identity, activate: activate),
            in: context)
        return buffer
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension _SpringLoadedRegion: SingleContentWrapper {
    /// Its content's geometry is its own — it registers a region over its content, where it is — so a guide
    /// inside it passes unmoved (``SingleContentWrapper/_keepsContentGeometry``).
    static var _keepsContentGeometry: Bool { true }

    var wrappedContent: Content { content }
}
