//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Grid.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Grid Cell Layout Values

/// How many columns a cell spans, set with ``View/gridCellColumns(_:)``.
private struct GridCellColumnsKey: LayoutValueKey {
    static let defaultValue = 1
}

/// A cell's own placement within its box, set with ``View/gridCellAnchor(_:)``.
private struct GridCellAnchorKey: LayoutValueKey {
    static let defaultValue: UnitPoint? = nil
}

/// A column-wide horizontal alignment, set with ``View/gridColumnAlignment(_:)``
/// on any cell in that column.
private struct GridColumnAlignmentKey: LayoutValueKey {
    static let defaultValue: HorizontalAlignment? = nil
}

/// The axes on which a cell does not size its column or row, set with
/// ``View/gridCellUnsizedAxes(_:)``.
private struct GridCellUnsizedAxesKey: LayoutValueKey {
    static let defaultValue: Axis.Set = []
}

extension View {
    /// Makes this cell span `count` columns of its ``Grid``.
    ///
    /// - Parameter count: The number of columns to span. Values below 1 are
    ///   treated as 1.
    /// - Returns: A view carrying the span.
    public func gridCellColumns(_ count: Int) -> some View {
        layoutValue(key: GridCellColumnsKey.self, value: max(1, count))
    }

    /// Overrides where this cell sits inside the box the grid gives it.
    ///
    /// - Parameter anchor: The point of the cell that meets the same point of
    ///   its box.
    /// - Returns: A view carrying the anchor.
    public func gridCellAnchor(_ anchor: UnitPoint) -> some View {
        layoutValue(key: GridCellAnchorKey.self, value: anchor)
    }

    /// Sets the horizontal alignment for this cell's whole **column**.
    ///
    /// As in SwiftUI, one cell decides for the column it is in; if several cells
    /// in a column disagree, the first one the grid walks wins.
    ///
    /// - Parameter guide: The alignment for the column.
    /// - Returns: A view carrying the column alignment.
    public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
        layoutValue(key: GridColumnAlignmentKey.self, value: guide)
    }

    /// Asks the grid not to size this cell's column or row from it, on the
    /// given axes.
    ///
    /// For a cell that fills whatever it is given — a `Color`, a `Divider`, a
    /// rule drawn across a row — so it takes the width (or height) the other
    /// cells decide instead of imposing its own:
    ///
    /// ```swift
    /// Grid {
    ///     GridRow { Text("Name"); Text("Size") }
    ///     GridRow {
    ///         Color.gray.frame(height: 1).gridCellUnsizedAxes(.horizontal)
    ///             .gridCellColumns(2)
    ///     }
    /// }
    /// ```
    ///
    /// On an axis it is unsized on, the cell adds nothing to its column's
    /// width or its row's height, and is drawn at the extent the rest decide.
    ///
    /// - Parameter axes: The axes on which the cell does not size the grid.
    /// - Returns: A view carrying the axes.
    public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View {
        layoutValue(key: GridCellUnsizedAxesKey.self, value: axes)
    }
}

// MARK: - Grid Row

/// One row of a ``Grid``.
///
/// Each view inside a row is one cell, unless it carries
/// ``View/gridCellColumns(_:)``.
///
/// A row is not a container of its own: like a `Group`, it hands its views to
/// the container around it, and only a ``Grid`` (or a ``GridLayout``) reads
/// where one row ends and the next begins. So `VStack { GridRow { a; b } }` is
/// `VStack { a; b }`, exactly as SwiftUI draws it, and a custom ``Layout``
/// over two rows of two sees four subviews.
public struct GridRow<Content: View>: View {
    /// Overrides the grid's vertical alignment for this row.
    public let alignment: VerticalAlignment?

    /// The row's cells.
    public let content: Content

    /// Creates a grid row.
    ///
    /// - Parameters:
    ///   - alignment: The vertical alignment for this row's cells, or `nil` to
    ///     use the grid's.
    ///   - content: The cells.
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    /// The cells themselves: a row's views stand alone, as a `Group`'s do,
    /// wherever no grid lays them out — measured on SwiftUI, where `VStack {
    /// GridRow { a; b } }` draws exactly as `VStack { a; b }` and not as
    /// `HStack { a; b }`.
    public var body: some View {
        content
    }

