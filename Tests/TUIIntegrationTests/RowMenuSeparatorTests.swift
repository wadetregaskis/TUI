//  🖥️ TUI — A Terminal UI framework for Swift
//  RowMenuSeparatorTests.swift
//
//  A row menu's `Divider` and `Section`s draw as every other TUI menu draws
//  them: a divider as wide as the items give the menu, and a rule between
//  sections (tuitree's feedback, Milestone 2 item 2: a `Divider` drew a
//  table's selection menu across the whole terminal, and sections drew no
//  rule).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
import TUITesting

private struct SeparatedItem: Identifiable {
    let id: Int
    var name: String { "Row \(id)" }
}

/// A table whose selection menu is `items`.
private struct SeparatedTable<Items: View>: View {
    let items: Items
    @State private var selection: Int? = 0

    var body: some View {
        Table((0..<5).map(SeparatedItem.init), selection: $selection) {
            TableColumn("Name", value: \.name)
        }
        .contextMenu(forSelectionType: Int.self) { _ in
            items
        } primaryAction: { _ in
        }
    }
}

/// The items, as a view of the app's own, as tuitree writes them.
private struct DividedItems: View {
    var body: some View {
        Button("First") {}
        Divider()
        Button("Second") {}
    }
}

private struct SectionedItems: View {
    var body: some View {
        Section { Button("First") {} }
        Section { Button("Second") {} }
    }
}

@MainActor
@Suite("A row menu's separators")
struct RowMenuSeparatorTests {
    /// The menu's rows between its borders, each trimmed: a rule reads `-`.
    private func menuRows(_ app: TestApp) throws -> (rows: [String], width: Int) {
        let lines = app.screen.lines
        let first = try #require(lines.firstIndex { $0.contains("First") })
        let top = try #require(lines[..<first].lastIndex { $0.contains("╭") })
        let bottom = try #require(lines[first...].firstIndex { $0.contains("╰") })
        let border = Array(lines[top])
        let left = try #require(border.firstIndex(of: "╭"))
        let right = try #require(border.firstIndex(of: "╮"))
        let width = right - left + 1
        let rows = lines[(top + 1)..<bottom].map { line -> String in
            let cells = Array(line).dropFirst(left).prefix(width)
            let inside = String(cells).trimmingCharacters(in: .init(charactersIn: "│ "))
            return !inside.isEmpty && inside.allSatisfy { $0 == "─" } ? "-" : inside
        }
        return (rows, width)
    }

    @Test("A divider draws the menu as wide as its items, and a rule that wide")
    func dividerTakesTheItemsWidth() throws {
        let app = TestApp(width: 60, height: 20) { SeparatedTable(items: DividedItems()) }
        app.press(.f10, modifiers: .shift)
        let (rows, width) = try menuRows(app)
        #expect(width < 20, "\(app.screen)")
        #expect(rows == ["First", "-", "Second"], "\(app.screen)")
    }

    @Test("Sections draw a rule between them")
    func sectionsDrawARule() throws {
        let app = TestApp(width: 60, height: 20) { SeparatedTable(items: SectionedItems()) }
        app.press(.f10, modifiers: .shift)
        let (rows, _) = try menuRows(app)
        #expect(rows == ["First", "-", "Second"], "\(app.screen)")
    }
}
