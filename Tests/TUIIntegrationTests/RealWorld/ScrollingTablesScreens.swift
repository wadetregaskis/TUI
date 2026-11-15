//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollingTablesScreens.swift
//
//  Real-world screens: several tables and lists of different lengths stacked
//  in one ScrollView, as a report or an inspector page lays them out. Each
//  must draw its rows with no filler between or after them, and every row of
//  the longest must be reachable by the wheel and the paging keys.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

private struct Server: Identifiable, Sendable {
    let id: Int
    var name: String { "srv-\(id)" }
    var load: String { "\(id * 7 % 100)%" }
}

private func servers(_ range: ClosedRange<Int>) -> [Server] { range.map(Server.init) }

/// A report of three tables, 2, 5 and 30 rows, each under a heading, and a
/// footer below them.
private struct ReportPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach([1...2, 101...105, 201...230], id: \.lowerBound) { range in
                    Text("Group \(range.lowerBound / 100)").bold()
                    Table(servers(range)) {
                        TableColumn("Name", value: \Server.name)
                        TableColumn("Load", value: \Server.load)
                    }
                }
                Text("End of report")
            }
        }
    }
}

/// Two plain lists of 3 and 25 rows in one ScrollView.
private struct TwoListsPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Favourites")
                List(servers(1...3)) { Text($0.name) }
                Text("All servers")
                List(servers(301...325)) { Text($0.name) }
                Button("Refresh") {}
            }
        }
    }
}

/// Sections of a LazyVStack, each a heading and rows of its own length.
private struct LazySectionsPage: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach([2, 7, 1, 20], id: \.self) { count in
                    Section {
                        ForEach(1...count, id: \.self) { row in Text("Item \(count)-\(row)") }
                    } header: {
                        Text("Section of \(count)").bold()
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("Real world: tables and lists of different lengths in one ScrollView")
struct ScrollingTablesScreens {
    @Test("A report of three unequal tables: rows contiguous, the last row and the footer reachable",
          arguments: TerminalSize.all)
    func reportOfThreeTables(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { ReportPage() }
        LayoutSanity.check(app, "launch")
        LayoutSanity.expectContiguous(app, ["srv-1", "srv-2"], "the table of 2")
        LayoutSanity.reach("srv-105", in: app, by: .wheelDown(over: nil))
        LayoutSanity.expectContiguous(app, servers(101...105).map(\.name), "the table of 5")
        LayoutSanity.reach("End of report", in: app, by: .wheelDown(over: nil), limit: 80)
        LayoutSanity.expectContiguous(app, servers(225...230).map(\.name), "the end of the table of 30")
    }

    @Test("A report of three unequal tables: Tab to the last, End, then Page Down shows the footer",
          arguments: TerminalSize.all)
    func reportByKeys(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { ReportPage() }
        for step in 0..<2 {
            app.press(.tab)
            LayoutSanity.check(app, "Tab ×\(step + 1)")
        }
        app.press(.end)
        LayoutSanity.check(app, "End")
        // At 20×6 the names are cut to "srv-2…".
        if size.height >= 12 {
            #expect(LayoutSanity.shows("srv-230", in: app), "End did not reach the last row:\n\(app.screen)")
        }
        // The table at its last row keeps Page Down, so the footer under it,
        // which takes no focus, is out of the keyboard's reach: the wheel
        // alone shows it (SCROLL-FIT's B-SCROLLFIT-5 pages by the outer
        // viewport, but not past a table at its end).
        withKnownIssue("Page Down at a table's last row does not page the scroll view to the footer below") {
            LayoutSanity.reach("End of report", in: app, by: .pageDown, limit: 3)
        } when: {
            !LayoutSanity.shows("End of report", in: app)
        }
    }

    /// Until SCROLL-FIT's P7 a `List` in scroll content filled the unbounded
    /// height it was offered, up to 4,096 rows, blank under its last: a known
    /// issue here until then.
    @Test("Two lists of 3 and 25: no filler under either, the Refresh button reachable by Tab",
          arguments: TerminalSize.all)
    func twoLists(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { TwoListsPage() }
        LayoutSanity.check(app, "launch")
        LayoutSanity.expectNoBlankRows(app, from: "srv-1", to: "All servers", "the short list")
        LayoutSanity.reach("srv-325", in: app, by: .wheelDown(over: nil), limit: 80)
        LayoutSanity.reach("Refresh", in: app, by: .wheelDown(over: nil), limit: 20)
        let tabbed = TestApp(width: size.width, height: size.height) { TwoListsPage() }
        for step in 0..<4 where !(tabbed.focusedID ?? "").hasPrefix("button") {
            tabbed.press(.tab)
            LayoutSanity.check(tabbed, "Tab ×\(step + 1)")
        }
        #expect(LayoutSanity.shows("Refresh", in: tabbed), "Tab did not bring Refresh in sight:\n\(tabbed.screen)")
    }

    @Test("Lazy sections of 2, 7, 1 and 20: each heading on the row after its last item", arguments: TerminalSize.all)
    func lazySections(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { LazySectionsPage() }
        LayoutSanity.check(app, "launch")
        LayoutSanity.expectContiguous(app, ["Section of 2", "Item 2-1", "Item 2-2", "Section of 7"], "the first section")
        LayoutSanity.reach("Item 20-20", in: app, by: .wheelDown(over: nil), limit: 80)
        LayoutSanity.expectContiguous(app, (15...20).map { "Item 20-\($0)" }, "the last section")
    }
}
