//  🖥️ TUI — A Terminal UI framework for Swift
//  DragAndDrop.swift
//
//  `.draggable(_:)` / `.dropDestination(for:action:isTargeted:)` — modelled
//  on SwiftUI's current (Transferable-era) drag-and-drop API, with the
//  deliberate terminal deviations documented on each entry point: payloads
//  are unconstrained in-process values (CoreTransferable is Apple-only and a
//  terminal cannot reach the system pasteboard anyway), and the drop action
//  receives a ``DropInfo`` (cell coordinates + the modifiers held at
//  release) instead of a `CGPoint`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Drag Preview Anchor

/// How the floating preview of a drag anchors to the cursor.
public enum DragPreviewAnchor: Sendable, Equatable {
    /// The cell that was pressed stays under the cursor — the preview sits
    /// exactly where it would conceptually land, like macOS. The default.
    case grabPoint

    /// The preview's top-left corner rides at a fixed offset from the
    /// cursor. `.offset(x: 1, y: 1)` trails below-right, keeping the
    /// pointed-at cell itself uncovered — clearer, but the image no longer
    /// shows the true drop position.
    case offset(x: Int, y: Int)
}

private struct DragPreviewAnchorKey: EnvironmentKey {
    static let defaultValue: DragPreviewAnchor = .grabPoint
}

extension EnvironmentValues {
    /// How drag previews started in this scope anchor to the cursor.
    package var dragPreviewAnchor: DragPreviewAnchor {
        get { self[DragPreviewAnchorKey.self] }
        set { self[DragPreviewAnchorKey.self] = newValue }
    }
}

extension View {
    /// Sets how the floating preview of drags started in this view's
    /// subtree anchors to the cursor (default: ``DragPreviewAnchor/grabPoint``).
    public func dragPreviewAnchor(_ anchor: DragPreviewAnchor) -> some View {
        environment(\.dragPreviewAnchor, anchor)
    }
}

// MARK: - Draggable

/// The view wrapper created by ``View/draggable(_:)``.
///
/// Renders its content and claims left presses over it: a press followed by
/// any cursor movement begins a drag session (the payload is evaluated
/// then), the drag preview follows the cursor as a floating overlay, and
/// release either drops on a targeted ``View/dropDestination(for:action:isTargeted:)``
/// or cancels. A press released without movement is a CLICK, forwarded to
/// the interactive child under the cursor — so a `Button` (or any control)
/// wrapped in `.draggable` still clicks, matching SwiftUI. Hover
/// transitions forward the same way, so the child keeps its hover
/// affordance. Only genuine drags (press + movement) are consumed here.
public struct DraggableModifier<Content: View, Payload>: View {
    let content: Content
    let payload: () -> Payload
    let preview: AnyView?

    public var body: Never {
        fatalError("DraggableModifier renders via Renderable")
    }
}

