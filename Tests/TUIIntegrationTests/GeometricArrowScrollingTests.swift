//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometricArrowScrollingTests.swift
//
//  `TUI_ARROW_FOCUS=geometric` past a scroll view's edge: the arrows go to the
//  control that lies that way in the layout whether or not the last frame
//  showed it, and the scroll views around it bring it into view — a grid much
//  larger than its viewport is walked with the arrows alone, as a stack of
//  rows, a `LazyVStack` of them, a `LazyVGrid`, and through a scroll view
//  inside another — and the arrow goes on through a scroll view's content
//  before it leaves for a control outside it that lies as near (GEO-SCROLL-EDGE).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("Geometric arrow focus past a scroll view's edge")
struct GeometricArrowScrollingTests {
    static let side = 20

    /// A cell's focus id and label: its row and column, two digits each, so
    /// every button is as wide as every other and the columns line up.
    static func cell(_ row: Int, _ column: Int) -> String {
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return "\(two(row))\(two(column))"
    }

    /// Twenty rows of twenty buttons in a scroll view thirty columns wide and
    /// ten rows tall: most of the grid is out of sight at any time.
    private struct StackGrid: View {
        var body: some View {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<GeometricArrowScrollingTests.side, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<GeometricArrowScrollingTests.side, id: \.self) { column in
                                let name = GeometricArrowScrollingTests.cell(row, column)
                                Button(name) {}.focusID(name)
                            }
                        }
                    }
                }
            }
            .frame(width: 30, height: 10)
        }
    }

    /// The same rows in a `LazyVStack`, which builds only the rows meeting the
    /// viewport, one past each edge, and the focused row's neighbours: the row
    /// an arrow goes to next is always among them.
    private struct LazyRows: View {
        var body: some View {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<GeometricArrowScrollingTests.side, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<GeometricArrowScrollingTests.side, id: \.self) { column in
                                let name = GeometricArrowScrollingTests.cell(row, column)
                                Button(name) {}.focusID(name)
                            }
                        }
                    }
                }
            }
            .frame(width: 30, height: 10)
        }
    }

    /// The same four hundred buttons flowed into a `LazyVGrid` of twenty fixed
    /// columns.
    private struct LazyGrid: View {
        var body: some View {
            ScrollView([.horizontal, .vertical]) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(8)), count: GeometricArrowScrollingTests.side)
                ) {
                    ForEach(0..<(GeometricArrowScrollingTests.side * GeometricArrowScrollingTests.side), id: \.self) {
                        let name = GeometricArrowScrollingTests.cell(
                            $0 / GeometricArrowScrollingTests.side, $0 % GeometricArrowScrollingTests.side)
                        Button(name) {}.focusID(name)
                    }
                }
            }
            .frame(width: 30, height: 10)
        }
    }

    private func app<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> TestApp {
        let app = TestApp(content: content)
        app.arrowFocus = .geometric
        return app
    }

    /// Whether `id` is drawn whole on screen: a region the control drew, and no
    /// corner a scroll view left where it cut it (a scroll view's mark that the
    /// control lies in it is no cut).
    private func isShownWhole(_ id: String, in app: TestApp) -> Bool {
        let regions = app.services.mouseEventDispatcher.regions.filter { $0.focusID == id }
        return regions.contains { !$0.isGeometryMarker && $0.width > 0 }
            && !regions.contains { $0.handlerID == .focusFrameStart || $0.handlerID == .focusFrameEnd }
    }

    /// Whether `id` is out of sight but laid out: only the corners a scroll
    /// view left where it cut it.
    private func isOutOfSight(_ id: String, in app: TestApp) -> Bool {
        let regions = app.services.mouseEventDispatcher.regions.filter { $0.focusID == id }
        return !regions.isEmpty && regions.allSatisfy(\.isGeometryMarker)
    }

    /// Presses `key` `times` times, and says whether the focused button was
    /// shown whole after every one of them.
    private func walk(_ app: TestApp, _ key: Key, times: Int, visited: inout Set<String>) -> Bool {
        var alwaysShown = true
        for _ in 0..<times {
            app.press(key)
            let focused = app.focusedID ?? "nil"
            visited.insert(focused)
            if !isShownWhole(focused, in: app) { alwaysShown = false }
        }
        return alwaysShown
    }

    @Test("Right reaches the end of the row and Down the bottom of the column, scrolling as they go")
    func edges() {
        let grid = app { StackGrid() }
        #expect(grid.focusedID == Self.cell(0, 0))
        #expect(isOutOfSight(Self.cell(0, 19), in: grid))
        var visited: Set<String> = []
        #expect(walk(grid, .right, times: 19, visited: &visited))
        #expect(grid.focusedID == Self.cell(0, 19))
        #expect(isOutOfSight(Self.cell(0, 0), in: grid))
        // No wrap to the next row, which comes next in Tab order.
        grid.press(.right)
        #expect(grid.focusedID == Self.cell(0, 19))
        #expect(walk(grid, .down, times: 19, visited: &visited))
        #expect(grid.focusedID == Self.cell(19, 19))
        grid.press(.down)
        #expect(grid.focusedID == Self.cell(19, 19))
        #expect(walk(grid, .left, times: 19, visited: &visited))
        #expect(walk(grid, .up, times: 19, visited: &visited))
        #expect(grid.focusedID == Self.cell(0, 0))
        #expect(isShownWhole(Self.cell(0, 0), in: grid))
    }

    /// Walks every row, right along the even ones and left along the odd ones,
    /// stepping down between them.
    private func snake(_ grid: TestApp) -> (visited: Set<String>, alwaysShown: Bool) {
        var visited: Set<String> = [grid.focusedID ?? "nil"]
        var alwaysShown = true
        for row in 0..<Self.side {
            alwaysShown = walk(grid, row.isMultiple(of: 2) ? .right : .left, times: Self.side - 1, visited: &visited)
                && alwaysShown
            if row < Self.side - 1 { alwaysShown = walk(grid, .down, times: 1, visited: &visited) && alwaysShown }
        }
        return (visited, alwaysShown)
    }

    private static let allCells: Set<String> = Set(
        (0..<side).flatMap { row in (0..<side).map { cell(row, $0) } })

    @Test("Every button of a stack of rows is reachable with the arrows alone")
    func everyCellOfAStack() {
        let walked = snake(app { StackGrid() })
        #expect(walked.visited == Self.allCells)
        #expect(walked.alwaysShown)
    }

    @Test("Every button of a LazyVStack's rows is reachable with the arrows alone")
    func everyCellOfLazyRows() {
        let grid = app { LazyRows() }
        #expect(grid.focusedID == Self.cell(0, 0))
        let walked = snake(grid)
        #expect(walked.visited == Self.allCells)
        #expect(walked.alwaysShown)
    }

    @Test("Every button of a LazyVGrid is reachable with the arrows alone")
    func everyCellOfALazyGrid() {
        let grid = app { LazyGrid() }
        #expect(grid.focusedID == Self.cell(0, 0))
        let walked = snake(grid)
        #expect(walked.visited == Self.allCells)
        #expect(walked.alwaysShown)
    }

    /// A button at the top right of a scroll view, and below the fold a row of
    /// buttons in a narrower scroll view that scrolls across: the buttons at
    /// that row's end are cut by both.
    private struct Nested: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button("far") {}.focusID("far").padding(.leading, 60)
                    ForEach(0..<12, id: \.self) { Text("line \($0)") }
                    ScrollView(.horizontal) {
                        HStack(spacing: 1) {
                            ForEach(0..<10, id: \.self) { Button("b\($0)") {}.focusID("b\($0)") }
                        }
                    }
                    .frame(width: 20)
                    ForEach(0..<12, id: \.self) { Text("after \($0)") }
                }
            }
            .frame(width: 70, height: 8)
        }
    }

    @Test("Through nested scroll views: the arrow goes by the layout, and both scroll to show the control")
    func nested() {
        let nested = app { Nested() }
        #expect(nested.focusedID == "far")
        // Below `far` (columns 60 to 66), at the end of the inner row, `b8`
        // (56 to 61) and `b9` (63 to 68) both overlap its columns, the same
        // distance down, and `b8` comes first in Tab order. Both lie below the
        // outer view's fold and past the inner view's right edge.
        #expect(isOutOfSight("b8", in: nested))
        nested.press(.down)
        #expect(nested.focusedID == "b8")
        #expect(isShownWhole("b8", in: nested))
        #expect(isOutOfSight("far", in: nested))
        // And back: `far` is above, out of sight, and found there.
        nested.press(.up)
        #expect(nested.focusedID == "far")
        #expect(isShownWhole("far", in: nested))
    }

    @Test("The default mode leaves no corners behind")
    func defaultKeepsNoCorners() {
        let plain = TestApp { StackGrid() }
        plain.press(.right)
        #expect(!plain.services.mouseEventDispatcher.regions.contains { $0.handlerID == .focusFrameStart })
        #expect(!plain.services.mouseEventDispatcher.regions.contains { $0.handlerID == .focusScrollMember })
    }

    /// A button above a scroll view of rows a blank line apart, or each over a
    /// caption, and a button below it: the row just past either edge of the
    /// viewport lies a line further than the button outside it, in screen
    /// coordinates. With captions, the row past either edge lies past one that
    /// holds no control, which a lazy stack draws for the focus ring
    /// (`StackFocusReach.swift`). The rows keep their default focus ids: a lazy
    /// stack finds the focused row, and so its neighbours, by the path in the
    /// id, which an explicit `.focusID(_:)` has none of.
    private struct Column: View {
        let lazy: Bool
        let captions: Bool

        @ViewBuilder private func row(_ index: Int) -> some View {
            Button("r\(index)") {}
            if captions { Text("c\(index)") }
        }

        @ViewBuilder private var rows: some View {
            if lazy {
                LazyVStack(alignment: .leading, spacing: captions ? 0 : 1) {
                    ForEach(0..<12, id: \.self) { row($0) }
                }
            } else {
                VStack(alignment: .leading, spacing: captions ? 0 : 1) {
                    ForEach(0..<12, id: \.self) { row($0) }
                }
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("above") {}.focusID("above")
                ScrollView { rows }.frame(width: 20, height: 5)
                Button("below") {}.focusID("below")
            }
        }
    }

    /// Presses `key` `times` times, and gives the focused control after each,
    /// each marked `!` where it was not shown whole: a row of ``Column`` as
    /// `r` and its index, which its default focus id ends in, the scroll view
    /// as `scroll`, and any other by its id.
    private func steps(_ app: TestApp, _ key: Key, times: Int) -> [String] {
        (0..<times).map { _ in
            app.press(key)
            let focused = app.focusedID ?? "nil"
            var name = focused
            if focused.hasPrefix("scrollview") {
                name = "scroll"
            } else if let index = focused.matches(of: /\[(\d+)\]/).last?.1 {
                name = "r\(index)"
            }
            return isShownWhole(focused, in: app) ? name : name + "!"
        }
    }

    @Test("Down and Up go through every row of a scroll view before the buttons outside it",
          arguments: [false, true], [false, true])
    func columnEdges(lazy: Bool, captions: Bool) {
        let column = app { Column(lazy: lazy, captions: captions) }
        #expect(column.focusedID == "above")
        // Down to the last row, past the viewport's bottom edge each time from
        // r2 on; Up to the first, past its top edge each time from r9 down,
        // and out; Down again through every row, and out at the bottom.
        let rows = (0..<12).map { "r\($0)" }
        #expect(steps(column, .down, times: 12) == rows)
        #expect(steps(column, .up, times: 12) == rows.dropLast().reversed() + ["above"])
        #expect(steps(column, .down, times: 13) == rows + ["below"])
    }

    /// A button either side of a scroll view across of buttons with no gap
    /// between them: the button just past the viewport's left edge ends where
    /// the button outside it does.
    private struct Row: View {
        var body: some View {
            HStack(spacing: 0) {
                Button("left") {}.focusID("left")
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<12, id: \.self) { Button("c\($0)") {}.focusID("c\($0)") }
                    }
                }
                .frame(width: 24)
                Button("right") {}.focusID("right")
            }
        }
    }

    @Test("Right and Left go through every button of a scroll view across before the buttons outside it")
    func rowEdges() {
        let row = app { Row() }
        #expect(row.focusedID == "left")
        #expect(steps(row, .right, times: 13) == (0..<12).map { "c\($0)" } + ["right"])
        #expect(steps(row, .left, times: 13) == (0..<12).reversed().map { "c\($0)" } + ["left"])
    }
}