    /// Its cells' answer: they are laid out as the enclosing container's own
    /// children, so a guide in any of them can be one that container reports.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

// MARK: - A Row's Cells as the Container's Children

/// A row hands its cells to the container around it, as a `Group` hands its
/// members, each carrying a ``GridRowMark`` — the first marked as starting the
/// row — so a grid can tell where one row ends and the next begins once the
/// rows are flattened into one list of children. Plain values, the same on
/// every walk, so they never defeat a cell's memo.
extension GridRow: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        resolveChildViews(from: content, context: context).enumerated().map { index, cell in
            cell.rewrapped(
                by: _GridRowMarkView(
                    mark: GridRowMark(startsRow: index == 0, alignment: alignment),
                    content: EmptyView()))
        }
    }
}

extension GridRow: ChildInfoProvider {
    public func childInfos(context: RenderContext) -> [ChildInfo] {
        resolveChildInfos(from: content, context: context)
    }
}

/// A view the enclosing ``Grid`` should treat as a row rather than a cell.
@MainActor
protocol GridRowProviding {
    /// This row's vertical alignment override, if it set one.
    var rowAlignment: VerticalAlignment? { get }

    /// The row's cells.
    func gridCells(context: RenderContext) -> [ChildView]
}

extension GridRow: GridRowProviding {
    var rowAlignment: VerticalAlignment? { alignment }

    func gridCells(context: RenderContext) -> [ChildView] {
        resolveChildViews(from: content, context: context)
    }
}

/// A modified row is still a row, and the modifier belongs to its CELLS.
///
/// SwiftUI: "If you apply a view modifier to a row, the row applies the
/// modifier to all of the cells, similar to how a `Group` behaves. For example,
/// if you apply the `border(_:width:)` modifier to a row, SwiftUI draws a
/// border on each cell in the row rather than around the row."
///
/// A row usually reaches its grid flattened: `GridRow` hands its cells out as a
/// `ChildViewProvider`, and so does a `ModifiedView` around one, re-wrapping
/// each cell. This conformance is for a modified row that arrives WHOLE — a
/// `ForEach` row, which a loop hands over one child per element — which the
/// grid takes apart through it (`wholeGridRow(_:context:)`). Before rows
/// flattened, a wrapped row missed the grid's row test, fell into the "not a
/// `GridRow`, therefore spans every column" branch that exists for a `Divider`
/// between rows, and its cells left the grid's columns.
///
/// The companion to `ModifiedView`'s ``ChildViewProvider`` conformance, and the
/// same shape: resolve through the wrapper, then put the wrapper back around
/// each thing that came out.
extension ModifiedView: GridRowProviding where Content: GridRowProviding {
    var rowAlignment: VerticalAlignment? { content.rowAlignment }

    func gridCells(context: RenderContext) -> [ChildView] {
        content.gridCells(context: context).map { $0.modified(by: modifier) }
    }
}

/// The same rule for a row wrapped in something that is not a `BufferModifier`
/// — `.foregroundStyle` and most other modifier factories return a bare
/// wrapper type, not a ``ModifiedView``.
///
/// A ``SingleContentWrapper`` conformance is all a wrapper needs to pick this
/// up; the body here is the one above with ``ChildView/rewrapped(by:)`` in
/// place of ``ChildView/modified(by:)``, for the reason
/// ``SingleContentWrapper`` states: a wrapper has no modifier VALUE to carry
/// to each cell, so it re-wraps them with its own initialiser instead.
extension GridRowProviding where Self: ContentRewrapping, WrappedContent: GridRowProviding {
    var rowAlignment: VerticalAlignment? { wrappedContent.rowAlignment }

    func gridCells(context: RenderContext) -> [ChildView] {
        wrappedContent.gridCells(context: context).map { $0.rewrapped(by: self) }
    }
}

