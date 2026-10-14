//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyGrids.swift
//
//  The grids that FLOW: you describe the tracks, hand over a pile of views, and
//  they wrap.
//
//  Distinct from ``Grid``, which is the one where you write the rows out
//  yourself with ``GridRow``. That one is a table with an explicit shape; this
//  one is a collection that reflows when the terminal is resized, and it is the
//  shape almost every real grid wants — swatches, thumbnails, a keypad.
//
//  Built on ``Layout`` rather than hand-rolled buffer arithmetic: track
//  placement is precisely what a layout does, so this needs no compositing code
//  of its own and inherits alignment guides, `LayoutValueKey`, and the measure
//  cache for free.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - The Layout

/// Flows subviews across a fixed set of tracks, wrapping onto a new line
/// whenever they run out.
///
/// Backs both grids: ``LazyVGrid`` repeats *columns* and wraps downward,
/// ``LazyHGrid`` repeats *rows* and wraps rightward. The two are mirror images,
/// so `axis` names which way the tracks repeat and the arithmetic below is
/// written once in terms of "across" (along the tracks) and "along" (the
/// direction it wraps).
private struct _LazyGridLayout: Layout, Sendable, Equatable {
    /// The direction subviews accumulate in: `.vertical` wraps downward
    /// (``LazyVGrid``), `.horizontal` rightward (``LazyHGrid``).
    let axis: Axis

    /// A lazy grid keeps the default guide merge.
    static var _definesExplicitAlignment: Bool { false }

    /// The track descriptions — columns when vertical, rows when horizontal.
    let items: [GridItem]

    /// Where a subview sits in its cell, unless its track says otherwise.
    let alignment: Alignment

    /// Cells between lines: rows when vertical, columns when horizontal.
    let spacing: Int

    // MARK: Geometry

    /// The size to offer a subview in a track of this extent.
    private func proposal(forTrack extent: Int) -> ProposedSize {
        axis == .vertical
            ? ProposedSize(width: extent, height: nil)
            : ProposedSize(width: nil, height: extent)
    }

    /// How thick each line is: row heights when vertical, column widths when
    /// horizontal — the largest subview on that line.
    private func lineBreadths(_ subviews: Subviews, tracks: [GridTrack]) -> [Int] {
        guard !tracks.isEmpty else { return [] }
        var breadths: [Int] = []
        var start = 0
        while start < subviews.count {
            var breadth = 0
            for column in 0..<tracks.count where start + column < subviews.count {
                let size = subviews[start + column].sizeThatFits(
                    proposal(forTrack: tracks[column].extent))
                breadth = max(breadth, axis == .vertical ? size.height : size.width)
            }
            breadths.append(breadth)
            start += tracks.count
        }
        return breadths
    }

    /// The tracks' total extent, gaps included.
    private func acrossExtent(_ tracks: [GridTrack]) -> Int {
        tracks.reduce(0) { $0 + $1.extent } + tracks.dropLast().reduce(0) { $0 + $1.spacing }
    }

    /// The extent available for the tracks to divide.
    ///
    /// A `nil` proposal (an unconstrained context — a `ScrollView`'s scrolling
    /// axis, or a stack probing a child's ideal size) resolves against the
    /// grid's own IDEAL demand instead.
    private func across(of proposal: ProposedSize, subviewCount: Int) -> Int {
        let proposed = axis == .vertical ? proposal.width : proposal.height
        guard let proposed, proposed > 0 else { return idealAcross(for: subviewCount) }
        return proposed
    }

    /// What the tracks ask for when nothing constrains them.
    ///
    /// Unconstrained means "how much would you LIKE", not "how little can you
    /// survive on" — and for `.adaptive` those differ enormously, because its
    /// track count is an output. Counting an adaptive item as ONE track made a
    /// 12-item grid report itself as twelve rows TALL; a stack believes that
    /// measure, budgets twelve rows, and every sibling after it falls off the
    /// screen. (Live-only: a bare render context proposes a width, so the
    /// fallback never ran and the headless tests all passed.)
    ///
    /// So the ideal is one repeat per subview: everything on a single line.
    /// A stack's unconstrained probe then sees one row rather than twelve, and
    /// the constrained measure that actually drives layout is unaffected.
    private func idealAcross(for subviewCount: Int) -> Int {
        var extents: [Int] = []
        var gaps: [Int] = []
        for item in items {
            let gap = item.spacing ?? GridItem.defaultSpacing(wrapping: axis)
            switch item.size {
            case .fixed(let extent):
                extents.append(max(0, extent))
                gaps.append(gap)
            case .flexible(let minimum, _):
                extents.append(max(1, minimum))
                gaps.append(gap)
            case .adaptive(let minimum, _):
                for _ in 0..<max(1, subviewCount) {
                    extents.append(max(1, minimum))
                    gaps.append(gap)
                }
            }
        }
        guard !extents.isEmpty else { return 0 }
        // Gaps go BETWEEN tracks, so there is one fewer than there are tracks.
        return extents.reduce(0, +) + gaps.dropLast().reduce(0, +)
    }

