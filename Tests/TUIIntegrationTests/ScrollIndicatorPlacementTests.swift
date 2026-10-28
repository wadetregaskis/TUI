//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollIndicatorPlacementTests.swift
//
//  `.scrollIndicatorPlacement(.overContent)`: the indicators take no room,
//  the content is laid out at the whole viewport, and they are drawn over its
//  edge while the pointer is over the view — never for the focus alone (the
//  owner's A-CHURN-2 and SCROLLBAR-NAMES, 2026-10-27).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Scroll indicators over the content")
struct ScrollIndicatorPlacementTests {
    private struct Scroller: View {
        let placement: ScrollIndicatorPlacement
        let style: ScrollIndicatorStyle
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<30, id: \.self) { row in
                        Text(verbatim: String(repeating: "x", count: 20) + " \(row)")
                    }
                }
            }
            .frame(width: 20, height: 8)
            .scrollIndicatorPlacement(placement)
            .scrollIndicatorStyle(style)
        }
    }

    private struct Lister: View {
        let placement: ScrollIndicatorPlacement
        var style: ScrollIndicatorStyle = .scrollbar
        /// Rows that are each a control, with a hit region of its own.
        var buttons = false
        var body: some View {
            List(0..<30, id: \.self) { row in
                if buttons {
                    Button(String(repeating: "x", count: 30) + " \(row)") {}
                } else {
                    Text(verbatim: String(repeating: "x", count: 30) + " \(row)")
                }
            }
            .frame(width: 20, height: 8)
            .scrollIndicatorPlacement(placement)
            .scrollIndicatorStyle(style)
        }
    }

    /// A row of a table: its number first, where a cut leaves it showing, and
    /// one word, so a wrapped row's first line carries it.
    private struct Row: Identifiable {
        let id: Int
        var name: String { "\(id)" + String(repeating: "x", count: 30) }
    }

    private struct Tabler: View {
        let placement: ScrollIndicatorPlacement
        var style: ScrollIndicatorStyle = .scrollbar
        let rows: Int
        /// A line limit above 1 takes the table's multi-line layout path.
        let multiLine: Bool
        /// Cells that are each a control, with a hit region of its own.
        let buttons: Bool
        var body: some View {
            Table((0..<rows).map(Row.init(id:))) {
                if buttons {
                    TableColumn("Name") { (row: Row) in Button(row.name) {} }
                } else if multiLine {
                    TableColumn("Name", value: \Row.name).lineLimit(2)
                } else {
                    TableColumn("Name", value: \Row.name)
                }
            }
            .frame(width: 20, height: 10)
            .scrollIndicatorPlacement(placement)
            .scrollIndicatorStyle(style)
        }
    }

    private enum Kind {
        case scroller
        case list(buttons: Bool = false)
        case table(rows: Int = 30, multiLine: Bool = false, buttons: Bool = false)
    }

    private struct ScrollerApp: App {
        let placement: ScrollIndicatorPlacement
        let style: ScrollIndicatorStyle
        init() { (placement, style) = (.overContent, .scrollbar) }
        init(placement: ScrollIndicatorPlacement, style: ScrollIndicatorStyle) {
            (self.placement, self.style) = (placement, style)
        }
        var kind = Kind.scroller
        var body: some Scene {
            WindowGroup {
                switch kind {
                case .scroller: Scroller(placement: placement, style: style)
                case .list(let buttons): Lister(placement: placement, style: style, buttons: buttons)
                case .table(let rows, let multiLine, let buttons):
                    Tabler(placement: placement, style: style, rows: rows, multiLine: multiLine, buttons: buttons)
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let app: HeadlessApp<ScrollerApp>
        private var now: Int64 = 0

        init(_ placement: ScrollIndicatorPlacement, style: ScrollIndicatorStyle = .scrollbar, kind: Kind = .scroller) {
            var scene = ScrollerApp(placement: placement, style: style)
            scene.kind = kind
            app = HeadlessApp(scene, width: 30, height: 10)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        /// The first row of the scroll view's content as drawn.
        var firstRow: String {
            app.screen.map(\.stripped).first { $0.contains("xxxx") } ?? ""
        }

        /// The number the first row drawn starts with.
        var firstRowNumber: Int? {
            Int(String(firstRow.drop { !$0.isNumber }.prefix { $0.isNumber }))
        }

        /// The whole screen, as text.
        var text: String { app.screen.map(\.stripped).joined(separator: "\n") }

        func move(to x: Int, _ y: Int) {
            app.send(MouseEvent(button: .none, phase: .moved, x: x, y: y))
            frame()
        }

        func mouse(_ phase: MousePhase, at x: Int, _ y: Int) {
            app.send(MouseEvent(button: .left, phase: phase, x: x, y: y))
            frame()
        }

        func press(_ key: Key, times: Int = 1) {
            for _ in 0..<times {
                _ = app.send(KeyEvent(key: key))
                frame()
            }
        }

        /// A cell inside the scroll view.
        var inside: (x: Int, y: Int) {
            let lines = app.screen.map(\.stripped)
            let y = lines.firstIndex { $0.contains("xxxx") } ?? 0
            let x = lines[y].range(of: "xxxx").map { lines[y].distance(from: lines[y].startIndex, to: $0.lowerBound) } ?? 0
            return (x + 2, y + 1)
        }
    }

    @Test("Beside the content, the bar takes a column; over it, the content keeps the column")
    func contentKeepsItsRoom() {
        let beside = Harness(.besideContent)
        let over = Harness(.overContent)
        let xs = { (row: String) in row.filter { $0 == "x" }.count }
        #expect(xs(over.firstRow) > xs(beside.firstRow), "\(beside.firstRow) / \(over.firstRow)")
    }

    @Test("Over the content, the bar shows while the pointer is over the view, and goes when it leaves")
    func barForThePointer() {
        let harness = Harness(.overContent)
        let before = harness.firstRow
        #expect(!before.contains("▲") && !before.contains("█"), "no bar until the pointer comes: \(before)")
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.firstRow != before, "the bar is drawn over the last column: \(harness.firstRow)")
        harness.move(to: 29, 9)
        #expect(harness.firstRow == before, "gone with the pointer: \(harness.firstRow)")
    }

    @Test("Over the content, the text lines show for the pointer only")
    func textForThePointer() {
        let harness = Harness(.overContent, style: .text)
        let screen = { harness.app.screen.map(\.stripped).joined(separator: "\n") }
        #expect(!screen().contains("below"), "no N more line until the pointer comes")
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(screen().contains("below"), "\(screen())")
    }

    @Test("A list's bar is drawn over its rows for the pointer, the rows laid out at the whole width")
    func listBarForThePointer() {
        let beside = Harness(.besideContent, kind: .list())
        let over = Harness(.overContent, kind: .list())
        let xs = { (row: String) in row.filter { $0 == "x" }.count }
        #expect(xs(over.firstRow) > xs(beside.firstRow), "\(beside.firstRow) / \(over.firstRow)")
        let before = over.firstRow
        let inside = over.inside
        over.move(to: inside.x, inside.y)
        #expect(over.firstRow != before, "the bar covers the last column: \(over.firstRow)")
        over.move(to: 29, 9)
        #expect(over.firstRow == before, "gone with the pointer: \(over.firstRow)")
    }

    @Test("A list's N more lines are written over its rows for the pointer only")
    func listTextForThePointer() {
        let harness = Harness(.overContent, style: .text, kind: .list())
        let screen = { harness.app.screen.map(\.stripped).joined(separator: "\n") }
        #expect(!screen().contains("below"), "no N more line until the pointer comes: \(screen())")
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(screen().contains("below"), "\(screen())")
    }

    @Test(
        "Over a control in a row, the pointer is still over the list or the table",
        arguments: [Kind.list(buttons: true), .table(buttons: true)])
    private func barOverARowsControl(_ kind: Kind) {
        let harness = Harness(.overContent, kind: kind)
        let before = harness.firstRow
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.firstRow != before, "the row's control hides nothing: \(harness.firstRow)")
    }

    // MARK: - Table

    /// A table on each of its content paths.
    nonisolated private static let tables: [Kind] = [.table(), .table(multiLine: true)]

    @Test("A table's columns keep the bar's room over the content", arguments: tables)
    private func tableKeepsItsRoom(_ kind: Kind) {
        let beside = Harness(.besideContent, kind: kind)
        let over = Harness(.overContent, kind: kind)
        let xs = { (row: String) in row.filter { $0 == "x" }.count }
        #expect(xs(over.firstRow) > xs(beside.firstRow), "\(beside.firstRow) / \(over.firstRow)")
    }

    @Test("A table's bar is drawn over its rows for the pointer, and goes when it leaves", arguments: tables)
    private func tableBarForThePointer(_ kind: Kind) {
        let harness = Harness(.overContent, kind: kind)
        let before = harness.firstRow
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.firstRow != before, "the bar covers the last column: \(harness.firstRow)")
        #expect(harness.firstRow.count == before.count, "and moves nothing: \(before) / \(harness.firstRow)")
        harness.move(to: 29, 9)
        #expect(harness.firstRow == before, "gone with the pointer: \(harness.firstRow)")
    }

    @Test("A table's N more lines are written over its rows for the pointer only", arguments: tables)
    private func tableTextForThePointer(_ kind: Kind) {
        let harness = Harness(.overContent, style: .text, kind: kind)
        #expect(!harness.text.contains("below"), "no N more line until the pointer comes: \(harness.text)")
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.text.contains("below"), "\(harness.text)")
    }

    @Test("Nothing is drawn over a table whose rows fit")
    func nothingOverATableThatFits() {
        for style in [ScrollIndicatorStyle.scrollbar, .text] {
            let harness = Harness(.overContent, style: style, kind: .table(rows: 3))
            let before = harness.text
            let inside = harness.inside
            harness.move(to: inside.x, inside.y)
            #expect(harness.text == before, "\(style): \(harness.text)")
        }
    }

    @Test("A table's focus alone draws nothing over its rows", arguments: tables)
    private func tableFocusAlone(_ kind: Kind) {
        let harness = Harness(.overContent, kind: kind)
        // Scrolled from the keyboard: the table has the focus.
        harness.press(.down, times: 12)
        #expect((harness.firstRowNumber ?? 0) > 0, "the keys scrolled the table: \(harness.firstRow)")
        let focused = harness.firstRow
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.firstRow != focused, "only the pointer brings the bar: \(focused) / \(harness.firstRow)")
    }

    @Test("A drag on a table's bar over its rows scrolls it", arguments: tables)
    private func tableBarDrags(_ kind: Kind) throws {
        let harness = Harness(.overContent, kind: kind)
        let before = Array(harness.firstRow)
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        let hovered = Array(harness.firstRow)
        // The bar's column: where the pointer's arrival changed the row.
        let barX = try #require(before.indices.first { $0 < hovered.count && before[$0] != hovered[$0] })
        harness.mouse(.pressed, at: barX, inside.y)
        harness.mouse(.dragged, at: barX, inside.y + 4)
        harness.mouse(.released, at: barX, inside.y + 4)
        #expect((harness.firstRowNumber ?? 0) > 0, "dragging the thumb scrolled the rows: \(harness.text)")
    }
}
