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

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
import TUIkitTables
@testable import TUIkitTestSupport

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
                        .dropDestination(for: String.self) { values, offset in
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

    /// The same rule as a hierarchical table's (below): the slot before the
    /// hand-written first row is no loop's, so it opens no gap and refuses
    /// the drop. It opened one, and the drop was reported taken.
    @Test("In a flat table a slot no loop reaches opens no gap, and a drop there is refused")
    func flatRefusesASlotNoLoopReaches() {
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
                        .dropDestination(for: String.self) { values, offset in
                            log.entries.append("insert \(values) at \(offset)")
                        }
                }
            }
        }
        let resting = harness.frame(build())
        let header = line(of: "header", in: resting)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: header))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: header))
        let hovering = harness.frame(build())
        #expect(line(of: "header", in: hovering) == header, "a gap opened: \(hovering.lines.map(\.stripped))")
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: header))
        harness.frame(build())
        #expect(log.entries.isEmpty, "\(log.entries)")
        #expect(harness.tui.dragAndDropSession.returnFlight != nil, "the drop was taken: nothing flies home")
    }

    /// A row of a hierarchical table: a folder, or a file in one.
    private struct Node: Identifiable {
        let id: String
        var children: [Self] = []
        var name: String { id }
    }

    private let folders = [
        Node(id: "A", children: [Node(id: "a1"), Node(id: "a2")]),
        Node(id: "B", children: [Node(id: "b1")]),
    ]

    /// Drags "seed" from a chip and drops it on the line of `target` in a
    /// hierarchical table, open throughout, whose loops say where it went:
    /// the roots' loop, and each folder's loop of files where `filesTake`.
    private func dropInOutline(on target: String, filesTake: Bool) -> [String] {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 16)
        let folders = self.folders
        @TableRowBuilder<Node>
        func files(of folder: Node) -> some TableRowContent<Node> {
            if filesTake {
                ForEach(folder.children) { TableRow($0) }
                    .dropDestination(for: String.self) { values, offset in
                        log.entries.append("\(folder.id) \(values) at \(offset)")
                    }
            } else {
                ForEach(folder.children) { TableRow($0) }
            }
        }
        func build() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("seed")
                Table(of: Node.self) {
                    TableColumn("Name", value: \.name)
                } rows: {
                    ForEach(folders) { folder in
                        DisclosureTableRow(folder, isExpanded: .constant(true)) { files(of: folder) }
                    }
                    .dropDestination(for: String.self) { values, offset in
                        log.entries.append("roots \(values) at \(offset)")
                    }
                }
            }
        }
        let resting = harness.frame(build())
        let row = line(of: target, in: resting)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: row))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: row))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: row))
        harness.frame(build())
        return log.entries
    }

    /// Measured on macOS 15.8 (`Tools/SwiftUIProbes/Hierarchical table
    /// insertions/outlineinsert.swift`): a drop among a branch's rows goes to
    /// their loop at its offset among them, and one among the roots to the
    /// roots' loop (decisions B80).
    @Test("In a hierarchical table a drop goes to the loop whose rows it falls among")
    func outlineInsertion() {
        // The gap opens before the row under the pointer.
        #expect(dropInOutline(on: "a2", filesTake: true) == ["A [\"seed\"] at 1"])
        #expect(dropInOutline(on: "A", filesTake: true) == ["roots [\"seed\"] at 0"])
        #expect(dropInOutline(on: "b1", filesTake: true) == ["B [\"seed\"] at 0"])
        // Before B is also after A's last file: the files', the deeper loop.
        #expect(dropInOutline(on: "B", filesTake: true) == ["A [\"seed\"] at 2"])
        // Where the files take nothing, the roots' loop has that slot.
        #expect(dropInOutline(on: "B", filesTake: false) == ["roots [\"seed\"] at 1"])
    }

    /// The common tree: a loop that takes drops among each branch's rows and
    /// none among the roots. The table took the drag over every row because a
    /// loop of it takes the payload, and opened its gap at every slot; a drop
    /// at one no loop takes was reported taken, and nothing heard it.
    @Test("In a hierarchical table a slot no loop takes opens no gap, and a drop there is refused")
    func outlineRefusesASlotNoLoopTakes() {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 16)
        let folders = self.folders
        func build() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("seed")
                Table(of: Node.self) {
                    TableColumn("Name", value: \.name)
                } rows: {
                    ForEach(folders) { folder in
                        DisclosureTableRow(folder, isExpanded: .constant(true)) {
                            ForEach(folder.children) { TableRow($0) }
                                .dropDestination(for: String.self) { values, offset in
                                    log.entries.append("\(folder.id) \(values) at \(offset)")
                                }
                        }
                    }
                }
            }
        }
        let resting = harness.frame(build())
        // Before the first root: among the roots, whose loop takes nothing.
        let row = line(of: "A", in: resting)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: row))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: row))
        let hovering = harness.frame(build())
        #expect(line(of: "A", in: hovering) == row, "a gap opened: \(hovering.lines.map(\.stripped))")
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: row))
        harness.frame(build())
        #expect(log.entries.isEmpty, "\(log.entries)")
        #expect(harness.tui.dragAndDropSession.returnFlight != nil, "the drop was taken: nothing flies home")
        // Among a branch's rows the loop takes it, as ever.
        #expect(dropInOutline(on: "a2", filesTake: true) == ["A [\"seed\"] at 1"])
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
