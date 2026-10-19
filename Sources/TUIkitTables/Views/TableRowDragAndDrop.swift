//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowDragAndDrop.swift
//
//  Drag and drop on a table's rows: the modifiers that make a row carry a
//  payload out or take a drop onto itself, a loop of rows that takes payloads
//  in between its rows, and the regions a table registers for them. The drop a
//  row takes, `_TableRowDrop`, is in _TableRowDrop.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitLists
import TUIkitView

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import UniformTypeIdentifiers
#endif

/// A loop of rows that takes payloads in between its rows, from
/// `.dropDestination(for:action:)` or `.onInsert(of:perform:)` on a `ForEach`
/// of rows.
struct _TableRowInsertion {
    /// The rows the loop drew, in the table's own numbering.
    var rows: Range<Int>
    /// Whether a drag carrying this payload can be inserted.
    let accepts: (Any) -> Bool
    /// Inserts payloads at an offset into the loop's own collection.
    let perform: (Int, [Any]) -> Void
}

extension _TableRowList {
    /// One table-wide insertion made of every loop's: a drop between two rows
    /// goes to the loop whose rows it falls among — its first offset to the
    /// slot above the loop's first row, its last to the slot after its last —
    /// at that loop's own offset, as SwiftUI's `onInsert` offsets are. A slot
    /// no loop that takes the payload reaches takes nothing.
    var insertionAction: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)? {
        let insertions = self.insertions
        guard !insertions.isEmpty else { return nil }
        return (
            accepts: { payload in insertions.contains { $0.accepts(payload) } },
            perform: { index, payloads in
                guard
                    let owner = insertions.first(where: { insertion in
                        insertion.rows.lowerBound <= index && index <= insertion.rows.upperBound
                            && payloads.contains(where: insertion.accepts)
                    })
                else { return }
                owner.perform(index - owner.rows.lowerBound, payloads.filter(owner.accepts))
            }
        )
    }
}

// MARK: - Row modifiers

/// What `.draggable(_:)` and `.itemProvider(_:)` record on a row.
struct _DraggableTableRowModifier: _TableRowTraitModifier {
    let payload: () -> Any?

    func apply(to traits: inout _TableRowTraits) {
        // The modifier nearest the row has already spoken.
        if traits.dragPayload == nil { traits.dragPayload = payload }
    }
}

/// What `.dropDestination(for:action:)` records on a row.
struct _DropDestinationTableRowModifier: _TableRowTraitModifier {
    let drop: _TableRowDrop

    func apply(to traits: inout _TableRowTraits) {
        traits.dropActions.append(drop)
    }
}

/// A modifier that a loop of table rows uses to take payloads in between its
/// rows — what ``DynamicTableRowContent/dropDestination(for:action:)`` and
/// `onInsert(of:perform:)` return.
public struct OnInsertTableRowModifier: _TableRowContentModifier, _TableRowListModifier {
    /// Whether a drag carrying this payload can be inserted.
    let accepts: (Any) -> Bool
    /// Inserts payloads at an offset into the loop's collection.
    let perform: (Int, [Any]) -> Void

    /// The modifier, as SwiftUI's row modifiers describe themselves.
    public var body: some _TableRowContentModifier { self }

    func apply<Value>(to rows: inout _TableRowList<Value>) {
        rows.addInsertion(accepts: accepts, perform: perform)
    }
}

extension TableRowContent {
    /// Activates this row as the source of a drag and drop operation.
    ///
    /// Press a row and move to begin the drag: the row's own line follows the
    /// pointer, and releasing over a destination that takes the payload
    /// delivers it — a view's `.dropDestination(for:action:isTargeted:)`,
    /// another row's ``TableRowContent/dropDestination(for:action:)``, or a table or list
    /// that inserts it. A press released without moving is a click, which
    /// selects the row as ever. The payload is evaluated when the drag begins.
    ///
    /// As for every TUIkit drag, the payload needs no `Transferable`
    /// conformance — the drag never leaves the app. A draggable row is not
    /// picked up for a table's own `onMove(_:)` reorder: the press carries its
    /// payload instead.
    ///
    /// - Parameter payload: The value the drag carries, evaluated when the
    ///   drag begins.
    public func draggable<T>(_ payload: @autoclosure @escaping () -> T) -> some TableRowContent<TableRowValue> {
        // `Any?`, so a payload that is an optional holding nothing — what an
        // `itemProvider` vending `nil` is too — starts no drag.
        ModifiedContent(content: self, modifier: _DraggableTableRowModifier(payload: { payload() as Any? }))
    }

