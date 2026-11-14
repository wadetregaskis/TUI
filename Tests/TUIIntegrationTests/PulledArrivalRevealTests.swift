//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledArrivalRevealTests.swift
//
//  SCROLL-FIT P6, design 2e (B-SCROLLFIT-6): with the switch on
//  (`EnvironmentValues.scrollFitsContent`), a control the focus arrives at
//  that is taller than the scroll view's viewport — a pulled table as tall as
//  its rows — is revealed by its cursor's row, and not moved at all when that
//  row shows: focused at launch under a title, the title stays on screen;
//  tabbed to below the fold, its first row comes up to the last line. A
//  control that fits is still revealed whole, its border and header with it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

private struct Item: Identifiable {
    let id: Int
}

/// `lead` lines (a button first, when `button`), then a table of `rows` rows,
/// in a scroll view with the switch on.
private struct ArrivalPage: View {
    let lead: Int
    let rows: Int
    var button = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if button {
                    Button("first") {}
                } else {
                    Text("title")
                }
                ForEach(0..<lead, id: \.self) { Text(verbatim: "line \($0)") }
                Table((1...rows).map(Item.init)) {
                    TableColumn("Name") { (item: Item) in Text(verbatim: "r\(item.id)") }
                }
            }
        }
        .environment(\.scrollFitsContent, true)
    }
}

@MainActor
@Suite("SCROLL-FIT P6: arriving at a control taller than the viewport reveals its cursor's row")
struct PulledArrivalRevealTests {
    @Test("Focused at launch, a table as tall as its 60 rows leaves the title above it on screen")
    func launchKeepsTheTitle() {
        let app = TestApp(width: 40, height: 12) { ArrivalPage(lead: 0, rows: 60, button: false) }
        #expect(app.focusedID?.hasPrefix("table-") == true)
        let lines = app.screen.lines
        #expect(lines[0].contains("title"), "\(app.screen)")
        #expect(lines[2].contains("Name") && lines[3].contains("r1"), "\(app.screen)")
    }

    @Test("Tabbed to below the fold, a table taller than the viewport shows its cursor's row, not its top")
    func tabRevealsTheCursorRow() {
        let app = TestApp(width: 40, height: 12) { ArrivalPage(lead: 20, rows: 60) }
        #expect(app.focusedID?.hasPrefix("button") == true)
        _ = app.press(.tab)
        #expect(app.focusedID?.hasPrefix("table-") == true)
        let lines = app.screen.lines
        // Brought up from below by as little as shows the first row: on the
        // last line, the header above it.
        #expect(lines[11].contains("r1"), "\(app.screen)")
        #expect(lines[10].contains("Name"), "\(app.screen)")
    }

    @Test("Tabbed to below the fold, a table that fits the viewport is shown whole")
    func tabRevealsAShortTableWhole() {
        let app = TestApp(width: 40, height: 12) { ArrivalPage(lead: 20, rows: 5) }
        _ = app.press(.tab)
        #expect(app.focusedID?.hasPrefix("table-") == true)
        let lines = app.screen.lines
        // Its bottom border on the last line, its top border and header on
        // the screen above its five rows.
        #expect(lines[11].contains("╰") && lines[10].contains("r5"), "\(app.screen)")
        #expect(lines[4].contains("╭") && lines[5].contains("Name"), "\(app.screen)")
    }
}
