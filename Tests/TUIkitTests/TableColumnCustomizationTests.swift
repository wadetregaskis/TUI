//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnCustomizationTests.swift
//
//  Which columns a table shows: a column's default visibility, and a
//  TableColumnCustomization the table is bound to — what SwiftUI measured on
//  macOS 26.2 does with each.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("Table column customization")
struct TableColumnCustomizationTests {

    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
        let age: Int
    }

    private static let rows = [Row(id: 1, name: "alpha", age: 30)]

    /// The titles in a table's header line.
    private func headers<V: View>(_ view: V) -> [String] {
        let buffer = renderToBuffer(view, context: makeRenderContext(width: 50, height: 8))
        guard buffer.lines.count > 1 else { return [] }
        return buffer.lines[1].stripped.split(separator: " ").map(String.init).filter { $0 != "│" }
    }

    @Test("A column hidden by default is not shown, with no customization bound")
    func defaultHidden() {
        let table = Table(Self.rows) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Age") { (row: Row) in Text(verbatim: "\(row.age)") }
                .defaultVisibility(.hidden)
        }
        #expect(headers(table) == ["Name"])
    }

    @Test("A customization shows, hides, and leaves to the default")
    func customizationDecides() {
        var customization = TableColumnCustomization<Row>()
        func table() -> some View {
            Table(
                Self.rows,
                columnCustomization: Binding(get: { customization }, set: { customization = $0 })
            ) {
                TableColumn("Name", value: \Row.name).customizationID("name")
                TableColumn("Age") { (row: Row) in Text(verbatim: "\(row.age)") }
                    .customizationID("age")
                    .defaultVisibility(.hidden)
                TableColumn("Fixed", value: \Row.name)
            }
        }
        #expect(headers(table()) == ["Name", "Fixed"])
        customization[visibility: "age"] = .visible
        #expect(headers(table()) == ["Name", "Age", "Fixed"])
        customization[visibility: "name"] = .hidden
        #expect(headers(table()) == ["Age", "Fixed"])
        customization[visibility: "age"] = .automatic
        #expect(headers(table()) == ["Fixed"])
    }

    @Test("A customization reads automatic until something is stated, whatever the column's default")
    func readsAutomatic() {
        var customization = TableColumnCustomization<Row>()
        #expect(customization[visibility: "anything"] == .automatic)
        customization[visibility: "x"] = .hidden
        #expect(customization[visibility: "x"] == .hidden)
        #expect(customization != TableColumnCustomization<Row>())
        customization[visibility: "x"] = .automatic
        #expect(customization == TableColumnCustomization<Row>())
    }

    @Test("A customization survives encoding, and resetOrder keeps its visibility")
    func codable() throws {
        var customization = TableColumnCustomization<Row>()
        customization[visibility: "age"] = .visible
        customization[visibility: "name"] = .hidden
        let data = try JSONEncoder().encode(customization)
        var decoded = try JSONDecoder().decode(TableColumnCustomization<Row>.self, from: data)
        #expect(decoded == customization)
        decoded.resetOrder()
        #expect(decoded[visibility: "age"] == .visible)
    }

    @Test("A modifier on a group of columns yields to one a column states itself")
    func nearestStatementWins() {
        let columns = tableColumns(
            of: Group {
                TableColumn("A", value: \Row.name).customizationID("a").defaultVisibility(.visible)
                TableColumn("B", value: \Row.name)
            }
            .customizationID("group")
            .defaultVisibility(.hidden)
            .disabledCustomizationBehavior(.resize))
        #expect(columns.map(\.customizationID) == ["a", "group"])
        #expect(columns.map(\.defaultVisibility) == [.visible, .hidden])
        #expect(columns.map(\.disabledCustomizationBehavior) == [.resize, .resize])
    }

    @Test("The customization behaviors are a set")
    func behaviorSet() {
        var behaviors = TableColumnCustomizationBehavior()
        #expect(behaviors.isEmpty)
        #expect(behaviors.insert(.reorder).inserted)
        #expect(!behaviors.insert(.reorder).inserted)
        behaviors.formUnion(.visibility)
        #expect(behaviors.contains(.visibility) && !behaviors.contains(.resize))
        #expect(TableColumnCustomizationBehavior.all == [.reorder, .resize, .visibility])
        #expect(TableColumnCustomizationBehavior.all.subtracting(behaviors) == .resize)
        #expect(behaviors.remove(.reorder) == .reorder)
        #expect(behaviors.remove(.reorder) == nil)
        #expect(behaviors.symmetricDifference(.all) == [.reorder, .resize])
    }
}
