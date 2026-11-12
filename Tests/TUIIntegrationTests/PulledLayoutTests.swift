//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledLayoutTests.swift
//
//  SCROLL-FIT's pull through an app's own `Layout` (design B-SCROLLFIT-13,
//  P9): a lazy stack among the subviews of a layout the app writes is pulled
//  through it, served by the placements the layout makes, rather than drawn
//  whole. Twins against the same layouts around the same rows drawn eagerly:
//  a top-to-bottom flow, two columns, and a flow spaced by a `LayoutValueKey`
//  and the subviews' spacing; and a flow of two lazy stacks one below the
//  other, which the adapter cannot place from its rects and draws whole.
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

/// Lines a subview asks for above it in a ``Flow``.
private struct Gap: LayoutValueKey {
    static let defaultValue = 0
}

/// Top to bottom, each subview offered the whole width and placed at its
/// height: its `Gap` lines, and the spacing its neighbour and it prefer,
/// above it.
private struct Flow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let width = proposal.width ?? 0
        let frames = frames(width: width, subviews: subviews)
        return ViewSize(width: width, height: frames.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CellPoint(x: bounds.x, y: bounds.y + frame.y),
                proposal: ProposedViewSize(width: bounds.width, height: frame.height))
        }
    }

    private func frames(width: Int, subviews: Subviews) -> [(y: Int, height: Int)] {
        var frames: [(y: Int, height: Int)] = []
        var y = 0
        for index in subviews.indices {
            if index > 0 { y += subviews[index - 1].spacing.distance(to: subviews[index].spacing, along: .vertical) }
            y += subviews[index][Gap.self]
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            frames.append((y, height))
            y += height
        }
        return frames
    }
}

/// The first subview in a gutter at its own width, the others top to bottom
/// in the column a cell to its right, the two columns' tops level.
private struct TwoColumns: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let width = proposal.width ?? 0
        let (gutter, frames) = frames(width: width, subviews: subviews)
        return ViewSize(width: width, height: max(gutter.height, frames.last.map { $0.y + $0.height } ?? 0))
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        let (gutter, frames) = frames(width: bounds.width, subviews: subviews)
        first.place(at: CellPoint(x: bounds.x, y: bounds.y), proposal: ProposedViewSize(width: gutter.width, height: gutter.height))
        let x = gutter.width + 1
        for (subview, frame) in zip(subviews.dropFirst(), frames) {
            subview.place(
                at: CellPoint(x: bounds.x + x, y: bounds.y + frame.y),
                proposal: ProposedViewSize(width: max(0, bounds.width - x), height: frame.height))
        }
    }

    private func frames(width: Int, subviews: Subviews) -> (gutter: ViewSize, [(y: Int, height: Int)]) {
        guard let first = subviews.first else { return (ViewSize(width: 0, height: 0), []) }
        let gutter = first.sizeThatFits(.unspecified)
        let column = max(0, width - gutter.width - 1)
        var frames: [(y: Int, height: Int)] = []
        var y = 0
        for subview in subviews.dropFirst() {
            let height = subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            frames.append((y, height))
            y += height
        }
        return (gutter, frames)
    }
}

@MainActor
@Suite("SCROLL-FIT pull: a lazy stack in an app's own Layout builds only what is on screen")
struct PulledLayoutTests {
    enum Shape: String, CaseIterable, Sendable {
        /// A flow: a heading, the rows, a tail.
        case flow
        /// Two columns: a gutter beside a heading, the rows and a tail.
        case twoColumns
        /// A flow whose rows and tail ask for lines above them by a
        /// `LayoutValueKey`, and whose heading prefers a line below it.
        case spaced
        /// A flow of two lazy stacks, one below the other: the second's place
        /// is where the first ends, which only drawing the first says.
        case stackedTwo
        /// A flow whose rows sit in an `if`: the `if`'s view is its child at
        /// index 0, laid out among the layout's subviews.
        case flowIf

        /// The shapes whose stack is pulled through the layout.
        static let pulled = allCases.filter { $0 != .stackedTwo }
    }

    private static func text(_ prefix: String, _ index: Int) -> Text {
        Text(verbatim: index.isMultiple(of: 3) ? "\(prefix)\(index)\n  more" : "\(prefix)\(index)")
    }

