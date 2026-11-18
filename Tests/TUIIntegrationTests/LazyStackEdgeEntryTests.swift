//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyStackEdgeEntryTests.swift
//
//  Tab and Shift-Tab coming into a `ScrollView`'s `LazyVStack` from a control
//  outside it land on the stack's first or last row with something to focus,
//  however far off screen and past however many rows with nothing to focus,
//  as an eager `VStack`'s do (LAZY-EDGE, owner 2026-11-17: an improvement on
//  SwiftUI, whose lazy stack lands on a row it has made). The scroll view
//  tells the stack, by last frame's Tab order, that the focus is about to come
//  in; the stack walks in from that edge until a row registers a focusable
//  (`StackFocusReach.swift`). A stack with nothing to focus is passed by, as a
//  `VStack`'s is, and walked once, not on every Tab, until its rows change.
//  The rows the walk looks at, and the row it draws off screen for the ring,
//  run no `onAppear`. And a row whose control has an explicit `.focusID(_:)`
//  is found by where that control registered, so its neighbours are drawn and
//  neither Tab nor the arrows leave the stack early.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

/// One row: its position, and whether it holds a button. Equatable, so the
/// stack can tell when the rows change.
private struct Item: Identifiable, Equatable {
    let id: Int
    var focusable: Bool
}

/// The rows a page draws, which a test changes to see the stack walked again.
@Observable
@MainActor
private final class Rows {
    var items: [Item]
    init(_ items: [Item]) { self.items = items }
}

/// How many times a row's body ran, and which rows appeared.
@MainActor
private enum Seen {
    static var builds = 0
    static var appeared: Set<Int> = []
}

@MainActor
@Suite("Tab into a lazy stack from outside its scroll view", .serialized)
struct LazyStackEdgeEntryTests {
    /// A row: a button when its value says so, a line of text otherwise; its
    /// `onAppear` notes its position.
    private struct Row: View {
        let item: Item
        var body: some View {
            Seen.builds += 1
            let index = item.id
            let name = LazyStackFocusSectionTests.pad(index % 100)
            return Group {
                if item.focusable {
                    Button("b\(name)") {}.focusID("b\(index)")
                } else {
                    Text("x\(name)")
                }
            }
            .onAppear { Seen.appeared.insert(index) }
        }
    }

    private struct Page: View {
        let lazy: Bool
        let rows: Rows

