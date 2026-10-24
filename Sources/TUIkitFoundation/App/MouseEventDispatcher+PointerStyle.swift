//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseEventDispatcher+PointerStyle.swift
//
//  The pointer's shape: the regions `.pointerStyle(_:)` files, the shapes
//  controls file for their own regions, and which one is under the pointer.
//  The run loop asks for the answer and has the terminal show it (OSC 22,
//  `Terminal.showPointerShape(_:)` in TUIkitApp).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitTerminalHost
import TUIkitView

extension MouseEventDispatcher {
    /// Files a region of the view `context` is rendering that shows `shape`
    /// under the pointer, and returns its id, for the region the caller puts
    /// in its buffer, in front of `contentRegions`: its content's.
    ///
    /// No handler is filed: the region hears nothing, is passed over by every
    /// event and by the hover machine (``matchingRegions(at:y:includingWheelOnly:)``),
    /// and so asks for no frame as the pointer crosses it. It is read only by
    /// ``pointerShapeUnderPointer()``.
    ///
    /// The regions among `contentRegions` the shape is read from are noted as
    /// inside this one (``pointerShapeEnclosures``): a nested style's region
    /// and an overlapping one's both come after it front to back, and only
    /// this tells them apart.
    ///
    /// Recorded for a value memo, as a handler's registration is, so a served
    /// subtree files it again under the id baked into its stored buffer.
    @MainActor
    package func registerPointerStyle(
        _ shape: PointerShape, over contentRegions: [HitTestRegion], in context: RenderContext
    ) -> HitTestRegion.HandlerID {
        let id = handlerIDs.id(registeredIn: context)
        guard !context.isMeasuring else { return id }
        let enclosed = pointerShapeRegions(among: contentRegions)
        fileStyle(shape, as: id, enclosing: enclosed)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return id }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.pointerStyleKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.fileStyle(shape, as: id, enclosing: enclosed)
            })
        return id
    }

    /// Files the style region `id`, and notes it as enclosing `enclosed`: the
    /// one write, shared by the live registration and a memo's replay of it.
    private func fileStyle(_ shape: PointerShape, as id: HitTestRegion.HandlerID, enclosing enclosed: [HitTestRegion.HandlerID]) {
        pointerStyleRegions[id] = shape
        noteEnclosure(by: id, of: enclosed)
    }

    /// Lets the pointer's shape be read through the region of the control
    /// `id` names to the content it covers, whose regions are
    /// `contentRegions`, wherever that content holds a style or a control's
    /// own shape.
    ///
    /// For the wrappers that take events for their content without hiding
    /// it — `.draggable` (`_DragHandle`), `.focusable()`'s click-to-focus,
    /// `.onMouseEvent`: each files a region over the whole of its content,
    /// after it, so front to back it comes first, and
    /// as the control under the pointer it covered every style inside it.
    /// `Image(…).pointerStyle(.grabIdle).draggable(item)` showed nothing. A
    /// control that draws its content as its own — a `Button`'s label — does
    /// not call this, and covers what it draws (decisions O12, B-O12-2).
    ///
    /// The caller passes its content's regions before it appends its own.
    /// Recorded for a value memo beside the registration it follows.
    @MainActor
    package func fileSeeThroughPointerShapes(
        for id: HitTestRegion.HandlerID, over contentRegions: [HitTestRegion], in context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        let enclosed = pointerShapeRegions(among: contentRegions)
        guard !enclosed.isEmpty else { return }
        fileSeeThroughWrapper(id, enclosing: enclosed)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.seeThroughWrapperKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.fileSeeThroughWrapper(id, enclosing: enclosed)
            })
    }

    /// Files `id` as a see-through wrapper enclosing `enclosed`, live or
    /// replayed.
    private func fileSeeThroughWrapper(_ id: HitTestRegion.HandlerID, enclosing enclosed: [HitTestRegion.HandlerID]) {
        pointerShapeWrappers.insert(id)
        noteEnclosure(by: id, of: enclosed)
    }

    /// Notes that each of `enclosed` is inside the view of the style or the
    /// see-through wrapper `id` names.
    private func noteEnclosure(by id: HitTestRegion.HandlerID, of enclosed: [HitTestRegion.HandlerID]) {
        for inner in enclosed { pointerShapeEnclosures[inner, default: []].append(id) }
    }

    /// The ids among `regions` that the pointer's shape is read from: the
    /// styles', the shaped controls' and the see-through wrappers'. Nothing
    /// at all while no style or shape is filed, which is every frame of a
    /// page with none on it.
    private func pointerShapeRegions(among regions: [HitTestRegion]) -> [HitTestRegion.HandlerID] {
        guard !pointerStyleRegions.isEmpty || !controlPointerShapes.isEmpty else { return [] }
        return regions.compactMap { region in
            let id = region.handlerID
            let read = pointerStyleRegions[id] != nil || controlPointerShapes[id] != nil
                || pointerShapeWrappers.contains(id)
            return read ? id : nil
        }
    }

    /// Files `shape` as the one the control whose handler `id` names shows
    /// under the pointer, unless a style in front of it asks for another: the
    /// I-beam over a text field. For TUIkit's own controls, and only where
    /// the terminal is trusted to put its pointer back
    /// (``TerminalFeatures/controlPointerShapes``): elsewhere this does
    /// nothing, so a control calls it unasked.
    ///
    /// Asks for motion reporting too, as `.pointerStyle(_:)` does: a shape
    /// shows where the pointer rests, and only motion reporting says where
    /// that is. The controls that ask for it to light under the pointer had
    /// it anyway, but a text editor, a split view's divider and a table's
    /// column gap do not: alone on a page, theirs showed only mid-drag.
    ///
    /// Recorded for a value memo, as the handler's registration beside it is.
    @MainActor
    package func fileControlPointerShape(
        _ shape: PointerShape, for id: HitTestRegion.HandlerID, in context: RenderContext
    ) {
        guard context.environment.terminalFeatures.controlPointerShapes, !context.isMeasuring else { return }
        fileControlShape(shape, for: id)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.controlPointerShapeKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.fileControlShape(shape, for: id)
            })
    }

    /// Files a control's own shape and the motion reporting it needs: what a
    /// render and a memo's replay of it both do.
    private func fileControlShape(_ shape: PointerShape, for id: HitTestRegion.HandlerID) {
        controlPointerShapes[id] = shape
        requestFeature(.motion)
    }

    /// The journal kind of a pointer style's region.
    static let pointerStyleKind = EffectJournal.Kind("pointerStyle")

    /// The journal kind of a control's own pointer shape.
    static let controlPointerShapeKind = EffectJournal.Kind("controlPointerShape")

    /// The journal kind of a wrapper the pointer's shape is read through.
    static let seeThroughWrapperKind = EffectJournal.Kind("pointerShapeSeeThrough")

    /// The shape the pointer should have where it rests, or `nil` for the
    /// terminal's own: resolved again only once the pointer has moved or the
    /// regions have, so the run loop can ask after every batch of input.
    ///
    /// `nil` while where the pointer rests is not known (``restingPosition``):
    /// before it has moved, once it has left the window, and from a suspend
    /// until it moves again.
    package func pointerShapeUnderPointer() -> PointerShape? {
        guard pointerShapeIsStale else { return resolvedPointerShape }
        pointerShapeIsStale = false
        if pointerStyleRegions.isEmpty && controlPointerShapes.isEmpty {
            resolvedPointerShape = nil
        } else {
            resolvedPointerShape = restingPosition.flatMap { resolvePointerShape(at: $0.x, y: $0.y) }
        }
        return resolvedPointerShape
    }

    /// The shape at a point: the innermost style on the view in front there,
    /// or, with none, the control's own shape.
    ///
    /// Read as the hover machine reads its observers (``resolveHover(at:y:)``):
    /// the regions on the point front to back, a hover observer seen through,
    /// until the first other region — the control under the pointer, which
    /// covers everything behind it. So a page's style under a sheet's
    /// backdrop, an open menu, or a button overlaid on it shows nothing, and a
    /// style on a container reaches every control in it.
    ///
    /// A style is seen through too, but only into its own view: a wrapper
    /// files its region after its content's, so front to back a style comes
    /// before the styles nested in it — and the innermost of those wins, as a
    /// style set on a view inside another's does in SwiftUI. But a view in
    /// front of another files its regions after it too, and so comes BEFORE
    /// it front to back: read by the order alone, the style behind an
    /// overlay, a `ZStack`'s back layer or a `.background` passed for the
    /// innermost, and won. So the walk goes on past a style only into what
    /// that style's view holds (``pointerShapeEnclosures``), and the first
    /// region outside it is behind it: the end of the walk. A see-through
    /// wrapper (``fileSeeThroughPointerShapes(for:over:in:)``) is gone into
    /// the same way: a control, but one that covers only what is behind it,
    /// not what it wraps.
    ///
    /// A style the app set beats the control's own shape, even one set
    /// further out: the app asked for it, and the control's is TUIkit's
    /// guess (decisions O12, B-O12-2).
    func resolvePointerShape(at x: Int, y: Int) -> PointerShape? {
        var styled: PointerShape?
        // The innermost see-through wrapper's own shape, should nothing
        // inside it have one.
        var wrapped: PointerShape?
        // The innermost style or see-through wrapper the walk has gone into:
        // what follows it front to back is inside its view, or behind it.
        var scope: HitTestRegion.HandlerID?
        for region in regions.reversed() where !region.isGeometryMarker && region.contains(x: x, y: y) {
            let id = region.handlerID
            let style = pointerStyleRegions[id]
            let seesThrough = style == nil && pointerShapeWrappers.contains(id)
            if style == nil, !seesThrough,
                hoverObserverIDs.contains(id) || isWheelHandler(id) || id == .selectionInterior { continue }
            if let scope, pointerShapeEnclosures[id]?.contains(scope) != true { break }
            if let style {
                styled = style
            } else if seesThrough {
                wrapped = controlPointerShapes[id] ?? wrapped
            } else {
                return styled ?? controlPointerShapes[id] ?? wrapped
            }
            scope = id
        }
        return styled ?? wrapped
    }
}
