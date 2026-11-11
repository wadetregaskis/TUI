//  🖥️ TUI — A Terminal UI framework for Swift
//  TableHorizontalScrollTests.swift
//
//  A table whose columns' minimum widths do not fit scrolls sideways, a whole
//  column at a time, as SwiftUI's on macOS scrolls once its columns overflow
//  it (decisions TABLE-HSCROLL): the header scrolls with its columns, a
//  horizontal scrollbar marks where the window is, and the keys and the wheel
//  move it. A table whose columns fit draws as it always did.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITables
import TUITesting
@testable import TUITestSupport

private struct Reading: Identifiable, Equatable {
    let id: Int
    var alpha: String { "a\(id)" }
    var bravo: String { "b\(id)" }
    var charlie: String { "c\(id)" }
    var delta: String { "d\(id)" }
    var echo: String { "e\(id)" }
    var foxtrot: String { "f\(id)" }
}

private struct SixColumns: View {
    let rows = (1...3).map(Reading.init)
    @State private var order = [KeyPathComparator(\Reading.alpha)]

    var body: some View {
        Table(rows, sortOrder: $order) {
            TableColumn("Alpha", value: \.alpha)
            TableColumn("Bravo", value: \.bravo)
            TableColumn("Charlie", value: \.charlie)
            TableColumn("Delta", value: \.delta)
            TableColumn("Echo", value: \.echo)
            TableColumn("Foxtrot", value: \.foxtrot)
        }
    }
}

private struct WideFirstColumn: View {
    let rows = (1...3).map(Reading.init)

    var body: some View {
        Table(rows) {
            TableColumn("Alpha", value: \.alpha).width(min: 40)
            TableColumn("Bravo", value: \.bravo)
        }
    }
}

/// The six columns under a button that holds the focus, so the table rests
/// unfocused and its indicators, under `.overContent` (the default), are
/// drawn over its rows for the pointer alone.
private struct UnderAButton: View {
    var body: some View {
        VStack(spacing: 0) {
            Button("top") {}
            SixColumns()
        }
    }
}

@MainActor
private final class Harness {
    let app: TestApp
    private var now: Int64 = 0

    init<Page: View>(_ page: Page, width: Int, height: Int = 10) {
        app = TestApp(width: width, height: height) { page }
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func key(_ event: KeyEvent) {
        app.send(event)
        frame()
    }

    func send(_ event: MouseEvent) {
        app.send(event)
        frame()
    }

    var lines: [String] { app.screen.lines }

    var screen: String { lines.joined(separator: "\n") }

    /// The header line: the one with the first title it shows.
    func header(showing title: String) -> String? { lines.first { $0.contains(title) } }

    /// The line the horizontal scrollbar is drawn on: the one above the bottom
    /// border, which holds no row.
    var barLine: String? {
        guard let bottom = lines.lastIndex(where: { $0.contains("└") || $0.contains("╰") }), bottom > 0 else {
            return nil
        }
        return lines[bottom - 1]
    }
}

// MARK: - The arithmetic

@Suite("A table's sideways window, as arithmetic")
struct TableHorizontalWindowArithmeticTests {
    @Test("The stops run to the first column from which the rest fit")
    func stops() {
        // Widths 5, 5, 7, 5 spaced by 1: starts 0, 6, 12, 20; total 25.
        let (stops, extent) = TableHorizontalWindow.stops(of: [5, 5, 7, 5], spacing: 1, viewport: 13)
        // From 12 the rest are 13 wide: the window fits them, and goes no further.
        #expect(stops == [0, 6, 12])
        #expect(extent == 25)
        // A last window that leaves blank space past the last column: the extent
        // counts it, so the thumb can reach the end.
        let wide = TableHorizontalWindow.stops(of: [10, 10, 10], spacing: 1, viewport: 15)
        #expect(wide.stops == [0, 11, 22])
        #expect(wide.extent == 37)
    }

    @Test("A step lands on the next column whichever way it went, a page on the column it fell in")
    func snapping() {
        let stops = [0, 6, 12, 20]
        // An arrow's one cell, either way.
        #expect(TableHorizontalWindow.snappedStart(requested: 7, drawn: 6, dragging: false, stops: stops) == 2)
        #expect(TableHorizontalWindow.snappedStart(requested: 5, drawn: 6, dragging: false, stops: stops) == 0)
        // A page from 0 by 13 falls in the column starting at 12.
        #expect(TableHorizontalWindow.snappedStart(requested: 13, drawn: 0, dragging: false, stops: stops) == 2)
        // A thumb drag lands on the nearest.
        #expect(TableHorizontalWindow.snappedStart(requested: 10, drawn: 0, dragging: true, stops: stops) == 2)
        #expect(TableHorizontalWindow.snappedStart(requested: 8, drawn: 0, dragging: true, stops: stops) == 1)
        // Past the end, the last stop; unmoved, where it was.
        #expect(TableHorizontalWindow.snappedStart(requested: 99, drawn: 12, dragging: false, stops: stops) == 3)
        #expect(TableHorizontalWindow.snappedStart(requested: 12, drawn: 12, dragging: false, stops: stops) == 2)
    }