extension DraggableModifier: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The keyboard's way to the payload: Copy while the view holds the
        // focus (`TransferKeys`), on a stop of the content's or one of its own.
        let keys = TransferKeys.applies(in: context)
        let own = keys ? TransferKeys.ownStop(prefix: "draggable", propertyIndex: -180, context: context) : nil
        var contentContext = context
        if let own { FocusRegistration.publishIsFocused(own.isFocused, context: context, into: &contentContext) }
        var buffer = TUIView.renderToBuffer(content, context: contentContext)
        if let own {
            let payload = self.payload
            TransferKeys.register(
                "c", focusIDs: TransferKeys.stops(of: buffer, ownID: own.id, context: context), context: context
            ) { _, clipboard in
                clipboard.copy([payload()])
                return true
            }
        }

        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return buffer }

        // A view being carried has LEFT its place: it is in the user's hand,
        // floating at the cursor, and drawing it here as well would be one
        // thing shown twice. Row reordering has always worked this way (see
        // `RowReorderFeedback.cursor`); a `.draggable` row in a list that a
        // drag is transferring OUT of now reads the same, rather than sitting
        // there as if nothing were happening.
        //
        // Blank rather than absent: the view owns this space in the layout,
        // and a list closing up under the pointer mid-drag would move the very
        // rows the drop is aimed between. A `List` drawing a landing SLOT for
        // this same drag collapses the row around the blank instead, so the
        // list keeps its length — see `_ListCore.decorateForReorder`.
        //
        // The answer is the session's, which no memo keys on: the session
        // reports every change of it to the render cache
        // (`DragAndDropSession.renderInvalidation`), so a memo above this view
        // is not served the card while the card is in the hand.
        let identity = context.identity
        if session.isDragSource(identity) {
            buffer = FrameBuffer(
                lines: Array(
                    repeating: String.spaces(max(0, buffer.width)),
                    count: max(1, buffer.height)))
        }

        // The floating preview: the explicit preview view when given, else
        // the content's own rendered buffer (regions/overlays stripped — the
        // preview is purely visual).
        var previewBuffer: FrameBuffer
        if let preview {
            previewBuffer = TUIView.renderToBuffer(preview, context: context)
        } else {
            previewBuffer = buffer
        }
        // Cut to its drag-preview content shape, where one covers it
        // (`contentShape(.dragPreview, _:)`).
        if let kept = previewBuffer.contentShapeRuns(.dragPreview) {
            previewBuffer = previewBuffer.clearing(keeping: kept)
        }
        previewBuffer.hitTestRegions = []
        previewBuffer.overlays = []

        let payload = self.payload
        let capturedPreview = previewBuffer
        let anchor = context.environment.dragPreviewAnchor
        let allowed = context.environment.allowedDragOperations
        _DragHandle.install(
            on: &buffer,
            context: context,
            dispatcher: dispatcher,
            onDragBegin: { _, grab in
                // A payload that turns out to be nothing — an `itemProvider`
                // that vends `nil` — starts no drag: the gesture goes on, and
                // carries nothing anywhere, as SwiftUI's does.
                let value = payload()
                guard !isNilOptional(value) else { return }
                session.begin(
                    payload: value, preview: capturedPreview,
                    grabX: grab.x, grabY: grab.y, anchor: anchor, source: identity, allowedOperations: allowed)
            },
            onDragMove: { _ in session.dragMoved() },
            onDragEnd: { _ in
                let dropped = session.performDrop()
                debugFocusLog("draggable drop performed=\(dropped)")
            })
        return buffer
    }
}

/// Whether `value` is an optional holding nothing, whatever it wraps.
private func isNilOptional(_ value: Any) -> Bool {
    let mirror = Mirror(reflecting: value)
    return mirror.displayStyle == .optional && mirror.children.isEmpty
}

// MARK: - Drag Handle Core