    /// Defines the entire row as a destination of a drag and drop operation
    /// that handles the dropped content with the closure that you specify.
    ///
    /// While a drag carrying a payload of `payloadType` is over the row, the
    /// row is drawn as a selected row is, so the place it would land shows;
    /// releasing there hands the action the dropped values.
    ///
    /// - Parameters:
    ///   - payloadType: The type of objects you want the row to receive.
    ///   - action: A closure that takes the dropped content.
    public func dropDestination<T>(
        for payloadType: T.Type = T.self, action: @escaping ([T]) -> Void
    ) -> some TableRowContent<TableRowValue> {
        let drop = _TableRowDrop(
            accepts: { $0 is T }, perform: { action($0.compactMap { $0 as? T }) })
        return ModifiedContent(content: self, modifier: _DropDestinationTableRowModifier(drop: drop))
    }
}

extension DynamicTableRowContent {
    /// Sets the insert action for the dynamic table rows: a drop of `payloadType`
    /// values between two of the loop's rows inserts them there.
    ///
    /// While such a drag is over the table, the rows open a gap where it would
    /// land, as a table's own ``Table/dropDestination(for:action:)`` does; on
    /// release `action` is told the offset into this loop's collection —
    /// counted from the loop's first row, whatever rows the table draws before
    /// it — and the dropped values. In a hierarchical table a loop among the
    /// roots or an open branch's rows takes the drops between its rows, a slot
    /// at the end of a branch's rows going to the deepest loop there that
    /// takes the payload; a loop under a closed branch takes none.
    ///
    /// - Parameters:
    ///   - payloadType: The type of the dropped values.
    ///   - action: Inserts the values at the offset.
    public func dropDestination<T>(
        for payloadType: T.Type = T.self, action: @escaping ([T], Int) -> Void
    ) -> ModifiedContent<Self, OnInsertTableRowModifier> {
        ModifiedContent(
            content: self,
            modifier: OnInsertTableRowModifier(
                accepts: { $0 is T }, perform: { offset, values in action(values.compactMap { $0 as? T }, offset) }))
    }
}

#if canImport(UniformTypeIdentifiers)
    /// A modifier that vends an item provider for a table row — what
    /// ``TableRowContent/itemProvider(_:)`` returns.
    public struct ItemProviderTableRowModifier: _TableRowContentModifier, _TableRowTraitModifier {
        /// Vends the provider when a drag begins.
        let action: (() -> NSItemProvider?)?

        /// The modifier, as SwiftUI's row modifiers describe themselves.
        public var body: some _TableRowContentModifier { self }

        func apply(to traits: inout _TableRowTraits) {
            guard traits.dragPayload == nil, let action else { return }
            traits.dragPayload = { action() }
        }
    }

    extension TableRowContent {
        /// Provides a closure that vends the drag representation for a
        /// particular data element: what dragging the row carries.
        ///
        /// A `nil` action, or one that vends `nil`, starts no drag. The drag is
        /// within the app, as every TUIkit drag is; an `onDrop(of:)` whose types
        /// the provider conforms to, or a loop's `onInsert(of:perform:)`, takes
        /// it.
        ///
        /// - Parameter action: Vends the provider when a drag begins.
        public func itemProvider(
            _ action: (() -> NSItemProvider?)?
        ) -> ModifiedContent<Self, ItemProviderTableRowModifier> {
            ModifiedContent(content: self, modifier: ItemProviderTableRowModifier(action: action))
        }
    }

    extension DynamicTableRowContent {
        /// Sets the insert action for the dynamic table rows: a drag carrying
        /// items of `supportedContentTypes` dropped between two of the loop's
        /// rows inserts them there.
        ///
        /// See ``DynamicTableRowContent/dropDestination(for:action:)`` for the gap and the offset. A
        /// drag from `onDrag(_:)` or ``TableRowContent/itemProvider(_:)``
        /// carries its provider; one from `draggable(_:)` with a string or a URL
        /// carries it as a provider of text or a URL.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the rows take.
        ///   - action: Inserts the providers' items at the offset.
        public func onInsert(
            of supportedContentTypes: [UTType], perform action: @escaping (Int, [NSItemProvider]) -> Void
        ) -> ModifiedContent<Self, OnInsertTableRowModifier> {
            ModifiedContent(
                content: self,
                modifier: OnInsertTableRowModifier(
                    accepts: { !ItemProviders.of($0, conformingTo: supportedContentTypes).isEmpty },
                    perform: { offset, payloads in
                        action(offset, payloads.flatMap { ItemProviders.of($0, conformingTo: supportedContentTypes) })
                    }))
        }
    }
