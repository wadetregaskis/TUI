//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledListPageOnTests.swift
//
//  A `Table` or a `List` as tall as its rows in a scroll view's content
//  (SCROLL-FIT): Page Down on its last row, where the cursor has nowhere to
//  go, pages the scroll view on to the text below it, and Page Up on its
//  first row back to the text above, as Page Down does over a focused button
//  in a page. Before, the list took the key and moved nothing, so text below
//  it that nothing could focus was out of reach of the keys. Home and End,
//  pressed once the page has gone past the list, bring its first row or its
//  last back into view.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

private struct Item: Identifiable {
    let id: Int
}

/// Twenty lines of text above, a table or a list of 40 rows, and forty
/// lines of text below, in a scroll view.
private struct PageOnPage: View {
    let table: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { Text(verbatim: "before \($0)") }
                rows
                ForEach(0..<40, id: \.self) { Text(verbatim: "after \($0)") }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        let items = (1...40).map(Item.init)
        if table {
            Table(items) { TableColumn("Name") { (item: Item) in Text(verbatim: "r\(item.id)") } }
        } else {
            List(items) { item in Text(verbatim: "r\(item.id)") }
        }
    }
}

@MainActor
@Suite("SCROLL-FIT: Page Down past a content-sized list's last row pages on to what follows it")
struct PulledListPageOnTests {
    @Test("Page Up on the first row shows the text above; Page Down on the last row the text below",
          arguments: [true, false])
    func pagesOnPastTheRows(_ table: Bool) {
        let app = TestApp(width: 30, height: 12) { PageOnPage(table: table) }
        // Focused at launch on its first row, below the text above it.
        #expect(app.screen.contains("r1"), "launch:\n\(app.screen)")
        #expect(!app.screen.contains("before 0"), "launch:\n\(app.screen)")
        _ = app.press(.pageUp, times: 3)
        #expect(app.screen.lines.first?.hasPrefix("before 0") == true, "page up on the first row:\n\(app.screen)")
        _ = app.press(.end)
        #expect(app.screen.contains("r40"), "end:\n\(app.screen)")
        #expect(!app.screen.contains("after 8"), "end:\n\(app.screen)")
        _ = app.press(.pageDown)
        #expect(app.screen.contains("after 8"), "page down on the last row:\n\(app.screen)")
        _ = app.press(.pageDown, times: 5)
        #expect(app.screen.contains("after 39"), "paged to the end:\n\(app.screen)")
    }

    @Test("Home and End on a list paged out of sight bring its first row and its last back into view",
          arguments: [true, false])
    func homeAndEndComeBack(_ table: Bool) {
        let app = TestApp(width: 30, height: 12) { PageOnPage(table: table) }
        _ = app.press(.end)
        _ = app.press(.pageDown, times: 6)
        #expect(app.screen.contains("after 39"), "paged past the list:\n\(app.screen)")
        _ = app.press(.home)
        #expect(shows("r1", app), "home, paged past the list:\n\(app.screen)")
        _ = app.press(.pageUp, times: 6)
        #expect(app.screen.lines.first?.hasPrefix("before 0") == true, "paged above the list:\n\(app.screen)")
        _ = app.press(.end)
        #expect(shows("r40", app), "end, paged above the list:\n\(app.screen)")
    }

    @Test("Home and End on a list the wheel has scrolled out of sight bring it back", arguments: [true, false])
    func homeAndEndAfterTheWheel(_ table: Bool) {
        let app = TestApp(width: 30, height: 12) { PageOnPage(table: table) }
        app.scroll(.down, by: 40, at: CellPoint(x: 5, y: 5))
        #expect(app.screen.contains("after 39"), "wheeled past the list:\n\(app.screen)")
        _ = app.press(.home)
        #expect(shows("r1", app), "home, wheeled past the list:\n\(app.screen)")
        app.scroll(.up, by: 40, at: CellPoint(x: 5, y: 5))
        #expect(app.screen.lines.first?.hasPrefix("before 0") == true, "wheeled above the list:\n\(app.screen)")
        _ = app.press(.end)
        #expect(shows("r40", app), "end, wheeled above the list:\n\(app.screen)")
    }

    /// Whether a line of the screen holds `row` as a word of its own ("r1",
    /// not the "r1" of "r12").
    private func shows(_ row: String, _ app: TestApp) -> Bool {
        app.screen.lines.contains { $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0 == row } }
    }
}