/// The shared plumbing of a drag-handle surface: claims left presses over a
/// rendered buffer, reports genuine drags (press + movement) through
/// callbacks, and keeps the buffer's interactive children working — a press
/// released without movement forwards to the child under the cursor as an
/// ordinary click, and hover transitions ride through likewise.
///
/// Used by ``DraggableModifier`` (drag-and-drop payloads) and the gradient
/// editor's stop chips (live reordering while the drag moves).
package enum _DragHandle {
    /// Registers the handle's handler and appends its whole-buffer region
    /// (innermost, so it claims presses ahead of the children it forwards
    /// to). Callback events are localized to the buffer's origin; a drag's
    /// events stay localized to the ORIGINAL press region even when content
    /// re-renders mid-drag (the dispatcher's press capture).
    @MainActor
    package static func install(
        on buffer: inout FrameBuffer,
        context: RenderContext,
        dispatcher: MouseEventDispatcher,
        onDragBegin: @escaping (MouseEvent, _ grab: (x: Int, y: Int)) -> Void,
        onDragMove: @escaping (MouseEvent) -> Void,
        onDragEnd: @escaping (MouseEvent) -> Void
    ) {
        // The content's interactive regions, captured WITH their handler
        // closures. Clicks and hover forward to them below — and that must
        // go through closures, never ids: the dispatcher's table of closures
        // is rebuilt on every walk while a press or hover routinely spans one
        // (a consumed press requests a re-render), so a child that stopped
        // rendering would leave an id resolving to nothing at delivery time.
        // Same reasoning as the dispatcher's own press capture.
        let children: [(region: HitTestRegion, handler: (MouseEvent) -> Bool)] =
            buffer.hitTestRegions.compactMap { region in
                dispatcher.handler(for: region.handlerID).map { (region, $0) }
            }
        // Innermost child at a point (in the buffer's space, which is also
        // the space of the events this handler receives — its region sits at
        // the buffer's origin). Last-registered = innermost, as dispatched.
        func innermostChild(atX x: Int, y: Int) -> (region: HitTestRegion, handler: (MouseEvent) -> Bool)? {
            children.last { $0.region.contains(x: x, y: y) }
        }
        func forward(
            _ event: MouseEvent, phase: MousePhase,
            to child: (region: HitTestRegion, handler: (MouseEvent) -> Bool)
        ) {
            let localized = MouseEvent(
                button: event.button, phase: phase,
                x: event.x - child.region.offsetX, y: event.y - child.region.offsetY,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                clickCount: event.clickCount)
            _ = child.handler(localized)
        }

        let scratch = DragScratch()
        // Weak: the dispatcher holds this handler (see `Button`'s).
        let id = dispatcher.register(in: context) { [weak dispatcher] event in
            // Hover transitions land here (the handle's region is the
            // innermost); ride them through to the children so they keep
            // their hover affordance. STATELESSLY: the hover-on re-render
            // replaces this closure (and its scratch) before the matching
            // .exited arrives, so remembering "which child is hovered" in
            // the closure loses the exit and strands the child hovered —
            // the gradient chips' stuck hover bullet. Entering targets the
            // child under the cursor; exiting broadcasts to every child (a
            // child that isn't hovered treats it as a no-op).
            switch event.phase {
            case .entered:
                if let child = innermostChild(atX: event.x, y: event.y) {
                    forward(event, phase: .entered, to: child)
                }
                return true
            case .exited:
                for child in children {
                    forward(event, phase: .exited, to: child)
                }
                return true
            default:
                break
            }
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                scratch.isDragging = false
                // The grab point: where the press landed within this
                // surface. `.grabPoint`-anchored previews keep this cell
                // under the cursor for the whole drag.
                scratch.grab = (event.x, event.y)
                return true
            case .dragged:
                if !scratch.isDragging {
                    scratch.isDragging = true
                    onDragBegin(event, scratch.grab)
                } else {
                    onDragMove(event)
                }
                return true
            case .released:
                debugFocusLog(
                    "drag handle release: isDragging=\(scratch.isDragging) at (\(event.x), \(event.y))")
                if scratch.isDragging {
                    onDragEnd(event)
                    scratch.isDragging = false
                } else if let child = innermostChild(atX: event.x, y: event.y) {
                    // A press released without movement is a CLICK. The
                    // press itself was claimed (as a potential drag), so
                    // deliver the whole click — synthetic press, then the
                    // release — to the interactive child under the cursor:
                    // a Button inside a drag handle still clicks.
                    forward(event, phase: .pressed, to: child)
                    forward(event, phase: .released, to: child)
                } else if let handlerID = scratch.handlerID {
                    // Nothing interactive INSIDE wanted it, so the click was
                    // never this handle's: hand it to whatever the handle is
                    // sitting on. A `List` row is the case that matters — a
                    // row of plain `Text` has no child to forward to, so a
                    // list of `.draggable` rows swallowed every click and
                    // could only be selected from the keyboard.
                    dispatcher?.passClickThrough(from: handlerID, event: event)
                }
                return true
            default:
                return false
            }
        }
        scratch.handlerID = id
        // Where text selection is enabled — around this handle, or by a scope
        // already filed this walk (one inside its content, a table's cells) —
        // a press on selectable text that no control's label is passes the
        // handle over (`PressRole.dragSource`). One read elsewhere.
        if context.environment.textSelectionAllowed == true || dispatcher.hasEnabledSelectionScope {
            dispatcher.filePressRole(.dragSource, for: id, in: context)
        }
        // A pointer style in the content shows through the handle, which
        // takes the presses and hides nothing.
        dispatcher.fileSeeThroughPointerShapes(for: id, over: buffer.hitTestRegions, in: context)
        buffer.hitTestRegions += buffer.frameHitRegions(handlerID: id)
    }
}