    private static func rows(_ prefix: String, _ count: Int, lazy: Bool, builds: Builds?) -> AnyView {
        if lazy {
            return AnyView(
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        builds?.count += 1
                        return text(prefix, index)
                    }
                })
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) { ForEach(0..<count, id: \.self) { text(prefix, $0) } }
                .frame(maxWidth: .infinity, alignment: .leading))
    }

    @ViewBuilder
    private static func layout(_ shape: Shape, rows count: Int, lazy: Bool, builds: Builds?) -> some View {
        switch shape {
        case .flow:
            Flow {
                Text("head")
                rows("a", count, lazy: lazy, builds: builds)
                Text("tail")
            }
        case .twoColumns:
            TwoColumns {
                Text("|\n|")
                Text("head")
                rows("a", count, lazy: lazy, builds: builds)
                Text("tail")
            }
        case .spaced:
            Flow {
                Text("head").padding(.bottom, 1)
                rows("a", count, lazy: lazy, builds: builds).layoutValue(key: Gap.self, value: 1)
                Text("tail").layoutValue(key: Gap.self, value: 2)
            }
        case .stackedTwo:
            Flow {
                Text("head")
                rows("a", count, lazy: lazy, builds: builds)
                Text("mid")
                rows("b", count, lazy: lazy, builds: builds)
            }
        case .flowIf:
            Flow {
                Text("head")
                if shows { rows("a", count, lazy: lazy, builds: builds) }
                Text("tail")
            }
        }
    }

    /// What `flowIf`'s `if` tests, read at run time so the compiler keeps the
    /// branch.
    private static let shows = !CommandLine.arguments.isEmpty

    private static func app(
        _ shape: Shape, rows count: Int, lazy: Bool, builds: Builds? = nil, height: Int = 12
    ) -> TestApp {
        TestApp(width: 30, height: height) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    layout(shape, rows: count, lazy: lazy, builds: builds)
                    Text("footer")
                }
            }
        }
    }

    /// The screen without the scrollbar's column: the lazy stack's thumb
    /// reads its estimated height, the eager one's its exact one.
    private static func lines(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
    }

    @Test("The layout draws what it draws around the eager rows: top, paged, wheeled, at the end and home",
          arguments: Shape.allCases)
    func drawsWhatTheEagerOneDraws(_ shape: Shape) {
        let lazy = Self.app(shape, rows: 300, lazy: true)
        let eager = Self.app(shape, rows: 300, lazy: false)
        func check(_ step: String) {
            #expect(Self.lines(lazy) == Self.lines(eager), "\(shape) \(step):\n\(lazy.screen)\n---\n\(eager.screen)")
        }
        check("top")
        for page in 1...3 {
            _ = lazy.press(.pageDown)
            _ = eager.press(.pageDown)
            check("page \(page)")
        }
        for step in 1...3 {
            lazy.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            eager.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            check("wheel \(step)")
        }
        _ = lazy.press(.end)
        _ = eager.press(.end)
        check("end")
        for step in 1...4 {
            lazy.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
            eager.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
            check("wheel up \(step)")
        }
        _ = lazy.press(.home)
        _ = eager.press(.home)
        check("home")
    }

    /// The rows built on the first frame, on each of five page-downs, on two
    /// wheel steps and at End.
    private static func builtPerStep(_ shape: Shape, rows: Int) -> [Int] {
        let builds = Builds()
        let app = app(shape, rows: rows, lazy: true, builds: builds)
        _ = app.screen
        var counts = [builds.count]
        func step(_ action: () -> Void) {
            builds.count = 0
            action()
            counts.append(builds.count)
        }
        for _ in 0..<5 { step { _ = app.press(.pageDown) } }
        for _ in 0..<2 { step { app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5)) } }
        step { _ = app.press(.end) }
        return counts
    }

    /// `layout-list`: 10,000 rows in an app's layout build under 100 a frame,
    /// the same as 1,000 do.
    @Test("The rows built a frame are under 100, the same at 1,000 and 10,000 rows", arguments: Shape.pulled)
    func builtRowsIndependentOfRowCount(_ shape: Shape) {
        let small = Self.builtPerStep(shape, rows: 1_000)
        #expect(small.allSatisfy { $0 < 100 }, "\(shape): \(small)")
        let large = Self.builtPerStep(shape, rows: 10_000)
        #expect(large.allSatisfy { $0 < 100 }, "\(shape): \(large)")
        #expect(Array(large.dropLast()) == Array(small.dropLast()), "\(shape): \(small) at 1,000, \(large) at 10,000")
    }

    @Test("End shows the 10,000th row and the tail and footer below it; Home brings the title back",
          arguments: Shape.pulled)
    func endReachesTheLastRow(_ shape: Shape) {
        let app = Self.app(shape, rows: 10_000, lazy: true)
        _ = app.press(.end)
        #expect(app.screen.contains("a9999"), "\(shape): \(app.screen)")
        #expect(app.screen.contains("tail") && app.screen.contains("footer"), "\(shape): \(app.screen)")
        _ = app.press(.home)
        #expect(app.screen.lines[0].hasPrefix("title"), "\(shape): \(app.screen)")
    }

    @Test("The wheel reaches every one of 10,000 rows, in order", arguments: [Shape.twoColumns])
    func wheelReachesEveryRow(_ shape: Shape) {
        let app = Self.app(shape, rows: 10_000, lazy: true, height: 40)
        var seen = Set<Int>()
        var last = -1
        var inOrder = true
        func collect() {
            for line in app.screen.lines {
                for match in line.matches(of: /a(\d+)/) {
                    guard let row = Int(match.1) else { continue }
                    if !seen.contains(row) {
                        if row < last { inOrder = false }
                        last = row
                    }
                    seen.insert(row)
                }
            }
        }
        collect()
        // Ten ticks, thirty lines: less than the screen.
        for _ in 0..<700 where !seen.contains(9_999) {
            app.scroll(.down, by: 10, at: CellPoint(x: 5, y: 5))
            collect()
        }
        let missing = (0..<10_000).filter { !seen.contains($0) }
        #expect(missing.isEmpty, "\(shape): \(missing.count) rows never drawn: \(missing.prefix(10))")
        #expect(inOrder, "\(shape)")
    }
}