        @ViewBuilder private var stack: some View {
            if lazy {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.items) { Row(item: $0) }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.items) { Row(item: $0) }
                }
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}.focusID("top")
                ScrollView { stack }.frame(height: 6)
                Button("bottom") {}.focusID("bottom")
            }
        }
    }

    /// `count` rows, focusable where `focusable` says.
    private static func rows(_ count: Int, focusable: (Int) -> Bool) -> Rows {
        Rows((0..<count).map { Item(id: $0, focusable: focusable($0)) })
    }

    private func app(lazy: Bool, _ rows: Rows) -> TestApp {
        Seen.builds = 0
        Seen.appeared = []
        let app = TestApp(width: 30, height: 12) { Page(lazy: lazy, rows: rows) }
        app.frame(atNanos: 16_666_667)
        return app
    }

    /// What the focus lands on, `times` presses of Tab (Shift-Tab with
    /// `backward`), each marked `!` when it is a row not on screen.
    private func walk(_ app: TestApp, backward: Bool = false, times: Int) -> [String] {
        (0..<times).map { _ in
            _ = app.press(.tab, modifiers: backward ? .shift : [])
            guard let id = app.focusedID else { return "nothing" }
            if id.hasPrefix("scrollview") { return "scroll" }
            guard id.hasPrefix("b"), let index = Int(id.dropFirst()) else { return id }
            let label = "b" + LazyStackFocusSectionTests.pad(index % 100)
            return app.screen.lines.contains { $0.contains(label) } ? id : id + "!"
        }
    }

    @Test("Tab from above walks past the rows with nothing to focus to the first that has, off screen, as a VStack")
    func tabPastEmptyRows() {
        let make = { Self.rows(40, focusable: { $0 >= 25 }) }
        let lazy = walk(app(lazy: true, make()), times: 6)
        let eager = walk(app(lazy: false, make()), times: 6)
        #expect(lazy == eager)
        #expect(lazy.first == "b25", "\(lazy)")
    }

    @Test("Shift-Tab from below walks up past the rows with nothing to focus to the last that has, as a VStack")
    func shiftTabPastEmptyRows() {
        // The band shows rows 0 to 5, all focusable; the last focusable row is
        // 14, and rows 15 to 39 have nothing to focus.
        let make = { Self.rows(40, focusable: { $0 < 15 }) }
        let lazy = walk(app(lazy: true, make()), backward: true, times: 6)
        let eager = walk(app(lazy: false, make()), backward: true, times: 6)
        #expect(lazy == eager)
        // Up from the top control: round to the bottom one, the scroll view's
        // own stop, then the stack's last focusable row.
        #expect(Array(lazy.prefix(4)) == ["bottom", "scroll", "b14", "b13"], "\(lazy)")
    }

    @Test("A stack with nothing to focus is passed by as a VStack's, and walked once until its rows change")
    func nothingToFocus() {
        let count = 400
        let rows = Self.rows(count, focusable: { _ in false })
        let app = app(lazy: true, rows)
        var buildsPerPress: [Int] = []
        var landed: [String] = []
        for _ in 0..<9 {
            let before = Seen.builds
            landed += walk(app, times: 1)
            buildsPerPress.append(Seen.builds - before)
        }
        #expect(landed == ["scroll", "bottom", "top", "scroll", "bottom", "top", "scroll", "bottom", "top"])
        // One walk of every row, at most: the band's rows are a few dozen
        // builds a frame.
        #expect(buildsPerPress.filter { $0 >= count }.count <= 1, "builds per Tab: \(buildsPerPress)")
        #expect(buildsPerPress.reduce(0, +) < 2 * count, "builds per Tab: \(buildsPerPress)")

        // New rows, one of them focusable: walked again, and Tab comes in.
        rows.items[300].focusable = true
        let after = walk(app, times: 4)
        #expect(after.contains("b300"), "\(after)")
    }

    @Test("Looking for a row to land on runs no onAppear; landing on it does, once it is on screen")
    func walkRunsNoOnAppear() {
        let app = app(lazy: true, Self.rows(40, focusable: { _ in true }))
        // Up from the top control: the bottom one, then the scroll view's own
        // stop, which is where the stack draws its last row off screen for the
        // ring, and where its walk in from the end looks at it.
        let way = walk(app, backward: true, times: 2)
        #expect(way == ["bottom", "scroll"])
        #expect(Seen.appeared.max() ?? 0 < 20, "appeared: \(Seen.appeared.sorted())")
        // Then onto the last row, which scrolls in and appears.
        #expect(walk(app, backward: true, times: 1) == ["b39"])
        #expect(Seen.appeared.contains(39))
    }

    @Test("Ten thousand rows with one focusable at the end: Tab from above lands on it")
    func tenThousandRows() {
        let count = 10_000
        let app = app(lazy: true, Self.rows(count, focusable: { $0 == count - 1 }))
        let clock = ContinuousClock()
        var longest = Duration.zero
        var landed: [String] = []
        for _ in 0..<3 {
            let start = clock.now
            landed += walk(app, times: 1)
            longest = max(longest, clock.now - start)
        }
        #expect(landed == ["b\(count - 1)", "scroll", "bottom"], "\(landed)")
        // The frame the walk holds, for the record: no bound is asserted.
        print("LAZY-EDGE 10k walk: longest Tab \(longest)")
    }

    // MARK: - Explicit focus ids

    /// Buttons `rNN` a line apart, each with an explicit id, between a button
    /// above and one below a five-line scroll view.
    private struct NamedRows: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("above") {}.focusID("above")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<20, id: \.self) { index in
                            let name = "r" + LazyStackFocusSectionTests.pad(index)
                            Button(name) {}.focusID(name)
                        }
                    }
                }
                .frame(height: 5)
                Button("below") {}.focusID("below")
            }
        }
    }

    @Test("Rows with explicit focus ids walk with the arrows and Tab to the last row before leaving",
          arguments: [ArrowFocus.tabOrder, .geometric])
    func explicitIDs(_ arrows: ArrowFocus) {
        let app = TestApp(width: 30, height: 12) { NamedRows() }
        app.arrowFocus = arrows
        app.frame(atNanos: 16_666_667)
        _ = app.press(.tab)
        var down: [String] = []
        for _ in 0..<20 {
            _ = app.press(.down)
            down.append(app.focusedID ?? "nothing")
        }
        let rows = (1..<20).map { "r" + LazyStackFocusSectionTests.pad($0) }
        #expect(Array(down.prefix(19)) == rows, "\(down)")
        #expect(down.last.map { $0.hasPrefix(arrows == .geometric ? "below" : "scrollview") } == true, "\(down)")
    }

    @Test("Shift-Tab from below enters rows with explicit focus ids at the last")
    func explicitIDsShiftTab() {
        let app = TestApp(width: 30, height: 12) { NamedRows() }
        app.frame(atNanos: 16_666_667)
        var seen: [String] = []
        for _ in 0..<4 {
            _ = app.press(.tab, modifiers: .shift)
            seen.append(app.focusedID.map { $0.hasPrefix("scrollview") ? "scroll" : $0 } ?? "nothing")
        }
        #expect(seen == ["below", "scroll", "r19", "r18"], "\(seen)")
    }
}
