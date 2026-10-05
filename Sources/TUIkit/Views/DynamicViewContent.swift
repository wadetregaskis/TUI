//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicViewContent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Dynamic row actions

/// The row-mutation actions a `ForEach` carries so an enclosing editable
/// `List` can discover and wire them — the internal seam behind SwiftUI's
/// `DynamicViewContent` (whose `onMove`/`onDelete` this mirrors).
///
/// The list looks its content up as one of these; a `nil` action means that
/// gesture is unavailable (a delete key does nothing, a row can't be dragged).
@MainActor
protocol DynamicViewContentActions {
    /// The `.onMove(perform:)` reorder action: `(source offsets, destination
    /// offset)`, both measured from the data's start. `nil` if not reorderable.
    var moveAction: ((IndexSet, Int) -> Void)? { get }

    /// The `.onDelete(perform:)` action: the offsets to delete. `nil` if the
    /// rows can't be deleted.
    var deleteAction: ((IndexSet) -> Void)? { get }

    /// The `.dropDestination(for:action:)` insertion action: whether a payload
    /// is accepted, and what to do with it at an index. `nil` if the rows take
    /// no drops.
    var dropInsertionAction: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)? { get }
}

/// The `ForEach` that owns a run of a `List`'s rows, and where that run sits
/// in the list's own row numbering.
///
/// A row's `.onDelete` / `.onMove` belong to the `ForEach` that produced the
/// row — SwiftUI's rule, and the only one under which an offset names a real
/// element — and the offsets those actions take are indices into THAT
/// `ForEach`'s data. In a flat `List { ForEach … }` the two numberings are the
/// same number and the distinction never shows. Inside a `Section` they differ
/// by everything drawn before the section's first item: the section's header,
/// and every row of every earlier section. ``rows``'s `lowerBound` IS that
/// difference — the list row at which the collection's element 0 is drawn.
///
/// One owner per editable `ForEach`, and its rows are contiguous by
/// construction (a `ForEach` draws its elements in order), which is what lets
/// a span stand in for the whole mapping — with ``elements`` saying which
/// element each row draws, for a loop whose rows are several views each
/// (decisions B15): a delete on any of an element's rows removes that element,
/// as SwiftUI's does (measured on macOS 15.8, `D1S/probe2/listdel`: the second
/// view of an element selected, `delete:` hands `.onDelete` that element's
/// offset and both of its rows go).
struct ListRowEditOwner {
    /// The actions the owning `ForEach` carries.
    let actions: any DynamicViewContentActions

    /// The list rows its elements occupy — `row - rows.lowerBound` is a row's
    /// place among them, which ``elements`` maps to the element it draws.
    let rows: Range<Int>

    /// Which element each of ``rows`` draws.
    var elements: ListRowElements = .onePerRow

    /// The offset in the loop's collection of the element row `row` draws.
    func elementOffset(ofRow row: Int) -> Int {
        let place = row - rows.lowerBound
        switch elements {
        case .onePerRow: return place
        case .perElement(let count): return place / max(1, count)
        case .listed(let offsets): return offsets[place]
        }
    }

    /// The offsets of the elements `rows` draw, each once — the rows outside
    /// this owner's span left out, as an offset into another collection would
    /// be wrong.
    func elementOffsets(ofRows rows: some Sequence<Int>) -> IndexSet {
        IndexSet(rows.filter { self.rows.contains($0) }.map(elementOffset(ofRow:)))
    }

    /// Whether every element draws exactly one row, so a row's place IS its
    /// element's offset — what a reorder, which moves rows, needs.
    var isOneRowPerElement: Bool {
        if case .onePerRow = elements { return true }
        return false
    }
}

/// Which element of its `ForEach` each of a ``ListRowEditOwner``'s rows draws.
enum ListRowElements {
    /// One row per element: a row's place among the owner's rows is its
    /// element's offset.
    case onePerRow
    /// The same number of rows from every element — `Group { a; b }`, a row
    /// of two views.
    case perElement(Int)
    /// Each row's element offset, by its place — a loop whose rows make a
    /// number of views only each row knows (an `if` among them, a loop).
    case listed([Int])

