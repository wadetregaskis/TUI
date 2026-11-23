//  🖥️ TUI — A Terminal UI framework for Swift
//  ListDragSelectionBatchTests.swift
//
//  A drag of a List's selection read in one batch with its release, before
//  any frame: the list gathers the selection on the frame after a drag
//  begins, so the drop waits for that frame and carries the selection whole
//  (decisions DRAG-SELECTION, 2026-10-27).
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
@Suite("Dragging a List's selection in one batch")
struct ListDragSelectionBatchTests {
    static let fruits = ["apple", "banana", "cherry", "damson", "elder"]

    private func tree(_ model: Model, _ dropped: Dropped) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            List(Self.fruits, id: \.self, selection: model.binding) { fruit in
                Text(fruit).draggable(fruit)
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
    private func cell(of text: String, in buffer: FrameBuffer) -> (x: Int, y: Int) {
        for (y, line) in buffer.lines.map(\.stripped).enumerated() {
            if let range = line.range(of: text) { return (line.distance(from: line.startIndex, to: range.lowerBound), y) }
        }
        Issue.record("\(text) not drawn")
        return (0, 0)
    }

    /// Hunt DND-6: the press, the drags and the release read in one drain, with
    /// no frame between, dropped the grabbed row alone, and the others stayed.
    @Test("A drop read in the same batch as the drag's start carries the whole selection")
    func sameBatchDropCarriesTheSelection() {
        let model = Model(["apple", "cherry", "damson"])
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 12)
        let resting = harness.frame(tree(model, dropped))
        let start = cell(of: "cherry", in: resting)
        let zone = cell(of: "ZONE", in: resting)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: start.x, y: start.y))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: start.x + 1, y: start.y + 1))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: zone.x + 2, y: zone.y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: zone.x + 2, y: zone.y))
        harness.frame(tree(model, dropped))
        #expect(dropped.drops == [["apple", "cherry", "damson"]])
        #expect(harness.tui.dragAndDropSession.active == nil, "the drop has ended the drag")
    }
}
