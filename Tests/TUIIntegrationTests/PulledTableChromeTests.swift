//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledTableChromeTests.swift
//
//  SCROLL-FIT P6 for `Table`: with the switch on
//  (`EnvironmentValues.scrollFitsContent`), a table pulled in a scroll view's
//  content — as tall as its rows — keeps its header at the viewport's top
//  edge and its horizontal scrollbar at the bottom edge while its rows are
//  under them, as a section's pinned header and footer (design 2c,
//  B-SCROLLFIT-9). The keys test, the lane's measure of done, also has the
//  title above the table stay on screen at launch (design 2e,
//  `PulledArrivalRevealTests`).
//
//  The oracle for the pinning is the same table drawn whole, framed to its
//  full height: pinning draws the header over the viewport's top line exactly
//  when that line is one of the table's rows, and the bar over its last line
//  on the same condition, and changes nothing else.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

private struct Item: Identifiable {
    let id: Int
}

/// Holds the table's selection for a test.
@MainActor private final class Selection {
    var value: Int?
}

/// A title, a table and a line after it in a scroll view, the switch on. Four
/// columns of twenty cells (`wide`) do not fit across sixty, and scroll
/// sideways under a bar of their own; two do.
private struct TitledTablePage: View {
    let count: Int
    var wide = true
    /// The twin: the same table drawn whole, framed to this height.
    var framed: Int?
    var selection: Selection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                if let framed {
                    table.frame(height: framed)
                } else {
                    table
                }
                Text("after")
            }
        }
        .environment(\.scrollFitsContent, true)
    }

    private var binding: Binding<Int?> {
        Binding(get: { selection?.value }, set: { selection?.value = $0 })
    }

    @ViewBuilder private var table: some View {
        let items = (1...count).map(Item.init)
        if wide {
            Table(items, selection: binding) {
                TableColumn("Name") { (item: Item) in Text(verbatim: "r\(item.id)") }.width(20)
                TableColumn("Alpha") { (item: Item) in Text(verbatim: "alpha-\(item.id)") }.width(20)
                TableColumn("Beta") { (item: Item) in Text(verbatim: "beta-\(item.id)") }.width(20)
                TableColumn("Gamma") { (item: Item) in Text(verbatim: "gamma-\(item.id)") }.width(20)
            }
        } else {
            Table(items, selection: binding) {
                TableColumn("Name") { (item: Item) in Text(verbatim: "r\(item.id)") }.width(20)
                TableColumn("Alpha") { (item: Item) in Text(verbatim: "alpha-\(item.id)") }.width(20)
            }
        }
    }
}

@MainActor
@Suite("SCROLL-FIT P6: a pulled Table's header and bar stay on screen, and arriving at it keeps the title")
struct PulledTableChromeTests {
    private static func app(_ count: Int = 60, wide: Bool = true, framed: Int? = nil) -> TestApp {
        TestApp(width: 60, height: 24) {
            TitledTablePage(count: count, wide: wide, framed: framed, selection: Selection())
        }
    }

