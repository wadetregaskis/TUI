//  🖥️ TUI — A Terminal UI framework for Swift
//  NestedScrollViewForwardTests.swift
//
//  SCROLL-FIT P7 (design 2a): a vertical `ScrollView` in a vertical scroll
//  view's content, given no height, is its content's height and scrolls
//  nothing: the outer view scrolls it. Its content is drawn in its place, so
//  a lazy stack in it is pulled by the column above, building only the rows
//  on screen; it draws what the same content written without the inner
//  scroll view draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// A title, `rows` rows (in a scroll view of their own, or not), and a line
/// below them, in a scroll view.
private struct NestedPage: View {
    let rows: Int
    let nested: Bool
    var lazy = false
    let probe: Counter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                if nested {
                    ScrollView { column }
                } else {
                    column
                }
                Text("below")
            }
        }
    }

    @ViewBuilder private var column: some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) { ForEach(0..<rows, id: \.self) { row($0) } }
        } else {
            VStack(alignment: .leading, spacing: 0) { ForEach(0..<rows, id: \.self) { row($0) } }
        }
    }

    private func row(_ index: Int) -> Text {
        probe.built += 1
        return Text(verbatim: "r\(index)")
    }
}

@MainActor private final class Counter { var built = 0 }

@MainActor
@Suite("SCROLL-FIT P7: a scroll view nested along the same axis draws its content in its place")
struct NestedScrollViewForwardTests {
    private static func app(rows: Int, nested: Bool, lazy: Bool = false, probe: Counter = Counter()) -> TestApp {
        TestApp(width: 30, height: 12) { NestedPage(rows: rows, nested: nested, lazy: lazy, probe: probe) }
    }

    @Test("A short nested scroll view is its content's height: the line below stands right under it")
    func shortNestedIsItsContentsHeight() {
        let app = Self.app(rows: 3, nested: true)
        let below = app.screen.lines.firstIndex { $0.hasPrefix("below") }
        #expect(below == 4, "\(app.screen)")
    }

    @Test("The nested scroll view draws what its content written in its place draws", arguments: [false, true])
    func drawsWhatItsContentDraws(_ lazy: Bool) {
        let nested = Self.app(rows: 400, nested: true, lazy: lazy)
        let plain = Self.app(rows: 400, nested: false, lazy: lazy)
        func check(_ step: String) {
            #expect(nested.screen.text == plain.screen.text, "\(step):\n\(nested.screen)\n---\n\(plain.screen)")
        }
        check("top")
        for step in 1...5 {
            nested.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
            plain.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
            check("wheel \(step)")
        }
        for app in [nested, plain] { _ = app.press(.end) }
        check("end")
        #expect(nested.screen.contains("below"), "\(nested.screen)")
        for app in [nested, plain] { app.scroll(.up, by: 7, at: CellPoint(x: 5, y: 5)) }
        check("wheel up from the end")
        // No bar of its own: only the page's, in the last column.
        #expect(!nested.screen.lines.contains { $0.dropLast().contains { "▲▼".contains($0) } }, "\(nested.screen)")
    }

    /// The rows a page builds for its first frame, a wheel step and End.
    private static func built(rows: Int, nested: Bool) -> (first: Int, step: Int, end: Int, screen: String) {
        let probe = Counter()
        let app = Self.app(rows: rows, nested: nested, lazy: true, probe: probe)
        let first = probe.built
        probe.built = 0
        app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
        let step = probe.built
        probe.built = 0
        _ = app.press(.end)
        return (first, step, probe.built, app.screen.text)
    }

    @Test("A lazy stack in a nested scroll view builds the rows the stack written in its place builds")
    func lazyStackInNestedIsPulled() {
        let small = Self.built(rows: 1_000, nested: true)
        let tall = Self.built(rows: 10_000, nested: true)
        let plain = Self.built(rows: 10_000, nested: false)
        #expect(tall.first < 150 && tall.step < 100 && tall.end < 150, "\(tall)")
        #expect(tall.first == plain.first && tall.step == plain.step && tall.end == plain.end, "\(tall) \(plain)")
        #expect(tall.first == small.first && tall.step == small.step && tall.end == small.end, "\(tall) \(small)")
        #expect(tall.screen.contains("r9999") && tall.screen.contains("below"), "\(tall.screen)")
    }
}