    @Test("Revealing a column starts the window no further along than it must")
    func revealing() {
        let widths = [5, 5, 7, 5, 4]
        let (stops, _) = TableHorizontalWindow.stops(of: widths, spacing: 1, viewport: 13)
        // Column 3 spans 20..<25: from 12 (index 2) it ends 13 cells on.
        #expect(
            TableHorizontalWindow.revealing(column: 3, from: 0, widths: widths, spacing: 1, viewport: 13, stops: stops)
                == 2)
        // A column left of the window starts it.
        #expect(
            TableHorizontalWindow.revealing(column: 1, from: 2, widths: widths, spacing: 1, viewport: 13, stops: stops)
                == 1)
    }

    @Test("The window shows whole columns, and the one it runs out in cut short")
    func shownWidths() {
        #expect(TableHorizontalWindow.shownWidths(from: 0, of: [5, 5, 7], spacing: 1, viewport: 13) == [5, 5, 1])
        #expect(TableHorizontalWindow.shownWidths(from: 1, of: [5, 5, 7], spacing: 1, viewport: 13) == [5, 7])
        // A column wider than the window is the window.
        #expect(TableHorizontalWindow.shownWidths(from: 0, of: [40, 5], spacing: 1, viewport: 13) == [13])
        // No cell left for the next: it is not drawn, and the last shown takes
        // what is left, so the window is always filled.
        #expect(TableHorizontalWindow.shownWidths(from: 0, of: [6, 6, 6], spacing: 1, viewport: 13) == [6, 6])
        #expect(TableHorizontalWindow.shownWidths(from: 0, of: [6, 5, 6], spacing: 1, viewport: 13) == [6, 6])
        #expect(TableHorizontalWindow.shownWidths(from: 1, of: [9, 4, 4], spacing: 1, viewport: 13) == [4, 8])
    }
}

// MARK: - The table

@MainActor
@Suite("A table whose columns do not fit scrolls sideways")
struct TableHorizontalScrollTests {
    @Test("Six columns in a narrow table show whole titles and a scrollbar, not a row of ellipses")
    func narrowTableShowsWholeColumns() throws {
        let harness = Harness(SixColumns(), width: 20)
        let header = try #require(harness.header(showing: "Alpha"), "\(harness.screen)")
        #expect(header.contains("Bravo"), "the columns that fit are drawn whole: \(harness.screen)")
        #expect(!header.contains("Foxtrot"), "\(harness.screen)")
        let bar = try #require(harness.barLine, "\(harness.screen)")
        #expect(bar.contains("◀") && bar.contains("▶"), "a horizontal scrollbar: \(harness.screen)")
    }