    /// The screen's lines without the scroll view's bar.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 60)).prefix(58)) }
    }

    /// Whether a screen line is one of the table's rows.
    private static func isRow(_ line: String) -> Bool {
        guard let r = line.range(of: " r") else { return false }
        return line[r.upperBound...].first?.isNumber == true
    }

    @Test("The keys test: the title stays on screen at launch; the header and the bar stay put as the keys move")
    func keysInTallTable() {
        let app = Self.app()
        let lines = { app.screen.lines }
        #expect(app.focusedID?.hasPrefix("table-") == true)
        #expect(lines()[0].contains("title"), "launch:\n\(app.screen)")
        #expect(lines()[2].contains("Name") && lines()[3].contains("r1"), "launch:\n\(app.screen)")
        func pinned(_ step: String) {
            #expect(lines()[0].contains("Name"), "\(step):\n\(app.screen)")
            #expect(lines()[23].contains("◀"), "\(step):\n\(app.screen)")
        }
        _ = app.press(.down, times: 31)
        pinned("down 31")
        #expect(lines()[22].contains("r32"), "\(app.screen)")
        _ = app.press(.pageDown)
        pinned("page down")
        // A page is the viewport less the header and the bar pinned over it.
        #expect(lines()[22].contains("r54"), "\(app.screen)")
        _ = app.press(.end)
        pinned("end")
        #expect(lines()[22].contains("r60"), "\(app.screen)")
        _ = app.press(.home)
        #expect(lines()[1].contains("r1") && lines()[0].contains("Name"), "\(app.screen)")
        app.type("r45")
        pinned("type-select r45")
        #expect(app.screen.contains("r45"), "\(app.screen)")
    }

    @Test(
        "The wheel draws the table drawn whole, its header over the top line and its bar over the last while rows are under them",
        arguments: [true, false])
    func wheelPinsOverTheWholeTable(wide: Bool) {
        let count = 60
        let pulled = Self.app(count, wide: wide)
        // The rows, the header, the bar where there is one, and two borders.
        let whole = Self.app(count, wide: wide, framed: count + (wide ? 4 : 3))
        let header = Self.content(pulled)[2]
        var pinnedHeader = 0
        var pinnedBar = 0
        for step in 0..<45 {
            if step > 0 {
                pulled.scroll(.down, by: 1, at: CellPoint(x: 5, y: 5))
                whole.scroll(.down, by: 1, at: CellPoint(x: 5, y: 5))
            }
            let shown = Self.content(pulled)
            var expected = Self.content(whole)
            if Self.isRow(expected[0]) {
                expected[0] = header
                pinnedHeader += 1
            }
            // The bar, where the twin's last line is a row: its thumb is the
            // pulled table's own (the twin's is below the screen), so only
            // that it is the bar is compared.
            let last = expected.count - 1
            if wide, Self.isRow(expected[last]) {
                #expect(shown[last].contains("◀") && shown[last].contains("▶"), "line \(step):\n\(pulled.screen)")
                expected[last] = shown[last]
                pinnedBar += 1
            }
            #expect(shown == expected, "line \(step):\n\(pulled.screen)\n---\n\(whole.screen)")
        }
        // A wheel tick moves three lines: the bar stops being pinned when the
        // table's end comes up the screen, fourteen ticks in; the header only
        // when the table goes off its top.
        #expect(pinnedHeader > 30 && (!wide || pinnedBar > 10), "\(pinnedHeader) \(pinnedBar)")
    }

    @Test("A click on the pinned header selects no row under it; the pinned bar scrolls the columns")
    func pinnedChromeTakesClicks() {
        let selection = Selection()
        let app = TestApp(width: 60, height: 24) { TitledTablePage(count: 60, selection: selection) }
        app.scroll(.down, by: 10, at: CellPoint(x: 5, y: 10))
        #expect(app.screen.lines[0].contains("Name") && app.screen.lines[23].contains("◀"), "\(app.screen)")
        app.click(at: CellPoint(x: 8, y: 0))
        #expect(selection.value == nil, "\(app.screen)")
        let bar = app.screen.lines[23]
        let arrow = bar.distance(from: bar.startIndex, to: bar.firstIndex(of: "▶")!)
        for _ in 0..<4 { app.click(at: CellPoint(x: arrow, y: 23)) }
        #expect(app.screen.lines[0].contains("Gamma") && !app.screen.lines[0].contains("Name"), "\(app.screen)")
        // The rows scrolled across with the header.
        #expect(app.screen.lines[5].contains("gamma-"), "\(app.screen)")
    }

    @Test("Two tables: the second's header takes the top edge from the first's")
    func nextHeaderTakesOver() {
        let app = TestApp(width: 40, height: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Table((1...12).map(Item.init)) {
                        TableColumn("First") { (item: Item) in Text(verbatim: "a\(item.id)") }
                    }
                    Table((1...40).map(Item.init)) {
                        TableColumn("Second") { (item: Item) in Text(verbatim: "b\(item.id)") }
                    }
                }
            }
            .environment(\.scrollFitsContent, true)
        }
        var seen: [String] = []
        for _ in 0..<30 {
            app.scroll(.down, by: 1, at: CellPoint(x: 5, y: 5))
            let top = app.screen.lines[0]
            let name = top.contains("First") ? "First" : top.contains("Second") ? "Second" : "-"
            if seen.last != name { seen.append(name) }
        }
        #expect(seen == ["First", "-", "Second"], "\(seen)\n\(app.screen)")
    }
}
