//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledVariableListTests.swift
//
//  SCROLL-FIT's pull (design P4) for a `List` whose rows are not all one
//  line: rows of several lines, sections, an outline, and an empty list. With
//  the switch on (`EnvironmentValues.scrollFitsContent`) such a list under a
//  title in a scroll view is its content's height — estimated for the rows
//  not yet built — and draws only the lines on screen, whatever its row
//  count; every row is still reached by the wheel, the keys, `scrollTo` and
//  Tab. Its drawing is the same list drawn whole, framed to its full height.
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

/// The shapes of list the page holds.
private enum Shape {
    /// Row `n` is `n % 3 + 1` lines: its number, then a dash a line.
    case multiLine
    /// Sections of ten one-line rows under a header.
    case sectioned
    /// Parents of two children each, collapsed.
    case outline
    /// No rows at all.
    case empty
}

private struct Node: Identifiable, Hashable {
    let id: Int
    var children: [Self]?
}

/// A title, a button, a list and a button below it in a scroll view, the
/// switch on, and `j` scrolling the reader's proxy to `target`.
private struct VariableListPage: View {
    let shape: Shape
    let count: Int
    let builds: Builds?
    var target: Int = 0
    /// The twin's frame: the same list drawn whole, framed to its full
    /// height, the switch off. `nil` for the pulled list.
    var framed: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    Button("above") {}
                    if let framed {
                        list.frame(height: framed)
                    } else {
                        list
                    }
                    Button("below") {}
                }
            }
            .onKeyEvent(.character("j")) { proxy.scrollTo(target, anchor: .top) }
        }
        .environment(\.scrollFitsContent, framed == nil)
    }

    /// Borderless, so the twin's frame is the rows' lines alone.
    @ViewBuilder var list: some View {
        switch shape {
        case .multiLine:
            List {
                ForEach(0..<count, id: \.self) { index in
                    builds?.count += 1
                    return Text(verbatim: (["r\(index)"] + Array(repeating: "-", count: index % 3)).joined(separator: "\n"))
                }
            }
            .listStyle(.plain)
        case .sectioned:
            List {
                ForEach(0..<(count / 10), id: \.self) { section in
                    Section {
                        ForEach((section * 10)..<(section * 10 + 10), id: \.self) { index in
                            builds?.count += 1
                            return Text(verbatim: "r\(index)")
                        }
                    } header: {
                        Text(verbatim: "S\(section)")
                    }
                }
            }
            .listStyle(.plain)
        case .outline:
            List(
                (0..<count).map { Node(id: $0 * 3, children: [Node(id: $0 * 3 + 1), Node(id: $0 * 3 + 2)]) },
                children: \.children
            ) { node in
                Text(verbatim: "r\(node.id)")
            }
            .listStyle(.plain)
        case .empty:
            List { ForEach(0..<0, id: \.self) { Text(verbatim: "r\($0)") } }
                .listStyle(.plain)
        }
    }
}

@MainActor
@Suite("SCROLL-FIT pull: a List of rows of varying height draws only the rows on screen, and reaches every one")
struct PulledVariableListTests {
    private static let size = (width: 30, height: 12)

    private static func app(
        _ shape: Shape, _ count: Int, builds: Builds? = nil, target: Int = 0, framed: Int? = nil
    ) -> TestApp {
        TestApp(width: size.width, height: size.height) {
            VariableListPage(shape: shape, count: count, builds: builds, target: target, framed: framed)
        }
    }

    /// The list's lines drawn whole: drawn alone on a screen taller than it,
    /// up to its last line that is not blank.
    private static func wholeHeight(_ shape: Shape, _ count: Int) -> Int {
        let tall = TestApp(width: size.width, height: 1_500) {
            VariableListPage(shape: shape, count: count, builds: nil).list
        }
        let lines = tall.screen.lines
        return (lines.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? 0) + 1
    }

    /// The pulled page and its twin.
    private static func twins(_ shape: Shape, _ count: Int) -> (pulled: TestApp, whole: TestApp) {
        (app(shape, count), app(shape, count, framed: wholeHeight(shape, count)))
    }

