//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollIndicatorPlacementTests.swift
//
//  `.scrollIndicatorPlacement(.overContent)`: for the pointer the indicators
//  take no room, the content is laid out at the whole viewport, and they are
//  drawn over its edge while the pointer is over the view; while the view
//  holds the focus they are beside the content, as `.besideContent` draws
//  them, and losing the focus gives the content its room back (the owner's
//  A-CHURN-2 and SCROLLBAR-NAMES, 2026-10-27, and the focus ruling of
//  2026-10-29).
//
//  Every app here puts a button before the scrolling view, which the focus
//  goes to first: a lone scrolling view would take the focus on the first
//  frame, and so draw its indicators beside its content from the start.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("Scroll indicators over the content")
struct ScrollIndicatorPlacementTests {
    private struct Scroller: View {
        let placement: ScrollIndicatorPlacement
        let style: ScrollIndicatorStyle
        var visibility = ScrollIndicatorVisibility.automatic
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
            .scrollIndicators(visibility)
        }
    }

    private struct Lister: View {
        let placement: ScrollIndicatorPlacement
        var style: ScrollIndicatorStyle = .scrollbar
        var visibility = ScrollIndicatorVisibility.automatic
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
            .scrollIndicators(visibility)
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
        var visibility = ScrollIndicatorVisibility.automatic
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
            .scrollIndicators(visibility)
        }
    }

    private struct Editor: View {
        let placement: ScrollIndicatorPlacement
        @State private var text: String
        init(placement: ScrollIndicatorPlacement, lines: Int) {
            self.placement = placement
            // Each line exactly as wide as the editor, and one word: the room a
            // bar beside it takes wraps every line.
            _text = State(initialValue: (0..<lines).map { "\($0)".padding(toLength: 20, withPad: "x", startingAt: 0) }
                .joined(separator: "\n"))
        }
        var body: some View {
            TextEditor(text: $text)
                .frame(width: 20, height: 8)
                .scrollIndicatorPlacement(placement)
        }
    }

    private enum Kind {
        case scroller
        case list(buttons: Bool = false)
        case table(rows: Int = 30, multiLine: Bool = false, buttons: Bool = false)
        case editor(lines: Int = 30)
    }

    private struct ScrollerApp: App {
        let placement: ScrollIndicatorPlacement
        let style: ScrollIndicatorStyle
        init() { (placement, style) = (.overContent, .scrollbar) }
        init(placement: ScrollIndicatorPlacement, style: ScrollIndicatorStyle) {
            (self.placement, self.style) = (placement, style)
        }
        var kind = Kind.scroller
        var visibility = ScrollIndicatorVisibility.automatic
        var body: some Scene {
            WindowGroup {
                VStack(spacing: 0) {
                    // Where the focus starts, and goes back to on Tab. It shows
                    // no focus, so nothing on screen breathes.
                    Button("Away") {}.focusEffectDisabled()
                    switch kind {
                    case .scroller: Scroller(placement: placement, style: style, visibility: visibility)
                    case .list(let buttons):
                        Lister(placement: placement, style: style, visibility: visibility, buttons: buttons)
                    case .table(let rows, let multiLine, let buttons):
                        Tabler(
                            placement: placement, style: style, visibility: visibility, rows: rows,
                            multiLine: multiLine, buttons: buttons)
                    case .editor(let lines): Editor(placement: placement, lines: lines)
                    }
                }
            }
        }
    }

    @MainActor
    private final class Harness {
        let app: TestApp
        private var now: Int64 = 0

        init(
            _ placement: ScrollIndicatorPlacement, style: ScrollIndicatorStyle = .scrollbar, kind: Kind = .scroller,
            visibility: ScrollIndicatorVisibility = .automatic
        ) {
            var scene = ScrollerApp(placement: placement, style: style)
            scene.kind = kind
            scene.visibility = visibility
            app = TestApp(scene, width: 30, height: 12)
            frame()
            frame()
        }

        /// Clicks inside the scrolling view, which gives it the focus.
        func click() {
            let inside = inside
            move(to: inside.x, inside.y)
            mouse(.pressed, at: inside.x, inside.y)
            mouse(.released, at: inside.x, inside.y)
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        /// The first row of the scroll view's content as drawn.
        var firstRow: String {
            app.screen.lines.first { $0.contains("xxxx") } ?? ""
        }

        /// The number the first row drawn starts with.
        var firstRowNumber: Int? {
            Int(String(firstRow.drop { !$0.isNumber }.prefix { $0.isNumber }))
        }

        /// The whole screen, as text.
        var text: String { app.screen.lines.joined(separator: "\n") }

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
            let lines = app.screen.lines
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
        let screen = { harness.app.screen.lines.joined(separator: "\n") }
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
        let screen = { harness.app.screen.lines.joined(separator: "\n") }
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

    // MARK: - TextEditor

    @Test("An editor's text keeps the bar's column over the content")
    func editorKeepsItsRoom() {
        let beside = Harness(.besideContent, kind: .editor())
        let over = Harness(.overContent, kind: .editor())
        let xs = { (row: String) in row.filter { $0 == "x" }.count }
        #expect(xs(over.firstRow) > xs(beside.firstRow), "\(beside.firstRow) / \(over.firstRow)")
    }

    @Test("An editor's bar is drawn over its text for the pointer, and goes when it leaves")
    func editorBarForThePointer() {
        let harness = Harness(.overContent, kind: .editor())
        // As drawn, styles and all: at the top, the bar's thumb is a painted
        // blank, over the blank the caret's room leaves after the last column.
        let before = harness.app.screen.styledLines
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.app.screen.styledLines != before, "the bar covers the last column")
        harness.move(to: 29, 9)
        #expect(harness.app.screen.styledLines == before, "gone with the pointer")
    }

    @Test("Nothing is drawn over an editor whose text fits")
    func nothingOverAnEditorThatFits() {
        let harness = Harness(.overContent, kind: .editor(lines: 3))
        let before = harness.text
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.text == before, "\(harness.text)")
    }

    // MARK: - The focus

    /// Every scrolling view, a table on each of its content paths.
    nonisolated private static let scrollers: [Kind] = [
        .scroller, .list(), .table(), .table(multiLine: true), .editor(),
    ]

    @Test(
        "Holding the focus, the indicators are beside the content, as .besideContent draws them",
        arguments: scrollers)
    private func focusPutsThemBeside(_ kind: Kind) {
        let over = Harness(.overContent, kind: kind)
        let beside = Harness(.besideContent, kind: kind)
        let unfocused = over.text
        // The pointer comes (the indicators over the content), and clicks.
        over.click()
        beside.click()
        #expect(over.text != unfocused, "the content is laid out again, beside the indicators: \(over.text)")
        #expect(over.text == beside.text, "as beside the content:\n\(over.text)\n---\n\(beside.text)")
        // The pointer leaving moves nothing while the view holds the focus.
        over.move(to: 29, 9)
        #expect(over.text == beside.text, "the pointer gone, the focus keeps them beside:\n\(over.text)")
    }

    @Test(
        "Losing the focus gives the content its whole room back, and the pointer its indicators",
        arguments: [Kind.scroller, .list(), .table(), .table(multiLine: true)])
    private func losingFocusRestores(_ kind: Kind) {
        let harness = Harness(.overContent, kind: kind)
        let unfocused = harness.text
        let unfocusedRow = harness.firstRow
        harness.click()
        harness.move(to: 29, 9)
        #expect(harness.text != unfocused, "beside the content while focused: \(harness.text)")
        // To the button before the view.
        harness.press(.tab)
        #expect(harness.text == unfocused, "neither focus nor pointer, no indicator:\n\(harness.text)")
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.firstRow != unfocusedRow, "the pointer's bar is over the content: \(harness.firstRow)")
        #expect(harness.firstRow.count == unfocusedRow.count, "and moves nothing: \(harness.firstRow)")
    }

    @Test(
        "Holding the focus under .visible, the N more lines take lines of their own",
        arguments: [Kind.scroller, .list(), .table()])
    private func focusedTextLinesTakeTheirOwnLines(_ kind: Kind) {
        let over = Harness(.overContent, style: .text, kind: kind, visibility: .visible)
        let beside = Harness(.besideContent, style: .text, kind: kind, visibility: .visible)
        #expect(!over.text.contains("below"), "neither focus nor pointer, no N more line: \(over.text)")
        over.click()
        beside.click()
        over.move(to: 29, 9)
        #expect(over.text.contains("below"), "\(over.text)")
        #expect(over.text == beside.text, "as beside the content:\n\(over.text)\n---\n\(beside.text)")
    }
}
