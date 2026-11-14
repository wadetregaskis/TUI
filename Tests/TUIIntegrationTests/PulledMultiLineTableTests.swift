//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledMultiLineTableTests.swift
//
//  SCROLL-FIT's pull (design P4) for a `Table` of multi-line rows: with the
//  switch on (`EnvironmentValues.scrollFitsContent`), a table whose rows wrap
//  to one to three lines, under a title in a scroll view, is its content's
//  height — estimated for the rows not yet built — and draws only the lines
//  on screen, whatever its row count; every row is still reached. Its
//  drawing is the same table drawn whole, framed to its full height.
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
    /// One to three words of eight letters: at the column's eight cells, one
    /// to three lines.
    var note: String { Array(repeating: "abcdefgh", count: id % 3 + 1).joined(separator: " ") }
}

/// A title, a button, a table and a button below it in a scroll view, and `j`
/// scrolling the reader's proxy to `target`.
private struct MultiLineTablePage: View {
    let entries: [Entry]
    let builds: Builds?
    var target: Int = 0
    /// The twin's frame: the same table drawn whole, framed to its full
    /// height, which the switch leaves as it was. `nil` for the pulled table.
    var framed: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    Button("above") {}
                    if let framed {
                        table.frame(height: framed)
                    } else {
                        table
                    }
                    Button("below") {}
                }
            }
            .onKeyEvent(.character("j")) { proxy.scrollTo(target, anchor: .top) }
        }
        .environment(\.scrollFitsContent, true)
    }

    var table: some View {
        Table(entries) {
            TableColumn("Row") { (entry: Entry) in
                builds?.count += 1
                return Text(verbatim: "r\(entry.id)")
            }
            .width(8)
            TableColumn("Note") { (entry: Entry) in Text(verbatim: entry.note) }
                .width(8).lineLimit(3)
        }
    }
}

@MainActor
@Suite("SCROLL-FIT pull: a Table of multi-line rows draws only the rows on screen, and reaches every one")
struct PulledMultiLineTableTests {
    private static func entries(_ count: Int) -> [Entry] { (0..<count).map { Entry(id: $0) } }

    private static func app(_ count: Int, builds: Builds? = nil, target: Int = 0, framed: Int? = nil) -> TestApp {
        TestApp(width: 30, height: 12) {
            MultiLineTablePage(entries: entries(count), builds: builds, target: target, framed: framed)
        }
    }

    /// The table drawn whole: its rows (one to three lines each), its header
    /// and its two borders.
    private static func wholeHeight(_ count: Int) -> Int {
        (0..<count).reduce(0) { $0 + $1 % 3 + 1 } + 3
    }

    /// The screen's lines without the scroll view's bar.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(28)) }
    }

    /// The row numbers on screen.
    private static func rowsShown(_ app: TestApp) -> [Int] {
        app.screen.lines.compactMap { line in
            guard let r = line.range(of: "r") else { return nil }
            return Int(line[r.upperBound...].prefix { $0.isNumber })
        }
    }

    @Test("The table draws what the same table drawn whole draws: top, wheeled, cursor moved, at the end and home")
    func drawsWhatTheWholeTableDraws() {
        let pulled = Self.app(300)
        let whole = Self.app(300, framed: Self.wholeHeight(300))
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
        pulled.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
        whole.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
        check("wheel up")
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

    /// The cells built on the first frame, three wheel steps, a `scrollTo`,
    /// two pages and End.
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

    @Test("The cells built a frame are under 100, the same at 1,000 and 10,000 rows")
    func builtRowsIndependentOfRowCount() {
        let small = Self.builtPerStep(rows: 1_000)
        #expect(small.allSatisfy { $0 < 100 }, "\(small)")
        #expect(Self.builtPerStep(rows: 10_000) == small)
    }

    @Test("The wheel reaches every one of 10,000 multi-line rows, and the button below")
    func wheelReachesEveryRow() {
        let app = Self.app(10_000)
        var seen = Set(Self.rowsShown(app))
        for _ in 0..<7_000 {
            app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
            seen.formUnion(Self.rowsShown(app))
            if seen.contains(9_999), app.screen.contains("below") { break }
        }
        #expect(seen == Set(0..<10_000), "missing \(Set(0..<10_000).subtracting(seen).sorted().prefix(10))")
        #expect(app.screen.contains("below"))
    }

    @Test("scrollTo lands a row never built at the top, at 10,000 multi-line rows", arguments: [517, 5_000, 9_999])
    func scrollToLandsARow(_ target: Int) {
        let app = Self.app(10_000, target: target)
        _ = app.press(.character("j"))
        #expect(Self.rowsShown(app).contains(target), "\(app.screen)")
        if target < 9_990 { #expect(Self.rowsShown(app).first == target, "\(app.screen)") }
    }
}
