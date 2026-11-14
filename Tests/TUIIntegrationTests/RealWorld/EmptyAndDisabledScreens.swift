//  🖥️ TUI — A Terminal UI framework for Swift
//  EmptyAndDisabledScreens.swift
//
//  Real-world screens: empty states and disabled pages. A search with no
//  results showing a ContentUnavailableView, an empty table under its header,
//  and a whole page disabled while it loads. An empty control must draw no
//  stray rows, and a disabled page must take no focus until it is enabled.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

/// A search field over a list that is empty until the query matches.
private struct SearchPage: View {
    @State private var query = "zzz"
    private let names = ["Apple", "Apricot", "Banana", "Cherry"]

    var body: some View {
        let matches = names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        VStack(alignment: .leading) {
            TextField("Search", text: $query).focusID("search")
            if matches.isEmpty {
                ContentUnavailableView {
                    Text("No Results")
                } description: {
                    Text("Nothing matches \(query).")
                }
            } else {
                List(matches, id: \.self) { Text($0) }.focusID("results")
            }
        }
    }
}

private struct Invoice: Identifiable, Sendable {
    let id: Int
    var number: String { "INV-\(id)" }
}

/// An empty table of invoices between a title and a New button.
private struct EmptyTablePage: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Invoices")
            Table([Invoice]()) {
                TableColumn("Number", value: \Invoice.number)
                TableColumn("Status") { _ in Text("open") }
            }
            .focusID("invoices")
            Button("New Invoice") {}.focusID("new")
        }
    }
}

@Observable @MainActor private final class Loader { var loading = true }

/// A page of controls disabled while it loads.
private struct LoadingPage: View {
    let loader: Loader
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(loader.loading ? "Loading…" : "Ready")
            TextField("Name", text: $name).focusID("name")
            Toggle("Subscribe", isOn: .constant(true)).focusID("subscribe")
            Button("Save") {}.focusID("save")
        }
        .disabled(loader.loading)
    }
}

@MainActor
@Suite("Real world: empty states and disabled pages")
struct EmptyAndDisabledScreens {
    @Test("A search with no results shows why, and clearing it fills the list", arguments: TerminalSize.all)
    func noResults(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { SearchPage() }
        LayoutSanity.check(app, "launch")
        if size.height >= 12 { #expect(app.screen.contains("No Results"), "no empty state:\n\(app.screen)") }
        for _ in 0..<2 where app.focusedID != "search" { app.press(.tab) }
        #expect(app.focusedID == "search")
        app.press(.backspace, times: 3)
        LayoutSanity.check(app, "query cleared")
        LayoutSanity.expectContiguous(app, ["Apple", "Apricot", "Banana", "Cherry"], "the results")
        app.type("ap")
        LayoutSanity.check(app, "typed ap")
        #expect(!app.screen.contains("Cherry"), "the list was not filtered:\n\(app.screen)")
    }

    @Test("An empty table: its header, no stray rows, the button under it reachable", arguments: TerminalSize.all)
    func emptyTable(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { EmptyTablePage() }
        LayoutSanity.check(app, "launch")
        LayoutSanity.reach("New Invoice", in: app, by: .tab, limit: 3)
        app.press(.down)
        app.press(.end)
        LayoutSanity.check(app, "keys on the empty table")
    }

    @Test("A page disabled while it loads takes no focus, then all of it once loaded", arguments: TerminalSize.all)
    func disabledWhileLoading(size: TerminalSize) {
        let loader = Loader()
        let app = TestApp(width: size.width, height: size.height) { LoadingPage(loader: loader) }
        LayoutSanity.check(app, "launch")
        app.press(.tab, times: 3)
        #expect(app.focusedID == nil, "a disabled control took the focus: \(app.focusedID ?? "")")
        loader.loading = false
        app.advance(by: .milliseconds(20))
        var seen: Set<String> = []
        for step in 0..<4 {
            app.press(.tab)
            LayoutSanity.check(app, "Tab ×\(step + 1) once loaded")
            if let focused = app.focusedID { seen.insert(focused) }
        }
        #expect(seen.isSuperset(of: ["name", "subscribe", "save"]), "Tab visited only \(seen.sorted())")
    }
}
