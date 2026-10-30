//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+DragSelection.swift
//
//  A `List`'s half of dragging a selection: a `.draggable` row that is one of
//  several selected carries them all, in the list's order, as a Mac's table
//  does; Shift held as the drag starts extends the selection to that row first,
//  as a Shift-click does (Finder). The owner's ruling DRAG-SELECTION,
//  2026-10-27: "we do it the Mac way".
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
    func gatherDraggedSelection(
        source: RowSource<SelectionValue>, handler: ItemListHandler<SelectionValue>, context: RenderContext
    ) {
        guard !context.isMeasuring, let session = context.environment.dragAndDropSession,
            session.gatheringOwner == context.identity, let drag = session.active,
            let selectionBinding = handler.multiSelection
        else { return }
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
        let selected = (0..<source.count).filter { index in handler.id(at: index).map(selection.contains) ?? false }
        // Drawn, so each one's `.draggable` notes its payload; a row the window
        // drew already has, and its render is kept.
        for index in selected { _ = source.row(at: index).buffer }
        let noted = session.endGatheringPayloads()
        var items: [Any] = []
        var pictures: [FrameBuffer] = []
        var grabbedItem = 0
        var sources = Set<ViewIdentity>()
        for index in selected {
            guard let row = source.content(at: index).rowIdentity,
                let (identity, draggable) = noted.first(where: { $0.key == row || row.isAncestor(of: $0.key) })
            else { continue }
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
