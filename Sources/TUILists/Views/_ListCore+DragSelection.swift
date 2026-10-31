//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+DragSelection.swift
//
//  A `List`'s half of dragging a selection: a `.draggable` row that is one of
//  several selected carries them all, in the list's order, as a Mac's table
//  does; Shift held as the drag starts extends the selection to that row first,
//  as a Shift-click does (Finder). The owner's ruling DRAG-SELECTION,
//  2026-10-27: "we do it the Mac way". Copy on such a row gathers them the same
//  way.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

extension _ListCore {
    /// Starts the gathering for a drag that started on one of this list's rows,
    /// the frame after it began, as the rows are extracted: every row drawn from
    /// here notes its `.draggable`'s payload
    /// (`DragAndDropSession.beginGatheringPayloads(for:)`).
    func armSelectionGathering(context: RenderContext) {
        guard multiSelection != nil, !context.isMeasuring, let session = context.environment.dragAndDropSession,
            session.wantsSelectionGathered(by: context.identity)
        else { return }
        session.beginGatheringPayloads(for: context.identity)
    }

    /// Starts the gathering for a Copy of the selection, the frame after the
    /// key (``RowDragOffer/selectionCopy``): as a drag's, but it needs the
    /// handler, which holds the request.
    func armSelectionCopy(handler: ItemListHandler<SelectionValue>, context: RenderContext) {
        guard handler.rowDragOffer.selectionCopy != nil, !context.isMeasuring,
            let session = context.environment.dragAndDropSession, session.gatheringOwner == nil
        else { return }
        session.beginGatheringPayloads(for: context.identity)
    }

    /// Ends this list's gathering, whatever the rows came to: an empty list
    /// never reaches ``gatherDraggedSelection(source:handler:context:)``.
    func endSelectionGathering(context: RenderContext) {
        guard let session = context.environment.dragAndDropSession, session.gatheringOwner == context.identity
        else { return }
        _ = session.endGatheringPayloads()
    }

    /// Hands the drag in flight the selection it was started from, on the frame
    /// after it began: the payloads the rows noted as they drew
    /// (`DragAndDropSession.beginGatheringPayloads(for:)`, armed in
    /// `renderFrame`), the selected rows outside the window drawn here to note
    /// theirs, in the list's order.
    ///
    /// A drag from a row that is not selected, or the only one selected, keeps
    /// its own payload. Rows are drawn off the window only on this one frame,
    /// and only the selected ones: a list of 50,000 rows with three selected
    /// draws three.
    ///
    /// A Copy of the selection waiting on this frame is answered first
    /// (``copySelection(source:handler:session:)``), and a drag begun in the
    /// same frame gathers on the next.
    func gatherDraggedSelection(
        source: RowSource<SelectionValue>, handler: ItemListHandler<SelectionValue>, context: RenderContext
    ) {
        guard !context.isMeasuring, let session = context.environment.dragAndDropSession,
            session.gatheringOwner == context.identity
        else { return }
        if handler.rowDragOffer.selectionCopy != nil {
            copySelection(source: source, handler: handler, session: session)
        } else {
            gatherSelection(source: source, handler: handler, session: session, context: context)
        }
    }

    /// Fills the clipboard a Copy left waiting with every selected row's
    /// payload, in the list's order. The selection is read now, a frame after
    /// the key, which nothing can have moved between.
    private func copySelection(
        source: RowSource<SelectionValue>, handler: ItemListHandler<SelectionValue>, session: DragAndDropSession
    ) {
        let clipboard = handler.rowDragOffer.selectionCopy
        handler.rowDragOffer.selectionCopy = nil
        let selected = drawSelectedRows(source: source, handler: handler)
        let noted = session.endGatheringPayloads()
        let values = selected.compactMap { draggable(ofRow: $0, in: source, noted: noted)?.draggable.payload() }
        if !values.isEmpty { clipboard?.copy(values) }
    }

    /// Every selected row, in the list's order, drawn so that each one's
    /// `.draggable` notes its payload; a row the window drew already has, and
    /// its render is kept.
    private func drawSelectedRows(
        source: RowSource<SelectionValue>, handler: ItemListHandler<SelectionValue>
    ) -> [Int] {
        let selection = handler.multiSelection?.wrappedValue ?? []
        let selected = (0..<source.count).filter { index in handler.id(at: index).map(selection.contains) ?? false }
        for index in selected { _ = source.row(at: index).buffer }
        return selected
    }

    /// The `.draggable` noted in the row at `index`.
    private func draggable(
        ofRow index: Int, in source: RowSource<SelectionValue>, noted: [ViewIdentity: DragAndDropSession.NotedDraggable]
    ) -> (identity: ViewIdentity, draggable: DragAndDropSession.NotedDraggable)? {
        guard let row = source.content(at: index).rowIdentity else { return nil }
        return noted.first { $0.key == row || row.isAncestor(of: $0.key) }.map { ($0.key, $0.value) }
    }

    /// ``gatherDraggedSelection(source:handler:context:)``'s drag.
    private func gatherSelection(
        source: RowSource<SelectionValue>, handler: ItemListHandler<SelectionValue>, session: DragAndDropSession,
        context: RenderContext
    ) {
        guard let drag = session.active, let selectionBinding = handler.multiSelection else { return }
        // The row the drag started in: among those drawn, since a press lands on
        // one.
        let grabbed = handler.visibleRange.first { index in
            index < source.count
                && (source.content(at: index).rowIdentity.map { session.isDragSource(within: $0) } ?? false)
        }
        guard let grabbed, let grabbedID = handler.id(at: grabbed) else {
            _ = session.endGatheringPayloads()
            session.carriesNoSelection()
            return
        }
        if drag.startedWithShift { handler.extendSelection(to: grabbed) }
        let selection = selectionBinding.wrappedValue
        guard selection.count > 1, selection.contains(grabbedID) else {
            _ = session.endGatheringPayloads()
            session.carriesNoSelection()
            return
        }
        let selected = drawSelectedRows(source: source, handler: handler)
        let noted = session.endGatheringPayloads()
        var items: [Any] = []
        var pictures: [FrameBuffer] = []
        var grabbedItem = 0
        var sources = Set<ViewIdentity>()
        for index in selected {
            guard let (identity, draggable) = draggable(ofRow: index, in: source, noted: noted) else { continue }
            if index == grabbed { grabbedItem = items.count }
            items.append(draggable.payload())
            pictures.append(draggable.preview)
            sources.insert(identity)
        }
        guard items.count > 1 else {
            session.carriesNoSelection()
            return
        }
        // The grabbed row's own picture is the one its drag began with: drawn
        // this frame, it is already the blank it leaves in the list.
        let picture = DragAndDropSession.selectionPicture(
            count: items.count, grabbed: grabbedItem, limit: context.environment.dragPreviewRowLimit,
            grabbedFrames: drag.pictureFrames, frames: { [pictures[$0]] })
        session.carrySelection(items, sources: sources, picture: picture)
    }
}
