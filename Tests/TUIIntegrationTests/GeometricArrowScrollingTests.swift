//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometricArrowScrollingTests.swift
//
//  `TUI_ARROW_FOCUS=geometric` past a scroll view's edge: the arrows go to the
//  control that lies that way in the layout whether or not the last frame
//  showed it, and the scroll views around it bring it into view — a grid much
//  larger than its viewport is walked with the arrows alone, as a stack of
//  rows, a `LazyVStack` of them, a `LazyVGrid`, and through a scroll view
//  inside another.
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
    /// corner a scroll view left where it cut it.
    private func isShownWhole(_ id: String, in app: TestApp) -> Bool {
        let regions = app.services.mouseEventDispatcher.regions.filter { $0.focusID == id }
        return regions.contains { !$0.isGeometryMarker && $0.width > 0 }
            && !regions.contains(where: \.isGeometryMarker)
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
        #expect(walk(grid, .down, times: 19, visited: &visited))
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
    }
}
