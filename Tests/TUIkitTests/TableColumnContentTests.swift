//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnContentTests.swift
//
//  SwiftUI's column surface: a column's cell is a view built from the row,
//  columns sort with whatever comparator the table's sort order holds, and a
//  sortable table takes columns that cannot sort beside the ones that can.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Table column content")
struct TableColumnContentTests {

    private struct Row: Identifiable, Sendable, Equatable {
        let id: Int
        let name: String
        let size: Int
    }

    private static let rows = [
        Row(id: 1, name: "alpha", size: 30),
        Row(id: 2, name: "bravo", size: 10),
    ]

    private func render<V: View>(_ view: V, width: Int = 40, height: Int = 10) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
    }

    /// The text of the line holding `needle`, with the escapes stripped.
    private func line(containing needle: String, in buffer: FrameBuffer) -> String? {
        buffer.lines.map(\.stripped).first { $0.contains(needle) }
    }

    // MARK: Cells

    @Test("A plain Text cell draws the same bytes as the String key-path column")
    func plainTextMatchesKeyPath() {
        let keyPath = render(Table(Self.rows) { TableColumn("Name", value: \Row.name) })
        let text = render(Table(Self.rows) { TableColumn("Name") { (row: Row) in Text(row.name) } })
        #expect(keyPath.lines == text.lines)
    }

    @Test("A content closure that builds a Text takes the text path; any other view, the view path")
    func textClosureTakesTextPath() {
        // Both draw the same bytes, so only the path says which was taken: a
        // Text closure that fell to the view path would render every cell.
        let text = _TableCellSource<Row>.content { (row: Row) in Text(row.name) }
        let view = _TableCellSource<Row>.content { (row: Row) in Text(row.name).padding(.leading, 1) }
        if case .text(let make) = text {
            #expect(make(Self.rows[0]).content == "alpha")
        } else {
            Issue.record("a Text content closure took the view path")
        }
        if case .text = view { Issue.record("a padded Text took the text path") }
    }

    @Test("Any other view is rendered into its cell")
    func viewCell() {
        let buffer = render(
            Table(Self.rows) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size") { (row: Row) in
                    HStack(spacing: 0) {
                        Text(verbatim: "<")
                        Text(verbatim: "\(row.size)")
                        Text(verbatim: ">")
                    }
                }
            })
        #expect(line(containing: "alpha", in: buffer)?.contains("<30>") == true)
        #expect(line(containing: "bravo", in: buffer)?.contains("<10>") == true)
    }

    @Test("A styled Text cell keeps its style")
    func styledTextCell() {
        let buffer = render(Table(Self.rows) { TableColumn("Name") { (row: Row) in Text(row.name).bold() } })
        let raw = buffer.lines.first { $0.stripped.contains("alpha") }
        #expect(raw?.contains("\u{1B}[1") == true)
    }

    @Test("A view cell is one line unless its column's line limit allows more")
    func viewCellLineLimit() {
        func table(lines: Int) -> some View {
            Table(Self.rows) {
                TableColumn("Name") { (row: Row) in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "top-\(row.name)")
                        Text(verbatim: "low-\(row.name)")
                    }
                }
                .lineLimit(lines)
            }
        }
        let one = render(table(lines: 1)).lines.map(\.stripped)
        #expect(one.contains { $0.contains("top-alpha") })
        #expect(!one.contains { $0.contains("low-alpha") })
        let two = render(table(lines: 2)).lines.map(\.stripped)
        let top = two.firstIndex { $0.contains("top-alpha") }
        let low = two.firstIndex { $0.contains("low-alpha") }
        #expect(top != nil && low == top.map { $0 + 1 })
    }

    @Test("A view column fits its widest rendered cell")
    func fitViewColumn() {
        let buffer = render(
            Table(Self.rows) {
                TableColumn("N") { (row: Row) in
                    HStack(spacing: 0) { Text(verbatim: "["); Text(verbatim: row.name); Text(verbatim: "]") }
                }
                .width(.fit)
                TableColumn("After") { (_: Row) in Text(verbatim: "x") }
            })
        // "[alpha]" is seven cells, and the next column starts after the gap.
        let header = buffer.lines[1].stripped
        let after = header.range(of: "After").map { header.distance(from: header.startIndex, to: $0.lowerBound) }
        let cell = line(containing: "[alpha]", in: buffer)
        let cellStart = cell?.range(of: "[alpha]").map { cell!.distance(from: cell!.startIndex, to: $0.lowerBound) }
        #expect(after != nil && cellStart != nil && after! - cellStart! == 7 + 2)
    }

    @Test("A Text label titles its column")
    func textLabel() {
        let buffer = render(Table(Self.rows) { TableColumn(Text(verbatim: "Title"), value: \Row.name) })
        #expect(buffer.lines[1].stripped.contains("Title"))
    }

    // MARK: Sorting

    @Test("A sortable table takes a column that cannot sort, and only the sortable one is marked")
    func mixedSortability() {
        let buffer = render(
            Table(Self.rows, sortOrder: .constant([KeyPathComparator(\Row.name)])) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size") { (row: Row) in Text(verbatim: "\(row.size)") }
            })
        let header = buffer.lines[1].stripped
        #expect(header.contains("Name ▲"))
        #expect(!header.contains("Size ▲") && !header.contains("Size ▼"))
    }

    @Test("A String key-path column in a sortable table is the sortable overload")
    func stringColumnSortsInASortableTable() {
        let column: TableColumn<Row, KeyPathComparator<Row>, Text, Text> =
            TableColumnBuilder<Row, KeyPathComparator<Row>>.buildExpression(
                TableColumn("Name", value: \Row.name))
        #expect(column.sortComparator?.keyPath == \Row.name)
    }

    @Test("sortUsing: sorts with the comparator it was given")
    func sortUsingComparator() {
        var order = [SortDescriptor(\Row.size)]
        let binding = Binding(get: { order }, set: { order = $0 })
        let columns = tableColumns(
            of: TableColumnBuilder<Row, SortDescriptor<Row>>.buildBlock(
                TableColumn("Name", sortUsing: SortDescriptor(\Row.name)) { (row: Row) in Text(row.name) },
                TableColumn("Size", sortUsing: SortDescriptor(\Row.size)) { (row: Row) in
                    Text(verbatim: "\(row.size)")
                }))
        let model = _TableSortModel(binding)
        // The primary sort is the Size column's, ascending.
        #expect(model.primaryOrder(columns[1].sortComparator!) == .forward)
        #expect(model.primaryOrder(columns[0].sortComparator!) == nil)
        // A click on Name makes it primary, ascending, with Size behind it.
        model.toggle(columns[0].sortComparator!)
        #expect(order == [SortDescriptor(\Row.name), SortDescriptor(\Row.size)])
        // A second click reverses it.
        model.toggle(columns[0].sortComparator!)
        #expect(order.first?.order == .reverse)
        #expect(order.count == 2)
    }

    // MARK: Alignment

    @Test("Each TableColumnAlignment places its column", arguments: [
        (TableColumnAlignment.automatic, HorizontalAlignment.leading),
        (.leading, .leading), (.center, .center), (.trailing, .trailing),
        (.numeric, .trailing), (.numeric(Locale.NumberingSystem("arab")), .trailing),
    ])
    func alignmentPlacement(_ alignment: TableColumnAlignment, _ expected: HorizontalAlignment) {
        let columns = tableColumns(of: TableColumn("Name", value: \Row.name).alignment(alignment))
        #expect(columns.map(\.alignment) == [expected])
    }

    @Test("A numeric column right-aligns its header and its cells")
    func numericDrawsTrailing() {
        let buffer = render(
            Table(Self.rows) {
                TableColumn("N") { (row: Row) in Text(verbatim: "\(row.size)") }
                    .width(6)
                    .alignment(.numeric)
                TableColumn("Name", value: \Row.name)
            })
        // Inside the border and its padding, the six-cell column ends at 8.
        #expect(buffer.lines[1].stripped.dropFirst(2).prefix(6) == "     N")
        #expect(line(containing: "alpha", in: buffer)?.dropFirst(2).prefix(6) == "    30")
    }

    @Test("An alignment on a group of columns yields to one a column states itself")
    func nearestAlignmentWins() {
        let columns = tableColumns(
            of: Group {
                TableColumn("A", value: \Row.name).alignment(.center)
                TableColumn("B", value: \Row.name)
            }
            .alignment(.trailing))
        #expect(columns.map(\.alignment) == [.center, .trailing])
    }

    // MARK: Width

    @Test("width(_:) fixes a column, and width(nil) changes nothing")
    func fixedWidth() {
        let column = TableColumn("Name", value: \Row.name)
        #expect(column.width(7).spec.width == .fixed(7))
        #expect(column.width(.fit).width(nil).spec.width == .fit)
        #expect(column.width(-3).spec.width == .fixed(0))
    }

    @Test("width(min:ideal:max:) keeps a bound it is not given")
    func boundsAccumulate() {
        let column = TableColumn("Name", value: \Row.name).width(min: 4).width(max: 9)
        #expect(column.spec.width == .flexible(min: 4, ideal: nil, max: 9))
    }

    @Test("Bounded columns start at their ideal and share the rest, as SwiftUI's do")
    func sharingMatchesSwiftUI() {
        // SwiftUI on macOS 26.2: three resizable columns sharing 457 points —
        // (min 40, ideal 90, max 200), (ideal 120), and an unbounded one whose
        // ideal is NSTableColumn's 100 — ended at 139, 169 and 149.
        #expect(
            TableFlexibleWidths.widths(
                [(40, 90, 200), (nil, 120, nil), (nil, 100, nil)], sharing: 457)
                == [139, 169, 149])
        // Unbounded columns split evenly, the first taking the odd cells.
        #expect(TableFlexibleWidths.widths([(nil, nil, nil), (nil, nil, nil)], sharing: 7) == [4, 3])
        // A maximum caps a column and hands its share to the others.
        #expect(TableFlexibleWidths.widths([(nil, nil, 2), (nil, nil, nil)], sharing: 10) == [2, 8])
        // Ideals that do not fit shrink toward the minimums.
        #expect(TableFlexibleWidths.widths([(2, 10, nil), (4, 10, nil)], sharing: 10) == [4, 6])
        // Minimums that do not fit are kept, and the row clips.
        #expect(TableFlexibleWidths.widths([(8, nil, nil), (8, nil, nil)], sharing: 10) == [8, 8])
    }

    @Test("A bounded column is laid out within its bounds")
    func boundedColumnDraws() {
        let buffer = render(
            Table(Self.rows) {
                TableColumn("Name", value: \Row.name).width(max: 5)
                TableColumn("Size") { (row: Row) in Text(verbatim: "\(row.size)") }
            },
            width: 40)
        // The five-cell name column ends before the gap; "alpha" just fits.
        let header = buffer.lines[1].stripped
        let size = header.range(of: "Size").map { header.distance(from: header.startIndex, to: $0.lowerBound) }
        #expect(size == 2 + 5 + 2)
    }

    // MARK: Builder

    @Test("A column list of ten builds ten columns")
    func tenColumns() {
        let columns = tableColumns(
            of: TableColumnBuilder<Row, Never>.buildBlock(
                TableColumn("1", value: \Row.name), TableColumn("2", value: \Row.name),
                TableColumn("3", value: \Row.name), TableColumn("4", value: \Row.name),
                TableColumn("5", value: \Row.name), TableColumn("6", value: \Row.name),
                TableColumn("7", value: \Row.name), TableColumn("8", value: \Row.name),
                TableColumn("9", value: \Row.name), TableColumn("10", value: \Row.name)))
        #expect(columns.map(\.title) == (1...10).map(String.init))
    }

    @Test("An optional column contributes only when present")
    func optionalColumn() {
        let present: TableColumn<Row, Never, Text, Text>? = TableColumn("Name", value: \Row.name)
        let absent: TableColumn<Row, Never, Text, Text>? = nil
        // Inferred on purpose: `Optional<…>.TableRowValue` is the alias a debug
        // build has to round-trip, which crashed the asserts compiler while
        // Optional declared it once per conformance (see `_TableRowValued`).
        let presentColumns = tableColumns(of: present)
        let absentColumns = tableColumns(of: absent)
        #expect(presentColumns.count == 1)
        #expect(absentColumns.isEmpty)
    }
}
