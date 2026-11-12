//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledTableTests.swift
//
//  SCROLL-FIT's pull (design P3) for `Table`: with the switch on
//  (`EnvironmentValues.scrollFitsContent`), a table of one-line rows under a
//  title in a scroll view is its content's height and draws only the lines
//  on screen — whatever its row count — and every row is still reached: by
//  the wheel, by the keys, by `scrollTo` and by Tab. Its drawing is the same
//  table drawn whole, framed to its full height.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts cells built.
@MainActor private final class Builds {
    var count = 0
}

private struct Entry: Identifiable {
    let id: Int
}

/// A title, a button, a table and a button below it in a scroll view, the
/// switch on, and `j` scrolling the reader's proxy to `target`.
private struct TablePage: View {
    let entries: [Entry]
    let builds: Builds?
    var target: Int = 0
    var pulled = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    Button("above") {}
                    if pulled {
                        table
                    } else {
                        // The twin: the same table drawn whole, framed to its
                        // full height (its rows, header and borders), the
                        // switch off.
                        table.frame(height: entries.count + 3)
                    }
                    Button("below") {}
                }
            }
            .onKeyEvent(.character("j")) { proxy.scrollTo(target, anchor: .top) }
        }
        .environment(\.scrollFitsContent, pulled)
    }

    private var table: some View {
        Table(entries) {
            TableColumn("Row") { (entry: Entry) in
                builds?.count += 1
                return Text(verbatim: "r\(entry.id)")
            }
        }
    }
}

@MainActor
@Suite("SCROLL-FIT pull: a Table under a title draws only the rows on screen, and reaches every one")
struct PulledTableTests {
    private static func app(_ count: Int, builds: Builds? = nil, target: Int = 0, pulled: Bool = true) -> TestApp {
        TestApp(width: 30, height: 12) {
            TablePage(entries: (0..<count).map(Entry.init), builds: builds, target: target, pulled: pulled)
        }
    }

    /// The screen's lines without the scroll view's bar, which reads an
    /// estimate on one side and a measure on the other.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(28)) }
    }

    /// The row numbers on screen.
    private static func rowsShown(_ app: TestApp) -> [Int] {
        app.screen.lines.compactMap { line in
            guard let r = line.range(of: " r") else { return nil }
            return Int(line[r.upperBound...].prefix { $0.isNumber })
        }
    }

    @Test("The table draws what the same table drawn whole draws: top, wheeled, cursor moved, at the end and home")
    func drawsWhatTheWholeTableDraws() {
        let pulled = Self.app(300)
        let whole = Self.app(300, pulled: false)
        func check(_ step: String) {
            #expect(Self.content(pulled) == Self.content(whole), "\(step):\n\(pulled.screen)\n---\n\(whole.screen)")
        }
        check("top")
        for step in 1...4 {
            pulled.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            whole.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            check("wheel \(step)")
        }
        pulled.scroll(.down, by: 30, at: CellPoint(x: 5, y: 5))
        whole.scroll(.down, by: 30, at: CellPoint(x: 5, y: 5))
        check("wheel burst")
        _ = pulled.press(.tab)
        _ = whole.press(.tab)
        check("tab")
        for step in 1...14 {
            _ = pulled.press(.down)
            _ = whole.press(.down)
            check("down \(step)")
        }
        _ = pulled.press(.end)
        _ = whole.press(.end)
        check("end")
        _ = pulled.press(.home)
        _ = whole.press(.home)
        check("home")
    }

    /// The cells built on the first frame, three wheel steps, a `scrollTo`
    /// of a row near the end, two cursor pages and End.
    private static func builtPerStep(rows: Int) -> [Int] {
        let builds = Builds()
        let app = app(rows, builds: builds, target: rows - 20)
        _ = app.screen
        var counts = [builds.count]
        func step(_ action: () -> Void) {
            builds.count = 0
            action()
            counts.append(builds.count)
        }
        for _ in 0..<3 { step { app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5)) } }
        step { _ = app.press(.character("j")) }
        _ = app.press(.tab)
        for _ in 0..<2 { step { _ = app.press(.pageDown) } }
        step { _ = app.press(.end) }
        return counts
    }

    @Test("The rows built a frame are under 100, the same at 1,000 and 10,000 rows")
    func builtRowsIndependentOfRowCount() {
        let small = Self.builtPerStep(rows: 1_000)
        #expect(small.allSatisfy { $0 < 100 }, "\(small)")
        #expect(Self.builtPerStep(rows: 10_000) == small)
    }

    @Test("The wheel reaches every one of 10,000 rows, and the button below")
    func wheelReachesEveryRow() {
        let app = Self.app(10_000)
        var seen = Set(Self.rowsShown(app))
        for _ in 0..<1_200 {
            app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
            seen.formUnion(Self.rowsShown(app))
        }
        #expect(seen == Set(0..<10_000), "missing \(Set(0..<10_000).subtracting(seen).sorted().prefix(10))")
        #expect(app.screen.contains("below"))
    }

    @Test("Page Down moves the cursor a screen at a time through 10,000 rows, End the last, Home the first")
    func keysReachEveryRow() {
        let app = Self.app(10_000)
        _ = app.press(.tab)
        var seen = Set(Self.rowsShown(app))
        var pages = 0
        while !seen.contains(9_999), pages < 1_000 {
            _ = app.press(.pageDown)
            seen.formUnion(Self.rowsShown(app))
            pages += 1
        }
        #expect(seen == Set(0..<10_000), "missing \(Set(0..<10_000).subtracting(seen).sorted().prefix(10))")
        // A page is the scroll view's screen, not the table's whole height.
        #expect(pages > 800, "\(pages) pages")
        _ = app.press(.home)
        #expect(Self.rowsShown(app).first == 0, "\(app.screen)")
        _ = app.press(.end)
        #expect(app.screen.contains("r9999"))
    }

    @Test("scrollTo lands a row never built at the top, at 10,000 rows", arguments: [0, 517, 5_000, 9_999])
    func scrollToLandsARow(_ target: Int) {
        let app = Self.app(10_000, target: target)
        _ = app.press(.character("j"))
        #expect(Self.rowsShown(app).contains(target), "\(app.screen)")
        if target != 0, target < 9_990 { #expect(Self.rowsShown(app).first == target, "\(app.screen)") }
    }

    @Test("Tab reaches the table and the button below 10,000 rows; Shift-Tab comes back")
    func tabReachesPastTheTable() {
        let app = Self.app(10_000)
        _ = app.press(.tab)  // the table
        _ = app.press(.tab)  // the button below it
        #expect(app.screen.contains("below"), "\(app.screen)")
        _ = app.press(.tab, modifiers: .shift)  // back to the table
        _ = app.press(.end)
        #expect(app.screen.contains("r9999"), "\(app.screen)")
    }
}