    // MARK: Layout

    func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        let tracks = GridItem.resolve(
            items, available: across(of: proposal, subviewCount: subviews.count), wrapping: axis)
        guard !tracks.isEmpty, !subviews.isEmpty else { return ViewSize(width: 0, height: 0) }

        let breadths = lineBreadths(subviews, tracks: tracks)
        let total: Int = breadths.reduce(0, +)
        let along = total + max(0, breadths.count - 1) * spacing
        // A partly-filled last line still claims the full track extent: a grid
        // that narrowed itself to its final row's content would jitter as items
        // are added, and would not line up with the rows above it.
        let across = acrossExtent(tracks)

        // A grid with any `.flexible` or `.adaptive` track FILLS the extent it
        // is offered — that is what those track kinds mean. Saying so is what
        // makes a stack offer the whole width rather than sizing the grid to
        // the ideal it reported from an unconstrained probe (and then clipping
        // the rows that ideal did not account for). Only an all-`.fixed` grid
        // is genuinely rigid.
        let fillsAcross = items.contains {
            switch $0.size {
            case .fixed: false
            case .flexible, .adaptive: true
            }
        }

        return axis == .vertical
            ? ViewSize(width: across, height: along, isWidthFlexible: fillsAcross)
            : ViewSize(width: along, height: across, isHeightFlexible: fillsAcross)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        let tracks = GridItem.resolve(
            items, available: axis == .vertical ? bounds.width : bounds.height, wrapping: axis)
        guard !tracks.isEmpty else { return }

        let breadths = lineBreadths(subviews, tracks: tracks)
        var along = axis == .vertical ? bounds.y : bounds.x

        for (line, breadth) in breadths.enumerated() {
            var across = axis == .vertical ? bounds.x : bounds.y
            for (column, track) in tracks.enumerated() {
                let index = line * tracks.count + column
                guard index < subviews.count else { break }

                let cell =
                    axis == .vertical
                    ? CellRect(x: across, y: along, width: track.extent, height: breadth)
                    : CellRect(x: along, y: across, width: breadth, height: track.extent)
                subviews[index].place(
                    in: cell,
                    anchor: (track.alignment ?? alignment).unitPoint,
                    proposal: ProposedSize(width: cell.width, height: cell.height))
                across += track.extent + track.spacing
            }
            along += breadth + spacing
        }
    }
}

// MARK: - LazyVGrid

/// A grid that grows downward, flowing its content across a fixed set of
/// columns.
///
/// Mirrors SwiftUI's `LazyVGrid`. Describe the columns with ``GridItem``; the
/// content wraps onto a new row each time it fills them.
///
/// ```swift
/// LazyVGrid(columns: [GridItem(.adaptive(minimum: 10))], spacing: 1) {
///     ForEach(swatches) { swatch in
///         Text(swatch.name).border(swatch.colour)
///     }
/// }
/// ```
///
/// `.adaptive` is the one to reach for in a terminal: the column count becomes
/// an output of the width rather than something to guess, so the grid reflows
/// when the window is resized.
///
/// # Sections
///
/// A `Section` among the grid's views starts a new row with its header, which
/// spans every column; its views flow across the columns from the start of the
/// row below, and its footer spans the columns after them. Views outside any
/// section flow as they do in a grid with none, between the sections. Header
/// and footer sit across the grid where `alignment` puts a view in a cell, as
/// SwiftUI's do (measured on macOS 15.8), drawn as written: outside a `List` a
/// section's header has no styling of its own. With `pinnedViews:`, they pin
/// to the enclosing scroll view's edges exactly as a ``LazyVStack``'s do:
///
/// ```swift
/// ScrollView {
///     LazyVGrid(columns: [GridItem(.adaptive(minimum: 12))], pinnedViews: .sectionHeaders) {
///         ForEach(albums) { album in
///             Section(album.title) {
///                 ForEach(album.photos) { Text($0.caption) }
///             }
///         }
///     }
/// }
/// ```
///
/// One deviation: a sectioned grid fills the width it is offered, as a grid
/// of `.flexible` or `.adaptive` columns always does, so a section's header
/// can sit across it. Its `spacing` falls between every two rows — a header
/// and its section's first row too — as SwiftUI's does.
///
/// - Note: Unlike SwiftUI's, this grid measures every subview — "lazy" here
///   describes the API shape, not deferred construction. A grid whose rows must
///   be built lazily belongs inside a ``ScrollView``, which windows what it
///   renders — section by section, when it has sections.
public struct LazyVGrid<Content: View>: View {
    /// The column tracks.
    public let columns: [GridItem]

