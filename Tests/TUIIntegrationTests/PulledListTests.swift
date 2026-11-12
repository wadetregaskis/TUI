//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledListTests.swift
//
//  SCROLL-FIT's pull (design P3) for `List`: with the switch on
//  (`EnvironmentValues.scrollFitsContent`), a list of one-line rows under a
//  title in a scroll view is its content's height and draws only the lines
//  on screen — whatever its row count — and every row is still reached: by
//  the wheel, by the keys, by `scrollTo` and by Tab. Its drawing is the same
//  list drawn whole, framed to its full height.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class Builds {
    var count = 0
}

/// A title, a button, a list and a button below it in a scroll view, the
/// switch on, and `j` scrolling the reader's proxy to `target`.
private struct ListPage: View {
    let count: Int
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
                        list
                    } else {
                        // The twin: the same list drawn whole, framed to its
                        // full height (a line a row), the switch off.
                        list.frame(height: count)
                    }
                    Button("below") {}
                }
            }
            .onKeyEvent(.character("j")) { proxy.scrollTo(target, anchor: .top) }
        }
        .environment(\.scrollFitsContent, pulled)
    }

    private var list: some View {
        List {
            ForEach(0..<count, id: \.self) { index in
                builds?.count += 1
                return Text(verbatim: "r\(index)")
            }
        }
        // Borderless, so the twin's frame is a line a row.
        .listStyle(.plain)
    }
}

@MainActor
@Suite("SCROLL-FIT pull: a List under a title draws only the rows on screen, and reaches every one")
struct PulledListTests {
    private static func app(_ count: Int, builds: Builds? = nil, target: Int = 0, pulled: Bool = true) -> TestApp {
        TestApp(width: 30, height: 12) { ListPage(count: count, builds: builds, target: target, pulled: pulled) }
    }

    /// The screen's lines without the scroll view's bar, which reads an
    /// estimate on one side and a measure on the other.
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

    @Test("The list draws what the same list drawn whole draws: top, wheeled, cursor moved, at the end and home")
    func drawsWhatTheWholeListDraws() {
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
        // Tab to the list, then walk its cursor past the screen's bottom.
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

    /// The rows built on the first frame, three wheel steps, two cursor
    /// pages, End, and a `scrollTo` of a row near the end.
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

    @Test("The wheel reaches every one of 10,000 rows, in order, and the button below")
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
            let shown = Self.rowsShown(app)
            #expect(!shown.isEmpty)
            seen.formUnion(shown)
            pages += 1
        }
        #expect(seen == Set(0..<10_000), "missing \(Set(0..<10_000).subtracting(seen).sorted().prefix(10))")
        // A page is the scroll view's screen, not the list's whole height.
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

    /// Type-select reads each row's text from the row, so a prefix builds the
    /// rows it scans from the cursor to its match, once per key: per key
    /// press, never per frame (SCROLL-FIT 2d). Typing `r5000` scans to rows 5,
    /// 50, 500 and 5,000 in turn.
    @Test("Type-select reaches a row never built, building the rows it scans and no more")
    func typeSelectReachesARow() {
        let builds = Builds()
        let app = Self.app(10_000, builds: builds)
        _ = app.press(.tab)
        builds.count = 0
        for character in "r5000" { _ = app.press(.character(character)) }
        #expect(Self.rowsShown(app).contains(5_000), "\(app.screen)")
        #expect(builds.count < 5_000 + 5 * 100, "\(builds.count)")
    }

    @Test("Tab reaches the list and the button below 10,000 rows; Shift-Tab comes back")
    func tabReachesThePastTheList() {
        let app = Self.app(10_000)
        _ = app.press(.tab)  // the list
        _ = app.press(.tab)  // the button below it
        #expect(app.screen.contains("below"), "\(app.screen)")
        _ = app.press(.tab, modifiers: .shift)  // back to the list
        _ = app.press(.end)
        #expect(app.screen.contains("r9999"), "\(app.screen)")
    }

    @Test("With the switch off the list is drawn as before: the measure ladder's height, scrolling itself")
    func switchOffChangesNothing() {
        let off = TestApp(width: 30, height: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    List { ForEach(0..<300, id: \.self) { Text("r\($0)") } }
                }
            }
        }
        let builds = Builds()
        let on = Self.app(300, builds: builds)
        _ = on.screen
        // Off, the list fills the first rung of the measure ladder and draws
        // its own scrollbar; on, it is its rows' height and draws none.
        #expect(off.screen != on.screen)
        #expect(builds.count < 100)
    }
}