    @Test("Right and Left move the window a column at a time, the header with it")
    func arrowsScroll() throws {
        let harness = Harness(SixColumns(), width: 20)
        try #require(harness.header(showing: "Alpha") != nil, "\(harness.screen)")
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .right))
        let moved = try #require(harness.header(showing: "Bravo"), "\(harness.screen)")
        #expect(!moved.contains("Alpha"), "\(harness.screen)")
        #expect(harness.lines.contains { $0.contains("b1") && !$0.contains("a1") }, "the rows go with it: \(harness.screen)")
        for _ in 0..<10 { harness.key(KeyEvent(key: .right)) }
        #expect(harness.header(showing: "Foxtrot") != nil, "the last column can be reached: \(harness.screen)")
        for _ in 0..<10 { harness.key(KeyEvent(key: .left)) }
        #expect(harness.header(showing: "Alpha") != nil, "and the first again: \(harness.screen)")
    }

    @Test("The sideways wheel, and Shift with the vertical wheel, scroll the columns")
    func wheelScrolls() throws {
        let harness = Harness(SixColumns(), width: 20)
        let y = try #require(harness.lines.firstIndex { $0.contains("a1") }, "\(harness.screen)")
        harness.send(MouseEvent(button: .scrollRight, phase: .pressed, x: 5, y: y))
        #expect(harness.header(showing: "Alpha") == nil, "\(harness.screen)")
        #expect(harness.header(showing: "Bravo") != nil, "\(harness.screen)")
        harness.send(MouseEvent(button: .scrollUp, phase: .pressed, x: 5, y: y, shift: true))
        #expect(harness.header(showing: "Alpha") != nil, "Shift turns the wheel sideways: \(harness.screen)")
    }

    @Test("A column picked from the keyboard is scrolled into sight")
    func pickedColumnIsRevealed() throws {
        let harness = Harness(SixColumns(), width: 20)
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .character("k"), ctrl: true))
        for _ in 0..<5 { harness.key(KeyEvent(key: .right)) }
        #expect(harness.header(showing: "Foxtrot") != nil, "\(harness.screen)")
    }

    @Test("Sorting by a column from the keyboard scrolls its header into sight")
    func sortedColumnIsRevealed() throws {
        let harness = Harness(SixColumns(), width: 20)
        harness.key(KeyEvent(key: .tab))
        // Ctrl-S sorts by the next sortable column, from Alpha on round.
        for _ in 0..<4 { harness.key(KeyEvent(key: .character("s"), ctrl: true)) }
        #expect(harness.header(showing: "Echo") != nil, "\(harness.screen)")
    }

    @Test("A column wider than the table is drawn alone, and the next is a step away")
    func wideColumnLeavesTheOthersReachable() throws {
        let harness = Harness(WideFirstColumn(), width: 20)
        #expect(harness.header(showing: "Alpha") != nil, "\(harness.screen)")
        #expect(harness.barLine != nil, "\(harness.screen)")
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .right))
        #expect(harness.header(showing: "Bravo") != nil, "\(harness.screen)")
    }

    @Test("Columns that fit draw no scrollbar and take no arrow key")
    func fittingColumnsAreUnchanged() throws {
        let harness = Harness(SixColumns(), width: 70)
        let header = try #require(harness.header(showing: "Alpha"), "\(harness.screen)")
        #expect(header.contains("Foxtrot"), "\(harness.screen)")
        let rows = harness.lines.filter { $0.contains("a1") || $0.contains("a2") || $0.contains("a3") }
        #expect(rows.count == 3)
        #expect(!(harness.barLine?.contains("◀") ?? false), "\(harness.screen)")
        harness.key(KeyEvent(key: .tab))
        harness.key(KeyEvent(key: .right))
        #expect(harness.header(showing: "Alpha")?.contains("Foxtrot") == true, "\(harness.screen)")
    }

    @Test("A click on the scrollbar's track pages the columns")
    func trackClickPages() throws {
        let harness = Harness(SixColumns(), width: 20)
        let barY = try #require(harness.lines.firstIndex { $0 == harness.barLine }, "\(harness.screen)")
        // The far end of the track, inside the border.
        let x = 20 - 3
        harness.send(MouseEvent(button: .left, phase: .pressed, x: x, y: barY))
        harness.send(MouseEvent(button: .left, phase: .released, x: x, y: barY))
        #expect(harness.header(showing: "Alpha") == nil, "\(harness.screen)")
    }

    @Test("Under .overContent, the horizontal scrollbar is drawn over the rows for the pointer, and works there")
    func overlaidBarForThePointer() throws {
        let harness = Harness(UnderAButton(), width: 20)
        try #require(harness.header(showing: "Alpha") != nil, "\(harness.screen)")
        #expect(!harness.screen.contains("◀"), "no bar with the pointer elsewhere: \(harness.screen)")
        let y = try #require(harness.lines.firstIndex { $0.contains("a1") }, "\(harness.screen)")
        harness.send(MouseEvent(button: .none, phase: .moved, x: 5, y: y))
        let bar = try #require(harness.barLine, "\(harness.screen)")
        #expect(bar.contains("◀") && bar.contains("▶"), "a bar over the rows' last line: \(harness.screen)")
        #expect(harness.lines.contains { $0.contains("a3") }, "the rows keep their lines: \(harness.screen)")
        let barY = try #require(harness.lines.firstIndex { $0 == bar }, "\(harness.screen)")
        harness.send(MouseEvent(button: .left, phase: .pressed, x: 20 - 3, y: barY))
        harness.send(MouseEvent(button: .left, phase: .released, x: 20 - 3, y: barY))
        #expect(harness.header(showing: "Alpha") == nil, "its track pages the columns: \(harness.screen)")
    }

    @Test("A table that scrolls sideways measures as it draws")
    func measureMatchesRender() {
        for (width, height) in [(12, 6), (20, 8), (20, 4), (20, 5), (30, 12)] {
            let table = SixColumns()
            // Beside the rows, as `TableAnalyticMeasureTests` places them: over
            // them, the render takes the focus and the measure after it is of a
            // focused table, whose indicators move beside the rows.
            let context = makeRenderContext(width: width, height: height) { env, _ in
                env.scrollIndicatorPlacement = .besideContent
            }
            var renderContext = context
            renderContext.hasExplicitWidth = false
            let buffer = renderToBuffer(table, context: renderContext)
            let measured = measureChild(
                table, proposal: ProposedViewSize(width: width, height: height), context: context)
            #expect(
                measured.width == buffer.width && measured.height == buffer.height,
                "\(width)x\(height): measured \(measured.width)x\(measured.height), drawn \(buffer.width)x\(buffer.height)")
        }
    }
}