/// A page whose `j` key scrolls the reader's proxy to row `key` at `anchor`.
private struct SeekPage<Content: View>: View {
    let key: Int
    let anchor: UnitPoint
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content() }
                .onKeyEvent(.character("j")) { proxy.scrollTo(key, anchor: anchor) }
        }
    }
}

@MainActor
@Suite("SCROLL-FIT pull: scrollTo and Tab reach every row of a lazy stack in an app's own Layout")
struct PulledLayoutReachTests {
    private static func page(rows count: Int, lazy: Bool, builds: Builds? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("title")
            TwoColumns {
                Text("|")
                Button("head") {}
                rows(count, lazy: lazy, builds: builds)
                Button("tail") {}
            }
            Button("footer") {}
        }
    }

    /// The rows, through an `AnyView` rather than an `if` (`flowIf` has the
    /// `if`), so the twins differ only by the stack.
    private static func rows(_ count: Int, lazy: Bool, builds: Builds?) -> AnyView {
        if lazy {
            return AnyView(
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        builds?.count += 1
                        return Button("a" + String(index)) {}
                    }
                })
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) { ForEach(0..<count, id: \.self) { Button("a" + String($0)) {} } }
                .frame(maxWidth: .infinity, alignment: .leading))
    }

    /// The key of the innermost `ForEach` row a focus id lies in, or the
    /// last steps of its path for a control in none, the same in both twins.
    private static func label(_ id: String?) -> String {
        guard let id else { return "-" }
        let keys = id.matches(of: /\[([^\]]+)\]/).map { String($0.1) }
        guard let key = keys.last(where: { $0.wholeMatch(of: /\d+/) != nil }) else {
            return id.split(separator: "/").suffix(3).joined(separator: "/")
        }
        return "a\(key)"
    }

    private static func stops(_ app: TestApp, _ key: Key, modifiers: EventModifiers = [], steps: Int) -> [String] {
        _ = app.screen
        return (0..<steps).map { _ in
            _ = app.press(key, modifiers: modifiers)
            return label(app.focusedID)
        }
    }

    @Test("scrollTo lands a row of 10,000 at the top, building a screenful")
    func scrollToLandsTheRow() {
        let builds = Builds()
        let app = TestApp(width: 30, height: 12) {
            SeekPage(key: 6_000, anchor: .top) { Self.page(rows: 10_000, lazy: true, builds: builds) }
        }
        _ = app.screen
        builds.count = 0
        _ = app.press(.character("j"))
        #expect(app.screen.lines.first?.contains("a6000") == true, "\(app.screen)")
        #expect(builds.count < 100, "\(builds.count)")
    }

    @Test("Tab runs through the controls in the eager order, each one on screen")
    func tabOrderMatchesTheEagerOne() {
        let lazy = TestApp(width: 30, height: 10) { ScrollView { Self.page(rows: 300, lazy: true) } }
        let eager = TestApp(width: 30, height: 10) { ScrollView { Self.page(rows: 300, lazy: false) } }
        let lazyStops = Self.stops(lazy, .tab, steps: 40)
        #expect(lazyStops == Self.stops(eager, .tab, steps: 40))
        #expect(lazy.screen.contains(lazyStops.last ?? "-"), "\(lazy.screen)")
    }

    @Test("Shift-Tab from the footer below 10,000 rows steps to the tail, then the last row")
    func shiftTabFromBelowReachesTheLastRow() {
        let app = TestApp(width: 30, height: 10) { ScrollView { Self.page(rows: 10_000, lazy: true) } }
        // Shift-Tab from no focus goes to the scroll view, then to the last
        // control in it.
        let stops = Self.stops(app, .tab, modifiers: .shift, steps: 4)
        #expect(stops.last == "a9999", "\(stops)")
        #expect(app.screen.contains("a9999"), "\(app.screen)")
    }
}