/// Per-handler scratch: whether the current press has turned into a drag,
/// and where it grabbed the surface. Press/drag/release all route through
/// the dispatcher's press capture to the SAME closure, so this state is
/// safe here; hover state is NOT (enter and exit straddle a re-render that
/// replaces the closure), which is why hover is handled statelessly above.
private final class DragScratch {
    var isDragging = false
    var grab: (x: Int, y: Int) = (0, 0)
    /// This handle's own handler id, stored back once registration returns it
    /// (the closure needs it, and cannot capture a `let` it is being assigned
    /// to). A click the handle turns out not to want is passed through from
    /// here to the region behind it.
    var handlerID: HitTestRegion.HandlerID?
}

// MARK: - Drop Destination

/// The view wrapper created by ``View/dropDestination(for:action:isTargeted:)``.
///
/// Renders its content and registers its on-screen rectangle as a drop
/// target for payloads of `Payload`. The region's own mouse handler is
/// inert (clicks fall through to the content) — the rectangle exists so the
/// active drag session can hit-test it.
public struct DropDestinationModifier<Content: View, Payload>: View {
    let content: Content
    /// Whether the view takes drops at all. Off, it registers no zone, so a
    /// drag passes over it as over anything else.
    var isEnabled = true
    let action: ([Payload], DropInfo) -> Bool
    let isTargeted: (Bool) -> Void

    public var body: Never {
        fatalError("DropDestinationModifier renders via Renderable")
    }
}

extension DropDestinationModifier: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The keyboard's way to drop here: Paste while the view holds the
        // focus (`TransferKeys`), of what a focused `.draggable` copied, or
        // of text that reads as `Payload`.
        let keys = isEnabled && TransferKeys.applies(in: context)
        let own = keys ? TransferKeys.ownStop(prefix: "dropdestination", propertyIndex: -190, context: context) : nil
        var contentContext = context
        if let own { FocusRegistration.publishIsFocused(own.isFocused, context: context, into: &contentContext) }
        var buffer = TUIView.renderToBuffer(content, context: contentContext)
        guard !context.isMeasuring, isEnabled else { return buffer }
        let action = self.action
        if let own {
            TransferKeys.register(
                "v", focusIDs: TransferKeys.stops(of: buffer, ownID: own.id, context: context), context: context
            ) { event, clipboard in
                let text: String?
                if case .paste(let pasted) = event.key { text = pasted } else { text = clipboard.read() }
                guard let text, !text.isEmpty, let items = clipboard.paste(text, as: Payload.self), !items.isEmpty
                else { return false }
                // Dropped from the keyboard, so at the view's first cell, with
                // no modifiers held and no preview.
                let info = DropInfo(
                    x: 0, y: 0, shift: false, ctrl: false, meta: false, previewX: 0, previewY: 0,
                    previewWidth: 0, previewHeight: 0, payload: DropPayload(items))
                return action(items, info)
            }
        }
        DropZone.install(
            on: &buffer, context: context,
            accepts: { $0 is Payload },
            perform: { payload, info in
                guard let typed = payload as? Payload else { return false }
                return action([typed], info)
            },
            setTargeted: isTargeted)
        return buffer
    }
}

// MARK: - Drop Zone

