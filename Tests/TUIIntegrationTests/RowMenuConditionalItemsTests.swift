//  🖥️ TUI — A Terminal UI framework for Swift
//  RowMenuConditionalItemsTests.swift
//
//  A row menu whose items are a view of the app's with an `if` among its
//  buttons runs the button chosen, in a `Table`'s and a `List`'s selection
//  menu alike (tuitree's feedback, Milestone 2 item 1: Duplicate ran Copy
//  PlistBuddy Path).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

@MainActor
private final class Fired {
    var names: [String] = []
}

/// Three buttons, then two inside an `if`: the shape that ran the `if`'s
/// buttons for the first two.
private struct ConditionalItems: View {
    let fired: Fired

    var body: some View {
        Button("Alpha") { fired.names.append("Alpha") }
        Button("Bravo") { fired.names.append("Bravo") }
        Button("Charlie") { fired.names.append("Charlie") }
        if fired.names.count < 100 {
            Button("Delta") { fired.names.append("Delta") }
            Button("Echo") { fired.names.append("Echo") }
        }
    }
}

private struct ConditionalItem: Identifiable {
    let id: Int
    var name: String { "Row \(id)" }
}

private struct ConditionalTable: View {
    let fired: Fired
    @State private var selection: Int? = 0

    var body: some View {
        Table((0..<5).map(ConditionalItem.init), selection: $selection) {
            TableColumn("Name", value: \.name)
        }
        .contextMenu(forSelectionType: Int.self) { _ in
            ConditionalItems(fired: fired)
        } primaryAction: { _ in
        }
    }
}

private struct ConditionalList: View {
    let fired: Fired
    @State private var selection: Int? = 0

    var body: some View {
        List((0..<5).map(ConditionalItem.init), selection: $selection) { item in
            Text(item.name)
        }
        .contextMenu(forSelectionType: Int.self) { _ in
            ConditionalItems(fired: fired)
        } primaryAction: { _ in
        }
    }
}

private struct Counter: View {
    let name: String
    @State private var count = 0

    var body: some View {
        Button("\(name) \(count)") { count += 1 }
    }
}

/// Counters before an `if` of counters: drawn whole, as an `AnyView` draws a
/// view of the app's own, the `if`'s first counter shared the first counter's
/// `@State`.
private struct Counters: View {
    let shows: Bool

    var body: some View {
        Counter(name: "A")
        Counter(name: "B")
        if shows {
            Counter(name: "D")
            Counter(name: "E")
        }
    }
}

@MainActor
@Suite("A row menu's items with an if among them")
struct RowMenuConditionalItemsTests {
    /// Opens the menu by Shift-F10 and picks each of `names` by a click.
    private func choose(_ names: [String], in app: TestApp) throws {
        for name in names {
            app.press(.f10, modifiers: .shift)
            try app.click(name)
        }
    }

    @Test("A table's selection menu runs the item chosen")
    func tableRunsChosenItem() throws {
        let fired = Fired()
        let app = TestApp(width: 60, height: 20) { ConditionalTable(fired: fired) }
        try choose(["Alpha", "Bravo", "Charlie", "Delta", "Echo"], in: app)
        #expect(fired.names == ["Alpha", "Bravo", "Charlie", "Delta", "Echo"])
    }

    @Test("A list's selection menu runs the item chosen")
    func listRunsChosenItem() throws {
        let fired = Fired()
        let app = TestApp(width: 60, height: 20) { ConditionalList(fired: fired) }
        try choose(["Alpha", "Bravo", "Charlie", "Delta", "Echo"], in: app)
        #expect(fired.names == ["Alpha", "Bravo", "Charlie", "Delta", "Echo"])
    }

    @Test("A plain context menu runs the item chosen")
    func contextMenuRunsChosenItem() throws {
        let fired = Fired()
        let app = TestApp(width: 60, height: 20) {
            Button("Target") {}.contextMenu { ConditionalItems(fired: fired) }
        }
        for name in ["Alpha", "Bravo", "Charlie", "Delta", "Echo"] {
            app.press(.f10, modifiers: .shift)
            try app.click(name)
        }
        #expect(fired.names == ["Alpha", "Bravo", "Charlie", "Delta", "Echo"])
    }

    @Test("Drawn whole, the views of an if keep their state apart from the views before them")
    func wholeDrawnConditionalKeepsItsOwnState() throws {
        let app = TestApp(width: 40, height: 10) { AnyView(Counters(shows: true)) }
        try app.click("A 0")
        try app.click("E 0")
        #expect(app.screen.contains("A 1"), "\(app.screen)")
        #expect(app.screen.contains("B 0"), "\(app.screen)")
        #expect(app.screen.contains("D 0"), "\(app.screen)")
        #expect(app.screen.contains("E 1"), "\(app.screen)")
    }

    @Test("Chosen by the keyboard, a table's selection menu runs the item highlighted")
    func tableRunsHighlightedItem() {
        let fired = Fired()
        let app = TestApp(width: 60, height: 20) { ConditionalTable(fired: fired) }
        for downs in 0..<5 {
            app.press(.f10, modifiers: .shift)
            if downs > 0 { app.press(.down, times: downs) }
            app.press(.enter)
        }
        #expect(fired.names == ["Alpha", "Bravo", "Charlie", "Delta", "Echo"])
    }
}
