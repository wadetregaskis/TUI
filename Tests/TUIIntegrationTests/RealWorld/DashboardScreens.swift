//  🖥️ TUI — A Terminal UI framework for Swift
//  DashboardScreens.swift
//
//  Real-world screens: dashboards. A Grid of GroupBoxes holding gauges, an
//  HStack of GroupBoxes each holding a table of its own length, and a
//  scrolling column of panels with a progress bar. Panels must not overlap,
//  a short table must not be padded to its neighbour's height, and every
//  panel must be reachable.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

private struct ProcessRow: Identifiable, Sendable {
    let id: Int
    var name: String { "p\(id)" }
    var cpu: String { "\(id % 9).\(id % 7)" }
}

/// Four gauges, two by two, each in a titled box, a Refresh button under them.
private struct GaugesPage: View {
    var body: some View {
        VStack(alignment: .leading) {
            Grid {
                GridRow {
                    GroupBox("CPU") { Gauge(value: 0.42) { Text("Load") } }
                    GroupBox("Memory") { Gauge(value: 0.73) { Text("Used") } }
                }
                GridRow {
                    GroupBox("Disk") { Gauge(value: 0.9) { Text("Full") } }
                    GroupBox("Network") { Gauge(value: 0.1) { Text("Busy") } }
                }
            }
            Button("Refresh") {}.focusID("refresh")
        }
    }
}

/// Two boxes side by side, holding tables of 3 and 12 rows.
private struct TablesSideBySidePage: View {
    var body: some View {
        HStack(alignment: .top) {
            GroupBox("Top") {
                Table((1...3).map(ProcessRow.init)) {
                    TableColumn("Name", value: \ProcessRow.name)
                    TableColumn("CPU", value: \ProcessRow.cpu)
                }
                .focusID("top")
            }
            GroupBox("All") {
                Table((11...22).map(ProcessRow.init)) {
                    TableColumn("Name", value: \ProcessRow.name)
                    TableColumn("CPU", value: \ProcessRow.cpu)
                }
                .focusID("all")
            }
        }
    }
}

/// A scrolling column of six panels, the third with a progress bar.
private struct PanelsPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(1...6, id: \.self) { panel in
                    GroupBox("Panel \(panel)") {
                        VStack(alignment: .leading) {
                            Text("Status of panel \(panel)")
                            if panel == 3 { ProgressView(value: 0.6) }
                            Button("Open \(panel)") {}.focusID("open-\(panel)")
                        }
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("Real world: dashboards")
struct DashboardScreens {
    @Test("A grid of gauges in boxes: nothing overlaps, Refresh is reachable", arguments: TerminalSize.all)
    func gaugeGrid(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { GaugesPage() }
        LayoutSanity.check(app, "launch")
        app.press(.tab)
        LayoutSanity.check(app, "Tab")
        if size.height >= 12 {
            #expect(app.screen.contains("Refresh"), "Refresh is not on screen:\n\(app.screen)")
        }
        for title in ["CPU", "Memory", "Disk", "Network"] { LayoutSanity.expectNotSilentlyCut(app, title, title) }
    }

    @Test("Tables of 3 and 12 side by side: the short one is not padded, the long one scrolls to its end",
          arguments: TerminalSize.all)
    func tablesSideBySide(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { TablesSideBySidePage() }
        LayoutSanity.check(app, "launch")
        for _ in 0..<4 where app.focusedID != "all" { app.press(.tab) }
        #expect(app.focusedID == "all")
        app.press(.end)
        LayoutSanity.check(app, "End")
        // At 20×6 each table, in a box in a box, has room for its header alone.
        guard size.height >= 12 else { return }
        LayoutSanity.expectContiguous(app, ["p1", "p2", "p3"], atLeast: 3, "the short table")
        LayoutSanity.expectContiguous(app, (18...22).map { "p\($0)" }, atLeast: 2, "the end of the long table")
        #expect(LayoutSanity.shows("p22", in: app), "End did not reach the last row:\n\(app.screen)")
    }

    @Test("A column of six panels: the last one reachable by Tab and by the wheel", arguments: TerminalSize.all)
    func panels(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { PanelsPage() }
        LayoutSanity.check(app, "launch")
        LayoutSanity.reach("Open 6", in: app, by: .tab, limit: 8)
        let wheeled = TestApp(width: size.width, height: size.height) { PanelsPage() }
        LayoutSanity.reach("Open 6", in: wheeled, by: .wheelDown(over: nil), limit: 60)
    }
}
