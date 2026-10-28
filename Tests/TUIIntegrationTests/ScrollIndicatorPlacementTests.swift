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

    private enum Kind {
        case scroller
        case list(buttons: Bool = false)
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

        func move(to x: Int, _ y: Int) {
            app.send(MouseEvent(button: .none, phase: .moved, x: x, y: y))
            frame()
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

    @Test("Over a control in a row, the pointer is still over the list")
    func barOverARowsControl() {
        let harness = Harness(.overContent, kind: .list(buttons: true))
        let before = harness.firstRow
        let inside = harness.inside
        harness.move(to: inside.x, inside.y)
        #expect(harness.firstRow != before, "the row's control hides nothing: \(harness.firstRow)")
    }
}