    /// The elements a loop's rows draw, from the rows' keys: each element in
    /// turn owns the run of rows carrying its key (``ChildView/keyedAsMember``
    /// keys every view of a row of several by its element) — or `nil` when a
    /// row carries no element's key in that order, and so cannot be attributed.
    @MainActor
    static func listed(rowKeys: [String?], of loop: any KeyedLoop) -> Self? {
        var offsets: [Int] = []
        offsets.reserveCapacity(rowKeys.count)
        var place = 0
        for element in 0..<loop.keyedElementCount {
            let key = loop.keyedRowKey(ofElement: element)
            while place < rowKeys.count, rowKeys[place] == key {
                offsets.append(element)
                place += 1
            }
        }
        return place == rowKeys.count ? .listed(offsets) : nil
    }
}

extension ForEach: DynamicViewContentActions where Content: View {
    var moveAction: ((IndexSet, Int) -> Void)? { onMoveAction }
    var deleteAction: ((IndexSet) -> Void)? { onDeleteAction }
    var dropInsertionAction: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)? {
        dropInsertion
    }
}

// MARK: - ForEach modifiers

extension ForEach where Content: View {
    /// Makes the rows a drop destination that reports WHERE the drop landed —
    /// mirrors SwiftUI's `DynamicViewContent.dropDestination(for:action:)`.
    ///
    /// The difference from the `View` modifier of the same name is the index.
    /// A view-level destination only knows that something was dropped on it; a
    /// row-level one knows which row it was dropped between, so the list can
    /// show a landing slot while the pointer moves and the app can insert at
    /// exactly that place.
    ///
    /// ```swift
    /// List {
    ///     ForEach(tracks, id: \.self) { Text($0.title) }
    ///         .dropDestination(for: Track.self) { index, tracks in
    ///             self.tracks.insert(contentsOf: tracks, at: index)
    ///         }
    /// }
    /// ```
    ///
    /// While a compatible drag is over the rows, the list opens a gap at the
    /// prospective index — the same gap a `.cursor` reorder shows, because it
    /// is the same machinery and it means the same thing.
    ///
    /// - Parameters:
    ///   - payloadType: The payload type these rows accept.
    ///   - action: Inserts the payloads at the given index.
    /// - Returns: A `ForEach` whose list takes drops between its rows.
    public func dropDestination<Payload>(
        for payloadType: Payload.Type = Payload.self,
        action: @escaping (Int, [Payload]) -> Void
    ) -> ForEach {
        var copy = self
        copy.dropInsertion = (
            accepts: { $0 is Payload },
            perform: { index, values in action(index, values.compactMap { $0 as? Payload }) }
        )
        return copy
    }

    /// Sets the deletion action for the dynamic view's rows — mirrors SwiftUI's
    /// `onDelete(perform:)`.
    ///
    /// Inside an editable `List`, pressing **Delete** (or Backspace) on the
    /// focused row calls this action with that row's offset; the closure mutates
    /// the backing collection (typically via `remove(atOffsets:)`). Passing
    /// `nil` makes the rows non-deletable again.
    ///
    /// ```swift
    /// List {
    ///     ForEach(items, id: \.self) { Text($0) }
    ///         .onDelete { items.remove(atOffsets: $0) }
    /// }
    /// ```
    ///
    /// - Note: SwiftUI returns `some DynamicViewContent`; TUIkit returns the
    ///   concrete `ForEach` (it has no `DynamicViewContent` protocol), which
    ///   still chains with ``onMove(perform:)`` since both live on `ForEach`.
    ///
    /// - Parameter action: The delete action, or `nil` to disable deletion.
    /// - Returns: A `ForEach` that reports the delete action to its `List`.
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> ForEach {
        var copy = self
        copy.onDeleteAction = action
        return copy
    }

    /// Sets the move (reorder) action for the dynamic view's rows — mirrors
    /// SwiftUI's `onMove(perform:)`.
    ///
    /// Inside an editable `List`, dragging a row with the mouse reorders it,
    /// committing through this action with the dragged row's source offset and
    /// the destination offset; the closure mutates the backing collection
    /// (typically via `move(fromOffsets:toOffset:)`).
    ///
    /// ```swift
    /// List {
    ///     ForEach(items, id: \.self) { Text($0) }
    ///         .onMove { items.move(fromOffsets: $0, toOffset: $1) }
    /// }
    /// ```
    ///
    /// - Note: As with ``onDelete(perform:)``, TUIkit returns the concrete
    ///   `ForEach` rather than SwiftUI's `some DynamicViewContent`.
    ///
    /// - Parameter action: The reorder action `(source, destination)`.
    /// - Returns: A `ForEach` that reports the move action to its `List`.
    public func onMove(perform action: @escaping (IndexSet, Int) -> Void) -> ForEach {
        var copy = self
        copy.onMoveAction = action
        return copy
    }
}
