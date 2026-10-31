//  🖥️ TUI — A Terminal UI framework for Swift
//  TableDropGapHeightTests.swift
//
//  The landing gap a drag of several rows opens in a table: as tall as the
//  rows it would land, as a list's is (`ListDropGapHeightTests`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUILists
import TUITables
@testable import TUITestSupport

@MainActor
@Suite("A table's landing gap for several rows", .serialized)
struct TableDropGapHeightTests {
    private struct Fruit: Identifiable {
        let id: String
        var name: String { id }
    }

    private final class Log {
        var offsets: [Int] = []
    }

    private let fruit = ["apple", "pear", "plum", "quince"].map(Fruit.init)

    private func table(_ log: Log) -> some View {
        Table(of: Fruit.self) {
            TableColumn("Name", value: \.name)
        } rows: {
            ForEach(fruit) { TableRow($0) }
                .dropDestination(for: String.self) { _, offset in log.offsets.append(offset) }
        }
        .frame(height: 11)
    }

    private func line(of text: String, in lines: [String]) -> Int? {
        lines.firstIndex { $0.contains(text) }
    }

    @Test("Three rows dragged in from elsewhere open a gap three lines tall, and land there")
    func foreignDragOpensATallGap() {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 14)
        let resting = harness.frame(table(log)).lines.map(\.stripped)
        let top = line(of: "plum", in: resting) ?? -1
        #expect(top > 0, "\(resting)")

        let session = harness.tui.dragAndDropSession
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 2, y: top)
        session.begin(payload: DragItems(items: ["x", "y", "z"]), preview: FrameBuffer(text: "x"))
        harness.frame(table(log))
        let open = harness.frame(table(log)).lines.map(\.stripped)
        #expect(line(of: "pear", in: open) == top - 1, "\(open)")
        #expect(line(of: "plum", in: open) == top + 3, "\(open)")
        #expect(line(of: "quince", in: open) == top + 4, "\(open)")

        _ = session.performDrop()
        #expect(log.offsets == [2])
    }

    @Test("One row still opens one line")
    func oneRowOpensOneLine() {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 14)
        let resting = harness.frame(table(log)).lines.map(\.stripped)
        let top = line(of: "pear", in: resting) ?? -1
        let session = harness.tui.dragAndDropSession
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 2, y: top)
        session.begin(payload: "x", preview: FrameBuffer(text: "x"))
        harness.frame(table(log))
        let one = harness.frame(table(log)).lines.map(\.stripped)
        #expect(line(of: "pear", in: one) == top + 1, "\(one)")
    }
}
