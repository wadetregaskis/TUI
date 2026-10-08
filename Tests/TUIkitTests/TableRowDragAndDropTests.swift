//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowDragAndDropTests.swift
//
//  Drag and drop on a table's rows: `.draggable(_:)` and `.itemProvider(_:)`
//  carry a row's payload out, `.dropDestination(for:action:)` on a row takes a
//  drop onto it, and a loop's `.dropDestination(for:action:)` and
//  `.onInsert(of:perform:)` take payloads in between its rows, at offsets into
//  the loop's own collection.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

@MainActor
@Suite("Table row drag and drop")
struct TableRowDragAndDropTests {
    private struct Fruit: Identifiable {
        let id: String
        var name: String { id }
    }

    private final class Log {
        var entries: [String] = []
    }

    private let fruit = ["apple", "pear", "plum"].map(Fruit.init)

    /// The line `text` is drawn on.
    private func line(of text: String, in buffer: FrameBuffer) -> Int {
        buffer.lines.firstIndex { $0.stripped.contains(text) } ?? -1
    }

    /// Presses at `from`, moves through the cells between, and lets go at
    /// `to`, with a frame of `build` after each event.
    private func carry(
        _ harness: InputChainHarness, from: (x: Int, y: Int), to: (x: Int, y: Int), _ build: () -> some View
    ) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: from.x, y: from.y))
        harness.frame(build())
        let midY = (from.y + to.y) / 2
        for point in [(from.x + 1, midY), (to.x, to.y), (to.x + 1, to.y)] {
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: point.0, y: point.1))
            harness.frame(build())
        }
        harness.mouse(MouseEvent(button: .left, phase: .released, x: to.x + 1, y: to.y))
        harness.frame(build())
    }

    @Test("A draggable row carries its payload to a view's drop destination")
    func draggableRowToView() {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 14)
        let fruit = self.fruit
        func build() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Table(of: Fruit.self) {
                    TableColumn("Name", value: \.name)
                } rows: {
                    ForEach(fruit) { item in
                        TableRow(item).draggable(item.name)
                    }
                }
                .frame(height: 7)
                Text("ZONE==========").dropDestination(for: String.self) { values, _ in
                    log.entries.append("dropped \(values)")
                    return true
                }
            }
        }
        let buffer = harness.frame(build())
        let pear = line(of: "pear", in: buffer)
        let zone = line(of: "ZONE", in: buffer)
        carry(harness, from: (x: 4, y: pear), to: (x: 3, y: zone), build)
        #expect(log.entries == ["dropped [\"pear\"]"], "\(buffer.lines.map(\.stripped))")
    }

    @Test("A press on a draggable row released without moving selects it")
    func draggableRowStillClicks() {
        var selection: String?
        let harness = InputChainHarness(width: 30, height: 10)
        let fruit = self.fruit
        func build() -> some View {
            Table(of: Fruit.self, selection: Binding(get: { selection }, set: { selection = $0 })) {
                TableColumn("Name", value: \.name)
            } rows: {
                ForEach(fruit) { item in
                    TableRow(item).draggable(item.name)
                }
            }
        }
        let buffer = harness.frame(build())
        let plum = line(of: "plum", in: buffer)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 5, y: plum))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 5, y: plum))
        harness.frame(build())
        #expect(selection == "plum")
    }

    @Test("A row's drop destination takes a drop onto it, and is drawn as selected while the drag is over it")
    func dropOntoRow() {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 14)
        let fruit = self.fruit
        func build() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("seed")
                Table(of: Fruit.self) {
                    TableColumn("Name", value: \.name)
                } rows: {
                    ForEach(fruit) { item in
                        TableRow(item).dropDestination(for: String.self) { values in
                            log.entries.append("\(item.name) got \(values)")
                        }
                    }
                }
            }
        }
        let resting = harness.frame(build())
        let pear = line(of: "pear", in: resting)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: pear))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: pear))
        let hovering = harness.frame(build())
        #expect(hovering.lines[pear] != resting.lines[pear], "the targeted row is drawn differently")
        #expect(hovering.lines[pear].stripped.contains("pear"))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: pear))
        let after = harness.frame(build())
        #expect(log.entries == ["pear got [\"seed\"]"])
        #expect(after.lines[pear] == resting.lines[pear], "and drawn as before once the drag is over")
    }

    @Test("A loop's drop destination inserts at an offset into its own collection")
    func loopInsertion() {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 16)
        let fruit = self.fruit
        func build() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("seed")
                Table(of: Fruit.self) {
                    TableColumn("Name", value: \.name)
                } rows: {
                    TableRow(Fruit(id: "header"))
                    ForEach(fruit) { TableRow($0) }
                        .dropDestination(for: String.self) { offset, values in
                            log.entries.append("insert \(values) at \(offset)")
                        }
                }
            }
        }
        let resting = harness.frame(build())
        let pear = line(of: "pear", in: resting)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: pear))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: pear))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: pear))
        harness.frame(build())
        // The gap opens before the row under the pointer: "pear", the table's
        // third row and the loop's second.
        #expect(log.entries == ["insert [\"seed\"] at 1"], "\(resting.lines.map(\.stripped))")
    }

    #if canImport(UniformTypeIdentifiers)
        @Test("A row's item provider is what its drag carries, and a loop's onInsert takes it")
        func itemProviderAndOnInsert() {
            let log = Log()
            let harness = InputChainHarness(width: 30, height: 20)
            let fruit = self.fruit
            func build() -> some View {
                VStack(alignment: .leading, spacing: 0) {
                    Table(of: Fruit.self) {
                        TableColumn("Name", value: \.name)
                    } rows: {
                        ForEach(fruit) { item in
                            TableRow(item).itemProvider { NSItemProvider(object: item.name as NSString) }
                        }
                    }
                    .frame(height: 7)
                    Table(of: Fruit.self) {
                        TableColumn("Basket", value: \.name)
                    } rows: {
                        ForEach([Fruit(id: "fig"), Fruit(id: "kiwi")]) { TableRow($0) }
                            .onInsert(of: [.plainText]) { offset, providers in
                                log.entries.append("insert \(providers.count) at \(offset)")
                            }
                    }
                    .frame(height: 7)
                }
            }
            let buffer = harness.frame(build())
            let plum = line(of: "plum", in: buffer)
            let kiwi = line(of: "kiwi", in: buffer)
            carry(harness, from: (x: 4, y: plum), to: (x: 3, y: kiwi), build)
            #expect(log.entries == ["insert 1 at 1"], "\(buffer.lines.map(\.stripped))")
        }
    #endif
}
