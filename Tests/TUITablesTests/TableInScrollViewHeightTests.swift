//  🖥️ TUI — A Terminal UI framework for Swift
//  TableInScrollViewHeightTests.swift
//
//  Tables of different sizes stacked in a vertical `ScrollView`, with no
//  frame, are each drawn at their rows' height: no blank rows after the last,
//  and no table cut short with a scroll bar of its own. Reported against
//  2026-11-09's main: a table of 2 rows was drawn 14 rows tall, blank under
//  its second, and a table of 30 cut to 13 beside it, because the scroll view
//  sized its column from the tables' rows and the column then dealt that
//  height out evenly, a table's height being flexible (decisions
//  TABLE-IN-SCROLL-HEIGHT, TABLE-IN-SCROLL-BLANK).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUITables
import TUITesting

private struct Entry: Identifiable, Sendable {
    let id: Int
    var name: String { "Row \(id)" }
    var value: String { "v\(id * 7)" }
}

private struct Group: Identifiable, Sendable {
    let id: Int
    let rows: [Entry]
    var title: String { "Table of \(rows.count)" }
}

@MainActor private final class BuiltCells { var count = 0 }

@Observable @MainActor private final class PageTitle { var text = "Title 0" }

private let groups = [2, 5, 30].enumerated().map { Group(id: $0.offset, rows: (1...$0.element).map(Entry.init)) }

@MainActor
@Suite("Tables in a ScrollView are drawn at their rows' height")
struct TableInScrollViewHeightTests {
    private func app(height: Int) -> TestApp {
        TestApp(width: 40, height: height) {
            ScrollView {
                VStack {
                    ForEach(groups) { group in
                        VStack {
                            Text(group.title)
                            Table(group.rows) {
                                TableColumn("Name", value: \Entry.name)
                                TableColumn("Value", value: \Entry.value)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The lines of the bordered box drawn under `title`, its top and bottom
    /// borders included, or `nil` when the box is not all on the screen.
    private func box(under title: String, in screen: TestScreen) -> [String]? {
        guard let titleRow = screen.location(of: title)?.y else { return nil }
        let lines = screen.lines
        guard titleRow + 1 < lines.count, lines[titleRow + 1].contains("╭") else { return nil }
        guard let bottom = lines[(titleRow + 1)...].firstIndex(where: { $0.contains("╰") }) else { return nil }
        return Array(lines[(titleRow + 1)...bottom])
    }

    /// The box's lines between its header and its bottom border that show no row.
    private func blankRows(_ box: [String]) -> Int {
        box.dropFirst(2).dropLast().count { !$0.contains("Row ") }
    }

    @Test("A short table is its rows' height, with no blank rows after them", arguments: [24, 40, 80])
    func shortTablesHug(height: Int) throws {
        let screen = app(height: height).screen
        let two = try #require(box(under: "Table of 2", in: screen), "\(screen)")
        #expect(two.count == 2 + 3, "2 rows, the header and two borders:\n\(screen)")
        #expect(blankRows(two) == 0, "\(screen)")
        let five = try #require(box(under: "Table of 5", in: screen), "\(screen)")
        #expect(five.count == 5 + 3, "5 rows, the header and two borders:\n\(screen)")
        #expect(blankRows(five) == 0, "\(screen)")
    }

    /// The whole column is 51 lines, so at 80 it is all on the screen.
    @Test("A long table shows every row, the outer scroll view scrolling to them")
    func longTableShowsEveryRow() throws {
        let screen = app(height: 80).screen
        let thirty = try #require(box(under: "Table of 30", in: screen), "\(screen)")
        #expect(thirty.count == 30 + 3, "\(screen)")
        #expect(screen.contains("Row 30"), "\(screen)")
        #expect(blankRows(thirty) == 0, "\(screen)")
    }

    /// Drawn whole, a table of 10,000 rows built every row on every frame: an
    /// idle redraw took 70 ms where it had taken 44 (debug build), and at
    /// 100,000 rows 927 ms, a scroll step 2.3 s. Never taller than the scroll
    /// view showing it, it scrolls its rows within itself and builds only the
    /// ones on screen.
    @Test("A table taller than its scroll view is the scroll view's height and builds only the rows it shows")
    func tallTableIsTheViewportsHeight() throws {
        let rows = (1...10_000).map(Entry.init)
        let built = BuiltCells()
        let title = PageTitle()
        let app = TestApp(width: 40, height: 24) {
            ScrollView {
                VStack {
                    Text(title.text)
                    Table(rows) {
                        TableColumn("Name") { (row: Entry) -> Text in
                            built.count += 1
                            return Text(row.name)
                        }
                    }
                }
            }
        }
        _ = app.screen
        #expect(built.count < 500, "the first frame built \(built.count) cells")
        built.count = 0
        title.text = "Title 1"
        app.advance(by: .milliseconds(17))
        #expect(built.count < 200, "a redraw built \(built.count) cells for 24 lines")
        built.count = 0
        app.scroll(.down, by: 1, at: CellPoint(x: 2, y: 0))
        app.advance(by: .milliseconds(17))
        #expect(built.count < 200, "a scroll step built \(built.count) cells for 24 lines")
        // The page scrolls one line, past the title: the table's box is the
        // whole screen, 24 lines, not 10,003.
        let scrolled = app.screen
        #expect(scrolled.lines.first?.contains("╭") == true, "\(scrolled)")
        #expect(scrolled.lines.last?.contains("╰") == true, "\(scrolled)")
    }

    /// A frame still gives a table its height, and the table fills it, as it
    /// does in SwiftUI (`FramedTableFillsTests` outside a scroll view).
    @Test("A framed table in a ScrollView still fills its frame")
    func framedTableFills() throws {
        let app = TestApp(width: 40, height: 24) {
            ScrollView {
                VStack {
                    Text("Framed")
                    Table(groups[0].rows) {
                        TableColumn("Name", value: \Entry.name)
                    }
                    .frame(height: 9)
                }
            }
        }
        let framed = try #require(box(under: "Framed", in: app.screen), "\(app.screen)")
        #expect(framed.count == 9, "\(app.screen)")
    }
}
