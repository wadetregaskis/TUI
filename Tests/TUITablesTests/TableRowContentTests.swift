//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowContentTests.swift
//
//  SwiftUI's row surface: a table whose rows come from a row builder —
//  `TableRow`s, `ForEach`, `Group`, an `if` — rather than from a collection.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITables
@testable import TUITestSupport

@MainActor
@Suite("Table row content")
struct TableRowContentTests {

    private struct Person: Identifiable, Sendable {
        let id: Int
        let name: String
    }

    private static let people = [
        Person(id: 1, name: "alpha"), Person(id: 2, name: "bravo"), Person(id: 3, name: "charlie"),
    ]

    /// The names a table draws, top to bottom.
    private func names<V: View>(_ view: V) -> [String] {
        let buffer = renderToBuffer(view, context: makeRenderContext(width: 40, height: 20))
        return buffer.lines.dropFirst(2).compactMap { line in
            let text = line.stripped
                .replacingOccurrences(of: "│", with: "")
                .trimmingCharacters(in: .whitespaces)
            return text.isEmpty || text.hasPrefix("╰") ? nil : text
        }
    }

    @Test("TableRow, ForEach and an if build the rows in order")
    func rowsInOrder() {
        func table(withLast: Bool) -> some View {
            Table(of: Person.self) {
                TableColumn("Name", value: \.name)
            } rows: {
                TableRow(Person(id: 0, name: "first"))
                ForEach(Self.people) { person in
                    TableRow(person)
                }
                if withLast {
                    TableRow(Person(id: 9, name: "last"))
                }
            }
        }
        #expect(names(table(withLast: true)) == ["first", "alpha", "bravo", "charlie", "last"])
        #expect(names(table(withLast: false)) == ["first", "alpha", "bravo", "charlie"])
    }

    @Test("ForEach(_:) alone builds one TableRow per element")
    func forEachOfData() {
        let table = Table(of: Person.self) {
            TableColumn("Name", value: \.name)
        } rows: {
            ForEach(Self.people)
        }
        #expect(names(table) == ["alpha", "bravo", "charlie"])
    }

    @Test("A Group and an if/else contribute their rows in place")
    func groupAndEither() {
        func table(reversed: Bool) -> some View {
            Table(of: Person.self) {
                TableColumn("Name", value: \.name)
            } rows: {
                Group {
                    TableRow(Self.people[0])
                    TableRow(Self.people[1])
                }
                if reversed {
                    TableRow(Person(id: 8, name: "yes"))
                } else {
                    TableRow(Person(id: 7, name: "no"))
                }
            }
        }
        #expect(names(table(reversed: true)) == ["alpha", "bravo", "yes"])
        #expect(names(table(reversed: false)) == ["alpha", "bravo", "no"])
    }

    /// Row content of an app's own type, its rows in its body.
    private struct Everyone: TableRowContent {
        let people: [Person]

        @TableRowBuilder<Person>
        var tableRowBody: some TableRowContent<Person> {
            TableRow(Person(id: 0, name: "header"))
            ForEach(people) { TableRow($0) }
        }
    }

    @Test("Row content of an app's own type contributes its body's rows")
    func customRowContent() {
        let table = Table(of: Person.self) {
            TableColumn("Name", value: \.name)
        } rows: {
            Everyone(people: Self.people)
        }
        #expect(names(table) == ["header", "alpha", "bravo", "charlie"])
    }

    @Test("A sortable table of rows infers its value type from its columns and rows")
    func sortableWithoutOf() {
        var selection: Person.ID? = 2
        let table = Table(
            selection: Binding(get: { selection }, set: { selection = $0 }),
            sortOrder: .constant([KeyPathComparator(\Person.name)])
        ) {
            TableColumn("Name", value: \.name)
        } rows: {
            ForEach(Self.people)
        }
        #expect(names(table).count == 3)
        let buffer = renderToBuffer(table, context: makeRenderContext(width: 40, height: 20))
        #expect(buffer.lines[1].stripped.contains("Name ▲"))
    }

    @Test("ForEach exposes the data and the content function it was built with")
    func forEachDataAndContent() {
        let loop = ForEach(Self.people) { TableRow($0) }
        #expect(loop.data.map(\.id) == [1, 2, 3])
        #expect(loop.content(Self.people[1]).value.name == "bravo")
        let dynamic: some DynamicTableRowContent = loop
        #expect(dynamic.data.count == 3)
    }

    @Test("A row builder of ten statements builds ten rows")
    func tenRows() {
        let rows = tableRows(
            of: TableRowBuilder<Person>.buildBlock(
                TableRow(Person(id: 1, name: "1")), TableRow(Person(id: 2, name: "2")),
                TableRow(Person(id: 3, name: "3")), TableRow(Person(id: 4, name: "4")),
                TableRow(Person(id: 5, name: "5")), TableRow(Person(id: 6, name: "6")),
                TableRow(Person(id: 7, name: "7")), TableRow(Person(id: 8, name: "8")),
                TableRow(Person(id: 9, name: "9")), TableRow(Person(id: 10, name: "10"))))
        #expect(rows.values.map(\.id) == Array(1...10))
    }
}
