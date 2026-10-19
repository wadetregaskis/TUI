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
package struct GridRowMark: Equatable {
    /// Whether this cell is the row's first.
    package let startsRow: Bool

    /// The row's vertical alignment override, if it set one.
    package let alignment: VerticalAlignment?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitGrid makes these, for `Grid`.
    package init(startsRow: Bool, alignment: VerticalAlignment?) {
        self.startsRow = startsRow
        self.alignment = alignment
    }
}

/// A view carrying a ``GridRowMark``.
@MainActor
package protocol GridRowMarking {
    var gridRowMark: GridRowMark { get }
}

/// A grid row's cell, marked — the wrapper ``GridRow`` puts round each cell it
/// hands to its container. Renders exactly as its content, and passes every
/// other question about its content through: layout values (a cell's span,
/// anchor and column alignment), an explicit `.id(_:)`, a guide, a z-index, a
/// container value.
package struct _GridRowMarkView<Content: View>: View {
    let mark: GridRowMark
    let content: Content

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitGrid makes these, for `Grid`.
    package init(mark: GridRowMark, content: Content) {
        self.mark = mark
        self.content = content
    }

    package var body: some View {
        content
    }

    /// Size-neutral, so a guide inside the cell is the cell's.
    package static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension _GridRowMarkView: GridRowMarking {
    package var gridRowMark: GridRowMark { mark }
}

extension _GridRowMarkView: SingleContentWrapper {
    package var wrappedContent: Content { content }
}

extension _GridRowMarkView: ContentRewrapping {
    package func rewrapping<V: View>(_ view: V) -> any View {
        _GridRowMarkView<V>(mark: mark, content: view)
    }
}

extension _GridRowMarkView: LayoutValueProviding {
    package func layoutValue(for key: ObjectIdentifier) -> Any? {
        (content as? LayoutValueProviding)?.layoutValue(for: key)
    }
}

extension _GridRowMarkView: ExplicitIDProviding {
    package var explicitIDKey: String? {
        (content as? ExplicitIDProviding)?.explicitIDKey
    }

    package var explicitID: AnyHashable? {
        (content as? ExplicitIDProviding)?.explicitID
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
package func wholeGridRow(
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
package protocol WholeGridRowExpanding {
    var expandsWholeGridRows: Bool { get }
}