    /// Where content sits in a cell, unless its column says otherwise.
    public let alignment: HorizontalAlignment

    /// Blank rows between the grid's rows.
    public let spacing: Int

    /// The views to flow.
    public let content: Content

    /// The kinds of child views pinned to the enclosing scroll view's edges.
    let pinnedViews: PinnedScrollableViews

    /// Creates a grid that grows vertically.
    ///
    /// - Parameters:
    ///   - columns: The column tracks to flow content across.
    ///   - alignment: Horizontal placement within a cell, and of a section's
    ///     header and footer across the grid (default: `.center`).
    ///   - spacing: Blank rows between rows, or `nil` (the default) for none.
    ///   - pinnedViews: The kinds of child views that will be pinned to the
    ///     enclosing scroll view's edges: the headers and footers of the
    ///     grid's `Section`s (default: none). See the discussion above.
    ///   - content: The views to flow.
    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Int? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.content = content()
        self.pinnedViews = pinnedViews
    }

    public var body: some View {
        _LazyGridSections(
            layout: _LazyGridLayout(
                axis: .vertical, items: columns,
                alignment: Alignment(horizontal: alignment, vertical: .center),
                spacing: spacing),
            pinnedViews: pinnedViews,
            content: content)
    }
}

// MARK: - A Grid's Sections

/// A grid's content: flowed across the tracks as written, or — when a
/// `Section` is among its views — section by section, each a section of its
/// own around a grid of its views, stacked as a pinned ``LazyVStack`` stacks
/// its sections, or laid along a row as a pinned ``LazyHStack`` lays out its
/// own.
///
/// The flat form is the grid as it always was, at this view's identity. The
/// sectioned one is taken apart with the section APIs (``SectionCollection``),
/// so the views outside any section form implicit sections of their own, and
/// is drawn under a step of its own, so a grid that gains or loses its sections
/// does not hand one form's state to the other.
private struct _LazyGridSections<Content: View>: View, Renderable, Layoutable {
    let layout: _LazyGridLayout
    let pinnedViews: PinnedScrollableViews
    let content: Content

    var body: Never {
        fatalError("_LazyGridSections renders via Renderable")
    }

    /// The grid as written: every view flowed across the tracks.
    private var flat: _LayoutCore<_LazyGridLayout, Content> {
        _LayoutCore(layout: layout, content: content)
    }

    /// Where a section's header and footer sit across the grid: where the
    /// grid's alignment puts a view in a cell, from the start of the section.
    private var chromeAlignment: Alignment {
        layout.axis == .vertical
            ? Alignment(horizontal: layout.alignment.horizontal, vertical: .top)
            : Alignment(horizontal: .leading, vertical: layout.alignment.vertical)
    }

    /// The grid section by section.
    @ViewBuilder private var sectioned: some View {
        if layout.axis == .vertical { sectionedColumn } else { sectionedRow }
    }

    /// A vertical grid section by section: each section's header across the
    /// columns, its views flowed under it, its footer across them below.
    private var sectionedColumn: some View {
        Group(sections: content) { [layout, pinnedViews, chromeAlignment] sections in
            _VStackCore(
                alignment: chromeAlignment.horizontal, spacing: layout.spacing, overflow: .window,
                pinnedViews: pinnedViews,
                content: ForEach(sections) { section in
                    Section {
                        _LayoutCore(layout: layout, content: section.content)
                            .frame(maxWidth: .infinity, alignment: chromeAlignment)
                    } header: {
                        section.header.frame(maxWidth: .infinity, alignment: chromeAlignment)
                    } footer: {
                        section.footer.frame(maxWidth: .infinity, alignment: chromeAlignment)
                    }
                })
        }
    }

    /// A horizontal grid section by section: each section's header down the
    /// rows, its views flowed after it, its footer down them after that —
    /// SwiftUI's vertical rule turned on its side (measured on macOS 15.8).
    private var sectionedRow: some View {
        Group(sections: content) { [layout, pinnedViews, chromeAlignment] sections in
            _HStackCore(
                alignment: chromeAlignment.vertical, spacing: layout.spacing, overflow: .window,
                pinnedViews: pinnedViews,
                content: ForEach(sections) { section in
                    Section {
                        _LayoutCore(layout: layout, content: section.content)
                            .frame(maxHeight: .infinity, alignment: chromeAlignment)
                    } header: {
                        section.header.frame(maxHeight: .infinity, alignment: chromeAlignment)
                    } footer: {
                        section.footer.frame(maxHeight: .infinity, alignment: chromeAlignment)
                    }
                })
        }
    }

