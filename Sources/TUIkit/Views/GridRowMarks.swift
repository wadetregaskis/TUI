//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GridRowMarks.swift
//
//  Where one grid row ends and the next begins, once rows are flattened into
//  their container's children.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Row Marks

/// What a ``GridRow`` tells the grid about each of its cells once the row has
/// been flattened into the grid's children: whether the cell starts a row, and
/// the row's vertical alignment.
///
/// A plain value, equal on every walk: a per-walk token would change every
/// frame and defeat every cell's memo.
struct GridRowMark: Equatable {
    /// Whether this cell is the row's first.
    let startsRow: Bool

    /// The row's vertical alignment override, if it set one.
    let alignment: VerticalAlignment?
}

/// A view carrying a ``GridRowMark``.
@MainActor
protocol GridRowMarking {
    var gridRowMark: GridRowMark { get }
}

/// A grid row's cell, marked — the wrapper ``GridRow`` puts round each cell it
/// hands to its container. Renders exactly as its content, and passes every
/// other question about its content through: layout values (a cell's span,
/// anchor and column alignment), an explicit `.id(_:)`, a guide, a z-index, a
/// container value.
struct _GridRowMarkView<Content: View>: View {
    let mark: GridRowMark
    let content: Content

    var body: some View {
        content
    }

    /// Size-neutral, so a guide inside the cell is the cell's.
    static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension _GridRowMarkView: GridRowMarking {
    var gridRowMark: GridRowMark { mark }
}

extension _GridRowMarkView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

extension _GridRowMarkView: ContentRewrapping {
    func rewrapping<V: View>(_ view: V) -> any View {
        _GridRowMarkView<V>(mark: mark, content: view)
    }
}

extension _GridRowMarkView: LayoutValueProviding {
    func layoutValue(for key: ObjectIdentifier) -> Any? {
        (content as? LayoutValueProviding)?.layoutValue(for: key)
    }
}

extension _GridRowMarkView: ExplicitIDProviding {
    var explicitIDKey: String? {
        (content as? ExplicitIDProviding)?.explicitIDKey
    }
}

extension ChildView {
    /// The mark this child carries as a flattened grid row's cell, read
    /// through any modifiers written on the row — they wrap each cell outside
    /// its mark — or `nil` for a child that is not one.
    var gridRowMark: GridRowMark? {
        throughWrappers(wrappedView, as: (any GridRowMarking).self)?.gridRowMark
    }
}

// MARK: - Rows That Arrive Whole

/// The cells of `child` when it is a grid row that arrived whole rather than
/// flattened — a `ForEach` row, which a loop hands over one child per element
/// — resolved under the row's own identity and pinned there, or `nil` for any
/// other child.
///
/// Through `ForEach`'s row memo, whose TYPE is asked first, so only a row type
/// is built.
@MainActor
func wholeGridRow(
    _ child: ChildView, context: RenderContext
) -> (cells: [ChildView], alignment: VerticalAlignment?)? {
    let provider: GridRowProviding
    if let row = child.wrappedView as? GridRowProviding {
        provider = row
    } else if child.identityChildKey != nil,
        let memo = child.wrappedView as? any _ValueMemoWrapping,
        memo.memoizedContentType is any GridRowProviding.Type,
        let row = memo.memoizedContent as? GridRowProviding
    {
        provider = row
    } else {
        return nil
    }
    let rowContext = child.renderContext(under: context)
    let cells = provider.gridCells(context: rowContext).map {
        $0.pinningIdentity(to: rowContext.identity)
    }
    return (cells, provider.rowAlignment)
}

/// `children` with every grid row that arrived whole taken apart into its
/// cells, marked as a flattened row's are, each with the index of the child it
/// came from; `nil` when no child was a whole row.
///
/// What a layout that lays cells out — `GridLayout`, and the stack layouts an
/// `AnyLayout` switches it with — sees, so a `ForEach` of rows is cells under
/// every one of them and keeps each cell's `@State` across the switch.
@MainActor
func expandingWholeGridRows(
    _ children: [ChildView], context: RenderContext
) -> (children: [ChildView], sourceIndices: [Int])? {
    var expanded: [ChildView] = []
    var sourceIndices: [Int] = []
    var expandedAny = false
    for (index, child) in children.enumerated() {
        guard child.identityChildKey != nil, let row = wholeGridRow(child, context: context) else {
            expanded.append(child)
            sourceIndices.append(index)
            continue
        }
        expandedAny = true
        for (offset, cell) in row.cells.enumerated() {
            expanded.append(
                cell.rewrapped(
                    by: _GridRowMarkView(
                        mark: GridRowMark(startsRow: offset == 0, alignment: row.alignment),
                        content: EmptyView())))
            sourceIndices.append(index)
        }
    }
    return expandedAny ? (expanded, sourceIndices) : nil
}

/// A layout that lays out a grid row's cells rather than the row: the cells of
/// a row that arrives whole are expanded into its subviews.
@MainActor
protocol WholeGridRowExpanding {
    var expandsWholeGridRows: Bool { get }
}

// MARK: - Grouping Children into Rows

/// One row of a grid, grouped from its container's children.
struct GridRowGroup<Cell> {
    /// The row's cells, in order.
    var cells: [Cell]

    /// The row's vertical alignment override, if it set one.
    var alignment: VerticalAlignment?

    /// Whether this row is one child that is in no row and spans every column.
    var spansFullWidth: Bool
}

/// `children` grouped into grid rows by their marks — what `Grid` and
/// `GridLayout` both lay out, so the two cannot group differently.
///
/// A marked child that starts a row starts one, and the marked children after
/// it join it. An unmarked child is offered to `wholeRow`, for a row that
/// arrived whole; anything else is one child spanning every column, which is
/// how a `Divider` between rows works.
@MainActor
func groupGridRows<Cell>(
    _ children: [Cell], mark: (Cell) -> GridRowMark?,
    wholeRow: (Cell) -> (cells: [Cell], alignment: VerticalAlignment?)?
) -> [GridRowGroup<Cell>] {
    var rows: [GridRowGroup<Cell>] = []
    var open: GridRowGroup<Cell>?
    for child in children {
        if let mark = mark(child) {
            if mark.startsRow || open == nil {
                if let row = open { rows.append(row) }
                open = GridRowGroup(cells: [child], alignment: mark.alignment, spansFullWidth: false)
            } else {
                open?.cells.append(child)
            }
            continue
        }
        if let row = open {
            rows.append(row)
            open = nil
        }
        if let whole = wholeRow(child) {
            rows.append(GridRowGroup(cells: whole.cells, alignment: whole.alignment, spansFullWidth: false))
        } else {
            rows.append(GridRowGroup(cells: [child], alignment: nil, spansFullWidth: true))
        }
    }
    if let row = open { rows.append(row) }
    return rows
}