// The three environment wrappers live in `TUIkitView`, which is below this
// module and cannot see `GridRowProviding` — so their conformances are written
// here rather than beside their `ChildViewProvider` ones. Nothing else differs:
// a row carrying `.environment(_:_:)` is as much a row as one carrying
// `.tint(_:)`, and leaving these three out was an artifact of where the files
// sit, not a decision about rows.

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension EnvironmentModifier: GridRowProviding where Content: GridRowProviding {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension TransformEnvironmentModifier: GridRowProviding where Content: GridRowProviding {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension ObjectEnvironmentModifier: GridRowProviding where Content: GridRowProviding {}

// MARK: - Grid

/// A container that arranges its ``GridRow``s into aligned columns.
///
/// Columns are as wide as their widest cell, so cells line up across rows
/// without any of them being told a width:
///
/// ```swift
/// Grid(alignment: .leading) {
///     GridRow {
///         Text("Name");  Text("Size"); Text("Kind")
///     }
///     GridRow {
///         Text("README"); Text("2 KB"); Text("Markdown")
///     }
/// }
/// ```
///
/// A child that is **not** a `GridRow` spans the whole width — which is how a
/// `Divider` between rows works.
///
/// ## Terminal specifics
///
/// Spacings are `Int` cells; `nil`, the default, is 1 column and 0 rows: a
/// column gap of zero would run adjacent text together, whereas rows are already
/// separated by being different lines.
///
/// ``GridLayout`` lays cells out the same way as a ``Layout``, for switching
/// with another layout through ``AnyLayout``.
///
/// A child that is not in a row already spans the full width without sizing a
/// column. A cell that should fill its column or row rather than size it says
/// so with ``View/gridCellUnsizedAxes(_:)``.
public struct Grid<Content: View>: View {
    /// How cells sit inside the boxes the grid gives them.
    public let alignment: Alignment

    /// Cells between columns, in cells.
    public let horizontalSpacing: Int

    /// Blank lines between rows.
    public let verticalSpacing: Int

    /// The grid's rows.
    public let content: Content

    /// Creates a grid.
    ///
    /// - Parameters:
    ///   - alignment: How each cell sits in its box (default `.center`).
    ///   - horizontalSpacing: Columns between cells, or `nil` (the default) for
    ///     one.
    ///   - verticalSpacing: Blank lines between rows, or `nil` (the default)
    ///     for none.
    ///   - content: The ``GridRow``s.
    public init(
        alignment: Alignment = .center,
        horizontalSpacing: Int? = nil,
        verticalSpacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing ?? GridLattice.defaultHorizontalSpacing
        self.verticalSpacing = verticalSpacing ?? GridLattice.defaultVerticalSpacing
        self.content = content()
    }

    public var body: some View {
        _GridCore(
            alignment: alignment, horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing, content: content)
    }
}

// MARK: - Core

/// Measures every cell, derives the column widths and row heights, then places
/// the cells into that lattice.
struct _GridCore<Content: View>: View, Renderable, Layoutable {
    let alignment: Alignment
    let horizontalSpacing: Int
    let verticalSpacing: Int
    let content: Content

    var body: Never {
        fatalError("_GridCore renders via Renderable")
    }

    /// One row's worth of resolved cells. A `nil` `row` marks a child that was
    /// not a `GridRow` and therefore spans every column.
    private struct Row {
        let cells: [ChildView]
        let spans: [Int]
        let alignment: VerticalAlignment?
        let spansFullWidth: Bool
    }

    /// The children grouped into rows.
    ///
    /// A row's cells arrive flattened, each carrying a ``GridRowMark``: a
    /// marked cell that starts a row starts one, and the cells after it join
    /// it. A row that arrives whole — a `ForEach` row, which a loop hands over
    /// one child per element — is taken apart here, its cells resolved under
    /// the row's own identity. Anything else is one child spanning every
    /// column, which is how a `Divider` between rows works.
    private func rows(context: RenderContext) -> [Row] {
        let children = resolveChildViews(from: content, context: context)
        return groupGridRows(
            children, mark: { $0.gridRowMark }, wholeRow: { wholeGridRow($0, context: context) }
        ).map { group in
            Row(
                cells: group.cells, spans: group.cells.map(\.gridSpan), alignment: group.alignment,
                spansFullWidth: group.spansFullWidth)
        }
    }

    /// The lattice both passes agree on: column widths, row heights, and the
    /// per-column alignment overrides — see ``GridLattice``.
    private func lattice(_ rows: [Row], context: RenderContext) -> GridLattice {
        GridLattice(
            rows: rows.map { row in
                GridLattice.Row(
                    cells: zip(row.cells, row.spans).map { cell, span in
                        GridLattice.Cell(
                            span: span,
                            size: cell.measure(proposal: .unspecified, context: context),
                            columnAlignment: cell.gridColumnAlignment,
                            unsizedAxes: cell.gridUnsizedAxes)
                    },
                    spansFullWidth: row.spansFullWidth)
            },
            horizontalSpacing: horizontalSpacing)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Ground the proposal into the context before the lattice reads it —
        // the same two lines `_ContainerViewCore.sizeThatFits` and
        // `_ViewThatFitsCore.sizeThatFits` open with. `lattice` measures every
        // cell at `.unspecified`, which a wrapping cell resolves against
        // `context.availableWidth`, so without this the proposal reached only
        // the final clamp and the row heights belonged to a width the grid was
        // never going to be drawn at. `_HStackCore.resolvedLayout` re-measures
        // a column it squeezed at `ProposedSize(width: allocated, height: nil)`
        // and leaves `availableWidth` at the whole row's, while `renderChild`
        // DOES narrow it: "alpha beta gamma delta epsilon" beside "TAIL" in a
        // 20-cell row measured as 2 lines wrapped at 20, the row became 2 lines
        // tall, and the render built its lattice at the 15 cells it was given
        // — 3 lines — and clamped "epsilon" away with nothing on screen to say
        // so. Grounded, both passes build the lattice from the same width.
        var context = context.publishingContainerAxis(.vertical)
        context.availableWidth = proposal.width ?? context.availableWidth
        context.availableHeight = proposal.height ?? context.availableHeight
        let rows = rows(context: context)
        guard !rows.isEmpty else { return ViewSize.fixed(0, 0) }
        let lattice = lattice(rows, context: context)
        // Every row at least a line, because that is what `renderToBuffer`
        // draws: it gives every row a canvas of `max(1, rowHeight)`, so a row
        // is at least a line whatever it holds. Summing the raw heights made
        // the reported height one line short for each row that measured zero
        // tall, and the parent clips what overflows — with one empty row, the
        // grid's LAST row did not appear. Aligned to the render rather than
        // the other way round: the render is what anyone has ever seen, so
        // this changes no pixels, only the number the grid tells its parent
        // about them.
        let height = lattice.totalHeight(spacing: verticalSpacing)
        return ViewSize(
            width: min(lattice.totalWidth, max(0, proposal.width ?? context.availableWidth)),
            height: min(height, max(0, proposal.height ?? context.availableHeight)))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A grid stacks its rows into a column, so it publishes `.vertical` for
        // everything inside it — exactly as `_VStackCore` does, and for the
        // same reader. It is a child that is NOT a `GridRow` that needs it: it
        // spans every column, so the `Divider` between two rows must be the
        // horizontal rule it is when the grid stands alone. Publishing nothing
        // is not the same as publishing this: with nothing published, a grid
        // placed inside an `HStack` handed that full-width child the ROW's
        // axis, and the rule collapsed to a single `│` in column 0.
        let context = context.publishingContainerAxis(.vertical)
        let rows = rows(context: context)
        guard !rows.isEmpty else { return FrameBuffer() }
        let lattice = lattice(rows, context: context)
        let heights = lattice.heights
        let width = lattice.totalWidth
        guard width > 0 else { return FrameBuffer() }
        let origins = lattice.columnOrigins

        // A `.gradientExtent(.subtree)` ramp spanning this grid. A grid is the
        // one container that places children two-dimensionally without being a
        // `Layout` — its cells are a lattice, which `LayoutSubviews` cannot
        // describe — so it cannot inherit `_LayoutCore`'s answer and has to
        // give its own. `nil` when nothing above asked for one, and then every
        // line below is the identity.
        let rowTops = lattice.rowTops(spacing: verticalSpacing)
        let gradientFrame = context.gradientContentFrame(
            width: width,
            height: (rowTops.last ?? 0) + max(1, heights.last ?? 1))

        var result = FrameBuffer()
        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = heights[rowIndex]
            var canvas = FrameBuffer(emptyWithWidth: width, height: max(1, rowHeight))
            var index = 0
            for (cell, span) in zip(row.cells, row.spans) {
                let boxWidth =
                    row.spansFullWidth ? width : lattice.boxWidth(fromColumn: index, span: span)
                let box = CellRect(
                    x: row.spansFullWidth ? 0 : origins[index], y: 0,
                    width: max(0, boxWidth), height: max(1, rowHeight))
                let rowAlignment = row.alignment
                let columnGuide = row.spansFullWidth ? nil : lattice.columnAlignment[index]
                var childContext = context
                if context.placesChildren {
                    // Where the cell will land, from its MEASURED size — the
                    // rendered one is a pass later, and the modifier's contract
                    // is that measure and render agree. The measure is the one
                    // `lattice` already took, so it is a memo hit.
                    let measured = cell.measure(
                        proposal: ProposedSize(width: max(0, boxWidth), height: max(1, rowHeight)),
                        context: context)
                    let seat = placement(
                        width: measured.width, height: measured.height, in: box, cell: cell,
                        rowAlignment: rowAlignment, columnAlignment: columnGuide)
                    childContext = context.placingChild(
                        gradient: gradientFrame, x: seat.x, y: rowTops[rowIndex] + seat.y)
                }
                let rendered = cell.render(
                    width: max(0, boxWidth), height: max(1, rowHeight), context: childContext)
                canvas = canvas.composited(
                    with: rendered,
                    at: placement(
                        width: rendered.width, height: rendered.height, in: box, cell: cell,
                        rowAlignment: rowAlignment, columnAlignment: columnGuide))
                index += span
            }
            result.appendVertically(canvas, spacing: rowIndex > 0 ? verticalSpacing : 0)
        }
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// Where a cell of this size sits inside its box — see
    /// ``GridLattice/placement(width:height:in:anchor:rowAlignment:columnAlignment:gridAlignment:)``.
    private func placement(
        width renderedWidth: Int,
        height renderedHeight: Int,
        in box: CellRect,
        cell: ChildView,
        rowAlignment: VerticalAlignment?,
        columnAlignment: HorizontalAlignment?
    ) -> (x: Int, y: Int) {
        GridLattice.placement(
            width: renderedWidth, height: renderedHeight, in: box, anchor: cell.gridCellAnchor,
            rowAlignment: rowAlignment, columnAlignment: columnAlignment, gridAlignment: alignment)
    }
}

// MARK: - Reading a Cell's Grid Values

extension ChildView {
    /// The span this cell asked for, or 1.
    var gridSpan: Int {
        gridValue(GridCellColumnsKey.self) ?? 1
    }

    /// The anchor this cell asked for, if any.
    var gridCellAnchor: UnitPoint? {
        gridValue(GridCellAnchorKey.self).flatMap { $0 }
    }

    /// The axes on which this cell does not size the grid.
    var gridUnsizedAxes: Axis.Set {
        gridValue(GridCellUnsizedAxesKey.self) ?? []
    }

    /// The column alignment this cell set for its column, if any.
    var gridColumnAlignment: HorizontalAlignment? {
        gridValue(GridColumnAlignmentKey.self).flatMap { $0 }
    }

    /// Reads a layout value straight off the wrapped view.
    ///
    /// `LayoutSubview`'s subscript is the public spelling of this, but a grid
    /// is not a `Layout` — its cells are two-dimensional, which
    /// `LayoutSubviews` (a flat collection) cannot describe — so it reads the
    /// same values through the same wrapper directly.
    private func gridValue<K: LayoutValueKey>(_ key: K.Type) -> K.Value? {
        guard let provider = wrappedView as? LayoutValueProviding,
            let value = provider.layoutValue(for: ObjectIdentifier(K.self)) as? K.Value
        else { return nil }
        return value
    }
}