    /// The screen's lines without the scroll view's bar, which reads an
    /// estimate on one side and a measure on the other.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: size.width)).prefix(size.width - 2)) }
    }

    /// The row numbers on screen.
    private static func rowsShown(_ app: TestApp) -> [Int] {
        app.screen.lines.compactMap { line in
            guard let r = line.range(of: "r") else { return nil }
            return Int(line[r.upperBound...].prefix { $0.isNumber })
        }
    }

    /// Walks the pulled page and its twin alike — the top, wheel steps one
    /// at a time and in a burst, Tab onto the list, the cursor down past the
    /// screen, End and Home — and expects them to draw alike at every step.
    private static func walkAlike(_ shape: Shape, _ count: Int, keys extra: [Key] = []) {
        let (pulled, whole) = twins(shape, count)
        func check(_ step: String) {
            #expect(content(pulled) == content(whole), "\(step):\n\(pulled.screen)\n---\n\(whole.screen)")
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
        for step in 1...3 {
            pulled.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
            whole.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
            check("wheel up \(step)")
        }
        _ = pulled.press(.tab)
        _ = whole.press(.tab)
        check("tab")
        for step in 1...14 {
            _ = pulled.press(.down)
            _ = whole.press(.down)
            check("down \(step)")
        }
        for (step, key) in extra.enumerated() {
            _ = pulled.press(key)
            _ = whole.press(key)
            check("key \(step)")
        }
        _ = pulled.press(.end)
        _ = whole.press(.end)
        check("end")
        for step in 1...3 {
            _ = pulled.press(.up)
            _ = whole.press(.up)
            check("up \(step)")
        }
        _ = pulled.press(.home)
        _ = whole.press(.home)
        check("home")
    }

    @Test("Rows of one to three lines draw what the list drawn whole draws")
    func multiLineDrawsWhatTheWholeListDraws() {
        Self.walkAlike(.multiLine, 300)
    }

    @Test("Sections draw what the list drawn whole draws")
    func sectionsDrawWhatTheWholeListDraws() {
        Self.walkAlike(.sectioned, 300)
    }

    @Test("An outline draws what the list drawn whole draws, opened and closed by the keys")
    func outlineDrawsWhatTheWholeListDraws() {
        Self.walkAlike(.outline, 100, keys: [.right, .down, .down, .right, .left])
    }

    @Test("An empty list is its placeholder's height, the view below it right under it")
    func emptyListIsItsPlaceholdersHeight() {
        let app = Self.app(.empty, 0)
        let lines = app.screen.lines
        let below = lines.firstIndex { $0.contains("below") }
        #expect(below == 3, "\(app.screen)")
    }

    /// The rows built on the first frame, three wheel steps, a `scrollTo` of
    /// a row near the end, two cursor pages, and End.
    private static func builtPerStep(_ shape: Shape, rows: Int) -> [Int] {
        let builds = Builds()
        let app = app(shape, rows, builds: builds, target: rows - 20)
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

    @Test("The rows built a frame are under 100, the same at 1,000 and 10,000 rows", arguments: [Shape.multiLine, .sectioned])
    fileprivate func builtRowsIndependentOfRowCount(_ shape: Shape) {
        let small = Self.builtPerStep(shape, rows: 1_000)
        #expect(small.allSatisfy { $0 < 100 }, "\(small)")
        #expect(Self.builtPerStep(shape, rows: 10_000) == small)
    }

    @Test("The wheel reaches every one of 10,000 rows of varying height, and the button below")
    func wheelReachesEveryRow() {
        let app = Self.app(.multiLine, 10_000)
        var seen = Set(Self.rowsShown(app))
        for _ in 0..<2_400 {
            app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
            seen.formUnion(Self.rowsShown(app))
            if seen.contains(9_999), app.screen.contains("below") { break }
        }
        #expect(seen == Set(0..<10_000), "missing \(Set(0..<10_000).subtracting(seen).sorted().prefix(10))")
        #expect(app.screen.contains("below"))
    }

    @Test("Page Down moves the cursor through 10,000 rows of varying height, End the last, Home the first")
    func keysReachEveryRow() {
        let app = Self.app(.multiLine, 10_000)
        _ = app.press(.tab)
        var seen = Set(Self.rowsShown(app))
        var pages = 0
        while !seen.contains(9_999), pages < 3_000 {
            _ = app.press(.pageDown)
            let shown = Self.rowsShown(app)
            #expect(!shown.isEmpty)
            seen.formUnion(shown)
            pages += 1
        }
        #expect(seen == Set(0..<10_000), "missing \(Set(0..<10_000).subtracting(seen).sorted().prefix(10))")
        _ = app.press(.home)
        #expect(Self.rowsShown(app).first == 0, "\(app.screen)")
        _ = app.press(.end)
        #expect(app.screen.contains("r9999"), "\(app.screen)")
    }

    @Test("scrollTo lands a row never built at the top, at 10,000 rows of varying height", arguments: [0, 517, 5_000, 9_999])
    func scrollToLandsARow(_ target: Int) {
        let app = Self.app(.multiLine, 10_000, target: target)
        _ = app.press(.character("j"))
        #expect(Self.rowsShown(app).contains(target), "\(app.screen)")
        if target != 0, target < 9_990 { #expect(Self.rowsShown(app).first == target, "\(app.screen)") }
    }

    @Test("Tab reaches the list and the button below 10,000 rows of varying height; Shift-Tab comes back")
    func tabReachesPastTheList() {
        let app = Self.app(.multiLine, 10_000)
        _ = app.press(.tab)  // the list
        _ = app.press(.tab)  // the button below it
        #expect(app.screen.contains("below"), "\(app.screen)")
        _ = app.press(.tab, modifiers: .shift)  // back to the list
        _ = app.press(.end)
        #expect(app.screen.contains("r9999"), "\(app.screen)")
    }
}
