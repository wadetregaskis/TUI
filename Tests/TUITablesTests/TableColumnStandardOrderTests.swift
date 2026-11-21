//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnStandardOrderTests.swift
//
//  A column of strings given no comparator sorts as Finder lists names on
//  every platform, as SwiftUI's does on a Mac, and every SwiftUI call shape
//  of `TableColumn(_:value:)` still resolves where it did.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITables

@MainActor
@Suite("A string column's default order")
struct TableColumnStandardOrderTests {
    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
    }

    private static let rows = ["item10", "item2", "Item1", "apple", "Zebra"].enumerated().map {
        Row(id: $0.offset, name: $0.element)
    }

    /// Finder's order, and `.localizedStandard`'s: case aside, numbers by
    /// their value.
    private static let natural = ["apple", "Item1", "item2", "item10", "Zebra"]

    /// The names in the order `comparator` sorts the rows, or `nil` where the
    /// column cannot sort or sorts by something else.
    private func names(sortedBy comparator: Any?) -> [String]? {
        guard let comparator = comparator as? KeyPathComparator<Row> else { return nil }
        return Self.rows.sorted(using: comparator).map(\.name)
    }

    private static let variableTitle = "Name"

    @TableColumnBuilder<Row, KeyPathComparator<Row>>
    private var sortable: some TableColumnContent<Row, KeyPathComparator<Row>> {
        TableColumn("Name", value: \.name)
        TableColumn(Self.variableTitle, value: \.name)
        TableColumn(Text(verbatim: "Name"), value: \.name)
        TableColumn("Name", value: \.name) { Text(verbatim: $0.name) }
    }

    @TableColumnBuilder<Row, KeyPathComparator<Row>>
    private var named: some TableColumnContent<Row, KeyPathComparator<Row>> {
        TableColumn("Name", value: \.name, comparator: .lexical)
        TableColumn(Self.variableTitle, value: \.name, comparator: .lexical)
        TableColumn(Text(verbatim: "Name"), value: \.name, comparator: .lexical)
    }

    @TableColumnBuilder<Row, Never>
    private var unsortable: some TableColumnContent<Row, Never> {
        TableColumn("Name", value: \.name)
        TableColumn(Self.variableTitle, value: \.name)
        TableColumn(Text(verbatim: "Name"), value: \.name)
    }

    @TableColumnBuilder<Row, SortDescriptor<Row>>
    private var otherComparator: some TableColumnContent<Row, SortDescriptor<Row>> {
        TableColumn("Name", value: \.name)
        TableColumn("Size", sortUsing: SortDescriptor(\Row.id)) { (row: Row) in Text(verbatim: "\(row.id)") }
    }

    @Test("Given no comparator, a column of strings sorts item2 before item10, whatever its title")
    func naturalByDefault() {
        let columns = tableColumns(of: sortable)
        #expect(columns.count == 4)
        for column in columns {
            #expect(names(sortedBy: column.sortComparator) == Self.natural)
        }
        #expect(columns.map(\.title) == ["Name", "Name", "Name", "Name"])
    }

    @Test("A comparator named is the one sorted by")
    func namedComparator() {
        for column in tableColumns(of: named) {
            #expect(names(sortedBy: column.sortComparator) == ["Item1", "Zebra", "apple", "item10", "item2"])
        }
    }

    @Test("In a table that cannot sort, and outside any table, the column cannot sort, as before")
    func unsortableWhereItWas() {
        for column in tableColumns(of: unsortable) {
            #expect(column.sortComparator == nil)
        }
        let literal = TableColumn("Name", value: \Row.name)
        let variable = TableColumn(Self.variableTitle, value: \Row.name)
        let text = TableColumn(Text(verbatim: "Name"), value: \Row.name)
        #expect(type(of: literal) == TableColumn<Row, Never, Text, Text>.self)
        #expect(type(of: variable) == TableColumn<Row, Never, Text, Text>.self)
        #expect(type(of: text) == TableColumn<Row, Never, Text, Text>.self)
    }

    @Test("In a table sorted by another comparator, a string column given none cannot sort, as before")
    func otherComparatorTable() {
        let columns = tableColumns(of: otherComparator)
        #expect(columns[0].sortComparator == nil)
        #expect(columns[1].sortComparator != nil)
    }

    @Test("The order sorts as localizedStandardCompare does, and reverses")
    func localizedStandardOrder() {
        #expect(["item10", "item2"].sorted(using: LocalizedStandardOrder()) == ["item2", "item10"])
        #expect(["item2", "item10"].sorted(using: LocalizedStandardOrder(order: .reverse)) == ["item10", "item2"])
        #expect(LocalizedStandardOrder().compare("a", "a") == .orderedSame)
    }
}
