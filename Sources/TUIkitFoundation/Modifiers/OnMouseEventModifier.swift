//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnMouseEventModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - On Mouse Event Modifier

/// A modifier that subscribes a view to mouse events.
///
/// The modifier registers a handler with the per-frame
/// `MouseEventDispatcher` and emits a ``HitTestRegion`` whose
/// dimensions match the wrapped content's rendered bounds. When a
/// mouse event lands inside the region the dispatcher calls the
/// handler; once the handler claims a button-down event the
/// dispatcher routes every subsequent `.dragged` / `.released` event
/// for that button to the same handler regardless of where the cursor
/// actually is, so drag tracking works naturally.
public struct OnMouseEventModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// Where the handler's coordinates are measured from: the view's own
    /// top-left cell (`.local`), as the dispatcher hands them over, or the
    /// terminal's (`.global`).
    var coordinateSpace: CoordinateSpace = .local

    /// The handler. Returns `true` if it consumed the event.
    let handler: (MouseEvent) -> Bool

    public var body: Never {
        fatalError("OnMouseEventModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension OnMouseEventModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Render first so the buffer dimensions are known; the
        // hit-test region we emit afterwards has to match the rendered
        // bounds exactly.
        var buffer = TUIkitView.renderToBuffer(content, context: context)

        // No dispatcher (e.g. measure pass) — skip registration. The
        // measure path renders content for sizing but never sees a
        // real mouse event, so the registration would just churn ids.
        //
        // Nor inside `.disabled(true)`: SwiftUI leaves a tap gesture there
        // dead, as `.onHover` already is here, and every gesture built on
        // this one — taps, scrolls, the long press — follows from the one
        // guard. Attached OUTSIDE the disabled scope (`.disabled(true)
        // .onTapGesture`), the modifier renders with an enabled environment
        // and still fires, which is SwiftUI's scoping too.
        guard !context.isMeasuring, context.environment.isEnabled,
            let dispatcher = context.environment.mouseEventDispatcher
        else {
            return buffer
        }

        // The global cell is the region's plus its origin, which is known only
        // where the region was composited, so it is looked up when the event
        // comes — see `RegionOrigin`; a named space's is the region's plus
        // where the space's owner found this view (`PointerSpaceOrigin`).
        let space = coordinateSpace
        let spaceOrigin = PointerSpaceOrigin(
            named: space.isNamed ? [space] : [], global: space == .global, context: context)
        spaceOrigin?.stamp(into: &buffer, context: context)
        let handler: (MouseEvent) -> Bool
        if let spaceOrigin {
            let local = self.handler
            handler = { event in
                let cell = pointerCell(of: event, in: space, origin: spaceOrigin)
                return local(event.moved(by: (x: cell.x - event.x, y: cell.y - event.y)))
            }
        } else {
            handler = self.handler
        }
        // On the app's lane: whether the closure takes a plain left press it
        // alone says, when offered one, so a drag handle in front of it
        // stands aside for selectable text and lets it say.
        let handlerID = dispatcher.registerApplicationHandler(in: context, handler)
        spaceOrigin?.handlerID = handlerID
        // A pointer style in the content shows through: the closure hears the
        // events, and hides nothing.
        dispatcher.fileSeeThroughPointerShapes(for: handlerID, over: buffer.hitTestRegions, in: context)
        buffer.hitTestRegions += buffer.frameHitRegions(handlerID: handlerID)
        return buffer
    }
}

extension MouseEvent {
    /// This event with its position moved by `offset` cells.
    func moved(by offset: (x: Int, y: Int)) -> MouseEvent {
        MouseEvent(
            button: button, phase: phase, x: x + offset.x, y: y + offset.y,
            shift: shift, ctrl: ctrl, meta: meta, clickCount: clickCount)
    }
}

// MARK: - Layoutable

extension OnMouseEventModifier: Layoutable {
    /// Forwards measurement straight to the content — the mouse
    /// modifier doesn't change layout.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension OnMouseEventModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension OnMouseEventModifier: DrawsContentUnchanged {}