/// The registration every drop destination makes: its rendered rectangle as
/// a zone the drag session hit-tests, and the target behind it.
package enum DropZone {
    /// Registers `buffer`'s rectangle as a drop target for this frame.
    ///
    /// - Parameters:
    ///   - buffer: The destination's rendered content, which gains the zone's
    ///     region.
    ///   - context: The render context; nothing is registered outside a
    ///     running app (no dispatcher or no session).
    ///   - accepts: Whether a drag carrying this payload can land here.
    ///   - perform: Performs the drop, given the payload and where it landed;
    ///     answers whether the destination took it.
    ///   - setTargeted: Told `true` when an accepted drag moves over the zone,
    ///     `false` when it leaves or drops.
    ///   - hovering: Told the pointer's cell, local to the zone, on every move
    ///     while it is the targeted one.
    ///   - hoveringInfo: Told the same, as the ``DropInfo`` a drop there would
    ///     be handed — for a destination that answers each move, as SwiftUI's
    ///     drop delegate does.
    ///   - proposedOperation: The operation the destination proposes for the
    ///     drag over it, which the preview's badge names; `nil` for none.
    @MainActor
    package static func install(
        on buffer: inout FrameBuffer, context: RenderContext,
        accepts: @escaping (Any) -> Bool,
        perform: @escaping (Any, DropInfo) -> Bool,
        setTargeted: @escaping (Bool) -> Void,
        hovering: ((_ x: Int, _ y: Int) -> Void)? = nil,
        hoveringInfo: ((DropInfo) -> Void)? = nil,
        proposedOperation: (() -> DropOperation?)? = nil
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return }

        // An inert region: it never consumes events itself (so clicks reach
        // the content), but its composited rectangle is the drop zone.
        // INSERTED AT THE FRONT, not appended: the dispatcher routes clicks
        // to the innermost (last-registered) matching region and stops even
        // when the handler declines, so an appended zone would eat every
        // press over its content — a `.draggable` chip INSIDE a drop zone
        // could never start its drag. Fronting the region keeps interactive
        // children clickable (the same fallback-region pattern List and
        // Picker containers use), while drop TARGETING is unaffected — it
        // matches hit ids against the registered targets and skips
        // non-targets, so the zone is still found at any depth.
        let id = dispatcher.registerPassive(in: context) { _ in false }
        buffer.hitTestRegions.insert(contentsOf: buffer.frameHitRegions(handlerID: id), at: 0)

        // The THIRD per-frame write a destination makes. The handler above is
        // replayed and the region travels in the buffer, but the session's
        // target registry is emptied every frame exactly as the handler table
        // is — so a served frame that did not register here left hit-testing
        // finding the id and `resolveTarget` finding nothing behind it. Hence
        // the journalled form.
        // Where a drop at `event` lands, in the destination's local space: the
        // event is absolute, the region offset is known here. The drag is
        // still active while its drop performs, so the preview frame is
        // reportable — localized the same way (effects anchor to the image,
        // not the cursor).
        func info(at event: MouseEvent, carrying payload: Any) -> DropInfo {
            let (dx, dy) = dispatcher.regionOffset(for: id) ?? (0, 0)
            let frame = session.previewFrame() ?? (x: event.x, y: event.y, width: 0, height: 0)
            return DropInfo(
                x: event.x - dx, y: event.y - dy,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                previewX: frame.x - dx, previewY: frame.y - dy,
                previewWidth: frame.width, previewHeight: frame.height,
                payload: DropPayload(payload))
        }
        var target = DragAndDropSession.Target(
            handlerID: id,
            accepts: accepts,
            perform: { payload, event in perform(payload, info(at: event, carrying: payload)) },
            setTargeted: setTargeted,
            proposedOperation: proposedOperation,
            identity: context.identity
        )
        if hovering != nil || hoveringInfo != nil {
            target.hovering = { x, y in
                hovering?(x, y)
                if let hoveringInfo, let event = session.lastAbsoluteEvent, let payload = session.active?.payload {
                    hoveringInfo(info(at: event, carrying: payload))
                }
            }
        }
        session.registerTarget(target, in: context)
    }
}

// MARK: - View Extensions

extension View {
    /// Makes this view draggable within the app, carrying `payload`.
    ///
    /// Press and move to begin the drag: the view's rendered appearance
    /// follows the cursor as a floating preview, and releasing over a
    /// matching ``View/dropDestination(for:action:isTargeted:)`` delivers
    /// the payload (evaluated lazily, at drag start).
    ///
    /// The whole view surface acts as the drag handle, but interactive
    /// children keep working: a press released without movement is delivered
    /// to the child under the cursor as an ordinary click (and hover rides
    /// through likewise), so `Button { … }.draggable(value)` both clicks and
    /// drags — matching SwiftUI. Only genuine drags are consumed.
    ///
    /// From the keyboard (TUI-specific): while the view holds the focus, Copy
    /// (⌘C, through ``EnvironmentValues/commandKey``) copies the payload, and
    /// Paste on a focused ``View/dropDestination(for:isEnabled:action:)`` drops
    /// it there. A view with focus stops of its own answers on those; one with
    /// none is given a stop, and reads ``EnvironmentValues/isFocused`` to show
    /// it.
    ///
    /// Deviation from SwiftUI, forced by the terminal: the payload needs no
    /// `Transferable` conformance (CoreTransferable is Apple-only, and there
    /// is no system pasteboard to marshal through — drags stay inside the
    /// app).
    ///
    /// - Parameter payload: The value delivered on drop, evaluated when the
    ///   drag begins.
    /// - Returns: A draggable view.
    public func draggable<Payload>(
        _ payload: @autoclosure @escaping () -> Payload
    ) -> some View {
        DraggableModifier(content: self, payload: payload, preview: nil)
    }

