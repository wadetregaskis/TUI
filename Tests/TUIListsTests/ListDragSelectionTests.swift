//  🖥️ TUI — A Terminal UI framework for Swift
//  ListDragSelectionTests.swift
//
//  Dragging a selected row of a List carries the whole selection, in the
//  list's order, as a Mac's table does; Shift held as the drag starts extends
//  the selection to that row first (decisions DRAG-SELECTION, 2026-10-27).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

/// What the zone was handed.
private final class Dropped: @unchecked Sendable {
    var drops: [[String]] = []
}

/// The list's selection, kept across frames.
private final class Model: @unchecked Sendable {
    var selection: Set<String>
    init(_ selection: Set<String>) { self.selection = selection }
    var binding: Binding<Set<String>> { Binding(get: { self.selection }, set: { self.selection = $0 }) }
}

@MainActor
@Suite("Dragging a List's selection", .serialized)
struct ListDragSelectionTests {
    static let fruits = ["apple", "banana", "cherry", "damson", "elder"]

    /// A list of draggable fruits over a drop zone; `rowLimit`, where given,
    /// is the list's `dragPreviewRowLimit(_:)`.
    private func tree(_ model: Model, _ dropped: Dropped, rowLimit: Int?? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let rowLimit {
                    List(Self.fruits, id: \.self, selection: model.binding) { fruit in
                        Text(fruit).draggable(fruit)
                    }
                    .dragPreviewRowLimit(rowLimit)
                } else {
                    List(Self.fruits, id: \.self, selection: model.binding) { fruit in
                        Text(fruit).draggable(fruit)
                    }
                }
            }
            .frame(height: 7)
            Text("ZONE==========")
                .dropDestination(for: String.self) { values, _ in
                    dropped.drops.append(values)
                    return true
                }
        }
    }

    /// Where `text` is drawn.
    private func cell(of text: String, in harness: InputChainHarness, _ build: () -> some View) -> (x: Int, y: Int) {
        let lines = harness.frame(build()).lines.map(\.stripped)
        for (y, line) in lines.enumerated() {
            if let range = line.range(of: text) { return (line.distance(from: line.startIndex, to: range.lowerBound), y) }
        }
        Issue.record("\(text) not drawn: \(lines)")
        return (0, 0)
    }

    /// Presses on `from`'s row, drags it onto the zone with frames between the
    /// moves (the list gathers on the frame after the drag begins), and lets go.
    private func drag(
        _ from: String, shift: Bool = false, harness: InputChainHarness, _ build: () -> some View
    ) {
        let start = cell(of: from, in: harness, build)
        let zone = cell(of: "ZONE", in: harness, build)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: start.x, y: start.y, shift: shift))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: start.x + 1, y: start.y + 1, shift: shift))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: zone.x + 2, y: zone.y, shift: shift))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .released, x: zone.x + 2, y: zone.y, shift: shift))
    }

    @Test("Dragging one of several selected rows drops them all, in the list's order")
    func carriesTheSelection() {
        let model = Model(["damson", "banana"])
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 12)
        drag("damson", harness: harness) { tree(model, dropped) }
        #expect(dropped.drops == [["banana", "damson"]])
    }

    @Test("Dragging a row that is not selected drops that row alone")
    func unselectedRowDragsAlone() {
        let model = Model(["banana", "cherry"])
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 12)
        drag("elder", harness: harness) { tree(model, dropped) }
        #expect(dropped.drops == [["elder"]])
    }

    @Test("A lone selected row drags alone")
    func loneSelectionDragsAlone() {
        let model = Model(["cherry"])
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 12)
        drag("cherry", harness: harness) { tree(model, dropped) }
        #expect(dropped.drops == [["cherry"]])
    }

    @Test("Shift held as the drag starts extends the selection to the row first, as a Shift-click does")
    func shiftDragExtendsFirst() {
        let model = Model([])
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 12)
        // A click on banana selects it and anchors the selection there.
        let banana = cell(of: "banana", in: harness) { tree(model, dropped) }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: banana.x, y: banana.y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: banana.x, y: banana.y))
        harness.frame(tree(model, dropped))
        #expect(model.selection == ["banana"])
        drag("damson", shift: true, harness: harness) { tree(model, dropped) }
        #expect(model.selection == ["banana", "cherry", "damson"])
        #expect(dropped.drops == [["banana", "cherry", "damson"]])
    }

    /// Presses on `from`'s row and moves it twice, a frame after each move, so
    /// the list has gathered the selection; the drag stays in hand.
    private func pickUp(_ from: String, harness: InputChainHarness, _ build: () -> some View) {
        let start = cell(of: from, in: harness, build)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: start.x, y: start.y))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: start.x + 1, y: start.y + 1))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: start.x + 2, y: start.y + 3))
        harness.frame(build())
    }

    /// The lines of the drag's picture, stripped.
    private func carried(_ harness: InputChainHarness) -> [String] {
        (harness.tui.dragAndDropSession.active?.preview.lines ?? []).map { $0.stripped }
    }

    @Test("By default a selection's drag shows the grabbed row and counts the rest")
    func defaultPreviewCountsTheRest() {
        let model = Model(["banana", "cherry", "damson"])
        let harness = InputChainHarness(width: 30, height: 12)
        pickUp("cherry", harness: harness) { tree(model, Dropped()) }
        #expect(carried(harness) == ["cherry", "+2 more"])
        #expect(harness.tui.dragAndDropSession.active?.grabY == 0, "the grabbed row is the picture's first line")
    }

    @Test("dragPreviewRowLimit(_:) above the count shows every carried row, in the list's order")
    func raisedLimitShowsEveryRow() {
        let model = Model(["banana", "cherry", "damson"])
        let harness = InputChainHarness(width: 30, height: 12)
        pickUp("damson", harness: harness) { tree(model, Dropped(), rowLimit: 5) }
        #expect(carried(harness) == ["banana", "cherry", "damson"])
        // Grabbed by its third row, so the stack hangs two lines above the
        // pointer and damson stays under it.
        #expect(harness.tui.dragAndDropSession.active?.grabY == 2)
    }

    @Test("dragPreviewRowLimit(_:) below the count shows that many, the grabbed one among them, and counts the rest")
    func partialLimitKeepsTheGrabbedRow() {
        let model = Model(["apple", "banana", "cherry", "damson"])
        let harness = InputChainHarness(width: 30, height: 12)
        pickUp("damson", harness: harness) { tree(model, Dropped(), rowLimit: 2) }
        #expect(carried(harness) == ["cherry", "damson", "+2 more"])
        #expect(harness.tui.dragAndDropSession.active?.grabY == 1)
    }

    @Test("dragPreviewRowLimit(nil) shows every row; a limit below 1 is taken as 1")
    func nilAndClampedLimits() {
        let all = InputChainHarness(width: 30, height: 12)
        pickUp("banana", harness: all) { tree(Model(["banana", "cherry", "damson"]), Dropped(), rowLimit: .some(nil)) }
        #expect(carried(all) == ["banana", "cherry", "damson"])
        let none = InputChainHarness(width: 30, height: 12)
        pickUp("banana", harness: none) { tree(Model(["banana", "cherry", "damson"]), Dropped(), rowLimit: 0) }
        #expect(carried(none) == ["banana", "+2 more"])
    }

    @Test("A selected row scrolled out of the list's window is carried too")
    func carriesRowsOutsideTheWindow() {
        let names = (0..<40).map { "row\($0)" }
        let model = Model(["row1", "row30"])
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 12)
        func build() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                List(names, id: \.self, selection: model.binding) { name in
                    Text(name).draggable(name)
                }
                .frame(height: 6)
                Text("ZONE==========")
                    .dropDestination(for: String.self) { values, _ in
                        dropped.drops.append(values)
                        return true
                    }
            }
        }
        #expect(!harness.frame(build()).lines.contains { $0.stripped.contains("row30") }, "row30 is off the window")
        drag("row1", harness: harness, build)
        #expect(dropped.drops == [["row1", "row30"]])
    }
}
