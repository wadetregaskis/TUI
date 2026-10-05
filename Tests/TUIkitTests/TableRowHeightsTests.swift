//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowHeightsTests.swift
//
//  `.tableRowHeights(_:)` (decisions B44): by default a cell is one line
//  unless its column's `lineLimit(_:)` allows more; `.automatic` grows a row
//  to its content-closure cells' natural height, as SwiftUI's table does;
//  `.automaticExceptText` grows it only for cells that are not a `Text`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Table row heights")
struct TableRowHeightsTests {
    private struct Person: Identifiable {
        let id: Int
        var name: String { "name\(id)" }
        var email: String { "e\(id)@x" }
        var phone: String { "p\(id)" }
        var notes: String { "one two three four five six seven eight nine ten" }
    }

    private let people = (1...3).map(Person.init)

    private func table(_ heights: TableRowHeights, statedLimit: Bool = false) -> some View {
        Table(people) {
            TableColumn("Name", value: \.name).width(8)
            if statedLimit {
                TableColumn("Contact") { (person: Person) in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: person.email)
                        Text(verbatim: person.phone)
                    }
                }
                .width(10).lineLimit(1)
            } else {
                TableColumn("Contact") { (person: Person) in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: person.email)
                        Text(verbatim: person.phone)
                    }
                }
                .width(10)
            }
            TableColumn("Notes") { (person: Person) in Text(verbatim: person.notes) }.width(16)
        }
        .tableRowHeights(heights)
    }

    private func lines(_ view: some View) -> [String] {
        let context = makeRenderContext(width: 50, height: 30)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    /// The lines between the rows' first and the next row's.
    private func rowHeight(_ lines: [String]) -> Int? {
        guard let first = lines.firstIndex(where: { $0.contains("name1") }),
            let second = lines.firstIndex(where: { $0.contains("name2") })
        else { return nil }
        return second - first
    }

    @Test("By default a view cell is one line, its second line clipped")
    func defaultIsOneLine() throws {
        let drawn = lines(table(.lineLimited))
        #expect(rowHeight(drawn) == 1, "\(drawn.joined(separator: "\n"))")
        #expect(!drawn.contains { $0.contains("p1") })
    }

    @Test("Automatic grows a row to its view cell, and wraps a Text cell at its column's width")
    func automaticGrows() throws {
        let drawn = lines(table(.automatic))
        let height = try #require(rowHeight(drawn), "\(drawn.joined(separator: "\n"))")
        #expect(drawn.contains { $0.contains("p1") }, "\(drawn.joined(separator: "\n"))")
        // Fifty characters of notes in sixteen cells: four lines, the tallest cell.
        #expect(height == 4, "\(drawn.joined(separator: "\n"))")
    }

    @Test("Automatic except Text grows a row to its view cell and keeps a Text cell to one line")
    func automaticExceptText() throws {
        let drawn = lines(table(.automaticExceptText))
        #expect(rowHeight(drawn) == 2, "\(drawn.joined(separator: "\n"))")
        #expect(drawn.contains { $0.contains("p1") })
    }

    @Test("A column that states its line limit keeps it")
    func statedLimitKept() throws {
        let drawn = lines(table(.automaticExceptText, statedLimit: true))
        #expect(rowHeight(drawn) == 1, "\(drawn.joined(separator: "\n"))")
    }

    @Test("A view that fills what it is offered keeps to its own height")
    func greedyViewKeepsItsHeight() throws {
        let view = Table(people) {
            TableColumn("Name", value: \.name).width(8)
            TableColumn("Gap") { (_: Person) in
                VStack(spacing: 0) {
                    Text(verbatim: "top")
                    Spacer(minLength: 0)
                }
            }
            .width(6)
        }
        .tableRowHeights(.automatic)
        let drawn = lines(view)
        #expect(rowHeight(drawn) == 1, "\(drawn.joined(separator: "\n"))")
    }
}