    /// Makes this view draggable, with a custom drag preview shown at the
    /// cursor instead of the view's own rendered appearance.
    ///
    /// - Parameters:
    ///   - payload: The value delivered on drop, evaluated at drag start.
    ///   - preview: The floating preview view.
    /// - Returns: A draggable view.
    public func draggable<Payload, Preview: View>(
        _ payload: @autoclosure @escaping () -> Payload,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        DraggableModifier(content: self, payload: payload, preview: AnyView(preview()))
    }

    /// Marks this view as a destination for drags carrying `Payload` values.
    ///
    /// While a matching drag hovers over the view, `isTargeted` receives
    /// `true` (and `false` when it leaves or ends) — use it to highlight the
    /// zone. On release, `action` receives the dropped values and a
    /// ``DropInfo`` (the drop cell in the view's local space plus the
    /// modifiers held at release — a deliberate deviation from SwiftUI's
    /// `CGPoint`, since a terminal deals in cells and CAN observe modifiers
    /// throughout a drag); return whether the drop was accepted.
    ///
    /// - Parameters:
    ///   - payloadType: The payload type this destination accepts.
    ///   - action: Performs the drop; returns `true` if the values were taken.
    ///   - isTargeted: Observes whether a compatible drag is over the view.
    /// - Returns: A view that can receive drops.
    public func dropDestination<Payload>(
        for payloadType: Payload.Type = Payload.self,
        action: @escaping ([Payload], DropInfo) -> Bool,
        isTargeted: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        DropDestinationModifier<Self, Payload>(
            content: self, action: action, isTargeted: isTargeted)
    }

    /// Marks this view as a destination for drags carrying `Payload` values,
    /// which it takes while `isEnabled` — SwiftUI's
    /// `dropDestination(for:isEnabled:action:)`.
    ///
    /// ```swift
    /// Color.pink
    ///     .dropDestination(for: String.self, isEnabled: acceptsTitles) { titles, info in
    ///         model.add(titles, at: info.location)
    ///     }
    /// ```
    ///
    /// The action is handed a ``DropInfo`` where SwiftUI's is handed a
    /// ``DropSession``, which TUI has as a value and hands out nowhere yet
    /// (decisions A53); the drop's ``DropInfo/location`` is on both. A
    /// drop the action is called for is taken. From the keyboard (TUI-specific),
    /// Paste (⌘V, or the terminal's own paste) while the view holds the focus
    /// drops what a focused `.draggable` copied, or text that reads as
    /// `Payload`, at the view's first cell. While
    /// `isEnabled` is `false` the view is no destination at all: a drag
    /// passes over it as over anything else.
    ///
    /// - Parameters:
    ///   - payloadType: The payload type this destination accepts.
    ///   - isEnabled: Whether the view takes drops.
    ///   - action: Performs the drop, given the values and where they landed.
    /// - Returns: A view that can receive drops.
    public func dropDestination<Payload>(
        for payloadType: Payload.Type = Payload.self, isEnabled: Bool = true,
        action: @escaping ([Payload], DropInfo) -> Void
    ) -> some View {
        DropDestinationModifier<Self, Payload>(
            content: self, isEnabled: isEnabled,
            action: { values, info in
                action(values, info)
                return true
            },
            isTargeted: { _ in })
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension DraggableModifier: SingleContentWrapper {
    /// Its content's geometry is its own — it registers a drag source over its content, where it is — so a guide
    /// inside it passes unmoved (``SingleContentWrapper/_keepsContentGeometry``).
    public static var _keepsContentGeometry: Bool { true }

    public var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension DropDestinationModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension DropDestinationModifier: DrawsContentUnchanged {}
