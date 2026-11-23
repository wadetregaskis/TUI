//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowDropScrollTests.swift
//
//  A table row's drop destination while the rows move under a held drag: the
//  row drawn as targeted is the one under the pointer, however the rows got
//  there, and none stays drawn so once the drag is over.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITables
@testable import TUITestSupport

@MainActor
@Suite("Table row drop targets under scrolled rows")
struct TableRowDropScrollTests {
    private struct Fruit: Identifiable {
        let id: String
        var name: String { id }
    }

    private final class Log {
        var entries: [String] = []
    }

    /// Thirty rows, so eight lines of table leave most of them out of sight.
    private let fruit = (10..<40).map { Fruit(id: "row\($0)") }

    /// A chip to drag, over a table of `fruit` whose rows each take a drop.
    private func build(_ log: Log) -> some View {
        let fruit = self.fruit
        return VStack(alignment: .leading, spacing: 0) {
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
            .frame(height: 8)
        }
    }

    /// The table's lines in `buffer` drawn otherwise than in `reference`, the
    /// same table at the same scroll with no drag: the lines drawn as targeted.
    private func litLines(_ buffer: FrameBuffer, against reference: FrameBuffer) -> [Int] {
        (1..<9).filter { buffer.lines[$0] != reference.lines[$0] }
    }

    /// The name of the row drawn on `line`: "row" and its two digits.
    private static func rowName(in line: String) -> String {
        guard let start = line.range(of: "row")?.lowerBound else { return "" }
        return String(line[start...].prefix(5))
    }

    /// Hunt DND-1: every row's zone is filed at the table's own identity, so
    /// its id is its place among the rows drawn, which a scroll gives to
    /// another row. The id under the pointer did not change, so no transition
    /// fired: the row that scrolled away stayed lit, the one under the pointer
    /// was not, and the drop's exit closed the wrong row and left the first lit
    /// for good.
    @Test("The row drawn as targeted is the one scrolled under the pointer, and none stays lit after the drop")
    func litRowFollowsTheScroll() {
        let log = Log()
        let harness = InputChainHarness(width: 30, height: 12)
        let resting = harness.frame(build(log))
        let last = (1..<9).last { resting.lines[$0].stripped.contains("row") } ?? -1
        let wheel = MouseEvent(button: .scrollDown, phase: .scrolled, x: 3, y: 4)

        // The same table scrolled by the same wheel with nothing in hand:
        // what each line looks like unlit.
        let unlit = InputChainHarness(width: 30, height: 12)
        unlit.frame(build(Log()))
        unlit.mouse(wheel)
        let reference = unlit.frame(build(Log()))

        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(build(log))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: last))
        harness.frame(build(log))
        harness.mouse(wheel)
        harness.frame(build(log))
        let under = Self.rowName(in: reference.lines[last].stripped)
        #expect(under.hasPrefix("row"), "\(reference.lines.map(\.stripped))")
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: last))
        let hovering = harness.frame(build(log))
        #expect(litLines(hovering, against: reference) == [last], "the pointer is on line \(last)")

        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: last))
        let after = harness.frame(build(log))
        #expect(log.entries == ["\(under) got [\"seed\"]"])
        #expect(litLines(after, against: reference).isEmpty, "a row stayed drawn as targeted")
    }
}
