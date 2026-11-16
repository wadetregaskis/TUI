//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedOutlineListRows.swift
//
//  An outline's rows as a `List` reads them, windowed: how many, what each is
//  called, and a row's box made only when the list walks to it. Here rather
//  than beside `OutlineGroup` so that a `Section` holding an outline can hand
//  its rows to the list windowed, as the outline alone does.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - The rows, windowed

/// An outline's rows as a `List` reads them: how many, what each is called,
/// and a row's box, made only when asked for.
///
/// What ``WindowedListRowExtractor`` is to a `ForEach`, for a view whose row
/// count needs a context to answer: an outline's rows depend on which of its
/// branches are open, which is state at its identity.
package struct OutlineListRows<RowID: Hashable> {
    /// The rows that show.
    package let count: Int

    /// The id the list knows row `index` by, or `nil` where neither the node's
    /// id nor the index can be one.
    package let rowID: (Int) -> RowID?

    /// Row `index`'s box, made on the call.
    package let make: (Int) -> LazyListRowContent

    package init(count: Int, rowID: @escaping (Int) -> RowID?, make: @escaping (Int) -> LazyListRowContent) {
        self.count = count
        self.rowID = rowID
        self.make = make
    }

    /// Every row, each with its box, in order: what the eager rows are. A row
    /// whose id the list cannot name is left out, as the eager rows leave it.
    @MainActor
    package var all: [ListRow<RowID>] {
        (0..<count).compactMap { index in rowID(index).map { ListRow(id: $0, content: make(index)) } }
    }

    /// These rows, each drawn through `transform`.
    @MainActor
    package func mappingBuffers(_ transform: @escaping (FrameBuffer) -> FrameBuffer) -> Self {
        let make = make
        return Self(count: count, rowID: rowID, make: { make($0).mapped(transform) })
    }
}

/// A view whose list rows are windowed but need a context to count:
/// `OutlineGroup`.
@MainActor
package protocol WindowedOutlineListRows {
    /// The rows, or `nil` when the list's ids cannot name them (row 0 answers
    /// to neither the node's id nor its index), and the eager path, which
    /// draws such rows as it can, takes them instead.
    func windowedListRows<RowID: Hashable>(context: RenderContext) -> OutlineListRows<RowID>?
}
