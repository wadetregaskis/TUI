//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GridLayout.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - Grid Layout

/// A grid that you can use in conditional layouts.
///
/// Lays its subviews out exactly as a ``Grid`` does — the same columns, the
/// same rows, the same placement within each cell — but conforms to ``Layout``,
/// so it can be erased into an ``AnyLayout`` and switched with another layout
/// while the cells keep their identity and their `@State`:
///
/// ```swift
/// let layout = isWide ? AnyLayout(GridLayout()) : AnyLayout(VStackLayout())
/// layout {
///     GridRow { Text("Name"); Text("Size") }
///     GridRow { Text("README"); Text("2 KB") }
/// }
/// ```
///
/// Under the grid the rows line their cells up in columns; under the stack
/// layout the same cells stack, because a ``GridRow`` hands its cells to
/// whatever lays them out. If you don't need to switch, use ``Grid``.
///
/// Spacings are whole cells. `nil`, the default, is the grid's: one column
/// between cells, no row between rows.
public struct GridLayout: Layout, Sendable, Equatable {
    /// How cells sit inside the boxes the grid gives them.
    public var alignment: Alignment

    /// Columns between cells, or `nil` for the default of one.
    public var horizontalSpacing: Int?

    /// Blank lines between rows, or `nil` for the default of none.
    public var verticalSpacing: Int?

    /// Creates a grid layout.
    ///
    /// - Parameters:
    ///   - alignment: How each cell sits in its box (default `.center`).
    ///   - horizontalSpacing: Columns between cells, or `nil` (the default)
    ///     for one.
    ///   - verticalSpacing: Blank lines between rows, or `nil` (the default)
    ///     for none.
    public init(
        alignment: Alignment = .center, horizontalSpacing: Int? = nil, verticalSpacing: Int? = nil
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    /// A stateful grid layout algorithm: the subviews grouped into rows, and
    /// the lattice the size question found, for the placement that follows.
    ///
    /// Like every layout's here, it lives for one pass (see ``Layout``).
    public struct Cache {
        fileprivate var rows: [GridRowGroup<Int>]
        fileprivate var lattice: GridLattice?
    }

    /// The column gap in force.
    private var columnGap: Int { horizontalSpacing ?? GridLattice.defaultHorizontalSpacing }

    /// The row gap in force.
    private var rowGap: Int { verticalSpacing ?? GridLattice.defaultVerticalSpacing }

    /// Groups the subviews into rows, by the marks a `GridRow` gives its
    /// cells: a subview in no row spans every column.
    public func makeCache(subviews: Subviews) -> Cache {
        Cache(
            rows: groupGridRows(
                Array(subviews.indices), mark: { subviews[$0].child.gridRowMark },
                wholeRow: { _ in nil }),
            lattice: nil)
    }

    /// Groups the subviews afresh.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    public func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout Cache) -> ViewSize {
        let lattice = lattice(cache.rows, subviews: subviews)
        cache.lattice = lattice
        return ViewSize(
            width: min(lattice.totalWidth, max(0, proposal.width ?? lattice.totalWidth)),
            height: min(
                lattice.totalHeight(spacing: rowGap),
                max(0, proposal.height ?? lattice.totalHeight(spacing: rowGap))))
    }

    public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout Cache
    ) {
        let lattice = cache.lattice ?? lattice(cache.rows, subviews: subviews)
        let origins = lattice.columnOrigins
        let rowTops = lattice.rowTops(spacing: rowGap)
        for (rowIndex, row) in cache.rows.enumerated() {
            let rowHeight = max(1, lattice.heights[rowIndex])
            var column = 0
            for index in row.cells {
                let subview = subviews[index]
                let span = row.spansFullWidth ? 1 : subview.child.gridSpan
                let boxWidth =
                    row.spansFullWidth
                    ? lattice.totalWidth : lattice.boxWidth(fromColumn: column, span: span)
                let box = CellRect(
                    x: bounds.x + (row.spansFullWidth ? 0 : origins[column]),
                    y: bounds.y + rowTops[rowIndex],
                    width: max(0, boxWidth), height: rowHeight)
                let cellProposal = ProposedSize(width: max(0, boxWidth), height: rowHeight)
                let size = subview.sizeThatFits(cellProposal)
                let seat = GridLattice.placement(
                    width: min(size.width, box.width), height: min(size.height, box.height),
                    in: box, anchor: subview.child.gridCellAnchor, rowAlignment: row.alignment,
                    columnAlignment: row.spansFullWidth ? nil : lattice.columnAlignment[column],
                    gridAlignment: alignment)
                subview.place(at: seat, proposal: cellProposal)
                column += span
            }
        }
    }

    /// Every subview's preference, merged on every edge — the default.
    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        var spacing = ViewSpacing.zero
        for subview in subviews {
            spacing.formUnion(subview.spacing)
        }
        return spacing
    }

    /// The subviews' explicit values for a custom guide, merged — the
    /// default; none for a built-in guide.
    public func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout Cache
    ) -> Double? {
        guard !guide.isBuiltIn else { return nil }
        return subviews.mergedExplicitGuide(.horizontal(guide))
    }

    /// The subviews' explicit values for a custom guide, merged — the
    /// default; none for a built-in guide.
    public func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout Cache
    ) -> Double? {
        guard !guide.isBuiltIn else { return nil }
        return subviews.mergedExplicitGuide(.vertical(guide))
    }

    /// The grid's lattice over `rows`, from each cell's size at an
    /// unspecified proposal — what ``Grid`` builds from its children.
    private func lattice(_ rows: [GridRowGroup<Int>], subviews: Subviews) -> GridLattice {
        GridLattice(
            rows: rows.map { row in
                GridLattice.Row(
                    cells: row.cells.map { index in
                        let subview = subviews[index]
                        return GridLattice.Cell(
                            span: row.spansFullWidth ? 1 : subview.child.gridSpan,
                            size: subview.sizeThatFits(.unspecified),
                            columnAlignment: subview.child.gridColumnAlignment,
                            unsizedAxes: subview.child.gridUnsizedAxes)
                    },
                    spansFullWidth: row.spansFullWidth)
            },
            horizontalSpacing: columnGap)
    }
}

extension GridLayout {
    /// A grid stacks its rows into a column, so a subview in no row — the
    /// `Divider` between two rows — draws as the horizontal rule it is in a
    /// ``Grid``.
    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .vertical
        return properties
    }

    /// A grid keeps the default guide merge.
    public static var _definesExplicitAlignment: Bool { false }
}

extension GridLayout: Animatable {
    /// A grid layout animates nothing of its own.
    public typealias AnimatableData = EmptyAnimatableData
}

/// A `ForEach` of rows is cells, as in a ``Grid``.
extension GridLayout: WholeGridRowExpanding {
    package var expandsWholeGridRows: Bool { true }
}