#endif

// MARK: - The regions a table registers

/// The drag handles and drop zones of a table's drawn rows.
enum _TableRowDragRegions {
    /// A drawn row: which row of the table, and where its lines are in the
    /// table's buffer.
    struct DrawnRow {
        let index: Int
        let y: Int
        let height: Int
    }

    /// Registers, over each drawn row its traits ask for: a drag handle that
    /// carries the row's payload out, with the row's own line as the picture,
    /// and a drop zone that hands the row the drops it takes, the row drawn
    /// as selected while one is over it (``ItemListHandler/rowDropTarget``).
    ///
    /// The handles go in last, ahead of the table's own region, so a press on
    /// such a row is the drag's; a press released without moving passes
    /// through to the table as a click. The zones go in first, behind it, so
    /// they never take a press — a drag finds a zone at any depth.
    @MainActor
    static func register<ID: Hashable>(
        to buffer: inout FrameBuffer,
        rows: [DrawnRow],
        traits: [_TableRowTraits],
        handler: ItemListHandler<ID>,
        columns: Range<Int>,
        context: RenderContext,
        preview: @escaping @MainActor (Int) -> [String]?
    ) {
        guard context.environment.isEnabled, !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return }
        let drawing = HandlerDrawing(context)
        let anchor = context.environment.dragPreviewAnchor
        for row in rows where traits.indices.contains(row.index) {
            let rowTraits = traits[row.index]
            if let payload = rowTraits.dragPayload {
                var surface = FrameBuffer(emptyWithWidth: columns.count, height: max(1, row.height))
                let index = row.index
                _DragHandle.install(
                    on: &surface, context: context, dispatcher: dispatcher,
                    onDragBegin: { _, grab in
                        guard let value = payload() else { return }
                        let frames = preview(index) ?? []
                        session.begin(
                            payload: value, preview: FrameBuffer(lines: [frames.last ?? ""]),
                            morph: frames.map { FrameBuffer(lines: [$0]) },
                            grabX: grab.x, grabY: grab.y, anchor: anchor)
                    },
                    onDragMove: { _ in session.dragMoved() },
                    onDragEnd: { _ in _ = session.performDrop() })
                buffer.hitTestRegions += surface.hitTestRegions.map { $0.shifted(byX: columns.lowerBound, y: row.y) }
            }
            let drops = rowTraits.dropActions
            guard !drops.isEmpty else { continue }
            var zone = FrameBuffer(emptyWithWidth: columns.count, height: max(1, row.height))
            let index = row.index
            let target = { handler.rowDropTarget }
            DropZone.install(
                on: &zone, context: context,
                accepts: { payload in drops.contains { $0.accepts(payload) } },
                perform: { payload, _ in
                    for drop in drops where drop.accepts(payload) { drop.perform([payload]) }
                    return true
                },
                setTargeted: { targeted in
                    drawing.reportingChanges(to: target) {
                        if targeted {
                            handler.rowDropTarget = index
                        } else if handler.rowDropTarget == index {
                            handler.rowDropTarget = nil
                        }
                    }
                })
            buffer.hitTestRegions.insert(
                contentsOf: zone.hitTestRegions.map { $0.shifted(byX: columns.lowerBound, y: row.y) }, at: 0)
        }
    }
}