    /// Whether a `Section` is among the grid's views — asked of a walk that
    /// keeps sections whole, to be found (`RenderContext.keepsSectionsWhole`).
    ///
    /// The content's type is asked first (``mayHandOver(_:in:)``), so a
    /// grid of a `ForEach` of cells — nearly every grid — resolves no child to
    /// learn it has no sections: that walk is a full resolve of every cell,
    /// under a context the layout's own resolve does not share, on every
    /// measure and render.
    private func hasSections(_ context: RenderContext) -> Bool {
        guard mayHandOver(.section, in: content) else { return false }
        return resolveChildViews(from: content, context: context.keepingSectionsWhole()).contains {
            sectionParts(of: $0) != nil
        }
    }

    /// The context the sectioned form is drawn and measured in.
    private func sectionedContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(type: Self.self)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard hasSections(context) else { return measureChild(flat, proposal: proposal, context: context) }
        return measureChild(sectioned, proposal: proposal, context: sectionedContext(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard hasSections(context) else { return TUIkitView.renderToBuffer(flat, context: context) }
        return TUIkitView.renderToBuffer(sectioned, context: sectionedContext(context))
    }
}

// MARK: - LazyHGrid

/// A grid that grows rightward, flowing its content down a fixed set of rows.
///
/// Mirrors SwiftUI's `LazyHGrid`, and the horizontal mirror of ``LazyVGrid`` in
/// every respect: the rows are the fixed tracks, and content wraps into a new
/// column each time it fills them.
///
/// ```swift
/// ScrollView(.horizontal) {
///     LazyHGrid(rows: [GridItem(.fixed(1)), GridItem(.fixed(1))]) {
///         ForEach(items) { Text($0.name) }
///     }
/// }
/// ```
///
/// Rows are measured in **lines**, so `.fixed(1)` is a single-line row — the
/// usual case in a terminal, and why an explicit `.fixed` is more useful here
/// than the `.adaptive` that suits columns.
///
/// # Sections
///
/// A `Section` among the grid's views starts a new column with its header,
/// which spans every row; its views flow down the rows from the column after
/// it, and its footer spans the rows after them — ``LazyVGrid``'s sections on
/// their side, as SwiftUI's are (measured on macOS 15.8). With `pinnedViews:`,
/// they pin to the enclosing horizontal scroll view's leading and trailing
/// edges exactly as a ``LazyHStack``'s do.
///
/// ```swift
/// ScrollView(.horizontal) {
///     LazyHGrid(rows: [GridItem(.fixed(1)), GridItem(.fixed(1))], pinnedViews: .sectionHeaders) {
///         ForEach(albums) { album in
///             Section(album.title) {
///                 ForEach(album.photos) { Text($0.caption) }
///             }
///         }
///     }
/// }
/// ```
///
/// A sectioned grid fills the height it is offered, so a section's header
/// can sit down it.
public struct LazyHGrid<Content: View>: View {
    /// The row tracks.
    public let rows: [GridItem]

    /// Where content sits in a cell, unless its row says otherwise.
    public let alignment: VerticalAlignment

    /// Blank columns between the grid's columns.
    public let spacing: Int

    /// The views to flow.
    public let content: Content

    /// The kinds of child views pinned to the enclosing scroll view's edges.
    let pinnedViews: PinnedScrollableViews

    /// Creates a horizontally-growing grid.
    ///
    /// - Parameters:
    ///   - rows: The row tracks to flow content down.
    ///   - alignment: Vertical placement within a cell, and of a section's
    ///     header and footer down the grid (default: `.center`).
    ///   - spacing: Blank columns between columns, or `nil` (the default) for
    ///     one, the gap an `HStack` leaves, so the words of two columns do not
    ///     run together.
    ///   - pinnedViews: The kinds of child views that will be pinned to the
    ///     enclosing horizontal scroll view's leading and trailing edges: the
    ///     headers and footers of the grid's `Section`s (default: none). See
    ///     the discussion above.
    ///   - content: The views to flow.
    public init(
        rows: [GridItem],
        alignment: VerticalAlignment = .center,
        spacing: Int? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing ?? 1
        self.content = content()
        self.pinnedViews = pinnedViews
    }

    public var body: some View {
        _LazyGridSections(
            layout: _LazyGridLayout(
                axis: .horizontal, items: rows,
                alignment: Alignment(horizontal: .center, vertical: alignment),
                spacing: spacing),
            pinnedViews: pinnedViews,
            content: content)
    }
}
